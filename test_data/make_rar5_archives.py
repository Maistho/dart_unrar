#!/usr/bin/env python3
"""
Creates all RAR5 test archives for the dart_unrar test suite using the `rar` CLI.

RAR5 is the default format for RAR 5.x/7.x — no special switch needed.

Archives produced (all in test_data/):
  basic_rar5.rar          hello.txt + world.txt, default compression
  with_dirs.rar           adds subdir/ directory + subdir/nested.txt
  solid.rar               -s flag, solid compression
  binary.rar              binary.bin, -m0 (store, no compression)
  encrypted_data.rar      -p test123, data encrypted, headers visible
  encrypted_headers.rar   -hp test123, headers + data encrypted
  unicode_names.rar       café.txt, UTF-8 filename
  multi.part01..04.rar    -v300b, ~300-byte volume splits

Run from the repository root:
  python3 test_data/make_rar5_archives.py
"""

import os
import shutil
import subprocess
import sys
import tempfile

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO_ROOT, 'test_data')
SRC = os.path.join(OUT, 'sources')


def src(*parts: str) -> str:
    """Absolute path to a source file."""
    return os.path.join(SRC, *parts)


def out(name: str) -> str:
    """Absolute path to an output archive."""
    return os.path.join(OUT, name)


# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------

def run(args: list, cwd: str = REPO_ROOT) -> None:
    """Run a command, printing it first; raise on failure."""
    print(' '.join(args))
    result = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stdout)
        print(result.stderr, file=sys.stderr)
        sys.exit(result.returncode)


def remove(path: str) -> None:
    """Delete a file if it exists (rar refuses to overwrite without -o+)."""
    if os.path.exists(path):
        os.remove(path)


def remove_multi(stem: str) -> None:
    """Delete all volume files matching stem.partNN.rar."""
    for f in os.listdir(OUT):
        if f.startswith(stem) and f.endswith('.rar'):
            os.remove(os.path.join(OUT, f))


# ---------------------------------------------------------------------------
# Archive creation
# ---------------------------------------------------------------------------

def make_basic() -> None:
    dest = out('basic_rar5.rar')
    remove(dest)
    run(['rar', 'a', dest, src('hello.txt'), src('world.txt')])


def make_with_dirs() -> None:
    dest = out('with_dirs.rar')
    remove(dest)
    # Add files and the subdir tree; -ep1 strips leading path up to SRC
    run([
        'rar', 'a', '-ep1', dest,
        src('hello.txt'),
        src('world.txt'),
        src('subdir'),          # adds the directory entry
        src('subdir', 'nested.txt'),
    ])


def make_solid() -> None:
    dest = out('solid.rar')
    remove(dest)
    run([
        'rar', 'a', '-s', '-ep1', dest,
        src('hello.txt'),
        src('world.txt'),
        src('subdir', 'nested.txt'),
    ])


def make_binary() -> None:
    dest = out('binary.rar')
    remove(dest)
    run(['rar', 'a', '-m0', dest, src('binary.bin')])


def make_encrypted_data() -> None:
    dest = out('encrypted_data.rar')
    remove(dest)
    run([
        'rar', 'a', '-p' + 'test123', dest,
        src('hello.txt'),
        src('world.txt'),
    ])


def make_encrypted_headers() -> None:
    dest = out('encrypted_headers.rar')
    remove(dest)
    run([
        'rar', 'a', '-hp' + 'test123', dest,
        src('hello.txt'),
        src('world.txt'),
    ])


def make_unicode() -> None:
    dest = out('unicode_names.rar')
    remove(dest)
    run(['rar', 'a', dest, src('café.txt')])


def make_multi() -> None:
    remove_multi('multi')
    dest = out('multi.part01.rar')
    run([
        'rar', 'a', '-v300b', dest,
        src('large_for_split.txt'),
    ])


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

ARCHIVES = [
    ('basic_rar5.rar',              make_basic),
    ('with_dirs.rar',               make_with_dirs),
    ('solid.rar',                   make_solid),
    ('binary.rar',                  make_binary),
    ('encrypted_data.rar',          make_encrypted_data),
    ('encrypted_headers.rar',       make_encrypted_headers),
    ('unicode_names.rar',           make_unicode),
    ('multi.part01..04.rar',        make_multi),
]


if __name__ == '__main__':
    for label, fn in ARCHIVES:
        print(f'\n=== {label} ===')
        fn()

    print('\nVerifying all archives...')
    # Archives that require a password to verify
    passwords = {
        'encrypted_data.rar': 'test123',
        'encrypted_headers.rar': 'test123',
    }
    for f in sorted(os.listdir(OUT)):
        if not f.endswith('.rar') or f.startswith('rar4'):
            continue
        # Only test the first volume of multi-volume sets
        if 'part' in f and not f.endswith('part01.rar'):
            continue
        path = os.path.join(OUT, f)
        cmd = ['unrar', 't']
        if f in passwords:
            cmd += ['-p' + passwords[f]]
        cmd.append(path)
        result = subprocess.run(cmd, capture_output=True, text=True)
        status = 'OK' if result.returncode == 0 else 'FAIL'
        print(f'  {f}: {status}')
        if result.returncode != 0:
            print(result.stdout)

    print('\nDone.')
