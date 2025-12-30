# Quick Start Guide for Web Support

This guide provides quick instructions for getting started with web support in dart_unrar.

## For Users (Consuming the Package)

### Prerequisites
- Dart SDK >= 3.10.0
- For web: Emscripten SDK installed and configured

### Installation

Add to your `pubspec.yaml`:
```yaml
dependencies:
  unrar: ^0.2.0
```

### Building for Web

1. **Install Emscripten** (one-time setup):
   ```bash
   git clone https://github.com/emscripten-core/emsdk.git ~/emsdk
   cd ~/emsdk
   ./emsdk install latest
   ./emsdk activate latest
   source ./emsdk_env.sh
   ```

2. **Build WASM module** (in the package directory):
   ```bash
   cd path/to/unrar/package
   ./build_wasm.sh
   ```

3. **Use in your web app**:
   ```dart
   import 'package:unrar/unrar.dart';
   
   void main() async {
     final extractor = UnrarExtractor();
     
     // Note: Methods are async on web
     final files = await extractor.listFiles('/archive.rar');
     for (final file in files) {
       print('${file.name}: ${file.size} bytes');
     }
   }
   ```

### Platform Detection

The package automatically uses the correct implementation:
- **Native platforms** (Windows, macOS, Linux): Uses FFI
- **Web platform**: Uses WebAssembly
- **Other platforms**: Throws `UnsupportedError`

## For Developers (Contributing to Web Support)

### Current Status

✅ **Architecture**: Platform-conditional structure is complete
✅ **Build System**: Emscripten build script is ready
✅ **Documentation**: Comprehensive guides available
⏳ **Bindings**: JS interop needs completion
⏳ **Testing**: Web-specific tests needed

### Quick Development Setup

1. **Clone the repository**:
   ```bash
   git clone https://github.com/Maistho/dart_unrar.git
   cd dart_unrar
   ```

2. **Install Emscripten**:
   ```bash
   # Follow instructions from Prerequisites section above
   ```

3. **Build WASM module**:
   ```bash
   ./build_wasm.sh
   ```

4. **Run web example**:
   ```bash
   cd example/web
   dart run webdev serve
   # Open browser to http://localhost:8080
   ```

### Key Files to Modify

For completing web support, focus on these files:

1. **`lib/src/unrar_extractor_web.dart`**
   - Implement JS interop bindings
   - Complete WASM function calls
   - Add file loading helpers

2. **`example/web/main.dart`**
   - Complete file upload handling
   - Implement VFS loading
   - Test all features

3. **`test/unrar_web_test.dart`** (create new)
   - Add browser-based tests
   - Test WASM module loading
   - Verify all operations

### Implementation Checklist

Use `IMPLEMENTATION.md` for detailed steps. Quick checklist:

- [ ] Complete `_ensureInitialized()` in web implementation
- [ ] Implement WASM function bindings (RAROpenArchive, etc.)
- [ ] Add memory management helpers (malloc, free, string conversion)
- [ ] Implement structure marshaling (RAROpenArchiveData, RARHeaderData)
- [ ] Add file loading into Emscripten FS
- [ ] Implement `listFiles()`
- [ ] Implement `extractAll()`
- [ ] Implement `extractFile()`
- [ ] Implement `testArchive()`
- [ ] Add error handling and cleanup
- [ ] Write tests
- [ ] Update documentation

### Testing

```bash
# Run all tests
dart test

# Run web-specific tests (requires Chrome)
dart test -p chrome test/unrar_web_test.dart

# Run example
cd example/web
dart run webdev serve
```

### Debugging Tips

1. **WASM not loading**: Check browser console for errors
2. **Module exports**: Verify `build_wasm.sh` EXPORTED_FUNCTIONS
3. **Memory errors**: Ensure proper malloc/free pairing
4. **String conversion**: Check UTF-8 encoding/decoding
5. **Browser compatibility**: Test in multiple browsers

### Resources

- **Implementation Guide**: See `IMPLEMENTATION.md`
- **Technical Overview**: See `WEB_SUPPORT.md`
- **Emscripten Docs**: https://emscripten.org/docs/
- **Dart JS Interop**: https://dart.dev/web/js-interop

## Common Issues

### Issue: "emcc: command not found"
**Solution**: Activate Emscripten environment:
```bash
source ~/emsdk/emsdk_env.sh
```

### Issue: WASM module fails to load
**Solution**: 
1. Check that `unrar.js` and `unrar.wasm` exist in `lib/src/wasm/`
2. Verify build completed without errors
3. Check browser console for specific error messages

### Issue: "UnimplementedError" on web
**Solution**: The web bindings are not complete yet. See `IMPLEMENTATION.md` for next steps.

### Issue: Different API (async vs sync)
**Solution**: The web implementation needs async methods due to WASM loading. This may require API changes across all platforms for consistency.

## Getting Help

- Check existing documentation: `WEB_SUPPORT.md`, `IMPLEMENTATION.md`
- Review example code: `example/web/main.dart`
- Open an issue on GitHub with details about your setup
- Include browser console logs and error messages

## Contributing

We welcome contributions! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Update documentation
6. Submit a pull request

Focus areas:
- Complete JS interop bindings
- Add comprehensive tests
- Improve error handling
- Optimize performance
- Enhance documentation
- Add more examples

## Next Steps

1. **For Users**: Wait for web support to be completed, or help by testing and providing feedback
2. **For Developers**: Pick a task from `IMPLEMENTATION.md` and start contributing!

Thank you for your interest in dart_unrar web support! 🚀
