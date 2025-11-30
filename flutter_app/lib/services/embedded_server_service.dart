import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

/// Service to manage the embedded MCP server
class EmbeddedServerService {
  Process? _serverProcess;
  bool _isRunning = false;
  String? _serverUrl;
  final int _port = 3001;

  /// Whether the server is currently running
  bool get isRunning => _isRunning;

  /// The WebSocket URL to connect to
  String get serverUrl => _serverUrl ?? 'ws://localhost:$_port/mcp';

  /// Start the embedded MCP server
  /// First tries to connect to an existing server, then tries to start a new one
  Future<bool> start() async {
    if (_isRunning) {
      print('[EmbeddedServer] Server already running');
      return true;
    }

    // First, check if server is already running (external process)
    print('[EmbeddedServer] Checking for existing server on port $_port...');
    if (await healthCheck()) {
      print('[EmbeddedServer] Found existing server running on port $_port');
      _isRunning = true;
      _serverUrl = 'ws://localhost:$_port/mcp';
      return true;
    }

    // Try to start embedded server
    try {
      // Find the server script path
      final serverPath = await _findServerPath();
      if (serverPath == null) {
        print('[EmbeddedServer] Could not find server script');
        return false;
      }

      print('[EmbeddedServer] Starting server from: $serverPath');

      // Find Node.js executable
      final nodePath = await _findNodePath();
      if (nodePath == null) {
        print('[EmbeddedServer] Node.js not found');
        return false;
      }
      print('[EmbeddedServer] Using Node.js: $nodePath');

      // Start the server process
      _serverProcess = await Process.start(
        nodePath,
        [serverPath, '--port', _port.toString()],
        environment: {
          ...Platform.environment,
          'PORT': _port.toString(),
        },
        workingDirectory: path.dirname(serverPath),
      );

      // Listen to stdout for startup confirmation
      final completer = Completer<bool>();
      Timer? timeoutTimer;

      _serverProcess!.stdout.listen((data) {
        final output = String.fromCharCodes(data);
        print('[EmbeddedServer] stdout: $output');
        if (output.contains('listening') || output.contains('MCP Server')) {
          if (!completer.isCompleted) {
            timeoutTimer?.cancel();
            completer.complete(true);
          }
        }
      });

      _serverProcess!.stderr.listen((data) {
        final output = String.fromCharCodes(data);
        print('[EmbeddedServer] stderr: $output');
        // Server logs go to stderr typically
        if (output.contains('listening') || output.contains('MCP Server')) {
          if (!completer.isCompleted) {
            timeoutTimer?.cancel();
            completer.complete(true);
          }
        }
      });

      _serverProcess!.exitCode.then((code) {
        print('[EmbeddedServer] Server exited with code: $code');
        _isRunning = false;
        if (!completer.isCompleted) {
          completer.complete(false);
        }
      });

      // Set timeout for startup
      timeoutTimer = Timer(const Duration(seconds: 5), () {
        if (!completer.isCompleted) {
          // Assume server started if no exit and no explicit message
          print('[EmbeddedServer] Timeout waiting for startup message, assuming started');
          completer.complete(true);
        }
      });

      final started = await completer.future;
      if (started) {
        _isRunning = true;
        _serverUrl = 'ws://localhost:$_port/mcp';
        print('[EmbeddedServer] Server started successfully at $_serverUrl');
      }

      return started;
    } catch (e) {
      print('[EmbeddedServer] Error starting server: $e');
      // If we can't start the process (sandbox), check if server came up anyway
      await Future.delayed(const Duration(seconds: 1));
      if (await healthCheck()) {
        print('[EmbeddedServer] Server is now available (started externally)');
        _isRunning = true;
        _serverUrl = 'ws://localhost:$_port/mcp';
        return true;
      }
      return false;
    }
  }

