## 0.2.0 (In Development)

### Features
- **Web Platform Support (Experimental)**: Added foundation for WebAssembly support
  - Platform-conditional architecture (FFI for native, WASM for web)
  - Emscripten build script for compiling UnRAR C++ to WASM
  - Web bindings skeleton with JS interop
  - Example web application demonstrating file upload and extraction
  - Comprehensive documentation for web implementation

### Documentation
- Added `WEB_SUPPORT.md` - Technical overview of web support approach
- Added `IMPLEMENTATION.md` - Step-by-step guide for completing web support
- Updated `README.md` with web platform information
- Added build artifacts documentation in `lib/src/wasm/README.md`

### Technical Changes
- Refactored `UnrarExtractor` to use platform-conditional exports
- Created `unrar_extractor_io.dart` for FFI-based native implementation
- Created `unrar_extractor_web.dart` for WASM-based web implementation
- Created `unrar_extractor_stub.dart` as fallback for unsupported platforms
- Added `web` package dependency for browser APIs
- Updated `.gitignore` to exclude WASM build artifacts

### Notes
- Web support is experimental and requires completion of JS interop bindings
- WASM module must be built manually using Emscripten
- See `IMPLEMENTATION.md` for remaining implementation steps

## 0.1.2
- Fixed some linking issues

## 0.1.1
- Updated to unrar 7.2.3
- Some changes to how the dynamic lib is found
- Still quite experimental

## 0.1.0

- Initial release
- Support for listing files in RAR archives
- Support for extracting files from RAR archives
- Support for testing archive integrity
- Uses Dart 3.10 build hooks for automatic compilation
- Cross-platform support (Windows, macOS, Linux)
