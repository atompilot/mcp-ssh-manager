import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

/// Model for SSH server info
class ServerInfo {
  final String name;
  final String host;
  final String user;
  final String? defaultDir;

  ServerInfo({
    required this.name,
    required this.host,
    required this.user,
    this.defaultDir,
  });

  factory ServerInfo.fromJson(Map<String, dynamic> json) {
    return ServerInfo(
      name: json['name'] ?? '',
      host: json['host'] ?? '',
      user: json['user'] ?? '',
      defaultDir: json['default_dir'],
    );
  }
}

/// Server selector widget with grid/list view and search
class ServerSelector extends StatefulWidget {
  final List<ServerInfo> servers;
  final Function(ServerInfo) onServerSelected;
  final bool isLoading;

  const ServerSelector({
    super.key,
    required this.servers,
    required this.onServerSelected,
    this.isLoading = false,
  });

  @override
  State<ServerSelector> createState() => _ServerSelectorState();
}

class _ServerSelectorState extends State<ServerSelector> {
  String _searchQuery = '';
  bool _isGridView = true;
  final TextEditingController _searchController = TextEditingController();

  List<ServerInfo> get _filteredServers {
    if (_searchQuery.isEmpty) return widget.servers;
    final query = _searchQuery.toLowerCase();
    return widget.servers.where((server) {
      return server.name.toLowerCase().contains(query) ||
          server.host.toLowerCase().contains(query) ||
          server.user.toLowerCase().contains(query);
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (widget.isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CupertinoActivityIndicator(),
            SizedBox(height: 16),
            Text('Loading servers...'),
          ],
        ),
      );
    }

    if (widget.servers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.desktopcomputer,
              size: 64,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'No servers configured',
              style: TextStyle(
                fontSize: 18,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add servers in Settings',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Search bar and view toggle
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              // Search field
              Expanded(
                child: CupertinoSearchTextField(
                  controller: _searchController,
                  placeholder: 'Search servers...',
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                  style: TextStyle(color: colorScheme.onSurface),
                ),
              ),
              const SizedBox(width: 12),
              // View toggle
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildViewToggleButton(
                      icon: CupertinoIcons.square_grid_2x2,
                      isSelected: _isGridView,
                      onTap: () => setState(() => _isGridView = true),
                    ),
                    _buildViewToggleButton(
                      icon: CupertinoIcons.list_bullet,
                      isSelected: !_isGridView,
                      onTap: () => setState(() => _isGridView = false),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Server count
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          alignment: Alignment.centerLeft,
          child: Text(
            '${_filteredServers.length} server${_filteredServers.length != 1 ? 's' : ''}',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.outline,
            ),
          ),
        ),
        // Server list/grid
        Expanded(
          child: _filteredServers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        CupertinoIcons.search,
                        size: 48,
                        color: colorScheme.outline,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No servers match "$_searchQuery"',
                        style: TextStyle(color: colorScheme.outline),
                      ),
                    ],
                  ),
                )
              : _isGridView
                  ? _buildGridView(colorScheme)
                  : _buildListView(colorScheme),
        ),
      ],
    );
  }

  Widget _buildViewToggleButton({
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          size: 18,
          color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
        ),
      ),
    );
  }

  Widget _buildGridView(ColorScheme colorScheme) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.3,
      ),
      itemCount: _filteredServers.length,
      itemBuilder: (context, index) {
        final server = _filteredServers[index];
        return _buildServerCard(server, colorScheme);
      },
    );
  }

  Widget _buildListView(ColorScheme colorScheme) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _filteredServers.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final server = _filteredServers[index];
        return _buildServerListItem(server, colorScheme);
      },
    );
  }

  Widget _buildServerCard(ServerInfo server, ColorScheme colorScheme) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.onServerSelected(server),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.outlineVariant,
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Server icon
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  CupertinoIcons.desktopcomputer,
                  size: 20,
                  color: colorScheme.primary,
                ),
              ),
              const Spacer(),
              // Server name
              Text(
                server.name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              // Host
              Text(
                server.host,
                style: TextStyle(
                  fontSize: 10,
                  color: colorScheme.outline,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              // User
              Text(
                server.user,
                style: TextStyle(
                  fontSize: 10,
                  color: colorScheme.outline,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServerListItem(ServerInfo server, ColorScheme colorScheme) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.onServerSelected(server),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: colorScheme.outlineVariant,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              // Server icon
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  CupertinoIcons.desktopcomputer,
                  size: 20,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              // Server info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      server.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${server.user}@${server.host}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              // Arrow
              Icon(
                CupertinoIcons.chevron_right,
                size: 16,
                color: colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
