import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../mcp/mcp_client.dart';
import '../models/app_settings.dart';

/// Result of a file download and open operation
class FileOpenResult {
  final bool success;
  final String? localPath;
  final String? error;

  const FileOpenResult({
    required this.success,
    this.localPath,
    this.error,
  });
}

/// Service for downloading remote files and opening them with an editor
class FileOpenerService {
  /// Download a remote file to local temp directory using base64 encoding
  Future<FileOpenResult> downloadFile({
    required McpClient client,
    required String server,
    required String remotePath,
    required String tempDir,
  }) async {
    try {
      print('[FileOpener] Starting download of $remotePath from $server');

      // Create temp directory if it doesn't exist
      final dir = Directory(tempDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // Generate local path
      final fileName = path.basename(remotePath);
      final localPath = path.join(tempDir, server, fileName);

      // Create server subdirectory
      final serverDir = Directory(path.dirname(localPath));
      if (!await serverDir.exists()) {
        await serverDir.create(recursive: true);
      }

      // Read file content via ssh_execute with base64 encoding
      print('[FileOpener] Executing base64 command...');
      final result = await client.execute(
        server,
        'base64 "$remotePath"',
        timeout: 60000,
      );
      print('[FileOpener] Command completed with code ${result.code}');

      if (result.code != 0) {
        print('[FileOpener] Error: ${result.stderr}');
        return FileOpenResult(
          success: false,
          error: 'Failed to read file: ${result.stderr}',
        );
      }

      // Decode base64 and write to local file
      print('[FileOpener] Decoding base64 (${result.stdout.length} chars)...');
      final base64Content = result.stdout.trim().replaceAll('\n', '');
      final bytes = base64Decode(base64Content);
      final file = File(localPath);
      await file.writeAsBytes(bytes);
      print('[FileOpener] File saved to $localPath (${bytes.length} bytes)');

      return FileOpenResult(
        success: true,
        localPath: localPath,
      );
    } catch (e) {
      print('[FileOpener] Exception: $e');
      return FileOpenResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Open a local file with the specified editor
  Future<bool> openWithEditor({
    required String filePath,
    required EditorInfo editor,
  }) async {
    try {
      print('[FileOpener] Opening $filePath with ${editor.name}');
      print('[FileOpener] Editor macCommand: ${editor.macCommand}, macPath: ${editor.macPath}');
      if (Platform.isMacOS) {
        final result = await _openOnMac(filePath, editor);
        print('[FileOpener] Open result: $result');
        return result;
      }
      // Add Linux/Windows support here if needed
      print('[FileOpener] Platform not supported');
      return false;
    } catch (e) {
      print('[FileOpener] Exception opening file: $e');
      return false;
    }
  }

  Future<bool> _openOnMac(String filePath, EditorInfo editor) async {
    try {
      // On macOS sandboxed apps, we must use 'open' command
      // Direct execution of commands like 'code' won't work due to sandbox restrictions

      // First try: open with the app bundle
      if (editor.macPath.isNotEmpty) {
        print('[FileOpener] Trying open -a with app: ${editor.macPath}');
        final appName = path.basenameWithoutExtension(editor.macPath);
        final result = await Process.run('open', ['-a', appName, filePath]);
        print('[FileOpener] open -a $appName result: exitCode=${result.exitCode}, stderr=${result.stderr}');
        if (result.exitCode == 0) {
          return true;
        }
      }

      // Second try: use the macCommand if it starts with 'open'
      if (editor.macCommand.isNotEmpty && editor.macCommand.startsWith('open')) {
        final cmdParts = editor.macCommand.split(' ');
        final args = [...cmdParts.skip(1), filePath];
        print('[FileOpener] Trying macCommand: open ${args.join(' ')}');
        final result = await Process.run('open', args);
        print('[FileOpener] macCommand result: exitCode=${result.exitCode}');
        if (result.exitCode == 0) {
          return true;
        }
      }

      // Last resort: just use 'open' to open with default app
      print('[FileOpener] Trying default open');
      final result = await Process.run('open', [filePath]);
      print('[FileOpener] Default open result: exitCode=${result.exitCode}');
      return result.exitCode == 0;
    } catch (e) {
      print('[FileOpener] _openOnMac exception: $e');
      return false;
    }
  }

  /// Download and open a remote file
  Future<FileOpenResult> downloadAndOpen({
    required McpClient client,
    required String server,
    required String remotePath,
    required String tempDir,
    required EditorInfo editor,
  }) async {
    print('[FileOpener] downloadAndOpen called for $remotePath');

    // Download the file
    final downloadResult = await downloadFile(
      client: client,
      server: server,
      remotePath: remotePath,
      tempDir: tempDir,
    );

    print('[FileOpener] Download result: success=${downloadResult.success}, path=${downloadResult.localPath}');

    if (!downloadResult.success) {
      print('[FileOpener] Download failed: ${downloadResult.error}');
      return downloadResult;
    }

    // Open with editor
    print('[FileOpener] About to call openWithEditor...');
    final opened = await openWithEditor(
      filePath: downloadResult.localPath!,
      editor: editor,
    );
    print('[FileOpener] openWithEditor returned: $opened');

    if (opened) {
      return downloadResult;
    } else {
      return FileOpenResult(
        success: false,
        localPath: downloadResult.localPath,
        error: 'Failed to open file with ${editor.name}',
      );
    }
  }

  /// Get default temp directory for downloads
  Future<String> getDefaultTempDir() async {
    final tempDir = await getTemporaryDirectory();
    return path.join(tempDir.path, 'mcp_file_manager', 'downloads');
  }
}
