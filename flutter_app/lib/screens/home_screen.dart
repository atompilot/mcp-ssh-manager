import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hugeicons/hugeicons.dart';

import '../mcp/mcp_client.dart';
import '../providers/connection_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/transfer_provider.dart';
import '../services/embedded_server_service.dart';
import '../services/file_opener_service.dart';
import '../services/file_sync_service.dart';
import '../widgets/advanced_settings_dialog.dart';
import '../widgets/connection_dialog.dart';
import '../widgets/local_file_browser.dart';
import '../widgets/remote_file_browser.dart';
import '../widgets/settings_dialog.dart';
import '../widgets/transfer_panel.dart';

// Re-export drag data types for convenience
export '../widgets/local_file_browser.dart' show LocalFile, DraggedLocalFiles, DraggedRemoteFiles;

/// Startup state for the app
enum StartupState {
  initializing,
  startingServer,
  connecting,
  ready,
  error,
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  TransferProvider? _transferProvider;
  bool _showTransferPanel = true;

  // Auto-connect state
  final EmbeddedServerService _serverService = EmbeddedServerService();
  final FileOpenerService _fileOpenerService = FileOpenerService();
  FileSyncService? _fileSyncService;
  StartupState _startupState = StartupState.initializing;
  String? _startupError;
  String _startupMessage = 'Initializing...';

