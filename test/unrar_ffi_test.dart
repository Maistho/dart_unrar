import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:unrar/unrar.dart';

void main() {
  group('UnrarExtractor', () {
    late UnrarExtractor extractor;
    late String testArchivePath;
    late String outputDir;

    setUp(() {
      extractor = UnrarExtractor();
      final testDir = Directory.current.path;
      testArchivePath = path.join(testDir, 'test', 'fixtures', 'test.rar');
      outputDir = path.join(testDir, 'test', 'output');

      // Create output directory if it doesn't exist
      Directory(outputDir).createSync(recursive: true);
    });

    tearDown(() {
      // Clean up output directory after each test
      if (Directory(outputDir).existsSync()) {
        Directory(outputDir).deleteSync(recursive: true);
      }
    });

    test('listFiles returns files from archive', () {
      final files = extractor.listFiles(testArchivePath);
      expect(files, isNotEmpty);
      expect(files.length, equals(2));
      expect(files.map((e) => e.name), containsAll(['test.txt', 'file2.txt']));
      expect(files.every((e) => !e.isDirectory), isTrue);
    });

    test('testArchive validates archive successfully', () {
      expect(() => extractor.testArchive(testArchivePath), returnsNormally);
    });

    test('extractAll extracts all files', () {
      extractor.extractAll(testArchivePath, outputDir);

      final extractedFile1 = File(path.join(outputDir, 'test.txt'));
      final extractedFile2 = File(path.join(outputDir, 'file2.txt'));

      expect(extractedFile1.existsSync(), isTrue);
      expect(extractedFile2.existsSync(), isTrue);
      expect(extractedFile1.readAsStringSync(), contains('test file'));
      expect(extractedFile2.readAsStringSync(), contains('Hello from file2'));
    });

    test('extractFile returns file data', () {
      final data = extractor.extractFile(testArchivePath, 'test.txt');

      expect(data, isNotEmpty);
      final content = String.fromCharCodes(data);
      expect(content, contains('test file'));
    });

    test('listFiles throws exception for non-existent archive', () {
      expect(
        () => extractor.listFiles('nonexistent.rar'),
        throwsA(isA<UnrarException>()),
      );
    });

    test('extractAll throws exception for non-existent archive', () {
      expect(
        () => extractor.extractAll('nonexistent.rar', outputDir),
        throwsA(isA<UnrarException>()),
      );
    });

    test('testArchive throws exception for non-existent archive', () {
      expect(
        () => extractor.testArchive('nonexistent.rar'),
        throwsA(isA<UnrarException>()),
      );
    });
  });

  group('ArchiveEntry', () {
    test('toString returns correct format', () {
      final entry = ArchiveEntry(
        name: 'test.txt',
        size: 1024,
        packedSize: 512,
        crc: 0x12345678,
        attributes: 0,
        modificationTime: DateTime(2025, 1, 1),
        isDirectory: false,
      );

      expect(
        entry.toString(),
        'ArchiveEntry(name: test.txt, size: 1024, isDirectory: false)',
      );
    });
  });

  group('UnrarException', () {
    test('toString without error code', () {
      final exception = UnrarException('Test error');
      expect(exception.toString(), 'UnrarException: Test error');
    });

    test('toString with error code', () {
      final exception = UnrarException('Test error', 42);
      expect(exception.toString(), 'UnrarException: Test error (code: 42)');
    });
  });
}
