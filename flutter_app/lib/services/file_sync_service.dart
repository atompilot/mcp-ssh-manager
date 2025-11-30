import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../mcp/mcp_client.dart';

/// Represents a file being watched for sync
class WatchedFile {
  final String localPath;
  final String remotePath;
  final String serverName;
  final DateTime lastModified;

  WatchedFile({
    required this.localPath,
    required this.remotePath,
    required this.serverName,
    required this.lastModified,
  });

  WatchedFile copyWith({DateTime? lastModified}) {
    return WatchedFile(
      localPath: localPath,
      remotePath: remotePath,
      serverName: serverName,
      lastModified: lastModified ?? this.lastModified,
    );
  }
}

/// Callback for sync events
typedef SyncCallback = void Function(String fileName, bool success, String? error);

/// Service for watching and syncing files between local and remote
class FileSyncService {
  final McpClient _client;
  final Map<String, WatchedFile> _watchedFiles = {};
  Timer? _watchTimer;
  SyncCallback? onSyncComplete;
  SyncCallback? onSyncStart;

  FileSyncService(this._client);

  /// Start watching a file for changes
  void watchFile({
    required String localPath,
    required String remotePath,
    required String serverName,
  }) {
    final file = File(localPath);
    if (!file.existsSync()) {
      print('[FileSyncService] File does not exist: $localPath');
      return;
    }

    final stat = file.statSync();
    _watchedFiles[localPath] = WatchedFile(
      localPath: localPath,
      remotePath: remotePath,
      serverName: serverName,
      lastModified: stat.modified,
    );

    print('[FileSyncService] Now watching: $localPath -> $serverName:$remotePath');

    // Start the watch timer if not already running
    _startWatchTimer();
  }

  /// Stop watching a specific file
  void unwatchFile(String localPath) {
    _watchedFiles.remove(localPath);
    print('[FileSyncService] Stopped watching: $localPath');

    if (_watchedFiles.isEmpty) {
      _stopWatchTimer();
    }
  }

  /// Stop watching all files
  void unwatchAll() {
    _watchedFiles.clear();
    _stopWatchTimer();
    print('[FileSyncService] Stopped watching all files');
  }

  /// Get list of currently watched files
  List<WatchedFile> get watchedFiles => _watchedFiles.values.toList();

  void _startWatchTimer() {
    if (_watchTimer != null) return;

    // Check for changes every 2 seconds
    _watchTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _checkForChanges();
    });
    print('[FileSyncService] Watch timer started');
  }

  void _stopWatchTimer() {
    _watchTimer?.cancel();
    _watchTimer = null;
    print('[FileSyncService] Watch timer stopped');
  }

  Future<void> _checkForChanges() async {
    for (final entry in _watchedFiles.entries.toList()) {
      final localPath = entry.key;
      final watchedFile = entry.value;

      final file = File(localPath);
      if (!file.existsSync()) {
        // File was deleted, stop watching
        _watchedFiles.remove(localPath);
        continue;
      }

      final stat = file.statSync();
      if (stat.modified.isAfter(watchedFile.lastModified)) {
        // File was modified, sync it
        print('[FileSyncService] File changed: $localPath');
        await _syncFile(watchedFile);

        // Update last modified time
        _watchedFiles[localPath] = watchedFile.copyWith(
          lastModified: stat.modified,
        );
      }
    }
  }

  Future<void> _syncFile(WatchedFile watchedFile) async {
    final fileName = watchedFile.localPath.split('/').last;

    try {
      onSyncStart?.call(fileName, true, null);
      print('[FileSyncService] Syncing $fileName to ${watchedFile.serverName}:${watchedFile.remotePath}');

      // Read local file and encode to base64
      final file = File(watchedFile.localPath);
      final bytes = await file.readAsBytes();
      final base64Content = base64Encode(bytes);

      // Upload via ssh_execute with base64 decode
      // Using echo with base64 -d to write the file
      final result = await _client.execute(
        watchedFile.serverName,
        'echo "$base64Content" | base64 -d > "${watchedFile.remotePath}"',
        timeout: 60000,
      );

      if (result.code == 0) {
        print('[FileSyncService] Sync successful: $fileName');
        onSyncComplete?.call(fileName, true, null);
      } else {
        print('[FileSyncService] Sync failed: ${result.stderr}');
        onSyncComplete?.call(fileName, false, result.stderr);
      }
    } catch (e) {
      print('[FileSyncService] Sync error: $e');
      onSyncComplete?.call(fileName, false, e.toString());
    }
  }

  /// Manually trigger sync for a file
  Future<bool> syncNow(String localPath) async {
    final watchedFile = _watchedFiles[localPath];
    if (watchedFile == null) {
      print('[FileSyncService] File not being watched: $localPath');
      return false;
    }

    await _syncFile(watchedFile);

    // Update last modified time
    final file = File(localPath);
    if (file.existsSync()) {
      final stat = file.statSync();
      _watchedFiles[localPath] = watchedFile.copyWith(
        lastModified: stat.modified,
      );
    }

    return true;
  }

  void dispose() {
    _stopWatchTimer();
    _watchedFiles.clear();
  }
}
