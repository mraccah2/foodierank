import 'package:flutter_test/flutter_test.dart';
import 'package:foodierank/services/photo_disk_cache.dart';

void main() {
  // A real Places photo reference: ~200 characters of path, with slashes.
  const ref =
      'places/ChIJN1t_tDeuEmsRUsoyG83frY4/photos/AeJbb3cQ9vK2mN4pR7sT1uV6wX8yZ0aB2cD4eF6gH8iJ0kL2mN4oP6qR8sT0uV2wX4yZ6aB8cD0eF2gH4iJ6kL8mN0oP2qR4sT6uV8wX0yZ2aB4cD6eF8gH0iJ2kL4mN6oP8qR0sT2uV4wX6yZ8';

  group('PhotoDiskCache.fileNameFor', () {
    test('is deterministic', () {
      // The whole point: a name derived from Object.hashCode would not be
      // guaranteed stable across runs, and the cache would never hit.
      expect(PhotoDiskCache.fileNameFor(ref), PhotoDiskCache.fileNameFor(ref));
    });

    test('is filesystem-safe', () {
      final name = PhotoDiskCache.fileNameFor(ref);
      expect(name, isNot(contains('/')));
      expect(name, isNot(contains('\\')));
      expect(name, matches(RegExp(r'^[0-9a-f]{16}_\d+$')));
    });

    test('stays well inside the filename length limit', () {
      expect(PhotoDiskCache.fileNameFor(ref).length, lessThan(64));
    });

    test('distinguishes references that differ by one character', () {
      final a = PhotoDiskCache.fileNameFor('places/abc/photos/XYZ');
      final b = PhotoDiskCache.fileNameFor('places/abc/photos/XYW');
      expect(a, isNot(b));
    });

    test('distinguishes references of different lengths', () {
      final a = PhotoDiskCache.fileNameFor('places/abc/photos/XYZ');
      final b = PhotoDiskCache.fileNameFor('places/abc/photos/XYZ0');
      expect(a, isNot(b));
    });

    test('never emits a sign, whatever the input', () {
      // Both hash lanes are masked to 32 bits so they cannot go negative and
      // produce a leading '-' in the hex.
      for (final input in [
        '',
        'a',
        ref,
        'places/${'z' * 500}/photos/x',
        'ünïcødé/photos/emoji-🍕',
      ]) {
        expect(PhotoDiskCache.fileNameFor(input), isNot(contains('-')));
      }
    });
  });

  group('PhotoDiskCache policy', () {
    test('sweeps entries after a fortnight', () {
      expect(PhotoDiskCache.maxAge, const Duration(days: 14));
    });

    test('caps the directory so a busy fortnight cannot run away', () {
      expect(PhotoDiskCache.maxBytes, greaterThan(0));
    });
  });
}
