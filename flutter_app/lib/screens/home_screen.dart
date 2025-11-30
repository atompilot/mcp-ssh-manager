import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/connection_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/transfer_provider.dart';
import '../services/embedded_server_service.dart';
import '../widgets/connection_dialog.dart';
import '../widgets/server_sidebar.dart';
import '../widgets/file_browser_panel.dart';
import '../widgets/settings_dialog.dart';
import '../widgets/transfer_panel.dart';

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
  StartupState _startupState = StartupState.initializing;
  String? _startupError;
  String _startupMessage = 'Initializing...';

  @override
  void initState() {
    super.initState();
    // Auto-start server and connect
    _autoStartAndConnect();
  }

  @override
  void dispose() {
    _serverService.dispose();
    super.dispose();
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
    final colorScheme = Theme.of(context).colorScheme;

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

          // Main content
          Expanded(
            child: connectionProvider.isConnected
                ? _buildMainContent(context, connectionProvider)
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
                child: Icon(
                  Icons.folder_shared,
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
            Icon(
              Icons.error_outline,
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
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: () => _showConnectionDialog(context),
                  icon: const Icon(Icons.settings),
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
          Icon(
            Icons.cloud_off,
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
            icon: const Icon(Icons.refresh),
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
      height: 48,
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
          Icon(Icons.folder_shared, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            'MCP File Manager',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 24),

          // Connection status
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: connectionProvider.isConnected
                  ? Colors.green.withOpacity(0.1)
                  : Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: connectionProvider.isConnected
                    ? Colors.green
                    : Colors.grey,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  connectionProvider.isConnected
                      ? Icons.cloud_done
                      : Icons.cloud_off,
                  size: 16,
                  color:
                      connectionProvider.isConnected ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 6),
                Text(
                  connectionProvider.isConnected ? 'Connected' : 'Disconnected',
                  style: TextStyle(
                    fontSize: 12,
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
              icon: Icon(
                _showTransferPanel
                    ? Icons.download_done
                    : Icons.download_outlined,
              ),
              tooltip: 'Toggle Transfer Panel',
              onPressed: () {
                setState(() {
                  _showTransferPanel = !_showTransferPanel;
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh Servers',
              onPressed: () => connectionProvider.refreshServers(),
            ),
          ],

          // Settings button
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => _showSettingsDialog(context),
          ),

          IconButton(
            icon: Icon(
              connectionProvider.isConnected ? Icons.link_off : Icons.link,
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
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(
      BuildContext context, ConnectionProvider connectionProvider) {
    return Row(
      children: [
        // Server sidebar
        SizedBox(
          width: 220,
          child: ServerSidebar(
            servers: connectionProvider.servers,
            selectedServer: connectionProvider.selectedServer,
            onServerSelected: connectionProvider.selectServer,
          ),
        ),

        // Divider
        const VerticalDivider(width: 1, thickness: 1),

        // File browser
        Expanded(
          child: connectionProvider.selectedServer != null
              ? _transferProvider != null
                  ? ChangeNotifierProvider.value(
                      value: _transferProvider!,
                      child: FileBrowserPanel(
                        client: connectionProvider.client,
                        server: connectionProvider.selectedServer!,
                      ),
                    )
                  : FileBrowserPanel(
                      client: connectionProvider.client,
                      server: connectionProvider.selectedServer!,
                    )
              : _buildNoServerSelected(context),
        ),
      ],
    );
  }

  Widget _buildNoServerSelected(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.dns_outlined,
            size: 64,
            color: colorScheme.onSurfaceVariant.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Select a server from the sidebar',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
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
}
