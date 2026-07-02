# ARCH-001 — Native `libunrar` Load Order

## Summary

`dart_unrar` builds UnRAR's C++ sources from scratch (via Dart native build
hooks) rather than depending on a system-installed `libunrar`. At runtime,
`UnrarExtractor._lib` (in [`lib/src/unrar_extractor.dart`](../lib/src/unrar_extractor.dart))
performs a manual `DynamicLibrary.open()` search across a fixed list of
candidate paths, rather than relying on the Dart VM's native-asset resolution.
This document records why, and the exact order.



**Confirmed and documented:**

- The 8-step search order is identical across macOS, Linux, and Windows **except** step 6 — the `.framework` bundle path — which is spliced in only on macOS (`Platform.isMacOS` check in code, line 111-114). Linux and Windows have no equivalent.
- Two things *do* differ per platform:
  1. **Filename** (`_libraryFileName()`): `libunrar.dylib` / `libunrar.so` / `unrar.dll`
  2. **Bare-name resolution** (step 3, `DynamicLibrary.open(libName)` with no directory): this delegates to the OS's own dynamic loader — `dyld` on macOS, `ld.so` on Linux, standard DLL search order on Windows. The Dart code doesn't control this step directly; it's inherited OS behavior.
- `native_assets.yaml`'s manifest keys follow `<os>_<arch>` (e.g. `macos_arm64`, `linux_x64`, `windows_x64`), but that's internal to `hooks_runner` — the loader only ever reads the resolved `.dart_tool/lib/<libName>` path, not the key.

> [!note]
> Confirmed via the code (`unrar_extractor.dart:96, 111-114, 179-184`)

---

## Two systems, wired together

### 1. Build — `hook/build.dart`

Invoked automatically by `dartdev`/`package:hooks_runner` on `dart build`,
`dart run`, or `dart test`. Compiles ~49 `.cpp` files from
[`third_party/unrar/`](../third_party/unrar) via `CBuilder.library` and
registers the output as code asset `package:unrar/unrar.dart`
(`assetName: '$packageName.dart'` in `hook/build.dart`).

Each build lands in a **content-hashed cache directory**:

```
.dart_tool/hooks_runner/shared/unrar/build/<hash>/libunrar.dylib
```

The hash is derived from build inputs (flags, sources, toolchain). Different
hash directories can coexist from different build configs/toolchain versions
— this is normal caching, not staleness.

### 2. Runtime manifest — `.dart_tool/native_assets.yaml`

`hooks_runner` also copies the resolved build output to a fixed, non-hashed
location and records it in a per-platform manifest:

```yaml
# .dart_tool/native_assets.yaml
native-assets:
  macos_arm64:
    package:unrar/unrar.dart:
      - absolute
      - /.../.dart_tool/lib/libunrar.dylib
```

`.dart_tool/lib/<libName>` is the canonical bundle location for JIT execution
(`dart run`, `dart test`) on the current platform/architecture.

### 3. The extractor's manual loader

This package hand-rolls its FFI bindings via `DynamicLibrary.lookupFunction`
(not `@Native` external functions tied to a code-asset ID), so the VM cannot
auto-resolve `package:unrar/unrar.dart` on its behalf. `UnrarExtractor._lib`
must open the library itself — and it knows to check the same location
`hooks_runner` populates.

**This is intentional, correct integration, not a bypass of the native-asset
system** — path #2 below is exactly where the build hooks bundle their output.

---

## Load order (all platforms)

`UnrarExtractor._lib` (`unrar_extractor.dart:88-177`) builds an ordered,
deduplicated candidate list and tries `DynamicLibrary.open()` on each in
order, stopping at the first path that both opens successfully **and** passes
the `RARGetDllVersion()` check (must be `>= RAR_DLL_VERSION`). A candidate
that opens but fails the version check throws immediately — it does not fall
through to the next candidate.

