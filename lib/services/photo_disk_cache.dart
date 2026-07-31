import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/debug_log.dart';
import 'restaurant_service.dart';

/// A disk tier under the in-memory photo cache.
///
/// The memory cache holds sixty photos and dies with the process, so a cold
/// start drew its list instantly and then re-downloaded every picture on it.
/// This keeps the bytes on disk, which makes a relaunch draw photos from local
/// storage and gives the LRU somewhere to fall back to instead of the network.
///
/// Lives in `Library/Caches` (via [getApplicationCacheDirectory]), which is the
/// right home for regenerable data: the OS may reclaim it under pressure and it
/// is excluded from backups.
class PhotoDiskCache {
  const PhotoDiskCache._();

  static const String _dirName = 'place_photos';

  /// Entries older than this are swept. Places change, and a photo nobody has
  /// looked at in a fortnight is not worth the space.
  static const Duration maxAge = Duration(days: 14);

  /// A backstop for heavy use inside the [maxAge] window — the age sweep alone
  /// puts no ceiling on how much a fortnight of browsing can accumulate.
  static const int maxBytes = 80 * 1024 * 1024;

  static Directory? _dir;
  static Future<Directory?>? _dirFuture;

  /// Point [RestaurantService] at this cache and schedule the sweep.
  ///
  /// The hooks are function fields rather than a direct import because
  /// `RestaurantService` is shared with `bin/foodierank.dart` and must stay
  /// free of Flutter imports — `path_provider` is a plugin.
  static void install() {
    RestaurantService.instance.photoCacheRead = read;
    RestaurantService.instance.photoCacheWrite = write;

    // After the first frame: sweeping means listing a directory and stat-ing
    // every file in it, which has no business competing with startup.
    SchedulerBinding.instance.addPostFrameCallback((_) => unawaited(sweep()));
  }

  static Future<Directory?> _directory() {
    return _dirFuture ??= () async {
      try {
        final base = await getApplicationCacheDirectory();
        final dir = Directory('${base.path}/$_dirName');
        if (!await dir.exists()) await dir.create(recursive: true);
        return _dir = dir;
      } catch (e) {
        debugLog('dBug/photo_cache: no cache directory: $e');
        return null;
      }
    }();
  }

  /// The bytes for [photoRef] if they are on disk and not past [maxAge].
  static Future<Uint8List?> read(String photoRef) async {
    try {
      final dir = _dir ?? await _directory();
      if (dir == null) return null;

      final file = File('${dir.path}/${fileNameFor(photoRef)}');
      if (!await file.exists()) return null;

      // An entry that outlived the window is treated as absent and removed,
      // so a photo nobody re-requests still goes away without a sweep.
      final age = DateTime.now().difference(await file.lastModified());
      if (age > maxAge) {
        unawaited(file.delete().catchError((_) => file));
        return null;
      }

      return await file.readAsBytes();
    } catch (e) {
      return null;
    }
  }

  static Future<void> write(String photoRef, Uint8List bytes) async {
    try {
      final dir = _dir ?? await _directory();
      if (dir == null) return;

      // Write beside the target and rename, so a kill mid-write cannot leave a
      // truncated file that would later decode as a corrupt image.
      final target = File('${dir.path}/${fileNameFor(photoRef)}');
      final temp = File('${target.path}.part');
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(target.path);
    } catch (e) {
      debugLog('dBug/photo_cache: could not persist photo: $e');
    }
  }

  /// Drops entries past [maxAge], then the oldest of what remains until the
  /// directory fits in [maxBytes]. Safe to call at any time.
  ///
  /// [olderThan] and [maxTotalBytes] exist so a test can exercise the policy
  /// without waiting a fortnight or writing eighty megabytes.
  static Future<void> sweep({Duration? olderThan, int? maxTotalBytes}) async {
    final ageLimit = olderThan ?? maxAge;
    final byteLimit = maxTotalBytes ?? maxBytes;
    try {
      final dir = _dir ?? await _directory();
      if (dir == null) return;

      final now = DateTime.now();
      final surviving = <({File file, DateTime modified, int size})>[];
      var total = 0;

      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        try {
          final stat = await entity.stat();
          // Abandoned partial writes are never useful.
          if (entity.path.endsWith('.part') ||
              now.difference(stat.modified) > ageLimit) {
            await entity.delete();
            continue;
          }
          surviving.add(
              (file: entity, modified: stat.modified, size: stat.size));
          total += stat.size;
        } catch (_) {
          // A file that vanished under us, or that we cannot stat, is not
          // worth failing the sweep over.
        }
      }

      if (total <= byteLimit) return;

      surviving.sort((a, b) => a.modified.compareTo(b.modified));
      for (final entry in surviving) {
        if (total <= byteLimit) break;
        try {
          await entry.file.delete();
          total -= entry.size;
        } catch (_) {
          // Ditto.
        }
      }
    } catch (e) {
      debugLog('dBug/photo_cache: sweep failed: $e');
    }
  }

  /// Remove everything. Not used by the app; here for a settings-style reset
  /// and for tests.
  static Future<void> clear() async {
    try {
      final dir = _dir ?? await _directory();
      if (dir == null) return;
      if (await dir.exists()) await dir.delete(recursive: true);
      _dir = null;
      _dirFuture = null;
    } catch (e) {
      debugLog('dBug/photo_cache: clear failed: $e');
    }
  }

  /// Point the cache at [dir] instead of asking path_provider, so the real
  /// read/write/sweep behaviour can be tested against actual files without
  /// standing up a plugin mock.
  @visibleForTesting
  static void useDirectoryForTesting(Directory? dir) {
    _dir = dir;
    _dirFuture = dir == null ? null : Future<Directory?>.value(dir);
  }

  /// A filesystem-safe, collision-resistant name for [photoRef].
  ///
  /// Places photo references are ~200 characters of path, well past the 255
  /// byte filename limit once escaped, so the name is hashed. FNV-1a over two
  /// 32-bit lanes rather than [Object.hashCode], which carries no guarantee of
  /// being stable across runs — a cache filename has to be.
  @visibleForTesting
  static String fileNameFor(String photoRef) {
    var h1 = 0x811c9dc5;
    var h2 = 0x01000193;
    for (final byte in utf8.encode(photoRef)) {
      h1 = ((h1 ^ byte) * 0x01000193) & 0xFFFFFFFF;
      h2 = ((h2 ^ byte) * 0x811c9dc5) & 0xFFFFFFFF;
    }
    final hash = h1.toRadixString(16).padLeft(8, '0') +
        h2.toRadixString(16).padLeft(8, '0');
    return '${hash}_${photoRef.length}';
  }
}
