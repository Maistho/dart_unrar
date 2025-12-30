#!/bin/bash

# Build script for compiling UnRAR C++ library to WebAssembly using Emscripten
# This script requires Emscripten SDK to be installed and activated
# See: https://emscripten.org/docs/getting_started/downloads.html

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Building UnRAR library for WebAssembly${NC}"

# Check if emcc is available
if ! command -v emcc &> /dev/null; then
    echo -e "${RED}Error: emcc (Emscripten compiler) not found${NC}"
    echo "Please install Emscripten SDK:"
    echo "  git clone https://github.com/emscripten-core/emsdk.git"
    echo "  cd emsdk"
    echo "  ./emsdk install latest"
    echo "  ./emsdk activate latest"
    echo "  source ./emsdk_env.sh"
    exit 1
fi

# Display Emscripten version
echo -e "${YELLOW}Using Emscripten version:${NC}"
emcc --version

# Source files directory
SRC_DIR="third_party/unrar"
OUT_DIR="lib/src/wasm"

# Create output directory
mkdir -p "$OUT_DIR"

# List of source files to compile
# Note: Using the same source list as in hook/build.dart
SOURCES=(
    "$SRC_DIR/rar.cpp"
    "$SRC_DIR/strlist.cpp"
    "$SRC_DIR/strfn.cpp"
    "$SRC_DIR/pathfn.cpp"
    "$SRC_DIR/smallfn.cpp"
    "$SRC_DIR/global.cpp"
    "$SRC_DIR/file.cpp"
    "$SRC_DIR/filefn.cpp"
    "$SRC_DIR/filcreat.cpp"
    "$SRC_DIR/archive.cpp"
    "$SRC_DIR/arcread.cpp"
    "$SRC_DIR/unicode.cpp"
    "$SRC_DIR/system.cpp"
    "$SRC_DIR/crypt.cpp"
    "$SRC_DIR/crc.cpp"
    "$SRC_DIR/rawread.cpp"
    "$SRC_DIR/encname.cpp"
    "$SRC_DIR/resource.cpp"
    "$SRC_DIR/match.cpp"
    "$SRC_DIR/timefn.cpp"
    "$SRC_DIR/rdwrfn.cpp"
    "$SRC_DIR/consio.cpp"
    "$SRC_DIR/options.cpp"
    "$SRC_DIR/errhnd.cpp"
    "$SRC_DIR/rarvm.cpp"
    "$SRC_DIR/secpassword.cpp"
    "$SRC_DIR/rijndael.cpp"
    "$SRC_DIR/getbits.cpp"
    "$SRC_DIR/sha1.cpp"
    "$SRC_DIR/sha256.cpp"
    "$SRC_DIR/blake2s.cpp"
    "$SRC_DIR/hash.cpp"
    "$SRC_DIR/extinfo.cpp"
    "$SRC_DIR/extract.cpp"
    "$SRC_DIR/volume.cpp"
    "$SRC_DIR/list.cpp"
    "$SRC_DIR/find.cpp"
    "$SRC_DIR/unpack.cpp"
    "$SRC_DIR/headers.cpp"
    "$SRC_DIR/threadpool.cpp"
    "$SRC_DIR/rs16.cpp"
    "$SRC_DIR/cmddata.cpp"
    "$SRC_DIR/ui.cpp"
    "$SRC_DIR/filestr.cpp"
    "$SRC_DIR/scantree.cpp"
    "$SRC_DIR/qopen.cpp"
    "$SRC_DIR/largepage.cpp"
    "$SRC_DIR/dll.cpp"
)

echo -e "${YELLOW}Compiling ${#SOURCES[@]} source files...${NC}"

# Compile with Emscripten
# Exported functions from dll.hpp that we need to expose
EXPORTED_FUNCTIONS='[
    "_RAROpenArchive",
    "_RARCloseArchive", 
    "_RARReadHeader",
    "_RARProcessFile",
    "_RARSetPassword",
    "_RARGetDllVersion",
    "_malloc",
    "_free"
]'

emcc \
    "${SOURCES[@]}" \
    -O3 \
    -s WASM=1 \
    -s EXPORTED_FUNCTIONS="$EXPORTED_FUNCTIONS" \
    -s EXPORTED_RUNTIME_METHODS='["ccall","cwrap","getValue","setValue","UTF8ToString","stringToUTF8","lengthBytesUTF8"]' \
    -s ALLOW_MEMORY_GROWTH=1 \
    -s INITIAL_MEMORY=33554432 \
    -s MAXIMUM_MEMORY=2147483648 \
    -s MODULARIZE=1 \
    -s EXPORT_NAME='createUnrarModule' \
    -s ENVIRONMENT='web' \
    -s FILESYSTEM=1 \
    -s FORCE_FILESYSTEM=1 \
    -DRARDLL \
    -D_FILE_OFFSET_BITS=64 \
    -D_LARGEFILE_SOURCE \
    -DRAR_SMP \
    -std=c++11 \
    -Wno-dangling-else \
    -Wno-switch \
    -o "$OUT_DIR/unrar.js"

# Check if build was successful
if [ -f "$OUT_DIR/unrar.js" ] && [ -f "$OUT_DIR/unrar.wasm" ]; then
    echo -e "${GREEN}✓ Build successful!${NC}"
    echo -e "${GREEN}Generated files:${NC}"
    ls -lh "$OUT_DIR/unrar.js" "$OUT_DIR/unrar.wasm"
    
    # Show file sizes
    JS_SIZE=$(stat -f%z "$OUT_DIR/unrar.js" 2>/dev/null || stat -c%s "$OUT_DIR/unrar.js" 2>/dev/null || echo "unknown")
    WASM_SIZE=$(stat -f%z "$OUT_DIR/unrar.wasm" 2>/dev/null || stat -c%s "$OUT_DIR/unrar.wasm" 2>/dev/null || echo "unknown")
    echo -e "  JS glue code: $JS_SIZE bytes"
    echo -e "  WASM binary: $WASM_SIZE bytes"
else
    echo -e "${RED}✗ Build failed!${NC}"
    exit 1
fi

echo -e "${GREEN}Done!${NC}"
