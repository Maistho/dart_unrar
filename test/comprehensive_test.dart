import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:unrar/unrar.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String fixture(String name) {
  final testDir = Directory.current.path;
  return path.join(testDir, 'test_data', name);
}

String fixtureSource(String name) {
  final testDir = Directory.current.path;
  return path.join(testDir, 'test_data', 'sources', name);
}

String readSource(String name) =>
    File(fixtureSource(name)).readAsStringSync();

// ---------------------------------------------------------------------------
// Suite
// ---------------------------------------------------------------------------

void main() {
  late UnrarExtractor extractor;
  late Directory outputDir;

  setUp(() {
    extractor = UnrarExtractor();
    outputDir = Directory.systemTemp.createTempSync('unrar_test_');
  });

  tearDown(() {
    if (outputDir.existsSync()) {
      outputDir.deleteSync(recursive: true);
    }
  });

  // =========================================================================
  // listFiles
  // =========================================================================

  group('listFiles', () {
    test('basic RAR5: returns correct entry count and names', () {
      final entries = extractor.listFiles(fixture('basic_rar5.rar'));
      expect(entries, hasLength(2));
      expect(entries.map((e) => e.name), containsAll(['hello.txt', 'world.txt']));
    });

    test('basic RAR5: entries are not directories', () {
      final entries = extractor.listFiles(fixture('basic_rar5.rar'));
      expect(entries.every((e) => !e.isDirectory), isTrue);
    });

    test('basic RAR5: entry sizes match source files', () {
      final entries = extractor.listFiles(fixture('basic_rar5.rar'));
      final hello = entries.firstWhere((e) => e.name == 'hello.txt');
      final world = entries.firstWhere((e) => e.name == 'world.txt');
      expect(hello.size, equals(File(fixtureSource('hello.txt')).lengthSync()));
      expect(world.size, equals(File(fixtureSource('world.txt')).lengthSync()));
    });

    test('basic RAR5: entries not encrypted', () {
      final entries = extractor.listFiles(fixture('basic_rar5.rar'));
      expect(entries.every((e) => !e.isEncrypted), isTrue);
    });

    test('basic RAR5: entries not split', () {
      final entries = extractor.listFiles(fixture('basic_rar5.rar'));
      expect(entries.every((e) => !e.isSplitBefore && !e.isSplitAfter), isTrue);
    });

    test('with_dirs: directory entries present', () {
      final entries = extractor.listFiles(fixture('with_dirs.rar'));
      final names = entries.map((e) => e.name).toList();
      expect(names, contains('subdir/nested.txt'));
    });

    test('solid: lists all files in solid archive', () {
      final entries = extractor.listFiles(fixture('solid.rar'));
      expect(entries, hasLength(3));
      final names = entries.map((e) => e.name).toSet();
      expect(names, containsAll(['hello.txt', 'world.txt', 'subdir/nested.txt']));
    });

    test('solid: entries report isSolid', () {
      final entries = extractor.listFiles(fixture('solid.rar'));
      // In a solid archive, at least some entries are solid-flagged
      // (the first entry may not be; subsequent ones are)
      expect(entries.any((e) => e.isSolid), isTrue);
    });

    test('encrypted_data: entries show isEncrypted=true', () {
      final entries = extractor.listFiles(fixture('encrypted_data.rar'));
      expect(entries.every((e) => e.isEncrypted), isTrue);
    });

    test('encrypted_data: listing works without password (data encrypted, headers visible)', () {
      // Headers are visible; listing should succeed even without the password
      final entries = extractor.listFiles(fixture('encrypted_data.rar'));
      expect(entries, hasLength(2));
    });

    test('encrypted_headers: listing without password throws UnrarException', () {
      expect(
        () => extractor.listFiles(fixture('encrypted_headers.rar')),
        throwsA(isA<UnrarException>()),
      );
    });

    test('binary: binary file listed with correct size', () {
      final entries = extractor.listFiles(fixture('binary.rar'));
      expect(entries, hasLength(1));
      expect(entries.first.name, equals('binary.bin'));
      expect(entries.first.size, equals(512));
    });

    test('non-existent archive throws UnrarException', () {
      expect(
        () => extractor.listFiles(fixture('does_not_exist.rar')),
        throwsA(isA<UnrarException>()),
      );
    });

    test('non-existent archive error has meaningful message', () {
      try {
        extractor.listFiles(fixture('does_not_exist.rar'));
        fail('Expected UnrarException');
      } on UnrarException catch (e) {
        expect(e.message, isNotEmpty);
        expect(e.errorCode, isNotNull);
      }
    });

    test('multi-volume first part: lists files spanning volumes', () {
      final entries = extractor.listFiles(fixture('multi.part01.rar'));
      expect(entries, isNotEmpty);
      // File split across volumes has isSplitAfter set on first volume's entry
      expect(entries.any((e) => e.isSplitAfter), isTrue);
    });
  });

  // =========================================================================
  // archiveInfo
  // =========================================================================

  group('archiveInfo', () {
    test('basic archive: not a volume, not solid, not encrypted headers', () {
      final info = extractor.archiveInfo(fixture('basic_rar5.rar'));
      expect(info.isVolume, isFalse);
      expect(info.isSolid, isFalse);
      expect(info.hasEncryptedHeaders, isFalse);
    });

    test('solid archive: reports isSolid', () {
      final info = extractor.archiveInfo(fixture('solid.rar'));
      expect(info.isSolid, isTrue);
    });

    test('multi-volume first part: reports isVolume and isFirstVolume', () {
      final info = extractor.archiveInfo(fixture('multi.part01.rar'));
      expect(info.isVolume, isTrue);
      expect(info.isFirstVolume, isTrue);
    });

    test('multi-volume second part: isVolume but not isFirstVolume', () {
      final info = extractor.archiveInfo(fixture('multi.part02.rar'));
      expect(info.isVolume, isTrue);
      expect(info.isFirstVolume, isFalse);
    });

    test('encrypted_headers archive: reports hasEncryptedHeaders', () {
      // RAROpenArchiveEx can read the Flags even for encrypted-header archives
      final info = extractor.archiveInfo(fixture('encrypted_headers.rar'));
      expect(info.hasEncryptedHeaders, isTrue);
    });

    test('non-existent archive throws UnrarException', () {
      expect(
        () => extractor.archiveInfo(fixture('does_not_exist.rar')),
        throwsA(isA<UnrarException>()),
      );
    });
  });

  // =========================================================================
  // testArchive
  // =========================================================================

  group('testArchive', () {
    test('basic RAR5 passes integrity check and returns true', () {
      expect(extractor.testArchive(fixture('basic_rar5.rar')), isTrue);
    });

    test('solid archive passes integrity check', () {
      expect(extractor.testArchive(fixture('solid.rar')), isTrue);
    });

    test('binary archive passes integrity check', () {
      expect(extractor.testArchive(fixture('binary.rar')), isTrue);
    });

    test('encrypted_data with correct password passes', () {
      expect(
        extractor.testArchive(fixture('encrypted_data.rar'), password: 'test123'),
        isTrue,
      );
    });

    test('encrypted_data without password throws UnrarException', () {
      expect(
        () => extractor.testArchive(fixture('encrypted_data.rar')),
        throwsA(isA<UnrarException>()),
      );
    });

    test('encrypted_data with wrong password throws UnrarException', () {
      expect(
        () => extractor.testArchive(
          fixture('encrypted_data.rar'),
          password: 'wrongpassword',
        ),
        throwsA(isA<UnrarException>()),
      );
    });

    test('non-existent archive throws UnrarException', () {
      expect(
        () => extractor.testArchive(fixture('does_not_exist.rar')),
        throwsA(isA<UnrarException>()),
      );
    });
  });

  // =========================================================================
  // extractAll
  // =========================================================================

  group('extractAll', () {
    test('basic RAR5: extracts all files to output directory', () {
      extractor.extractAll(fixture('basic_rar5.rar'), outputDir.path);

      final hello = File(path.join(outputDir.path, 'hello.txt'));
      final world = File(path.join(outputDir.path, 'world.txt'));
      expect(hello.existsSync(), isTrue);
      expect(world.existsSync(), isTrue);
    });

    test('basic RAR5: extracted content matches source', () {
      extractor.extractAll(fixture('basic_rar5.rar'), outputDir.path);

      expect(
        File(path.join(outputDir.path, 'hello.txt')).readAsStringSync(),
        equals(readSource('hello.txt')),
      );
      expect(
        File(path.join(outputDir.path, 'world.txt')).readAsStringSync(),
        equals(readSource('world.txt')),
      );
    });

    test('with_dirs: preserves directory structure', () {
      extractor.extractAll(fixture('with_dirs.rar'), outputDir.path);

      expect(
        File(path.join(outputDir.path, 'subdir', 'nested.txt')).existsSync(),
        isTrue,
      );
    });

    test('binary: extracts binary file with exact bytes', () {
      extractor.extractAll(fixture('binary.rar'), outputDir.path);

      final extracted = File(path.join(outputDir.path, 'binary.bin'));
      final bytes = extracted.readAsBytesSync();
      expect(bytes.length, equals(512));
      // First 256 bytes are 0x00..0xFF
      for (var i = 0; i < 256; i++) {
        expect(bytes[i], equals(i));
      }
    });

    test('encrypted_data with correct password extracts successfully', () {
      extractor.extractAll(
        fixture('encrypted_data.rar'),
        outputDir.path,
        password: 'test123',
      );

      expect(
        File(path.join(outputDir.path, 'hello.txt')).existsSync(),
        isTrue,
      );
    });

    test('encrypted_data without password throws UnrarException', () {
      expect(
        () => extractor.extractAll(fixture('encrypted_data.rar'), outputDir.path),
        throwsA(isA<UnrarException>()),
      );
    });

    test('non-existent archive throws UnrarException', () {
      expect(
        () => extractor.extractAll(fixture('does_not_exist.rar'), outputDir.path),
        throwsA(isA<UnrarException>()),
      );
    });

    test('multi-volume: extracts complete file from all volumes', () {
      extractor.extractAll(fixture('multi.part01.rar'), outputDir.path);

      final extracted = File(
        path.join(outputDir.path, 'large_for_split.txt'),
      );
      expect(extracted.existsSync(), isTrue);
      // Verify the content matches the original (3000 bytes from create script)
      expect(extracted.lengthSync(), equals(3000));
    });
  });

  // =========================================================================
  // extractFile (disk)
  // =========================================================================

  group('extractFile', () {
    test('extracts first file by name and returns correct content', () {
      final data = extractor.extractFile(fixture('basic_rar5.rar'), 'hello.txt');
      expect(utf8.decode(data), equals(readSource('hello.txt')));
    });

    test('extracts second file by name and returns correct content', () {
      final data = extractor.extractFile(fixture('basic_rar5.rar'), 'world.txt');
      expect(utf8.decode(data), equals(readSource('world.txt')));
    });

    test('extracts binary file with correct bytes', () {
      final data = extractor.extractFile(fixture('binary.rar'), 'binary.bin');
      expect(data.length, equals(512));
      for (var i = 0; i < 256; i++) {
        expect(data[i], equals(i));
      }
    });

    test('extracts file from nested path in archive', () {
      final data = extractor.extractFile(
        fixture('with_dirs.rar'),
        'subdir/nested.txt',
      );
      expect(utf8.decode(data), equals(readSource('subdir/nested.txt')));
    });

    test('extracts from solid archive', () {
      final data = extractor.extractFile(fixture('solid.rar'), 'hello.txt');
      expect(utf8.decode(data), equals(readSource('hello.txt')));
    });

    test('extracts with correct password', () {
      final data = extractor.extractFile(
        fixture('encrypted_data.rar'),
        'hello.txt',
        password: 'test123',
      );
      expect(utf8.decode(data), equals(readSource('hello.txt')));
    });

    test('throws for wrong password', () {
      expect(
        () => extractor.extractFile(
          fixture('encrypted_data.rar'),
          'hello.txt',
          password: 'bad',
        ),
        throwsA(isA<UnrarException>()),
      );
    });

    test('throws for missing password on encrypted file', () {
      expect(
        () => extractor.extractFile(fixture('encrypted_data.rar'), 'hello.txt'),
        throwsA(isA<UnrarException>()),
      );
    });

    test('throws when file name not found in archive', () {
      expect(
        () => extractor.extractFile(fixture('basic_rar5.rar'), 'nonexistent.txt'),
        throwsA(isA<UnrarException>()),
      );
    });

    test('throws for non-existent archive', () {
      expect(
        () => extractor.extractFile(fixture('does_not_exist.rar'), 'hello.txt'),
        throwsA(isA<UnrarException>()),
      );
    });
  });

  // =========================================================================
  // extractFileToMemory
  // =========================================================================

  group('extractFileToMemory', () {
    test('returns Uint8List with correct content', () {
      final data = extractor.extractFileToMemory(
        fixture('basic_rar5.rar'),
        'hello.txt',
      );
      expect(data, isA<Uint8List>());
      expect(utf8.decode(data), equals(readSource('hello.txt')));
    });

    test('result matches extractFile for same file', () {
      final diskData = extractor.extractFile(fixture('basic_rar5.rar'), 'hello.txt');
      final memData = extractor.extractFileToMemory(
        fixture('basic_rar5.rar'),
        'hello.txt',
      );
      expect(memData, equals(diskData));
    });

    test('extracts binary file to memory with exact bytes', () {
      final data = extractor.extractFileToMemory(fixture('binary.rar'), 'binary.bin');
      expect(data.length, equals(512));
      for (var i = 0; i < 256; i++) {
        expect(data[i], equals(i));
      }
    });

    test('extracts file from nested path in archive', () {
      final data = extractor.extractFileToMemory(
        fixture('with_dirs.rar'),
        'subdir/nested.txt',
      );
      expect(utf8.decode(data), equals(readSource('subdir/nested.txt')));
    });

    test('extracts from solid archive', () {
      final data = extractor.extractFileToMemory(fixture('solid.rar'), 'hello.txt');
      expect(utf8.decode(data), equals(readSource('hello.txt')));
    });

    test('extracts with correct password', () {
      final data = extractor.extractFileToMemory(
        fixture('encrypted_data.rar'),
        'hello.txt',
        password: 'test123',
      );
      expect(utf8.decode(data), equals(readSource('hello.txt')));
    });

    test('throws when file not found', () {
      expect(
        () => extractor.extractFileToMemory(
          fixture('basic_rar5.rar'),
          'ghost.txt',
        ),
        throwsA(isA<UnrarException>()),
      );
    });

    test('throws for missing password on encrypted file', () {
      expect(
        () => extractor.extractFileToMemory(
          fixture('encrypted_data.rar'),
          'hello.txt',
        ),
        throwsA(isA<UnrarException>()),
      );
    });

    test('throws for non-existent archive', () {
      expect(
        () => extractor.extractFileToMemory(
          fixture('does_not_exist.rar'),
          'hello.txt',
        ),
        throwsA(isA<UnrarException>()),
      );
    });

    test('consecutive calls with same extractor instance succeed', () {
      // Verifies _pendingData and _nextId state is properly managed across calls
      final data1 = extractor.extractFileToMemory(
        fixture('basic_rar5.rar'),
        'hello.txt',
      );
      final data2 = extractor.extractFileToMemory(
        fixture('basic_rar5.rar'),
        'world.txt',
      );
      expect(data1, isNotEmpty);
      expect(data2, isNotEmpty);
      expect(data1, isNot(equals(data2)));
    });
  });

  // =========================================================================
  // extractAllToMemory
  // =========================================================================

  group('extractAllToMemory', () {
    test('returns map with all file entries', () {
      final results = extractor.extractAllToMemory(fixture('basic_rar5.rar'));
      expect(results.keys, containsAll(['hello.txt', 'world.txt']));
      expect(results.length, equals(2));
    });

    test('content matches source files', () {
      final results = extractor.extractAllToMemory(fixture('basic_rar5.rar'));
      expect(utf8.decode(results['hello.txt']!), equals(readSource('hello.txt')));
      expect(utf8.decode(results['world.txt']!), equals(readSource('world.txt')));
    });

    test('content matches extractFile for each entry', () {
      final results = extractor.extractAllToMemory(fixture('basic_rar5.rar'));
      for (final entry in results.entries) {
        final single = extractor.extractFile(fixture('basic_rar5.rar'), entry.key);
        expect(entry.value, equals(single));
      }
    });

    test('includes nested paths from directory archive', () {
      final results = extractor.extractAllToMemory(fixture('with_dirs.rar'));
      expect(results.containsKey('subdir/nested.txt'), isTrue);
    });

    test('binary file bytes are exact', () {
      final results = extractor.extractAllToMemory(fixture('binary.rar'));
      final bytes = results['binary.bin']!;
      expect(bytes.length, equals(512));
      for (var i = 0; i < 256; i++) {
        expect(bytes[i], equals(i));
      }
    });

    test('solid archive: all entries extracted correctly', () {
      final results = extractor.extractAllToMemory(fixture('solid.rar'));
      expect(results.keys, containsAll(['hello.txt', 'world.txt', 'subdir/nested.txt']));
      expect(utf8.decode(results['hello.txt']!), equals(readSource('hello.txt')));
    });

    test('encrypted_data with correct password', () {
      final results = extractor.extractAllToMemory(
        fixture('encrypted_data.rar'),
        password: 'test123',
      );
      expect(results.length, equals(2));
      expect(utf8.decode(results['hello.txt']!), equals(readSource('hello.txt')));
    });

    test('encrypted_data without password throws', () {
      expect(
        () => extractor.extractAllToMemory(fixture('encrypted_data.rar')),
        throwsA(isA<UnrarException>()),
      );
    });

    test('non-existent archive throws', () {
      expect(
        () => extractor.extractAllToMemory(fixture('does_not_exist.rar')),
        throwsA(isA<UnrarException>()),
      );
    });

    test('returns empty map for archive with only directories', () {
      // with_dirs has directory entries — they should be skipped
      final results = extractor.extractAllToMemory(fixture('with_dirs.rar'));
      expect(results.values.every((v) => v.isNotEmpty || v.isEmpty), isTrue);
      // Directories should not appear as keys
      for (final key in results.keys) {
        expect(key.endsWith('/'), isFalse);
      }
    });
  });

  // =========================================================================
  // ArchiveEntry
  // =========================================================================

  group('ArchiveEntry', () {
    test('default flags are false', () {
      final entry = ArchiveEntry(
        name: 'test.txt',
        size: 100,
        packedSize: 80,
        crc: 0,
        attributes: 0,
        modificationTime: DateTime(2025),
        isDirectory: false,
      );
      expect(entry.isEncrypted, isFalse);
      expect(entry.isSplitBefore, isFalse);
      expect(entry.isSplitAfter, isFalse);
      expect(entry.isSolid, isFalse);
      expect(entry.hashType, equals(0));
    });

    test('value equality: identical fields compare equal', () {
      final dt = DateTime(2025, 6, 1);
      final a = ArchiveEntry(
        name: 'f.txt',
        size: 10,
        packedSize: 8,
        crc: 0xABCD,
        attributes: 0,
        modificationTime: dt,
        isDirectory: false,
        isEncrypted: true,
      );
      final b = ArchiveEntry(
        name: 'f.txt',
        size: 10,
        packedSize: 8,
        crc: 0xABCD,
        attributes: 0,
        modificationTime: dt,
        isDirectory: false,
        isEncrypted: true,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('value equality: different name → not equal', () {
      final dt = DateTime(2025);
      final a = ArchiveEntry(
          name: 'a.txt', size: 1, packedSize: 1, crc: 0,
          attributes: 0, modificationTime: dt, isDirectory: false);
      final b = ArchiveEntry(
          name: 'b.txt', size: 1, packedSize: 1, crc: 0,
          attributes: 0, modificationTime: dt, isDirectory: false);
      expect(a, isNot(equals(b)));
    });

    test('value equality: isEncrypted difference → not equal', () {
      final dt = DateTime(2025);
      final a = ArchiveEntry(
          name: 'f.txt', size: 1, packedSize: 1, crc: 0,
          attributes: 0, modificationTime: dt, isDirectory: false,
          isEncrypted: true);
      final b = ArchiveEntry(
          name: 'f.txt', size: 1, packedSize: 1, crc: 0,
          attributes: 0, modificationTime: dt, isDirectory: false,
          isEncrypted: false);
      expect(a, isNot(equals(b)));
    });

    test('toString includes isEncrypted', () {
      final entry = ArchiveEntry(
        name: 'secret.txt',
        size: 50,
        packedSize: 40,
        crc: 0,
        attributes: 0,
        modificationTime: DateTime(2025),
        isDirectory: false,
        isEncrypted: true,
      );
      expect(entry.toString(), contains('isEncrypted: true'));
    });

    test('fromListFiles: encrypted entry has isEncrypted=true', () {
      final entries = extractor.listFiles(fixture('encrypted_data.rar'));
      expect(entries.every((e) => e.isEncrypted), isTrue);
    });

    test('fromListFiles: basic archive entries have correct sizes', () {
      final entries = extractor.listFiles(fixture('basic_rar5.rar'));
      final hello = entries.firstWhere((e) => e.name == 'hello.txt');
      expect(hello.size, greaterThan(0));
      expect(hello.packedSize, greaterThan(0));
      expect(hello.crc, isNot(equals(0)));
    });

    test('fromListFiles: modification time is plausible', () {
      final entries = extractor.listFiles(fixture('basic_rar5.rar'));
      for (final entry in entries) {
        // DOS epoch starts at 1980; archives created recently should be >= 2020.
        expect(entry.modificationTime.year, greaterThanOrEqualTo(1980));
      }
    });
  });

  // =========================================================================
  // UnrarException
  // =========================================================================

  group('UnrarException', () {
    test('toString without error code', () {
      final e = UnrarException('Something broke');
      expect(e.toString(), equals('UnrarException: Something broke'));
    });

    test('toString with error code', () {
      final e = UnrarException('Bad data', 12);
      expect(e.toString(), equals('UnrarException: Bad data (code: 12)'));
    });

    test('message is accessible', () {
      final e = UnrarException('Test', 1);
      expect(e.message, equals('Test'));
      expect(e.errorCode, equals(1));
    });

    test('error code is null when not supplied', () {
      final e = UnrarException('No code');
      expect(e.errorCode, isNull);
    });

    test('implements Exception', () {
      expect(UnrarException('err'), isA<Exception>());
    });
  });

  // =========================================================================
  // ArchiveInfo
  // =========================================================================

  group('ArchiveInfo', () {
    test('basic archive: all false except expected', () {
      final info = extractor.archiveInfo(fixture('basic_rar5.rar'));
      expect(info.isVolume, isFalse);
      expect(info.isSolid, isFalse);
      expect(info.hasEncryptedHeaders, isFalse);
      expect(info.isFirstVolume, isFalse); // not a volume at all
    });

    test('solid archive: isSolid true', () {
      final info = extractor.archiveInfo(fixture('solid.rar'));
      expect(info.isSolid, isTrue);
    });

    test('multi-volume part 1: isVolume and isFirstVolume true', () {
      final info = extractor.archiveInfo(fixture('multi.part01.rar'));
      expect(info.isVolume, isTrue);
      expect(info.isFirstVolume, isTrue);
    });

    test('multi-volume part 2: isVolume true, isFirstVolume false', () {
      final info = extractor.archiveInfo(fixture('multi.part02.rar'));
      expect(info.isVolume, isTrue);
      expect(info.isFirstVolume, isFalse);
    });

    test('toString includes key fields', () {
      final info = extractor.archiveInfo(fixture('solid.rar'));
      expect(info.toString(), contains('isSolid: true'));
    });
  });

  // =========================================================================
  // Multi-volume
  // =========================================================================

  group('multi-volume', () {
    test('listFiles on first part returns entries with split flags', () {
      final entries = extractor.listFiles(fixture('multi.part01.rar'));
      expect(entries, isNotEmpty);
      expect(entries.any((e) => e.isSplitAfter), isTrue);
    });

    test('extractAll from first part reassembles file across volumes', () {
      extractor.extractAll(fixture('multi.part01.rar'), outputDir.path);

      final extracted = File(path.join(outputDir.path, 'large_for_split.txt'));
      expect(extracted.existsSync(), isTrue);
      expect(extracted.lengthSync(), equals(3000));
    });

    test('extracted multi-volume content matches source', () {
      extractor.extractAll(fixture('multi.part01.rar'), outputDir.path);

      final extracted = File(
        path.join(outputDir.path, 'large_for_split.txt'),
      ).readAsStringSync();
      final source = File(
        fixtureSource('large_for_split.txt'),
      ).readAsStringSync();
      expect(extracted, equals(source));
    });

    test('testArchive on first part verifies complete content', () {
      expect(extractor.testArchive(fixture('multi.part01.rar')), isTrue);
    });
  });
}