  // Keys to access browser state
  final GlobalKey<dynamic> _localBrowserKey = GlobalKey();
  final GlobalKey<dynamic> _remoteBrowserKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Auto-start server and connect
    _autoStartAndConnect();
  }

  @override
  void dispose() {
    _serverService.dispose();
    _fileSyncService?.dispose();
    super.dispose();
  }

  void _initFileSyncService(McpClient client) {
    _fileSyncService = FileSyncService(client);
    _fileSyncService!.onSyncStart = (fileName, success, error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text('Syncing $fileName...'),
              ],
            ),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    };
    _fileSyncService!.onSyncComplete = (fileName, success, error) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Synced $fileName to server'
                  : 'Failed to sync $fileName: $error',
            ),
            backgroundColor: success ? Colors.green : Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    };
  }

  Future<void> _autoStartAndConnect() async {
    final connectionProvider = context.read<ConnectionProvider>();

    try {
      // Step 1: Start embedded server
      setState(() {
        _startupState = StartupState.startingServer;
        _startupMessage = 'Starting MCP server...';
      });

      final serverStarted = await _serverService.start();
      if (!serverStarted) {
        throw Exception('Failed to start MCP server');
      }

      // Small delay to ensure server is fully ready
      await Future.delayed(const Duration(milliseconds: 500));

      // Step 2: Connect to server
      setState(() {
        _startupState = StartupState.connecting;
        _startupMessage = 'Connecting...';
      });

      await connectionProvider.connect(_serverService.serverUrl);

      // Step 3: Ready
      setState(() {
        _startupState = StartupState.ready;
      });
    } catch (e) {
      print('[HomeScreen] Auto-connect error: $e');
      setState(() {
        _startupState = StartupState.error;
        _startupError = e.toString();
      });
    }
  }

  Future<void> _retry() async {
    setState(() {
      _startupState = StartupState.initializing;
      _startupError = null;
    });
    await _autoStartAndConnect();
  }

  @override
  Widget build(BuildContext context) {
    final connectionProvider = context.watch<ConnectionProvider>();

    // Show splash screen during startup
    if (_startupState != StartupState.ready && _startupState != StartupState.error) {
      return _buildSplashScreen(context);
    }

    // Show error screen if startup failed
    if (_startupState == StartupState.error) {
      return _buildErrorScreen(context);
    }

    // Initialize transfer provider when connected
    if (connectionProvider.isConnected && _transferProvider == null) {
      _transferProvider = TransferProvider(client: connectionProvider.client);
    } else if (!connectionProvider.isConnected && _transferProvider != null) {
      _transferProvider = null;
    }

    return Scaffold(
      body: Column(
        children: [
          // Toolbar
          _buildToolbar(context, connectionProvider),

          // Main content - Dual pane layout
          Expanded(
            child: connectionProvider.isConnected
                ? _buildDualPaneContent(context, connectionProvider)
                : _buildDisconnectedScreen(context, connectionProvider),
          ),

          // Transfer panel
          if (_showTransferPanel && _transferProvider != null)
            ChangeNotifierProvider.value(
              value: _transferProvider!,
              child: const TransferPanel(),
            ),
        ],
      ),
    );
  }

  Widget _buildSplashScreen(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.primaryContainer,
              colorScheme.surface,
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // App icon
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedFolderShared01,
                  size: 64,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'MCP File Manager',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: 200,
                child: LinearProgressIndicator(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _startupMessage,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorScreen(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            HugeIcon(
              icon: HugeIcons.strokeRoundedAlertCircle,
              size: 64,
              color: colorScheme.error,
            ),
            const SizedBox(height: 24),
            Text(
              'Failed to Start',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxWidth: 400),
              padding: const EdgeInsets.all(16),
              child: Text(
                _startupError ?? 'Unknown error',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _retry,
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 18, color: Colors.white),
                  label: const Text('Retry'),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: () => _showConnectionDialog(context),
                  icon: HugeIcon(icon: HugeIcons.strokeRoundedSettings02, size: 18, color: Theme.of(context).colorScheme.primary),
                  label: const Text('Manual Connect'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDisconnectedScreen(
      BuildContext context, ConnectionProvider connectionProvider) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          HugeIcon(
            icon: HugeIcons.strokeRoundedCloud,
            size: 64,
            color: colorScheme.onSurfaceVariant.withOpacity(0.5),
          ),
          const SizedBox(height: 24),
          Text(
            'Disconnected',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Connection to MCP server lost',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _retry,
            icon: const HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 18, color: Colors.white),
            label: const Text('Reconnect'),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(
      BuildContext context, ConnectionProvider connectionProvider) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          // Logo/Title
          HugeIcon(icon: HugeIcons.strokeRoundedFolderShared01, size: 20, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            'MCP File Manager',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 16),

          // Connection status
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: connectionProvider.isConnected
                  ? Colors.green.withOpacity(0.1)
                  : Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: connectionProvider.isConnected
                    ? Colors.green
                    : Colors.grey,
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                HugeIcon(
                  icon: connectionProvider.isConnected
                      ? HugeIcons.strokeRoundedCloudSavingDone01
                      : HugeIcons.strokeRoundedCloud,
                  size: 14,
                  color:
                      connectionProvider.isConnected ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 4),
                Text(
                  connectionProvider.isConnected ? 'Connected' : 'Disconnected',
                  style: TextStyle(
                    fontSize: 11,
                    color: connectionProvider.isConnected
                        ? Colors.green
                        : Colors.grey,
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Actions
          if (connectionProvider.isConnected) ...[
            IconButton(
              icon: HugeIcon(
                icon: _showTransferPanel
                    ? HugeIcons.strokeRoundedDownload02
                    : HugeIcons.strokeRoundedDownload01,
                size: 18,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              tooltip: 'Toggle Transfer Panel',
              onPressed: () {
                setState(() {
                  _showTransferPanel = !_showTransferPanel;
                });
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            IconButton(
              icon: HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 18, color: Theme.of(context).colorScheme.onSurface),
              tooltip: 'Refresh Servers',
              onPressed: () => connectionProvider.refreshServers(),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],

          // Settings button (editor settings)
          IconButton(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedPencilEdit02, size: 18, color: Theme.of(context).colorScheme.onSurface),
            tooltip: 'Editor Settings',
            onPressed: () => _showSettingsDialog(context),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),

          // Advanced settings button (servers, tools, Claude Code)
          IconButton(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedSettings01, size: 18, color: Theme.of(context).colorScheme.onSurface),
            tooltip: 'Advanced Settings',
            onPressed: () => _showAdvancedSettingsDialog(context),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),

          IconButton(
            icon: HugeIcon(
              icon: connectionProvider.isConnected ? HugeIcons.strokeRoundedUnlink01 : HugeIcons.strokeRoundedLink01,
              size: 18,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            tooltip:
                connectionProvider.isConnected ? 'Disconnect' : 'Connect',
            onPressed: () {
              if (connectionProvider.isConnected) {
                connectionProvider.disconnect();
              } else {
                _showConnectionDialog(context);
              }
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildDualPaneContent(
      BuildContext context, ConnectionProvider connectionProvider) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        // Left pane - Local files
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
              ),
            ),
            child: Column(
              children: [
                // Local pane header
                Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh,
                    border: Border(
                      bottom: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      HugeIcon(icon: HugeIcons.strokeRoundedComputer, size: 14, color: colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Local',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                // Local file browser
                Expanded(
                  child: LocalFileBrowser(
                    key: _localBrowserKey,
                    onFileSelected: (file) => _openLocalFile(context, file.fullPath),
                    onUploadFiles: (files) => _uploadFilesToServer(context, connectionProvider, files),
                    onDownloadFiles: (remoteFiles, localDestination) =>
                        _downloadFilesToLocal(context, connectionProvider, remoteFiles, localDestination),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Right pane - Remote files
        Expanded(
          child: Column(
            children: [
              // Remote pane header
              Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  border: Border(
                    bottom: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    HugeIcon(icon: HugeIcons.strokeRoundedCloud, size: 14, color: colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Remote',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              // Remote file browser
              Expanded(
                child: RemoteFileBrowser(
                  key: _remoteBrowserKey,
                  client: connectionProvider.client,
                  servers: connectionProvider.servers,
                  onFileSelected: (file, server, fullPath) => _openRemoteFile(context, connectionProvider, server, fullPath),
                  onUploadFiles: (localFiles, remoteDestination, server) =>
                      _uploadLocalFilesToRemote(context, connectionProvider, localFiles, remoteDestination, server),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showConnectionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const ConnectionDialog(),
    );
  }

  void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const SettingsDialog(),
    );
  }

  void _showAdvancedSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const AdvancedSettingsDialog(),
    );
  }

  /// Open a local file with the default editor
  Future<void> _openLocalFile(BuildContext context, String filePath) async {
    final settingsProvider = context.read<SettingsProvider>();
    final editor = settingsProvider.settings.currentEditor;

    if (editor == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No editor configured. Please set a default editor in Settings.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }

    print('[HomeScreen] Opening local file: $filePath with ${editor.name}');

    final opened = await _fileOpenerService.openWithEditor(
      filePath: filePath,
      editor: editor,
    );

    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to open file with ${editor.name}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  /// Open a remote file (download then open with editor)
  Future<void> _openRemoteFile(
    BuildContext context,
    ConnectionProvider connectionProvider,
    SshServer server,
    String remotePath,
  ) async {
    final settingsProvider = context.read<SettingsProvider>();
    final editor = settingsProvider.settings.currentEditor;
    final fileName = remotePath.split('/').last;

    if (editor == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No editor configured. Please set a default editor in Settings.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }

    print('[HomeScreen] Opening remote file: $remotePath from ${server.name}');

    // Show loading indicator
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text('Downloading $fileName...'),
          ],
        ),
        duration: const Duration(seconds: 30),
      ),
    );

    // Get temp directory
    final tempDir = await _fileOpenerService.getDefaultTempDir();

    // Download and open
    final result = await _fileOpenerService.downloadAndOpen(
      client: connectionProvider.client,
      server: server.name,
      remotePath: remotePath,
      tempDir: tempDir,
      editor: editor,
    );

    if (!mounted) return;

    // Hide loading snackbar
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (result.success && result.localPath != null) {
      // Initialize sync service if needed
      if (_fileSyncService == null) {
        _initFileSyncService(connectionProvider.client);
      }

      // Start watching the file for changes
      _fileSyncService!.watchFile(
        localPath: result.localPath!,
        remotePath: remotePath,
        serverName: server.name,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Opened $fileName - changes will sync automatically'),
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to open file: ${result.error}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  /// Upload local files to the currently selected remote server
  Future<void> _uploadFilesToServer(
    BuildContext context,
    ConnectionProvider connectionProvider,
    List<LocalFile> files,
  ) async {
    // Get the remote browser state to find selected server and path
    final remoteBrowserState = _remoteBrowserKey.currentState;
    if (remoteBrowserState == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select a server first'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    final server = remoteBrowserState.selectedServer;
    final remotePath = remoteBrowserState.currentPath;

    if (server == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select a server first'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    // Queue uploads
    for (final file in files) {
      final remoteDestPath = remotePath.endsWith('/')
          ? '$remotePath${file.name}'
          : '$remotePath/${file.name}';

      _transferProvider?.queueUpload(
        serverName: server.name,
        localPath: file.fullPath,
        remotePath: remoteDestPath,
        fileName: file.name,
      );
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Uploading ${files.length} file(s) to ${server.name}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Upload local files that were dropped on the remote browser
  Future<void> _uploadLocalFilesToRemote(
    BuildContext context,
    ConnectionProvider connectionProvider,
    DraggedLocalFiles localFiles,
    String remoteDestination,
    SshServer server,
  ) async {
    // Queue uploads
    for (final file in localFiles.files) {
      final remoteDestPath = remoteDestination.endsWith('/')
          ? '$remoteDestination${file.name}'
          : '$remoteDestination/${file.name}';

      _transferProvider?.queueUpload(
        serverName: server.name,
        localPath: file.fullPath,
        remotePath: remoteDestPath,
        fileName: file.name,
      );
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Uploading ${localFiles.files.length} file(s) to ${server.name}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Download remote files to local
  Future<void> _downloadFilesToLocal(
    BuildContext context,
    ConnectionProvider connectionProvider,
    DraggedRemoteFiles remoteFiles,
    String localDestination,
  ) async {
    // Queue downloads
    for (final file in remoteFiles.files) {
      final remoteFile = file as RemoteFile;
      final remotePath = remoteFiles.sourcePath.endsWith('/')
          ? '${remoteFiles.sourcePath}${remoteFile.name}'
          : '${remoteFiles.sourcePath}/${remoteFile.name}';
      final localPath = '$localDestination/${remoteFile.name}';

      _transferProvider?.queueDownload(
        serverName: remoteFiles.serverName,
        remotePath: remotePath,
        localPath: localPath,
        fileName: remoteFile.name,
      );
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Downloading ${remoteFiles.files.length} file(s)'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
