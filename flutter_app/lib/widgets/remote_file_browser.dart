import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';

import '../mcp/mcp_client.dart';
import 'server_selector.dart';

/// Context menu action types
enum FileAction {
  open,
  download,
  info,
  delete,
  rename,
  duplicate,
  move,
  newFolder,
  newFile,
  refresh,
}

/// Remote file browser widget with server selector - Finder-like design
class RemoteFileBrowser extends StatefulWidget {
  final McpClient client;
  final List<SshServer> servers;
  /// Called when a file is double-clicked. Parameters: file, server, full remote path
  final Function(RemoteFile, SshServer, String fullPath)? onFileSelected;
  final Function(List<RemoteFile>, SshServer)? onFilesSelected;
  /// Called when file needs to be downloaded
  final Function(RemoteFile, SshServer, String fullPath)? onDownloadFile;

  const RemoteFileBrowser({
    super.key,
    required this.client,
    required this.servers,
    this.onFileSelected,
    this.onFilesSelected,
    this.onDownloadFile,
  });

  @override
  State<RemoteFileBrowser> createState() => _RemoteFileBrowserState();
}

class _RemoteFileBrowserState extends State<RemoteFileBrowser> {
  SshServer? _selectedServer;
  String _currentPath = '~';
  List<RemoteFile> _files = [];
  Set<String> _selectedFiles = {};
  bool _isLoading = false;
  String? _error;
  bool _showHidden = false;

  // Convert SshServer list to ServerInfo list for the selector
  List<ServerInfo> get _serverInfos {
    return widget.servers.map((s) => ServerInfo(
      name: s.name,
      host: s.host,
      user: s.user,
      defaultDir: s.defaultDir,
    )).toList();
  }

