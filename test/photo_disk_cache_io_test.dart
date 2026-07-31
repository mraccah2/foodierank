import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:foodierank/services/photo_disk_cache.dart';

/// Exercises the real file behaviour — round-trip, expiry, the size cap —
/// against a temp directory. Previously only the filename derivation and the
/// policy constants were covered, so the 14-day sweep and the byte cap had
/// never actually run.
void main() {
  late Directory dir;

  Uint8List bytes(int n, [int fill = 7]) =>
      Uint8List.fromList(List<int>.filled(n, fill));

  File fileFor(String ref) =>
      File('${dir.path}/${PhotoDiskCache.fileNameFor(ref)}');

  Future<void> backdate(String ref, Duration by) async {
    final f = fileFor(ref);
    await f.setLastModified(DateTime.now().subtract(by));
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('photo_cache_test');
    PhotoDiskCache.useDirectoryForTesting(dir);
  });

  tearDown(() async {
    PhotoDiskCache.useDirectoryForTesting(null);
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  group('round trip', () {
    test('what is written comes back', () async {
      await PhotoDiskCache.write('ref-a', bytes(32));
      expect(await PhotoDiskCache.read('ref-a'), bytes(32));
    });

    test('a photo never written reads as absent', () async {
      expect(await PhotoDiskCache.read('never-written'), isNull);
    });

    test('two photos do not collide', () async {
      await PhotoDiskCache.write('ref-a', bytes(8, 1));
      await PhotoDiskCache.write('ref-b', bytes(8, 2));
      expect(await PhotoDiskCache.read('ref-a'), bytes(8, 1));
      expect(await PhotoDiskCache.read('ref-b'), bytes(8, 2));
    });

    test('a rewrite replaces the old bytes', () async {
      await PhotoDiskCache.write('ref-a', bytes(8, 1));
      await PhotoDiskCache.write('ref-a', bytes(16, 2));
      expect(await PhotoDiskCache.read('ref-a'), bytes(16, 2));
    });

    test('writing leaves no .part file behind', () async {
      await PhotoDiskCache.write('ref-a', bytes(32));
      final leftovers = dir
          .listSync()
          .where((e) => e.path.endsWith('.part'))
          .toList();
      expect(leftovers, isEmpty);
    });
  });

  group('expiry on read', () {
    test('an entry past the window reads as absent', () async {
      await PhotoDiskCache.write('old', bytes(32));
      await backdate('old', PhotoDiskCache.maxAge + const Duration(days: 1));

      expect(await PhotoDiskCache.read('old'), isNull);
    });

    test('and is deleted, so it does not linger until a sweep', () async {
      await PhotoDiskCache.write('old', bytes(32));
      await backdate('old', PhotoDiskCache.maxAge + const Duration(days: 1));

      await PhotoDiskCache.read('old');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await fileFor('old').exists(), isFalse);
    });

    test('an entry just inside the window still reads', () async {
      await PhotoDiskCache.write('fresh', bytes(32));
      await backdate('fresh', PhotoDiskCache.maxAge - const Duration(hours: 1));

      expect(await PhotoDiskCache.read('fresh'), isNotNull);
    });
  });

  group('sweep', () {
    test('drops what is past the age limit and keeps the rest', () async {
      await PhotoDiskCache.write('old', bytes(32));
      await PhotoDiskCache.write('new', bytes(32));
      await backdate('old', const Duration(days: 30));

      await PhotoDiskCache.sweep(olderThan: const Duration(days: 14));

      expect(await fileFor('old').exists(), isFalse);
      expect(await fileFor('new').exists(), isTrue);
    });

    test('removes abandoned partial writes', () async {
      final orphan = File('${dir.path}/abandoned.part');
      await orphan.writeAsBytes(bytes(16));

      await PhotoDiskCache.sweep();

      expect(await orphan.exists(), isFalse);
    });

    test('enforces the size cap, oldest first', () async {
      // Three 1 KB entries, capped at 2 KB: the oldest must go, the two
      // newest must stay.
      await PhotoDiskCache.write('oldest', bytes(1024));
      await PhotoDiskCache.write('middle', bytes(1024));
      await PhotoDiskCache.write('newest', bytes(1024));
      await backdate('oldest', const Duration(hours: 3));
      await backdate('middle', const Duration(hours: 2));
      await backdate('newest', const Duration(hours: 1));

      await PhotoDiskCache.sweep(maxTotalBytes: 2048);

      expect(await fileFor('oldest').exists(), isFalse);
      expect(await fileFor('middle').exists(), isTrue);
      expect(await fileFor('newest').exists(), isTrue);
    });

    test('leaves everything alone when under the cap', () async {
      await PhotoDiskCache.write('a', bytes(64));
      await PhotoDiskCache.write('b', bytes(64));

      await PhotoDiskCache.sweep(maxTotalBytes: 1024 * 1024);

      expect(await fileFor('a').exists(), isTrue);
      expect(await fileFor('b').exists(), isTrue);
    });

    test('an empty directory is not an error', () async {
      await PhotoDiskCache.sweep();
      expect(await dir.exists(), isTrue);
    });
  });

  group('degradation', () {
    test('reads and writes are no-ops when there is no directory', () async {
      PhotoDiskCache.useDirectoryForTesting(Directory('/nonexistent/nope'));

      // Must not throw: the service treats a failure here as "not cached" and
      // carries on to the network.
      await PhotoDiskCache.write('x', bytes(8));
      expect(await PhotoDiskCache.read('x'), isNull);
    });
  });
}