  /// Stop the embedded server
  Future<void> stop() async {
    if (_serverProcess != null) {
      print('[EmbeddedServer] Stopping server...');
      _serverProcess!.kill(ProcessSignal.sigterm);

      // Wait for graceful shutdown
      try {
        await _serverProcess!.exitCode.timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            print('[EmbeddedServer] Force killing server...');
            _serverProcess!.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
      } catch (e) {
        print('[EmbeddedServer] Error stopping server: $e');
      }

      _serverProcess = null;
      _isRunning = false;
      print('[EmbeddedServer] Server stopped');
    }
  }

  /// Find Node.js executable path
  Future<String?> _findNodePath() async {
    final home = Platform.environment['HOME'] ?? '';

    // List of common Node.js installation paths
    final possiblePaths = <String>[
      // NVM paths (most common for developers)
      '$home/.nvm/versions/node/v20.19.0/bin/node',
      '$home/.nvm/versions/node/v18.20.0/bin/node',
      '$home/.nvm/versions/node/v22.0.0/bin/node',
      // Homebrew paths
      '/opt/homebrew/bin/node',
      '/usr/local/bin/node',
      // System paths
      '/usr/bin/node',
      // Volta
      '$home/.volta/bin/node',
      // fnm
      '$home/.local/share/fnm/node-versions/v20.19.0/installation/bin/node',
    ];

    // Also try to find any nvm version
    final nvmDir = Directory('$home/.nvm/versions/node');
    if (await nvmDir.exists()) {
      try {
        final versions = await nvmDir.list().toList();
        for (final version in versions) {
          if (version is Directory) {
            final nodeBin = '${version.path}/bin/node';
            if (!possiblePaths.contains(nodeBin)) {
              possiblePaths.insert(0, nodeBin);
            }
          }
        }
      } catch (e) {
        print('[EmbeddedServer] Error listing NVM versions: $e');
      }
    }

    for (final nodePath in possiblePaths) {
      print('[EmbeddedServer] Checking node path: $nodePath');
      if (await File(nodePath).exists()) {
        print('[EmbeddedServer] Found Node.js at: $nodePath');
        return nodePath;
      }
    }

    // Last resort: try 'which node' (may not work in sandboxed apps)
    try {
      final result = await Process.run('which', ['node']);
      if (result.exitCode == 0) {
        final path = result.stdout.toString().trim();
        if (path.isNotEmpty && await File(path).exists()) {
          return path;
        }
      }
    } catch (e) {
      print('[EmbeddedServer] which node failed: $e');
    }

    return null;
  }

  /// Find the server script path
  Future<String?> _findServerPath() async {
    // List of possible locations to find the server
    final possiblePaths = <String>[];

    // 1. Check if running from development (flutter run)
    // In dev mode, we can use the relative path from the flutter_app directory
    final devPath = path.join(
      Directory.current.path,
      '..',
      'src',
      'server-http.js',
    );
    possiblePaths.add(path.normalize(devPath));

    // 2. Check in the app bundle (for production builds)
    final executable = Platform.resolvedExecutable;
    final appDir = path.dirname(path.dirname(path.dirname(executable)));
    final bundledPath = path.join(appDir, 'Resources', 'mcp-server', 'server-http.js');
    possiblePaths.add(bundledPath);

    // 3. Check in common installation paths
    final home = Platform.environment['HOME'] ?? '';
    possiblePaths.addAll([
      path.join(home, '.mcp-ssh-manager', 'src', 'server-http.js'),
      path.join(home, 'mcp-ssh-manager', 'src', 'server-http.js'),
      '/usr/local/lib/mcp-ssh-manager/src/server-http.js',
    ]);

    // 4. Hardcoded path for testing (you might want to remove this in production)
    possiblePaths.add('/Users/jeremy/mcp/test-pr-7/src/server-http.js');

    for (final serverPath in possiblePaths) {
      print('[EmbeddedServer] Checking path: $serverPath');
      if (await File(serverPath).exists()) {
        print('[EmbeddedServer] Found server at: $serverPath');
        return serverPath;
      }
    }

    return null;
  }

  /// Check if the server is healthy
  Future<bool> healthCheck() async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(
        Uri.parse('http://localhost:$_port/health'),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 2),
      );
      client.close();
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  void dispose() {
    stop();
  }
}
