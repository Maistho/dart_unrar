# unrar

A Dart FFI package for extracting RAR archives using the official UnRAR library from RARLab.

## Features

- Extract RAR archives (RAR4 and RAR5 formats)
- List files in RAR archives
- Extract to memory or disk
- Native performance using FFI
- Cross-platform support (Windows, macOS, Linux, Web)
- Uses Dart 3.10 build hooks for automatic compilation
- WebAssembly support for web browsers (experimental)

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

## Web Platform Support

**Experimental**: Web support is available through WebAssembly compilation of the UnRAR library.

### Building for Web

To use this package on the web platform, you need to compile the UnRAR C++ library to WebAssembly:

1. Install [Emscripten SDK](https://emscripten.org/docs/getting_started/downloads.html):
   ```bash
   git clone https://github.com/emscripten-core/emsdk.git
   cd emsdk
   ./emsdk install latest
   ./emsdk activate latest
   source ./emsdk_env.sh
   ```

2. Build the WASM library:
   ```bash
   ./build_wasm.sh
   ```

This will generate `lib/src/wasm/unrar.js` and `lib/src/wasm/unrar.wasm` files.

### Web-Specific Considerations

- The web implementation uses Emscripten's virtual filesystem (FS)
- File paths refer to the virtual filesystem, not actual browser files
- You'll need to load RAR files into the virtual filesystem using File API
- Extraction works within the virtual filesystem
- Use `extractFile()` to get file contents as `Uint8List` for best web compatibility

For detailed implementation information, see [WEB_SUPPORT.md](WEB_SUPPORT.md).

## License

This package uses the UnRAR library which has its own license terms. Please see the UnRAR license for details on usage restrictions.
