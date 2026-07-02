# ISSUE-001 — `ffigen` emits zero `@Native` functions despite `ffi-native:` config

**Status:** Open — fix unverified (not yet tested by running `ffigen`)

## Summary

`lib/src/unrar_bindings.dart` — the auto-generated `ffigen` bindings file —
contains only `ffi.Struct` definitions, typedefs, and constants. It has
**zero `@Native`-annotated function bindings**, even though
`pubspec.yaml`'s `ffigen:` config already sets the `ffi-native:` key, which
exists specifically to opt into generating native-asset-tied `@Native`
external functions. `third_party/unrar/dll.hpp` unconditionally declares 12
exported functions with fully resolvable C-ABI types, so this is not a case
of an unparseable header — `ffigen` is silently dropping declarations it
should be able to bind.

This gap is the direct cause of two downstream design decisions documented
elsewhere in this repo: `UnrarExtractor` hand-declares 9 functions via
`DynamicLibrary.lookupFunction` instead of relying on VM auto-resolution,
and therefore needs a manual native-library path-search loader. See
[Impact](#impact) below.

---

## Evidence

### 1. The generated file has no `@Native` functions

```
$ grep -n "@Native\|@ffi.Native" lib/src/unrar_bindings.dart
(no matches)
```

The entire ~217-line file is limited to `ffi.Struct` definitions
(`RARHeaderData`, `RAROpenArchiveDataEx`, etc.), callback typedefs
(`UNRARCALLBACKFunction`, `CHANGEVOLPROCFunction`, `PROCESSDATAPROCFunction`),
an enum (`UNRARCALLBACK_MESSAGES`), and `ERAR_*`/`RAR_*` constants. Not one
top-level `external` function exists.

### 2. The header declares functions unconditionally

`third_party/unrar/dll.hpp:172-191`:

```c
#ifdef __cplusplus
extern "C" {
#endif

HANDLE PASCAL RAROpenArchive(struct RAROpenArchiveData *ArchiveData);
HANDLE PASCAL RAROpenArchiveEx(struct RAROpenArchiveDataEx *ArchiveData);
int    PASCAL RARCloseArchive(HANDLE hArcData);
int    PASCAL RARReadHeader(HANDLE hArcData,struct RARHeaderData *HeaderData);
int    PASCAL RARReadHeaderEx(HANDLE hArcData,struct RARHeaderDataEx *HeaderData);
int    PASCAL RARProcessFile(HANDLE hArcData,int Operation,char *DestPath,char *DestName);
int    PASCAL RARProcessFileW(HANDLE hArcData,int Operation,wchar_t *DestPath,wchar_t *DestName);
void   PASCAL RARSetCallback(HANDLE hArcData,UNRARCALLBACK Callback,LPARAM UserData);
void   PASCAL RARSetChangeVolProc(HANDLE hArcData,CHANGEVOLPROC ChangeVolProc);
void   PASCAL RARSetProcessDataProc(HANDLE hArcData,PROCESSDATAPROC ProcessDataProc);
void   PASCAL RARSetPassword(HANDLE hArcData,char *Password);
int    PASCAL RARGetDllVersion();

#ifdef __cplusplus
}
#endif
```

Under the `-D_UNIX` flag already passed via `compiler-opts`, the
Windows-only macros resolve to plain, ffigen-parseable types
(`third_party/unrar/dll.hpp:42-49`):

```c
#ifdef _UNIX
#define CALLBACK
#define PASCAL
#define LONG long
#define HANDLE void *
#define LPARAM long
#define UINT unsigned int
#endif
```

So all 12 functions should present as ordinary C functions with
`void*`/`long`/`unsigned int`/pointer-to-struct parameters — nothing here
should be unparseable.

### 3. It's not stale output — `ffigen` was re-run with `ffi-native:` already set, and still produced zero functions

`ffi-native:` was added to `pubspec.yaml` in commit `a162e0d` ("add rar
7.2.3"), and `lib/src/unrar_bindings.dart` was regenerated in that **same
commit**:

```
$ git show a162e0d -- lib/src/unrar_bindings.dart
```

The diff shows only dart-format reflow changes and one struct
(`RAROpenArchiveDataEx`) becoming `ffi.Opaque` (a separate, already-tracked
`wchar_t` sizing issue — see `devdocs/Gap_analysis_dll_vs_dart.md` Gap 3 /
`devdocs/ARCH-001_unrarLib_load_order.md`). **No functions were added,
before or after.** This rules out "nobody regenerated the file since
enabling `ffi-native`" as the explanation.

### 4. Current `ffigen:` config (`pubspec.yaml`)

```yaml
ffigen:
  name: UnrarBindings
  description: FFI bindings for UnRAR
  output: "lib/src/unrar_bindings.dart"
  ffi-native:
  headers:
    entry-points:
      - "third_party/unrar/dll.hpp"
  compiler-opts:
    - "-D_UNIX"
  preamble: |
    ...
  comments:
    style: any
    length: full
```

No `language:` key. No `-x c` / `-x c++` override in `compiler-opts`.

---

## Root-cause hypothesis

Since the entry-point file is `third_party/unrar/dll.hpp` (a `.hpp`
extension) and there is no explicit language override, clang almost
certainly parses it as **C++** by default. In C++ mode, `__cplusplus` is
defined, so the 12 functions in `dll.hpp:176-187` end up wrapped inside an
`extern "C" { ... }` block — a C++-only linkage-specification construct
(`LinkageSpecDecl` in clang's AST). Structs, typedefs, and enums declared
*outside* that block are unaffected by this wrapping and parse normally,
which matches the observed symptom exactly: **everything inside
`extern "C" {}` is missing from the output; everything outside it is
present.**

This is consistent with a known class of rough edges in `ffigen`'s C++
header handling, where the declaration visitor doesn't reliably traverse
into linkage-spec-wrapped blocks depending on version/config — not a
fundamental incapability of `ffigen` to emit `@Native` functions (the
`ffi-native:` key exists and works for the general case; there's just
nothing in this header's function declarations for it to bind to once the
`extern "C"` wrapper causes them to be skipped).

---

## Possible fix (untested — needs verification)

Force clang to parse `dll.hpp` as plain C, so `__cplusplus` is never
defined and the `extern "C" {}` wrapper — along with its associated
linkage-spec AST handling — never comes into play:

```yaml
compiler-opts:
  - "-D_UNIX"
  - "-x"
  - "c"
```

With `__cplusplus` undefined, the `#ifdef __cplusplus` guards around
`extern "C" {` / `}` simply evaluate false, and the 12 functions become
ordinary top-level C declarations with no special wrapping at all.

### Verification steps (follow-up task, not yet done)

1. Add the `-x c` compiler-opts above.
2. Run `dart run ffigen`.
3. Confirm all 12 functions from `dll.hpp:176-187` appear as
   `@Native`-annotated externals in the regenerated
   `lib/src/unrar_bindings.dart`.
4. Confirm the existing struct definitions (`RARHeaderData`,
   `RAROpenArchiveData`, etc.) are unaffected — re-parsing as C should not
   change struct layout since none of them depend on C++-only features.
5. Re-run `dart test` to confirm nothing downstream breaks.
6. If successful, consider whether `unrar_extractor.dart`'s 9 hand-rolled
   `lookupFunction` declarations (lines 200-232+) could be replaced with
   the generated `@Native` functions, which would let the manual
   `DynamicLibrary` path-search loader (`ARCH-001`) be simplified or
   potentially removed in favor of VM auto-resolution.

### Fallback if `-x c` doesn't fix it

Add an explicit `functions:` include-all block to the `ffigen:` config to
rule out a symbol-filtering issue rather than a parsing issue:

```yaml
ffigen:
  functions:
    include:
      - '.*'
```

---

## Impact

- `lib/src/unrar_extractor.dart:200-232+` hand-declares 9 functions via
  `DynamicLibrary.lookupFunction` instead of using generated `@Native`
  bindings. See `devdocs/Gap_analysis_dll_vs_dart.md`, "Gap 1 — used
  functions are hand-bound, not in the generated bindings."
- Because no `@Native` function exists anywhere in the package, the Dart
  VM has nothing to auto-resolve against the code asset
  `package:unrar/unrar.dart` (registered in `hook/build.dart`). This forces
  `UnrarExtractor` to manually open a `DynamicLibrary` itself, which is why
  the multi-step native-library path-search loader exists at all. See
  `devdocs/ARCH-001_unrarLib_load_order.md`.
- If this issue is fixed, that manual loader could potentially be
  simplified or retired — but that's a separate, larger follow-up, not
  covered here.
