# unrar

A Dart FFI package for extracting RAR archives using the official UnRAR library from RARLab.

## Features

- Extract RAR archives (RAR4 and RAR5 formats)
- List files in RAR archives
- Extract to memory or disk
- Native performance using FFI
- Cross-platform support (Windows, macOS, Linux)
- Uses Dart 3.10 build hooks for automatic compilation

## Usage

```dart
import 'package:unrar/unrar.dart';

void main() {
  final extractor = UnrarExtractor();

  // List files in archive
  final files = extractor.listFiles('archive.rar');
  for (final file in files) {
    print('${file.name}: ${file.size} bytes');
  }

  // Extract all files
  extractor.extractAll('archive.rar', 'output_dir/');

  // Extract specific file
  final data = extractor.extractFile('archive.rar', 'file.txt');
}
```

## License

This package uses the UnRAR library which has its own license terms. Please see the UnRAR license for details on usage restrictions.