  Future<void> _loadFiles() async {
    if (_selectedServer == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await widget.client.listFiles(
        _selectedServer!.name,
        path: _currentPath,
        showHidden: _showHidden,
      );

      setState(() {
        _files = result.files;
        _currentPath = result.path;
        _isLoading = false;
        _selectedFiles.clear();
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _navigateTo(String newPath) {
    setState(() {
      _currentPath = newPath;
    });
    _loadFiles();
  }

  void _navigateUp() {
    if (_currentPath == '/' || _currentPath == '~' || _currentPath == '\$HOME') return;
    final parts = _currentPath.split('/');
    if (parts.length > 1) {
      parts.removeLast();
      final parent = parts.isEmpty ? '/' : parts.join('/');
      _navigateTo(parent);
    }
  }

  void _openItem(RemoteFile file) {
    if (file.isDirectory) {
      final newPath = _currentPath.endsWith('/')
          ? '$_currentPath${file.name}'
          : '$_currentPath/${file.name}';
      _navigateTo(newPath);
    } else {
      // Build full path for the file
      final fullPath = _currentPath.endsWith('/')
          ? '$_currentPath${file.name}'
          : '$_currentPath/${file.name}';
      widget.onFileSelected?.call(file, _selectedServer!, fullPath);
    }
  }

  void _toggleSelection(RemoteFile file) {
    setState(() {
      final key = '$_currentPath/${file.name}';
      if (_selectedFiles.contains(key)) {
        _selectedFiles.remove(key);
      } else {
        _selectedFiles.add(key);
      }
    });

    // Notify parent of selection change
    final selectedRemoteFiles = _files
        .where((f) => _selectedFiles.contains('$_currentPath/${f.name}'))
        .toList();
    widget.onFilesSelected?.call(selectedRemoteFiles, _selectedServer!);
  }

  void _selectServer(ServerInfo serverInfo) {
    // Find the matching SshServer
    final server = widget.servers.firstWhere(
      (s) => s.name == serverInfo.name,
      orElse: () => widget.servers.first,
    );

    setState(() {
      _selectedServer = server;
      _currentPath = server.defaultDir ?? '~';
      _files = [];
      _selectedFiles.clear();
    });
    _loadFiles();
  }

  void _disconnectServer() {
    setState(() {
      _selectedServer = null;
      _currentPath = '~';
      _files = [];
      _selectedFiles.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Show server selector if no server is selected
    if (_selectedServer == null) {
      return ServerSelector(
        servers: _serverInfos,
        onServerSelected: _selectServer,
        isLoading: false,
      );
    }

    // Show file browser when server is selected
    return Column(
      children: [
        // Connected server header with disconnect button
        _buildConnectedServerHeader(colorScheme),

        // Header with path breadcrumb
        _buildHeader(colorScheme),

        // Column headers
        _buildColumnHeaders(colorScheme),

        // File list
        Expanded(
          child: _isLoading
              ? const Center(child: CupertinoActivityIndicator())
              : _error != null
                  ? _buildErrorView(colorScheme)
                  : _buildFileList(colorScheme),
        ),

        // Status bar
        _buildStatusBar(colorScheme),
      ],
    );
  }

  Widget _buildConnectedServerHeader(ColorScheme colorScheme) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withOpacity(0.3),
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(CupertinoIcons.checkmark_circle_fill, size: 16, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_selectedServer!.name} (${_selectedServer!.user}@${_selectedServer!.host})',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Disconnect button
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minSize: 28,
            onPressed: _disconnectServer,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.xmark_circle, size: 14, color: colorScheme.error),
                const SizedBox(width: 4),
                Text(
                  'Disconnect',
                  style: TextStyle(fontSize: 11, color: colorScheme.error),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    final pathParts = _currentPath.split('/').where((p) => p.isNotEmpty && p != '\$HOME').toList();
    final isHome = _currentPath == '~' || _currentPath == '\$HOME' || _currentPath.isEmpty;

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Navigation buttons
          IconButton(
            icon: const Icon(Icons.arrow_upward, size: 16),
            onPressed: _navigateUp,
            tooltip: 'Go up',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: const Icon(Icons.home, size: 16),
            onPressed: () => _navigateTo('~'),
            tooltip: 'Home',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 16),
            onPressed: _loadFiles,
            tooltip: 'Refresh',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          // Default directory button if available
          if (_selectedServer?.defaultDir != null)
            IconButton(
              icon: const Icon(Icons.folder_special, size: 16),
              onPressed: () => _navigateTo(_selectedServer!.defaultDir!),
              tooltip: 'Default directory',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          const SizedBox(width: 8),

          // Breadcrumb path
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // Root/Home
                  InkWell(
                    onTap: () => _navigateTo(isHome ? '/' : '~'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        isHome ? Icons.home : Icons.storage,
                        size: 14,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                  // Path parts
                  if (!isHome)
                    for (var i = 0; i < pathParts.length; i++) ...[
                      Icon(Icons.chevron_right, size: 14, color: colorScheme.onSurfaceVariant),
                      InkWell(
                        onTap: () {
                          final newPath = '/${pathParts.sublist(0, i + 1).join('/')}';
                          _navigateTo(newPath);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            pathParts[i],
                            style: TextStyle(
                              fontSize: 12,
                              color: i == pathParts.length - 1
                                  ? colorScheme.onSurface
                                  : colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                ],
              ),
            ),
          ),

          // Show hidden toggle
          IconButton(
            icon: Icon(
              _showHidden ? Icons.visibility : Icons.visibility_off,
              size: 16,
              color: _showHidden ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
            onPressed: () {
              setState(() => _showHidden = !_showHidden);
              _loadFiles();
            },
            tooltip: _showHidden ? 'Hide hidden files' : 'Show hidden files',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildColumnHeaders(ColorScheme colorScheme) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text('', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            flex: 3,
            child: Text('Name', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: colorScheme.onSurfaceVariant)),
          ),
          SizedBox(
            width: 100,
            child: Text('Date', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: colorScheme.onSurfaceVariant)),
          ),
          SizedBox(
            width: 70,
            child: Text('Size', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: colorScheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  Widget _buildFileList(ColorScheme colorScheme) {
    if (_files.isEmpty) {
      return GestureDetector(
        onSecondaryTapDown: (details) => _showEmptySpaceContextMenu(context, details.globalPosition),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.folder_open, size: 48, color: colorScheme.onSurfaceVariant.withOpacity(0.5)),
              const SizedBox(height: 8),
              Text('Empty folder', style: TextStyle(color: colorScheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              Text('Right-click to create a file or folder', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: _files.length + 1, // +1 for empty space at bottom
      itemBuilder: (context, index) {
        if (index < _files.length) {
          final file = _files[index];
          final key = '$_currentPath/${file.name}';
          final isSelected = _selectedFiles.contains(key);
          return _buildFileRow(file, isSelected, colorScheme);
        }
        // Empty space at bottom for context menu
        return GestureDetector(
          onSecondaryTapDown: (details) => _showEmptySpaceContextMenu(context, details.globalPosition),
          behavior: HitTestBehavior.opaque,
          child: const SizedBox(height: 200),
        );
      },
    );
  }

  Widget _buildFileRow(RemoteFile file, bool isSelected, ColorScheme colorScheme) {
    return GestureDetector(
      onSecondaryTapDown: (details) {
        // Stop propagation to prevent parent context menu from showing
        _showFileContextMenu(context, details.globalPosition, file);
      },
      behavior: HitTestBehavior.opaque,
      child: InkWell(
        onTap: () => _toggleSelection(file),
        onDoubleTap: () => _openItem(file),
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? colorScheme.primaryContainer.withOpacity(0.5) : null,
          ),
          child: Row(
            children: [
              // Icon
              SizedBox(
                width: 24,
                child: Icon(
                  _getFileIcon(file),
                  size: 16,
                  color: _getFileIconColor(file, colorScheme),
                ),
              ),
              // Name
              Expanded(
                flex: 3,
                child: Text(
                  file.name,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Date
              SizedBox(
                width: 100,
                child: Text(
                  _formatDate(file.modified),
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              // Size
              SizedBox(
                width: 70,
                child: Text(
                  file.formattedSize,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Show context menu for a file
  void _showFileContextMenu(BuildContext context, Offset position, RemoteFile file) async {
    final colorScheme = Theme.of(context).colorScheme;
    final fullPath = _currentPath.endsWith('/')
        ? '$_currentPath${file.name}'
        : '$_currentPath/${file.name}';

    final result = await showMenu<FileAction>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        if (!file.isDirectory) ...[
          PopupMenuItem(
            value: FileAction.download,
            child: Row(
              children: [
                Icon(Icons.download, size: 18, color: colorScheme.onSurface),
                const SizedBox(width: 12),
                Text('Download "${file.name}"'),
              ],
            ),
          ),
          PopupMenuItem(
            value: FileAction.open,
            child: Row(
              children: [
                Icon(Icons.open_in_new, size: 18, color: colorScheme.onSurface),
                const SizedBox(width: 12),
                const Text('Open'),
              ],
            ),
          ),
          const PopupMenuDivider(),
        ],
        PopupMenuItem(
          value: FileAction.info,
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: colorScheme.onSurface),
              const SizedBox(width: 12),
              const Text('Info'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: FileAction.rename,
          child: Row(
            children: [
              Icon(Icons.edit, size: 18, color: colorScheme.onSurface),
              const SizedBox(width: 12),
              const Text('Rename'),
            ],
          ),
        ),
        PopupMenuItem(
          value: FileAction.duplicate,
          child: Row(
            children: [
              Icon(Icons.copy, size: 18, color: colorScheme.onSurface),
              const SizedBox(width: 12),
              const Text('Duplicate'),
            ],
          ),
        ),
        PopupMenuItem(
          value: FileAction.move,
          child: Row(
            children: [
              Icon(Icons.drive_file_move, size: 18, color: colorScheme.onSurface),
              const SizedBox(width: 12),
              const Text('Move...'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: FileAction.delete,
          child: Row(
            children: [
              Icon(Icons.delete, size: 18, color: colorScheme.error),
              const SizedBox(width: 12),
              Text('Delete', style: TextStyle(color: colorScheme.error)),
            ],
          ),
        ),
      ],
    );

    if (result != null) {
      await _handleFileAction(result, file, fullPath);
    }
  }

  /// Show context menu for empty space
  void _showEmptySpaceContextMenu(BuildContext context, Offset position) async {
    final colorScheme = Theme.of(context).colorScheme;

    final result = await showMenu<FileAction>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        PopupMenuItem(
          value: FileAction.newFolder,
          child: Row(
            children: [
              Icon(Icons.create_new_folder, size: 18, color: colorScheme.onSurface),
              const SizedBox(width: 12),
              const Text('New folder'),
            ],
          ),
        ),
        PopupMenuItem(
          value: FileAction.newFile,
          child: Row(
            children: [
              Icon(Icons.note_add, size: 18, color: colorScheme.onSurface),
              const SizedBox(width: 12),
              const Text('New file'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: FileAction.refresh,
          child: Row(
            children: [
              Icon(Icons.refresh, size: 18, color: colorScheme.onSurface),
              const SizedBox(width: 12),
              const Text('Refresh'),
            ],
          ),
        ),
      ],
    );

    if (result != null) {
      await _handleFileAction(result, null, null);
    }
  }

  /// Handle context menu action
  Future<void> _handleFileAction(FileAction action, RemoteFile? file, String? fullPath) async {
    switch (action) {
      case FileAction.open:
        if (file != null && fullPath != null) {
          widget.onFileSelected?.call(file, _selectedServer!, fullPath);
        }
        break;

      case FileAction.download:
        if (file != null && fullPath != null) {
          widget.onDownloadFile?.call(file, _selectedServer!, fullPath);
        }
        break;

      case FileAction.info:
        if (file != null && fullPath != null) {
          await _showFileInfo(file, fullPath);
        }
        break;

      case FileAction.delete:
        if (file != null && fullPath != null) {
          await _deleteFile(file, fullPath);
        }
        break;

      case FileAction.rename:
        if (file != null && fullPath != null) {
          await _renameFile(file, fullPath);
        }
        break;

      case FileAction.duplicate:
        if (file != null && fullPath != null) {
          await _duplicateFile(file, fullPath);
        }
        break;

      case FileAction.move:
        if (file != null && fullPath != null) {
          await _moveFile(file, fullPath);
        }
        break;

      case FileAction.newFolder:
        await _createNewFolder();
        break;

      case FileAction.newFile:
        await _createNewFile();
        break;

      case FileAction.refresh:
        await _loadFiles();
        break;
    }
  }

  /// Show file info dialog
  Future<void> _showFileInfo(RemoteFile file, String fullPath) async {
    try {
      final result = await widget.client.execute(
        _selectedServer!.name,
        'stat "$fullPath" && file "$fullPath"',
        timeout: 10000,
      );

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(_getFileIcon(file), color: _getFileIconColor(file, Theme.of(context).colorScheme)),
              const SizedBox(width: 12),
              Expanded(child: Text(file.name, overflow: TextOverflow.ellipsis)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildInfoRow('Path', fullPath),
                _buildInfoRow('Size', file.formattedSize),
                _buildInfoRow('Modified', file.modified),
                _buildInfoRow('Permissions', file.permissions),
                const SizedBox(height: 16),
                const Text('Details:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    result.stdout.isNotEmpty ? result.stdout : result.stderr,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showError('Failed to get file info: $e');
    }
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }

  /// Delete a file or directory
  Future<void> _deleteFile(RemoteFile file, String fullPath) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Are you sure you want to delete "${file.name}"?\n\nThis action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final flags = file.isDirectory ? '-rf' : '-f';
      final result = await widget.client.execute(
        _selectedServer!.name,
        'rm $flags "$fullPath"',
        timeout: 30000,
      );

      if (result.code == 0) {
        _showSuccess('Deleted "${file.name}"');
        await _loadFiles();
      } else {
        _showError('Failed to delete: ${result.stderr}');
      }
    } catch (e) {
      _showError('Failed to delete: $e');
    }
  }

  /// Rename a file or directory
  Future<void> _renameFile(RemoteFile file, String fullPath) async {
    final controller = TextEditingController(text: file.name);

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'New name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty || newName == file.name) return;

    try {
      final newPath = _currentPath.endsWith('/')
          ? '$_currentPath$newName'
          : '$_currentPath/$newName';

      final result = await widget.client.execute(
        _selectedServer!.name,
        'mv "$fullPath" "$newPath"',
        timeout: 10000,
      );

      if (result.code == 0) {
        _showSuccess('Renamed to "$newName"');
        await _loadFiles();
      } else {
        _showError('Failed to rename: ${result.stderr}');
      }
    } catch (e) {
      _showError('Failed to rename: $e');
    }
  }

  /// Duplicate a file or directory
  Future<void> _duplicateFile(RemoteFile file, String fullPath) async {
    try {
      // Generate duplicate name
      final baseName = file.name;
      final ext = baseName.contains('.') ? '.${baseName.split('.').last}' : '';
      final nameWithoutExt = ext.isNotEmpty ? baseName.substring(0, baseName.length - ext.length) : baseName;
      final duplicateName = '${nameWithoutExt} copy$ext';

      final newPath = _currentPath.endsWith('/')
          ? '$_currentPath$duplicateName'
          : '$_currentPath/$duplicateName';

      final flags = file.isDirectory ? '-r' : '';
      final result = await widget.client.execute(
        _selectedServer!.name,
        'cp $flags "$fullPath" "$newPath"',
        timeout: 60000,
      );

      if (result.code == 0) {
        _showSuccess('Created "$duplicateName"');
        await _loadFiles();
      } else {
        _showError('Failed to duplicate: ${result.stderr}');
      }
    } catch (e) {
      _showError('Failed to duplicate: $e');
    }
  }

  /// Move a file (shows path dialog)
  Future<void> _moveFile(RemoteFile file, String fullPath) async {
    final controller = TextEditingController(text: fullPath);

    final newPath = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Move "${file.name}"'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Destination path',
            border: OutlineInputBorder(),
            helperText: 'Enter the full destination path',
          ),
          autofocus: true,
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Move'),
          ),
        ],
      ),
    );

    if (newPath == null || newPath.isEmpty || newPath == fullPath) return;

    try {
      final result = await widget.client.execute(
        _selectedServer!.name,
        'mv "$fullPath" "$newPath"',
        timeout: 30000,
      );

      if (result.code == 0) {
        _showSuccess('Moved to "$newPath"');
        await _loadFiles();
      } else {
        _showError('Failed to move: ${result.stderr}');
      }
    } catch (e) {
      _showError('Failed to move: $e');
    }
  }

  /// Create new folder
  Future<void> _createNewFolder() async {
    final controller = TextEditingController();

    final folderName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Folder name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (folderName == null || folderName.isEmpty) return;

    try {
      final newPath = _currentPath.endsWith('/')
          ? '$_currentPath$folderName'
          : '$_currentPath/$folderName';

      final result = await widget.client.execute(
        _selectedServer!.name,
        'mkdir -p "$newPath"',
        timeout: 10000,
      );

      if (result.code == 0) {
        _showSuccess('Created folder "$folderName"');
        await _loadFiles();
      } else {
        _showError('Failed to create folder: ${result.stderr}');
      }
    } catch (e) {
      _showError('Failed to create folder: $e');
    }
  }

  /// Create new file
  Future<void> _createNewFile() async {
    final controller = TextEditingController();

    final fileName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New File'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'File name',
            border: OutlineInputBorder(),
            hintText: 'e.g., example.txt',
          ),
          autofocus: true,
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (fileName == null || fileName.isEmpty) return;

    try {
      final newPath = _currentPath.endsWith('/')
          ? '$_currentPath$fileName'
          : '$_currentPath/$fileName';

      final result = await widget.client.execute(
        _selectedServer!.name,
        'touch "$newPath"',
        timeout: 10000,
      );

      if (result.code == 0) {
        _showSuccess('Created file "$fileName"');
        await _loadFiles();
      } else {
        _showError('Failed to create file: ${result.stderr}');
      }
    } catch (e) {
      _showError('Failed to create file: $e');
    }
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  String _formatDate(String modified) {
    try {
      final date = DateTime.parse(modified);
      return DateFormat('dd.MM.yy HH:mm').format(date);
    } catch (e) {
      return modified;
    }
  }

  IconData _getFileIcon(RemoteFile file) {
    if (file.isDirectory) return Icons.folder;
    if (file.isLink) return Icons.link;

    final ext = file.name.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'svg':
      case 'webp':
        return Icons.image;
      case 'mp3':
      case 'wav':
      case 'flac':
        return Icons.audio_file;
      case 'mp4':
      case 'mkv':
      case 'avi':
      case 'mov':
        return Icons.video_file;
      case 'zip':
      case 'tar':
      case 'gz':
      case 'rar':
        return Icons.folder_zip;
      case 'js':
      case 'ts':
      case 'py':
      case 'dart':
      case 'java':
      case 'c':
      case 'cpp':
      case 'rs':
      case 'go':
        return Icons.code;
      case 'json':
      case 'xml':
      case 'yaml':
      case 'yml':
      case 'toml':
        return Icons.data_object;
      case 'css':
        return Icons.css;
      case 'html':
        return Icons.html;
      case 'md':
      case 'txt':
        return Icons.article;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileIconColor(RemoteFile file, ColorScheme colorScheme) {
    if (file.isDirectory) return Colors.blue;
    if (file.isLink) return Colors.teal;

    final ext = file.name.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Colors.red;
      case 'doc':
      case 'docx':
        return Colors.blue;
      case 'xls':
      case 'xlsx':
        return Colors.green;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'svg':
        return Colors.purple;
      case 'mp3':
      case 'wav':
        return Colors.orange;
      case 'mp4':
      case 'mkv':
        return Colors.pink;
      case 'zip':
      case 'tar':
      case 'gz':
        return Colors.brown;
      case 'js':
      case 'ts':
        return Colors.amber;
      case 'py':
        return Colors.blue;
      case 'dart':
        return Colors.cyan;
      case 'css':
        return Colors.blue;
      case 'html':
        return Colors.orange;
      default:
        return colorScheme.onSurfaceVariant;
    }
  }

  Widget _buildErrorView(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: colorScheme.error),
          const SizedBox(height: 8),
          Text(
            'Cannot access folder',
            style: TextStyle(color: colorScheme.error),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(
              _error ?? '',
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _navigateUp,
            child: const Text('Go back'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(ColorScheme colorScheme) {
    final totalItems = _files.length;
    final selectedCount = _selectedFiles.length;
    final selectedSize = _files
        .where((f) => _selectedFiles.contains('$_currentPath/${f.name}'))
        .fold<int>(0, (sum, f) => sum + f.size);

    String statusText;
    if (selectedCount > 0) {
      final sizeStr = _formatSize(selectedSize);
      statusText = '$selectedCount selected ($sizeStr)';
    } else {
      statusText = '$totalItems items';
    }

    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Text(
            statusText,
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
          const Spacer(),
          Text(
            _selectedServer!.name,
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _formatSize(int size) {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
