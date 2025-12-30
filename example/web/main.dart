import 'dart:html';
import 'package:unrar/unrar.dart';

void main() {
  final output = querySelector('#output') as DivElement;
  final uploadArea = querySelector('#uploadArea') as DivElement;
  final fileInput = querySelector('#fileInput') as InputElement;
  final controls = querySelector('#controls') as DivElement;
  final listBtn = querySelector('#listBtn') as ButtonElement;
  final extractBtn = querySelector('#extractBtn') as ButtonElement;
  final testBtn = querySelector('#testBtn') as ButtonElement;

  String? currentFilePath;
  final extractor = UnrarExtractor();

  void log(String message, {String type = 'info'}) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final className = type == 'error'
        ? 'error'
        : type == 'success'
            ? 'success'
            : '';
    output.innerHtml = '''
      <div class="$className">[$timestamp] $message</div>
      ${output.innerHtml}
    ''';
  }

  // Set up drag and drop
  uploadArea.onDragOver.listen((event) {
    event.preventDefault();
    uploadArea.classes.add('dragover');
  });

  uploadArea.onDragLeave.listen((event) {
    uploadArea.classes.remove('dragover');
  });

  uploadArea.onDrop.listen((event) {
    event.preventDefault();
    uploadArea.classes.remove('dragover');

    final files = event.dataTransfer?.files;
    if (files != null && files.isNotEmpty) {
      handleFile(files[0]);
    }
  });

  uploadArea.onClick.listen((event) {
    fileInput.click();
  });

  fileInput.onChange.listen((event) {
    final files = fileInput.files;
    if (files != null && files.isNotEmpty) {
      handleFile(files[0]);
    }
  });

  void handleFile(File file) {
    log('Loading file: ${file.name} (${_formatBytes(file.size)})');

    final reader = FileReader();
    reader.onLoadEnd.listen((event) {
      try {
        // In a full implementation, we would:
        // 1. Load the file data into Emscripten's virtual filesystem
        // 2. Store the path for use by the extractor
        currentFilePath = '/${file.name}';
        controls.style.display = 'block';
        log('File loaded successfully', type: 'success');
        log('Note: Full WASM implementation is pending. See WEB_SUPPORT.md for details.');
      } catch (e) {
        log('Error loading file: $e', type: 'error');
      }
    });

    reader.onError.listen((event) {
      log('Error reading file', type: 'error');
    });

    reader.readAsArrayBuffer(file);
  }

  listBtn.onClick.listen((event) async {
    if (currentFilePath == null) return;

    try {
      log('Listing files in archive...');
      final files = await extractor.listFiles(currentFilePath!);

      final html = StringBuffer();
      html.write('<h3>Archive Contents (${files.length} files):</h3>');
      html.write('<ul class="file-list">');
      for (final file in files) {
        html.write('''
          <li class="file-item">
            <span class="file-name">${file.isDirectory ? '📁' : '📄'} ${file.name}</span>
            <span class="file-size">${_formatBytes(file.size)}</span>
          </li>
        ''');
      }
      html.write('</ul>');

      output.innerHtml = html.toString();
    } catch (e) {
      log('Error listing files: $e', type: 'error');
    }
  });

  extractBtn.onClick.listen((event) async {
    if (currentFilePath == null) return;

    try {
      log('Extracting files...');
      await extractor.extractAll(currentFilePath!, '/output');
      log('Files extracted successfully', type: 'success');
      log('Files are in the virtual filesystem at /output');
    } catch (e) {
      log('Error extracting files: $e', type: 'error');
    }
  });

  testBtn.onClick.listen((event) async {
    if (currentFilePath == null) return;

    try {
      log('Testing archive integrity...');
      final isValid = await extractor.testArchive(currentFilePath!);
      if (isValid) {
        log('Archive is valid ✓', type: 'success');
      } else {
        log('Archive validation failed', type: 'error');
      }
    } catch (e) {
      log('Error testing archive: $e', type: 'error');
    }
  });

  log('UnRAR Web Example ready');
  log('Upload a RAR file to get started');
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
