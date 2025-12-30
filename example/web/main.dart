import 'package:web/web.dart' as web;
import 'package:unrar/unrar.dart';

void main() {
  final output = web.document.querySelector('#output') as web.HTMLDivElement;
  final uploadArea = web.document.querySelector('#uploadArea') as web.HTMLDivElement;
  final fileInput = web.document.querySelector('#fileInput') as web.HTMLInputElement;
  final controls = web.document.querySelector('#controls') as web.HTMLDivElement;
  final listBtn = web.document.querySelector('#listBtn') as web.HTMLButtonElement;
  final extractBtn = web.document.querySelector('#extractBtn') as web.HTMLButtonElement;
  final testBtn = web.document.querySelector('#testBtn') as web.HTMLButtonElement;

  String? currentFilePath;
  final extractor = UnrarExtractor();

  void log(String message, {String type = 'info'}) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final className = type == 'error'
        ? 'error'
        : type == 'success'
            ? 'success'
            : '';
    output.innerHTML = '''
      <div class="$className">[$timestamp] $message</div>
      ${output.innerHTML}
    ''';
  }

  // Set up drag and drop
  uploadArea.addEventListener('dragover', ((web.Event event) {
    event.preventDefault();
    uploadArea.classList.add('dragover');
  }).toJS);

  uploadArea.addEventListener('dragleave', ((web.Event event) {
    uploadArea.classList.remove('dragover');
  }).toJS);

  uploadArea.addEventListener('drop', ((web.Event event) {
    event.preventDefault();
    uploadArea.classList.remove('dragover');

    final dragEvent = event as web.DragEvent;
    final files = dragEvent.dataTransfer?.files;
    if (files != null && files.length > 0) {
      handleFile(files.item(0)!);
    }
  }).toJS);

  uploadArea.addEventListener('click', ((web.Event event) {
    fileInput.click();
  }).toJS);

  fileInput.addEventListener('change', ((web.Event event) {
    final files = fileInput.files;
    if (files != null && files.length > 0) {
      handleFile(files.item(0)!);
    }
  }).toJS);

  void handleFile(web.File file) {
    log('Loading file: ${file.name} (${_formatBytes(file.size)})');

    final reader = web.FileReader();
    reader.addEventListener('loadend', ((web.Event event) {
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
    }).toJS);

    reader.addEventListener('error', ((web.Event event) {
      log('Error reading file', type: 'error');
    }).toJS);

    reader.readAsArrayBuffer(file);
  }

  listBtn.addEventListener('click', ((web.Event event) async {
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

      output.innerHTML = html.toString();
    } catch (e) {
      log('Error listing files: $e', type: 'error');
    }
  }).toJS);

  extractBtn.addEventListener('click', ((web.Event event) async {
    if (currentFilePath == null) return;

    try {
      log('Extracting files...');
      await extractor.extractAll(currentFilePath!, '/output');
      log('Files extracted successfully', type: 'success');
      log('Files are in the virtual filesystem at /output');
    } catch (e) {
      log('Error extracting files: $e', type: 'error');
    }
  }).toJS);

  testBtn.addEventListener('click', ((web.Event event) async {
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
  }).toJS);

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
