#!/usr/bin/env python3
"""
Creates minimal valid RAR4 (legacy) test archives for dart_unrar test suite.

RAR 7.x dropped the -ma4 switch and can no longer create RAR4 archives.
This script crafts them at the binary level using the RAR4 format specification.

RAR4 archive structure:
  MARKER     (7 bytes)   52 61 72 21 1A 07 00
  MAIN_HEAD  (type 0x73) archive-level header
  FILE_HEAD* (type 0x74) per-file headers + raw file data
  END_HEAD   (type 0x7B) end-of-archive marker

All multi-byte integers are little-endian.
Header CRCs are computed as the lower 16 bits of CRC32.
File CRCs (FileCRC) are the full 32-bit CRC32.

Reference: UnRAR source / rarformat.hpp for field layout.
"""
import binascii
import os
import struct

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def crc16(data: bytes) -> int:
    """Header CRC: lower 16 bits of CRC32."""
    return binascii.crc32(data) & 0xFFFF

def crc32(data: bytes) -> int:
    return binascii.crc32(data) & 0xFFFFFFFF

def dos_datetime(year: int = 2026, month: int = 6, day: int = 24,
                 hour: int = 12, minute: int = 0, second: int = 0) -> int:
    """
    Pack a date and time into DOS format (uint32).
    Bits 31-25: year-1980  (0..127)
    Bits 24-21: month      (1..12)
    Bits 20-16: day        (1..31)
    Bits 15-11: hour       (0..23)
    Bits 10-5:  minute     (0..59)
    Bits  4-0:  second/2   (0..29)
    """
    date = ((year - 1980) << 9) | (month << 5) | day
    time_val = (hour << 11) | (minute << 5) | (second // 2)
    return (date << 16) | time_val

FILE_TIME = dos_datetime()

# ---------------------------------------------------------------------------
# Block builders
# ---------------------------------------------------------------------------

#  RAR marker — always exactly these 7 bytes
MARKER = bytes([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00])

# MAIN_HEAD flags
MHD_SOLID = 0x0008
MHD_COMMENT = 0x0002
MHD_PROTECT = 0x0040

def build_main_head(flags: int = 0) -> bytes:
    """
    MAIN_HEAD (type 0x73):
      uint16 CRC     — crc16 of body
      uint8  Type    — 0x73
      uint16 Flags   — archive-level flags
      uint16 Size    — total header size (7 bytes for minimal header)
    """
    body = struct.pack('<BHH', 0x73, flags, 7)
    return struct.pack('<H', crc16(body)) + body

def build_main_head_signed(pos_av: int) -> bytes:
    """
    Extended MAIN_HEAD (13 bytes) carrying the AV block position:
      uint16 CRC
      uint8  Type    0x73
      uint16 Flags
      uint16 Size    13
      uint16 HighPosAV
      uint32 PosAV
    The C reader treats a non-zero PosAV as 'archive is signed'.
    """
    body = struct.pack('<BHH', 0x73, 0, 13)
    body += struct.pack('<HI', 0, pos_av)
    return struct.pack('<H', crc16(body)) + body

def build_dir_entry(dirname: str) -> bytes:
    """
    FILE_HEAD directory entry (type 0x74, LHD_DIRECTORY flags = 0x00E0).
    Directories have zero pack and unpack size; no file data follows.
    """
    name_bytes = dirname.encode('utf-8')
    name_size = len(name_bytes)
    head_size = 32 + name_size
    # LHD_DIRECTORY (0x00E0) sets the window bits to the directory sentinel value
    flags = 0x00E0

    body = struct.pack('<BHH', 0x74, flags, head_size)
    body += struct.pack('<II', 0, 0)          # PackSize=0, UnpSize=0
    body += struct.pack('<B', 3)               # HostOS=Unix
    body += struct.pack('<II', 0, FILE_TIME)  # FileCRC=0, FileTime
    body += struct.pack('<BB', 20, 0x30)      # UnpVer=2.0, Method=store
    body += struct.pack('<HI', name_size, 0x41ED)  # NameSize, Attr=drwxr-xr-x
    body += name_bytes
    return struct.pack('<H', crc16(body)) + body
    # No file data for directory entries

def build_file_entry(filename: str, data: bytes, flags: int = 0x0020) -> bytes:
    """
    FILE_HEAD + raw file data for a stored file (Method=0x30, no compression).

    File header layout (after the 2-byte CRC):
      uint8  Type      0x74
      uint16 Flags     file-level flags
      uint16 HeadSize  2(CRC)+30+NameSize
      uint32 PackSize  = len(data) for stored
      uint32 UnpSize   = len(data)
      uint8  HostOS    3 (Unix)
      uint32 FileCRC   CRC32 of raw data
      uint32 FileTime  DOS date/time
      uint8  UnpVer    20 (RAR 2.0 minimum)
      uint8  Method    0x30 (store)
      uint16 NameSize
      uint32 FileAttr
      char[] FileName  [NameSize bytes, UTF-8]
    """
    name_bytes = filename.encode('utf-8')
    name_size = len(name_bytes)
    head_size = 32 + name_size
    pack_size = len(data)
    unp_size = len(data)

    body = struct.pack('<BHH', 0x74, flags, head_size)
    body += struct.pack('<II', pack_size, unp_size)
    body += struct.pack('<B', 3)               # HostOS=Unix
    body += struct.pack('<II', crc32(data), FILE_TIME)
    body += struct.pack('<BB', 20, 0x30)      # UnpVer, Method=store
    body += struct.pack('<HI', name_size, 0x81A4)  # NameSize, FileAttr (Unix -rw-r--r--)
    body += name_bytes

    return struct.pack('<H', crc16(body)) + body + data

def build_end_head() -> bytes:
    """
    END_HEAD (type 0x7B, 7 bytes total):
      uint16 CRC
      uint8  Type    0x7B
      uint16 Flags   0x0000
      uint16 Size    7
    """
    body = struct.pack('<BHH', 0x7B, 0x0000, 7)
    return struct.pack('<H', crc16(body)) + body

# ---------------------------------------------------------------------------
# Archive assembler
# ---------------------------------------------------------------------------

Entry = dict  # {type: 'file'|'dir', name: str, data?: bytes}

def make_rar4(entries: list, main_flags: int = 0,
              main_head: bytes = None) -> bytes:
    parts = [MARKER, main_head if main_head is not None
             else build_main_head(main_flags)]
    for e in entries:
        if e['type'] == 'dir':
            parts.append(build_dir_entry(e['name']))
        else:
            parts.append(build_file_entry(e['name'], e['data']))
    parts.append(build_end_head())
    return b''.join(parts)

# ---------------------------------------------------------------------------
# Source files
# ---------------------------------------------------------------------------

OUT = 'test_data'
SRC = os.path.join(OUT, 'sources')

def src(name: str) -> bytes:
    with open(os.path.join(SRC, name), 'rb') as f:
        return f.read()

# ---------------------------------------------------------------------------
# Create archives
# ---------------------------------------------------------------------------

if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)

    hello  = src('hello.txt')
    world  = src('world.txt')
    nested = src('subdir/nested.txt')
    binary = src('binary.bin')

    archives = {
        # 1. Two text files, default window (128 KB), no special flags
        'basic_rar4.rar': make_rar4([
            {'type': 'file', 'name': 'hello.txt', 'data': hello},
            {'type': 'file', 'name': 'world.txt', 'data': world},
        ]),

        # 2. With explicit directory entry and nested file
        'rar4_with_dirs.rar': make_rar4([
            {'type': 'file', 'name': 'hello.txt', 'data': hello},
            {'type': 'file', 'name': 'world.txt', 'data': world},
            {'type': 'dir',  'name': 'subdir'},
            {'type': 'file', 'name': 'subdir/nested.txt', 'data': nested},
        ]),

        # 3. Solid flag set in MAIN_HEAD (MHD_SOLID = 0x0008)
        'rar4_solid.rar': make_rar4([
            {'type': 'file', 'name': 'hello.txt', 'data': hello},
            {'type': 'file', 'name': 'world.txt', 'data': world},
            {'type': 'file', 'name': 'subdir/nested.txt', 'data': nested},
        ], main_flags=MHD_SOLID),

        # 4. Binary data — 512 bytes (0x00..0xFF repeated twice)
        'rar4_binary.rar': make_rar4([
            {'type': 'file', 'name': 'binary.bin', 'data': binary},
        ]),

        # 5. Archive comment: MHD_COMMENT flag set in MAIN_HEAD
        'rar4_comment.rar': make_rar4([
            {'type': 'file', 'name': 'hello.txt', 'data': hello},
        ], main_flags=MHD_COMMENT),

        # 6. Recovery record present: MHD_PROTECT flag set in MAIN_HEAD
        'rar4_protected.rar': make_rar4([
            {'type': 'file', 'name': 'hello.txt', 'data': hello},
        ], main_flags=MHD_PROTECT),

        # 7. Signed archive: extended MAIN_HEAD with a non-zero PosAV
        'rar4_signed.rar': make_rar4([
            {'type': 'file', 'name': 'hello.txt', 'data': hello},
        ], main_head=build_main_head_signed(pos_av=16)),
    }

    for name, data in archives.items():
        path = os.path.join(OUT, name)
        with open(path, 'wb') as f:
            f.write(data)
        print(f'Created {name} ({len(data):,} bytes)')
