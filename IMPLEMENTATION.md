# Next Steps for Web Support Implementation

This document outlines the remaining work needed to complete web support for the dart_unrar package.

## Current Status

✅ **Completed:**
- Platform-conditional architecture (stub/IO/web implementations)
- Emscripten build script (`build_wasm.sh`)
- Web bindings skeleton (`lib/src/unrar_extractor_web.dart`)
- Example web application (`example/web/`)
- Documentation (`WEB_SUPPORT.md`, `README.md`)
- Build artifacts configuration (`.gitignore`)

⏳ **Pending:**
- Complete WASM JavaScript interop bindings
- Implement file loading into Emscripten virtual filesystem
- Test WASM compilation and bindings
- Handle memory management for web platform
- Add web-specific tests

## Step-by-Step Completion Guide

### 1. Build the WASM Module

First, ensure you have Emscripten installed:

```bash
# Install Emscripten
git clone https://github.com/emscripten-core/emsdk.git
cd emsdk
./emsdk install latest
./emsdk activate latest
source ./emsdk_env.sh
cd ..
```

Then build the WASM module:

```bash
./build_wasm.sh
```

This generates:
- `lib/src/wasm/unrar.js`
- `lib/src/wasm/unrar.wasm`

### 2. Complete the Web Bindings

Edit `lib/src/unrar_extractor_web.dart` to implement the JavaScript interop:

```dart
// Example of calling WASM functions:
final ccall = _module!.getProperty('ccall'.toJS) as JSFunction;
final result = ccall.callAsFunction(
  _module,
  'RAROpenArchive'.toJS,  // Function name
  'number'.toJS,           // Return type
  ['number'].toJS,         // Argument types array
  [archiveDataPtr].toJS,   // Arguments array
);
```

Key functions to bind:
- `RAROpenArchive`
- `RARCloseArchive`
- `RARReadHeader`
- `RARProcessFile`
- `RARSetPassword`

### 3. Implement Virtual Filesystem Loading

Add helper methods to load files from browser File API into Emscripten FS:

```dart
// Load a file into the virtual filesystem
Future<void> loadFileIntoFS(web.File file, String virtualPath) async {
  final reader = web.FileReader();
  final completer = Completer<Uint8List>();
  
  reader.onload = ((web.Event event) {
    final data = reader.result as JSArrayBuffer;
    final bytes = data.toDart.asUint8List();
    completer.complete(bytes);
  }).toJS;
  
  reader.readAsArrayBuffer(file);
  final bytes = await completer.future;
  
  // Write to Emscripten FS
  final fs = _module!.getProperty('FS'.toJS) as JSObject;
  final writeFile = fs.getProperty('writeFile'.toJS) as JSFunction;
  writeFile.callAsFunction(
    fs,
    virtualPath.toJS,
    bytes.toJS,
  );
}
```

### 4. Handle Memory Management

Implement proper allocation/deallocation for strings and structures:

```dart
// Allocate memory
int _malloc(int size) {
  final mallocFn = _module!.getProperty('_malloc'.toJS) as JSFunction;
  return (mallocFn.callAsFunction(_module, size.toJS) as JSNumber).toDartInt;
}

// Free memory
void _free(int ptr) {
  final freeFn = _module!.getProperty('_free'.toJS) as JSFunction;
  freeFn.callAsFunction(_module, ptr.toJS);
}

// String conversion
int _stringToPtr(String str) {
  final stringToUTF8 = _module!.getProperty('stringToUTF8'.toJS) as JSFunction;
  final lengthBytesUTF8 = _module!.getProperty('lengthBytesUTF8'.toJS) as JSFunction;
  
  final len = (lengthBytesUTF8.callAsFunction(_module, str.toJS) as JSNumber).toDartInt;
  final ptr = _malloc(len + 1);
  stringToUTF8.callAsFunction(_module, str.toJS, ptr.toJS, (len + 1).toJS);
  return ptr;
}
```

### 5. Implement RAROpenArchiveData Structure

Create helper for working with the C structure in WASM memory:

