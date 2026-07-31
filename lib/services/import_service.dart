import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';

import '../utils/debug_log.dart';
import 'auth_service.dart';

enum ImportSource { dataportability, takeout }

enum ImportState { pending, inProgress, complete, failed, cancelled }

/// A single import, as reported by the backend.
class ImportJob {
  final String id;
  final ImportSource source;
  final ImportState state;
  final int? placesImported;
  final String? error;
  final DateTime? createdAt;

  const ImportJob({
    required this.id,
    required this.source,
    required this.state,
    this.placesImported,
    this.error,
    this.createdAt,
  });

  bool get isRunning =>
      state == ImportState.pending || state == ImportState.inProgress;

  factory ImportJob.fromDoc(String id, Map<String, dynamic> data) => ImportJob(
        id: id,
        source: data['source'] == 'takeout'
            ? ImportSource.takeout
            : ImportSource.dataportability,
        state: switch (data['state']) {
          'COMPLETE' => ImportState.complete,
          'FAILED' => ImportState.failed,
          'CANCELLED' => ImportState.cancelled,
          'IN_PROGRESS' => ImportState.inProgress,
          _ => ImportState.pending,
        },
        placesImported: (data['placesImported'] as num?)?.toInt(),
        error: data['error'] as String?,
        createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      );
}

/// Pulls the retry timestamp out of a callable's error details, tolerating the
/// loosely-typed map that arrives over the wire.
DateTime? _retryAfterFrom(Object? details) {
  if (details is! Map) return null;
  final raw = details['retryAfter'];
  if (raw is! String) return null;
  return DateTime.tryParse(raw);
}

/// Starts imports and reports on their progress.
class ImportService {
  static final ImportService instance = ImportService._();

  ImportService._();

  /// Live view of this user's imports, newest first.
  Stream<List<ImportJob>> watchJobs() {
    final uid = AuthService.instance.uid;
    if (uid == null) return Stream.value(const []);

    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('importJobs')
        .orderBy('createdAt', descending: true)
        .limit(10)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => ImportJob.fromDoc(doc.id, doc.data()))
            .toList());
  }

  /// Kick off a Starred places export.
  ///
  /// Returns a human-readable error, or null on success. Success only means the
  /// job was *accepted* — Google may take hours or days to build the archive,
  /// after which a scheduled function ingests it.
  Future<String?> startStarredPlacesImport() async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('startStarredPlacesImport')
          .call();
      return null;
    } on FirebaseFunctionsException catch (e) {
      debugLog('dBug/import: start failed: ${e.code} ${e.message}');

      // Google allows one export per resource group per 24 hours. Resetting
      // authorization would clear it only by revoking every scope and forcing
      // a fresh consent, so tell the user when to come back instead.
      if (e.code == 'resource-exhausted') {
        final retryAfter = _retryAfterFrom(e.details);
        if (retryAfter == null) {
          return 'Already synced in the last 24 hours. Try again later.';
        }
        return 'Already synced recently. You can sync again after '
            '${DateFormat('MMM d, h:mm a').format(retryAfter.toLocal())}.';
      }

      return e.message ?? 'Could not start the import.';
    } catch (e) {
      debugLog('dBug/import: start failed: $e');
      return 'Could not start the import.';
    }
  }

  /// Allow the same data to be exported again.
  ///
  /// This revokes every granted scope, so the user has to reconnect afterwards.
  Future<String?> resetAuthorization() async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('resetImportAuthorization')
          .call();
      return null;
    } on FirebaseFunctionsException catch (e) {
      return e.message ?? 'Could not reset authorization.';
    } catch (e) {
      return 'Could not reset authorization.';
    }
  }

  /// Pick a Takeout archive from the phone and upload it for parsing.
  ///
  /// This is the only route to Loved, Want to go and custom lists — the Data
  /// Portability API has no scope for any of them.
  ///
  /// Returns a human-readable error, or null on success. A null return with
  /// [cancelled] set means the user backed out of the picker.
  Future<({String? error, bool cancelled})> uploadTakeoutArchive({
    void Function(double progress)? onProgress,
  }) async {
    final uid = AuthService.instance.uid;
    if (uid == null) return (error: 'Sign in first.', cancelled: false);

    FilePickerResult? picked;
    try {
      picked = await FilePicker.pickFiles(
        dialogTitle: 'Choose your Takeout .zip',
        type: FileType.custom,
        allowedExtensions: ['zip'],
        // Takeout archives can be gigabytes; stream from disk rather than
        // pulling the whole thing into memory.
        withData: false,
      );
    } catch (e) {
      debugLog('dBug/import: picker failed: $e');
      return (error: 'Could not open the file picker.', cancelled: false);
    }

    final path = picked?.files.single.path;
    if (path == null) return (error: null, cancelled: true);

    try {
      // The filename is only for humans reading logs; the function keys off the
      // uid in the path.
      final ref = FirebaseStorage.instance
          .ref()
          .child('takeout/$uid/${DateTime.now().millisecondsSinceEpoch}.zip');

      final task = ref.putFile(
        File(path),
        SettableMetadata(contentType: 'application/zip'),
      );

      if (onProgress != null) {
        task.snapshotEvents.listen((snapshot) {
          if (snapshot.totalBytes > 0) {
            onProgress(snapshot.bytesTransferred / snapshot.totalBytes);
          }
        });
      }

      await task;
      return (error: null, cancelled: false);
    } on FirebaseException catch (e) {
      debugLog('dBug/import: upload failed: ${e.code} ${e.message}');
      return (
        error: e.message ?? 'Upload failed.',
        cancelled: false,
      );
    } catch (e) {
      debugLog('dBug/import: upload failed: $e');
      return (error: 'Upload failed.', cancelled: false);
    }
  }
}
