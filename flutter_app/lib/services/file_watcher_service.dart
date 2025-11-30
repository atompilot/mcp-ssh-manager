import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../mcp/mcp_client.dart';

/// Represents a watched file with its metadata
class WatchedFile {
  final String localPath;
  final String remotePath;
  final String server;
  DateTime lastModified;
  String? lastContentHash;
  StreamSubscription<FileSystemEvent>? subscription;

  WatchedFile({
    required this.localPath,
    required this.remotePath,
    required this.server,
    required this.lastModified,
    this.lastContentHash,
    this.subscription,
  });
}

/// Callback for sync events
typedef SyncCallback = void Function(String fileName, SyncStatus status, String? error);

/// Sync status enum
enum SyncStatus {
  syncing,
  success,
  error,
}

/// Service for watching local files and syncing changes to remote server
class FileWatcherService {
  final McpClient _client;
  final Map<String, WatchedFile> _watchedFiles = {};
  SyncCallback? onSyncStatusChanged;

  // Debounce timer to avoid multiple syncs on rapid changes
  Timer? _debounceTimer;
  String? _pendingSync;

  // Flag to prevent concurrent syncs
  bool _isSyncing = false;

  FileWatcherService(this._client);

  /// Calculate MD5 hash of file content
  String _calculateHash(List<int> bytes) {
    return md5.convert(bytes).toString();
  }

  /// Start watching a file for changes
  void watchFile({
    required String localPath,
    required String remotePath,
    required String server,
  }) {
    // Stop existing watch if any
    stopWatching(localPath);

    final file = File(localPath);
    if (!file.existsSync()) {
      print('[FileWatcher] File does not exist: $localPath');
      return;
    }

    final stat = file.statSync();
    final bytes = file.readAsBytesSync();
    final initialHash = _calculateHash(bytes);

    final watchedFile = WatchedFile(
      localPath: localPath,
      remotePath: remotePath,
      server: server,
      lastModified: stat.modified,
      lastContentHash: initialHash,
    );

    // Watch the file for modifications
    final subscription = file.watch(events: FileSystemEvent.modify).listen(
      (event) => _onFileChanged(localPath),
      onError: (error) {
        print('[FileWatcher] Watch error for $localPath: $error');
      },
    );

    watchedFile.subscription = subscription;
    _watchedFiles[localPath] = watchedFile;

    print('[FileWatcher] Started watching: $localPath -> $server:$remotePath');
  }

  /// Stop watching a specific file
  void stopWatching(String localPath) {
    final watched = _watchedFiles.remove(localPath);
    if (watched != null) {
      watched.subscription?.cancel();
      print('[FileWatcher] Stopped watching: $localPath');
    }
  }

  /// Stop watching all files
  void stopAll() {
    for (final watched in _watchedFiles.values) {
      watched.subscription?.cancel();
    }
    _watchedFiles.clear();
    _debounceTimer?.cancel();
    print('[FileWatcher] Stopped all watches');
  }

  /// Handle file change event with debouncing
  void _onFileChanged(String localPath) {
    print('[FileWatcher] File changed event: $localPath');

    // If already syncing, just update pending sync path
    if (_isSyncing) {
      print('[FileWatcher] Sync in progress, queuing...');
      _pendingSync = localPath;
      return;
    }

    // Debounce: wait 1 second after last change before syncing
    _debounceTimer?.cancel();
    _pendingSync = localPath;

    _debounceTimer = Timer(const Duration(milliseconds: 1000), () {
      if (_pendingSync != null) {
        _syncFile(_pendingSync!);
        _pendingSync = null;
      }
    });
  }

  /// Sync local file to remote server
  Future<void> _syncFile(String localPath) async {
    final watched = _watchedFiles[localPath];
    if (watched == null) {
      print('[FileWatcher] No watch info for: $localPath');
      return;
    }

    // Prevent concurrent syncs
    if (_isSyncing) {
      print('[FileWatcher] Sync already in progress, skipping');
      return;
    }

    final fileName = localPath.split('/').last;

    try {
      final file = File(localPath);
      if (!file.existsSync()) {
        throw Exception('Local file no longer exists');
      }

      // Read file and check if content actually changed
      final bytes = await file.readAsBytes();
      final currentHash = _calculateHash(bytes);

      if (currentHash == watched.lastContentHash) {
        print('[FileWatcher] Content unchanged for $fileName, skipping sync');
        return;
      }

      // Mark as syncing
      _isSyncing = true;

      print('[FileWatcher] Syncing $fileName to ${watched.server}:${watched.remotePath}');

      // Notify syncing started
      onSyncStatusChanged?.call(fileName, SyncStatus.syncing, null);

      // Encode to base64
      final base64Content = base64Encode(bytes);

      // Upload using base64 decode on remote
      // Using echo with base64 -d to write the file
      final result = await _client.execute(
        watched.server,
        'echo "$base64Content" | base64 -d > "${watched.remotePath}"',
        timeout: 60000,
      );

      if (result.code != 0) {
        throw Exception('Upload failed: ${result.stderr}');
      }

      // Update the stored hash
      watched.lastContentHash = currentHash;
      watched.lastModified = DateTime.now();

      print('[FileWatcher] Sync successful for $fileName');
      onSyncStatusChanged?.call(fileName, SyncStatus.success, null);
    } catch (e) {
      print('[FileWatcher] Sync error for $fileName: $e');
      onSyncStatusChanged?.call(fileName, SyncStatus.error, e.toString());
    } finally {
      _isSyncing = false;

      // Check if there's a pending sync that came in while we were syncing
      if (_pendingSync != null && _pendingSync != localPath) {
        final pending = _pendingSync;
        _pendingSync = null;
        // Use a short delay to avoid rapid successive calls
        Timer(const Duration(milliseconds: 500), () {
          _syncFile(pending!);
        });
      }
    }
  }

  /// Get list of currently watched files
  List<String> get watchedFiles => _watchedFiles.keys.toList();

  /// Check if a file is being watched
  bool isWatching(String localPath) => _watchedFiles.containsKey(localPath);

  void dispose() {
    stopAll();
  }
}