```dart
class _RAROpenArchiveData {
  final int ptr;
  
  _RAROpenArchiveData(this.ptr);
  
  void setArcName(int namePtr) {
    // Write to memory at offset 0
    final setValue = _module!.getProperty('setValue'.toJS) as JSFunction;
    setValue.callAsFunction(_module, ptr.toJS, namePtr.toJS, 'i32'.toJS);
  }
  
  void setOpenMode(int mode) {
    // Write to memory at offset 4 (assuming 32-bit pointer)
    final setValue = _module!.getProperty('setValue'.toJS) as JSFunction;
    setValue.callAsFunction(_module, (ptr + 4).toJS, mode.toJS, 'i32'.toJS);
  }
  
  int getOpenResult() {
    // Read from memory at offset 8
    final getValue = _module!.getProperty('getValue'.toJS) as JSFunction;
    return (getValue.callAsFunction(_module, (ptr + 8).toJS, 'i32'.toJS) as JSNumber).toDartInt;
  }
}
```

### 6. Update Return Types

Since the web implementation is async (loading WASM), update method signatures:

Current (IO):
```dart
List<ArchiveEntry> listFiles(String archivePath)
```

Update to:
```dart
Future<List<ArchiveEntry>> listFiles(String archivePath)
```

**Note:** This would require updating the stub and may require API changes. Consider:
- Making all methods async across platforms
- Or providing separate async methods for web (`listFilesAsync`)

### 7. Add Web-Specific Tests

Create `test/unrar_web_test.dart`:

```dart
@TestOn('browser')
import 'package:test/test.dart';
import 'package:unrar/unrar.dart';

void main() {
  group('UnrarExtractor Web', () {
    late UnrarExtractor extractor;

    setUp(() {
      extractor = UnrarExtractor();
    });

    test('initializes WASM module', () async {
      // Test that module loads
      expect(() => extractor.listFiles('/test.rar'), returnsNormally);
    });

    // Add more web-specific tests
  });
}
```

Run with:
```bash
dart test -p chrome
```

### 8. Update Example Web App

Complete the file loading in `example/web/main.dart`:

```dart
void handleFile(File file) async {
  log('Loading file: ${file.name}');
  
  final reader = FileReader();
  reader.onLoadEnd.listen((event) async {
    try {
      final bytes = reader.result as ByteBuffer;
      
      // Load into WASM virtual filesystem
      await _loadIntoVFS(file.name, bytes.asUint8List());
      
      currentFilePath = '/${file.name}';
      controls.style.display = 'block';
      log('File loaded successfully', type: 'success');
    } catch (e) {
      log('Error: $e', type: 'error');
    }
  });
  
  reader.readAsArrayBuffer(file);
}

Future<void> _loadIntoVFS(String filename, Uint8List data) async {
  // Implementation depends on extractor providing a helper method
  // or direct access to the WASM FS
}
```

### 9. Performance Optimization

Consider these optimizations:
- Use worker threads for large extractions
- Implement streaming for large files
- Add progress callbacks
- Cache the WASM module

### 10. Documentation

Update documentation with:
- Browser compatibility matrix
- Performance characteristics vs native
- Memory limitations and recommendations
- Example deployments

## Testing Checklist

- [ ] WASM module builds successfully
- [ ] Module loads in browser
- [ ] Can list files from RAR archive
- [ ] Can extract files to virtual FS
- [ ] Can extract single file to memory
- [ ] Password-protected archives work
- [ ] Multi-volume archives work (if supported)
- [ ] Error handling works correctly
- [ ] Memory is properly freed
- [ ] Works in Chrome, Firefox, Safari, Edge

## Known Limitations

1. **Threading**: RAR_SMP (multithreading) may not work in WASM without Workers
2. **Memory**: Large archives limited by browser memory
3. **File System**: Virtual FS only, need to download extracted files
4. **Performance**: 2-3x slower than native is expected

## Resources

- [Emscripten Documentation](https://emscripten.org/docs/)
- [Dart JS Interop](https://dart.dev/web/js-interop)
- [WebAssembly.org](https://webassembly.org/)
- [Emscripten File System API](https://emscripten.org/docs/api_reference/Filesystem-API.html)

## Questions or Issues?

If you encounter issues:
1. Check Emscripten version compatibility
2. Verify WASM module exports are correct
3. Check browser console for errors
4. Review Emscripten build flags in `build_wasm.sh`
5. Test with minimal example first

## Contributing

PRs welcome! Please test thoroughly and update documentation.