| # | Path | Notes |
|---|------|-------|
| 1 | `$UNRAR_LIBRARY_PATH` (env var) | If set to a directory, `<dir>/<libName>` is used; if set to a file, used as-is. Explicit override for CI/packaging. |
| 2 | `.dart_tool/lib/<libName>` | **Matches the hooks_runner bundle location** — the common case for `dart run` / `dart test` in a dev checkout. |
| 3 | `<libName>` (bare) | Resolved via the OS's default dynamic-loader search (cwd / library search path — see platform notes below). |
| 4 | `<exeDir>/<libName>` | Directory containing `Platform.resolvedExecutable` — the compiled/AOT executable's own directory. |
| 5 | `<exeDir>/../lib/<libName>` | Sibling `lib/` directory relative to the executable — typical for `dart compile exe` distribution layouts. |
| 6 | *(macOS only)* `<exeDir>/../Frameworks/unrar.framework/unrar` | Standard macOS `.app` bundle Frameworks convention. **Not present on Linux/Windows.** |
| 7 | `<scriptDir>/<libName>` | Only added if `Platform.script` is a `file://` URI (true for `dart run script.dart`, not for compiled binaries). |
| 8 | `<scriptDir>/../lib/<libName>` | Sibling `lib/` relative to the running script. |

Steps 6 is the only platform-conditional *insertion* — it's spliced in
between steps 5 and 7 only when `Platform.isMacOS`. All other steps run
identically on macOS, Linux, and Windows; only the **filename** (`libName`,
step below) and the OS's own dynamic-loader resolution semantics for bare
names (step 3) differ.

---

## Platform differences

### Library filename (`_libraryFileName()`, line 179-184)

| Platform | Filename |
|----------|----------|
| macOS | `libunrar.dylib` |
| Linux | `libunrar.so` |
| Windows | `unrar.dll` |
| other | throws `UnsupportedError` |

### Bare-name resolution (step 3) — OS dynamic loader semantics

When `DynamicLibrary.open(libName)` is called with no directory component,
each OS's native loader applies its own default search rules — this package
does not control or override this step:

| Platform | Bare-name resolution mechanism |
|----------|--------------------------------|
| macOS | `dyld` search: `@rpath`, `DYLD_LIBRARY_PATH`, `DYLD_FALLBACK_LIBRARY_PATH`, then standard system paths. |
| Linux | `ld.so` search: `LD_LIBRARY_PATH`, `/etc/ld.so.cache`, then default trusted paths (`/lib`, `/usr/lib`, etc.). |
| Windows | Standard DLL search order: application directory, system directories, then `PATH`. |

### macOS-only step (step 6)

The `.../Frameworks/unrar.framework/unrar` path only makes sense inside a
macOS `.app` bundle (Flutter desktop, packaged CLI apps that embed
frameworks). No equivalent step exists for Linux or Windows because neither
platform has a `.framework` bundle convention.

### `native_assets.yaml` platform keys

`hooks_runner` keys the manifest by `<os>_<arch>` (e.g. `macos_arm64`,
`macos_x64`, `linux_x64`, `windows_x64`). The **value** — the bundled
`.dart_tool/lib/<libName>` path — is what matters to the loader; the key
itself is internal to `hooks_runner`'s resolution and not read directly by
`UnrarExtractor`.

---

## Version guard, not path-ordering, is the real defense

The path search order alone does not guarantee a compatible library is
loaded — a stale system-wide `libunrar.dylib`/`.so`/`.dll` earlier in the
OS's own default search path (step 3) could shadow the correct build.
The actual safety net is the immediate post-open check:

```dart
final version = getVersion(); // RARGetDllVersion()
if (version < bindings.RAR_DLL_VERSION) {
  _dylib = null;
  throw UnrarException(
    'Loaded unrar library version $version is older than the '
    'required version ${bindings.RAR_DLL_VERSION}. '
    'Please rebuild with "dart build".',
  );
}
```

Any candidate that opens but reports a version below `RAR_DLL_VERSION`
(defined in `unrar_bindings.dart`, currently corresponds to UnRAR 7.0+)
aborts the whole search with a clear error rather than silently falling
through to try the next path. This is why step ordering is secondary —
correctness is enforced by the version check, not by hoping the "right"
path is checked first.

---

## Debugging load failures

Set `UNRAR_DEBUG=1` to get a verbose failure report listing every attempted
path, whether each file exists on disk, and any `dlopen` error message per
candidate:

```bash
UNRAR_DEBUG=1 dart test
```

## Overriding the search entirely

Set `UNRAR_LIBRARY_PATH` to force a specific library (file path) or
directory (containing `<libName>`), bypassing steps 2–8:

```bash
UNRAR_LIBRARY_PATH=/custom/path/to/libunrar.dylib dart test
```
