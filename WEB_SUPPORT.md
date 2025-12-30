# Web Support for dart_unrar

This document outlines the approach for adding web support to the dart_unrar package by compiling the UnRAR C++ library to WebAssembly (WASM).

## Overview

The dart_unrar package currently uses Dart FFI to interface with native C++ UnRAR library compiled for desktop/mobile platforms. To support web browsers, we need to:

1. Compile the UnRAR C++ code to WebAssembly using Emscripten
2. Create web-specific bindings using `dart:js_interop` or `package:web`
3. Implement platform detection to use FFI on native and WASM on web
4. Ensure API compatibility across platforms

## Technical Approach

### 1. Emscripten Compilation

Emscripten is a complete compiler toolchain to WebAssembly, using LLVM. It can compile C/C++ code to WebAssembly that runs in browsers.

#### Build Configuration

Create a build script or Makefile that uses Emscripten to compile all UnRAR C++ sources:

```bash
emcc -O3 \
  -s WASM=1 \
  -s EXPORTED_FUNCTIONS='["_RAROpenArchive","_RARCloseArchive","_RARReadHeader","_RARProcessFile","_RARSetPassword"]' \
  -s EXPORTED_RUNTIME_METHODS='["ccall","cwrap","getValue","setValue"]' \
  -s ALLOW_MEMORY_GROWTH=1 \
  -s MODULARIZE=1 \
  -s EXPORT_NAME='UnrarModule' \
  -DRARDLL \
  -D_FILE_OFFSET_BITS=64 \
  -D_LARGEFILE_SOURCE \
  -DRAR_SMP \
  -std=c++11 \
  third_party/unrar/*.cpp \
  -o lib/src/unrar.js
```

Key flags:
- `-s WASM=1`: Enable WebAssembly output
- `-s EXPORTED_FUNCTIONS`: List of C++ functions to expose
- `-s MODULARIZE=1`: Create a module that can be imported
- `-s ALLOW_MEMORY_GROWTH=1`: Allow dynamic memory allocation
- `-DRARDLL`: Build as library (same as native build)

### 2. Platform Detection

Use conditional imports to load the appropriate implementation:

```dart
// lib/src/unrar_extractor.dart
export 'unrar_extractor_stub.dart'
    if (dart.library.io) 'unrar_extractor_io.dart'
    if (dart.library.js_interop) 'unrar_extractor_web.dart';
```

### 3. Web Implementation

Create a web-specific implementation that:
- Loads the WASM module
- Calls WASM functions via JS interop
- Manages memory for strings and buffers
- Implements the same API as the FFI version

### 4. File System Considerations

Web browsers don't have direct file system access. Options:
- Use File API to read RAR files uploaded by users
- Support extracting to in-memory buffers (already supported via `extractFile`)
- Consider using OPFS (Origin Private File System) for temporary extraction

## Implementation Steps

1. Install Emscripten toolchain
2. Create build script for WASM compilation
3. Generate WASM binaries
4. Implement web-specific UnrarExtractor
5. Add platform-conditional exports
6. Update examples and documentation
7. Add web-specific tests

## Dependencies

### Native (existing)
- `ffi`: ^2.1.0
- `native_toolchain_c`: ^0.17.4

### Web (new)
- `web`: ^1.0.0 or `package:js`
- Build tooling for WASM generation

## Limitations on Web

1. **File System Access**: Limited to File API and in-memory operations
2. **Performance**: WASM may be slower than native for some operations
3. **Memory**: Large archives may hit browser memory limits
4. **Threading**: Web Workers needed for true parallelism (RAR_SMP may not work)

## Testing Strategy

1. Unit tests for WASM bindings
2. Integration tests with sample RAR files
3. Browser-based manual testing
4. Performance benchmarks comparing native vs WASM

## References

- [Emscripten Documentation](https://emscripten.org/docs/getting_started/downloads.html)
- [Dart JS Interop](https://dart.dev/web/js-interop)
- [UnRAR DLL API](third_party/unrar/dll.hpp)
- [WebAssembly File System Access](https://developer.mozilla.org/en-US/docs/Web/API/File_System_Access_API)
