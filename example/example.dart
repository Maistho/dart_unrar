import 'package:unrar/unrar.dart';

void main() {
  final extractor = UnrarExtractor();

  // Example RAR file path
  final archivePath = 'example.rar';

  try {
    // List all files in the archive
    print('Files in archive:');
    final files = extractor.listFiles(archivePath);
    for (final file in files) {
      print('  ${file.name} (${file.size} bytes)');
    }

    // Extract all files to a directory
    print('\nExtracting all files...');
    extractor.extractAll(archivePath, 'output/');
    print('Extraction complete!');

    // Extract a specific file
    print('\nExtracting specific file...');
    final data = extractor.extractFile(archivePath, 'readme.txt');
    print('Extracted ${data.length} bytes');

    // Test archive integrity
    print('\nTesting archive...');
    final isValid = extractor.testArchive(archivePath);
    print('Archive is ${isValid ? "valid" : "invalid"}');
  } on UnrarException catch (e) {
    print('Error: $e');
  }
}
