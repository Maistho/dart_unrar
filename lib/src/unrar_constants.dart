/// Constants from the UnRAR DLL API
/// These are shared across all platform implementations (FFI and WASM)
/// 
/// Corresponds to definitions in third_party/unrar/dll.hpp
library;

// Error codes
const int ERAR_SUCCESS = 0;
const int ERAR_END_ARCHIVE = 10;
const int ERAR_NO_MEMORY = 11;
const int ERAR_BAD_DATA = 12;
const int ERAR_BAD_ARCHIVE = 13;
const int ERAR_UNKNOWN_FORMAT = 14;
const int ERAR_EOPEN = 15;
const int ERAR_ECREATE = 16;
const int ERAR_ECLOSE = 17;
const int ERAR_EREAD = 18;
const int ERAR_EWRITE = 19;
const int ERAR_SMALL_BUF = 20;
const int ERAR_UNKNOWN = 21;
const int ERAR_MISSING_PASSWORD = 22;

// Open modes
const int RAR_OM_LIST = 0;
const int RAR_OM_EXTRACT = 1;
const int RAR_OM_LIST_INCSPLIT = 2;

// Process file modes
const int RAR_SKIP = 0;
const int RAR_TEST = 1;
const int RAR_EXTRACT = 2;

// Header flags
const int RHDF_SPLITBEFORE = 0x01;
const int RHDF_SPLITAFTER = 0x02;
const int RHDF_ENCRYPTED = 0x04;
const int RHDF_SOLID = 0x10;
const int RHDF_DIRECTORY = 0x20;

/// Get error message for error code
String getErrorMessage(int errorCode) {
  switch (errorCode) {
    case ERAR_NO_MEMORY:
      return 'Not enough memory';
    case ERAR_BAD_DATA:
      return 'Archive header or data is broken';
    case ERAR_BAD_ARCHIVE:
      return 'File is not a valid RAR archive';
    case ERAR_UNKNOWN_FORMAT:
      return 'Unknown archive format';
    case ERAR_EOPEN:
      return 'Cannot open file';
    case ERAR_ECREATE:
      return 'Cannot create file';
    case ERAR_ECLOSE:
      return 'Cannot close file';
    case ERAR_EREAD:
      return 'Read error';
    case ERAR_EWRITE:
      return 'Write error';
    case ERAR_SMALL_BUF:
      return 'Buffer too small';
    case ERAR_MISSING_PASSWORD:
      return 'Password required';
    case ERAR_UNKNOWN:
    default:
      return 'Unknown error';
  }
}
