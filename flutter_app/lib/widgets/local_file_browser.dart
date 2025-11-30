import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:path/path.dart' as path;
import 'package:intl/intl.dart';

/// Context menu action types for local files
enum LocalFileAction {
  open,
  openInFinder,
  uploadToServer,
  info,
  delete,
  rename,
  duplicate,
  move,
  newFolder,
  newFile,
  refresh,
}

/// Data model for drag operations
class DraggedLocalFiles {
  final List<LocalFile> files;
  final String sourcePath;

  DraggedLocalFiles({required this.files, required this.sourcePath});
}

/// Model for a local file entry
class LocalFile {
  final String name;
  final String fullPath;
  final bool isDirectory;
  final int size;
  final DateTime modified;

  LocalFile({
    required this.name,
    required this.fullPath,
    required this.isDirectory,
    required this.size,
    required this.modified,
  });

  String get formattedSize {
    if (isDirectory) return '-';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String get formattedDate {
    return DateFormat('dd.MM.yy HH:mm').format(modified);
  }

  String get fileExtension {
    if (isDirectory) return '';
    final ext = path.extension(name);
    return ext.isNotEmpty ? ext.substring(1).toUpperCase() : '';
  }
}

/// Data model for remote files being dropped
class DraggedRemoteFiles {
  final List<dynamic> files; // RemoteFile from mcp_client
  final String serverName;
  final String sourcePath;

  DraggedRemoteFiles({
    required this.files,
    required this.serverName,
    required this.sourcePath,
  });
}

/// Local file browser widget - Finder-like design
class LocalFileBrowser extends StatefulWidget {
  final Function(LocalFile)? onFileSelected;
  final Function(List<LocalFile>)? onFilesSelected;
  /// Called when files should be uploaded to remote server
  final Function(List<LocalFile> files)? onUploadFiles;
  /// Called when remote files are dropped here for download
  final Function(DraggedRemoteFiles remoteFiles, String localDestination)? onDownloadFiles;

  const LocalFileBrowser({
    super.key,
    this.onFileSelected,
    this.onFilesSelected,
    this.onUploadFiles,
    this.onDownloadFiles,
  });

  @override
  State<LocalFileBrowser> createState() => _LocalFileBrowserState();
}

class _LocalFileBrowserState extends State<LocalFileBrowser> {
  String _currentPath = '';
  List<LocalFile> _files = [];
  Set<String> _selectedFiles = {};
  bool _isLoading = false;
  String? _error;
  bool _showHidden = false;
  bool _isDragOver = false;

  /// Get current path for external access
  String get currentPath => _currentPath;

  @override
  void initState() {
    super.initState();
    _currentPath = Platform.environment['HOME'] ?? '/';
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final dir = Directory(_currentPath);
      final entities = await dir.list().toList();

      final files = <LocalFile>[];
      for (final entity in entities) {
        final name = path.basename(entity.path);

        // Skip hidden files unless enabled
        if (!_showHidden && name.startsWith('.')) continue;

        try {
          final stat = await entity.stat();
          files.add(LocalFile(
            name: name,
            fullPath: entity.path,
            isDirectory: entity is Directory,
            size: stat.size,
            modified: stat.modified,
          ));
        } catch (e) {
          // Skip files we can't stat
        }
      }

      // Sort: directories first, then by name
      files.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      setState(() {
        _files = files;
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
    final parent = path.dirname(_currentPath);
    if (parent != _currentPath) {
      _navigateTo(parent);
    }
  }

  void _openItem(LocalFile file) {
    if (file.isDirectory) {
      _navigateTo(file.fullPath);
    } else {
      widget.onFileSelected?.call(file);
    }
  }

  void _toggleSelection(LocalFile file) {
    setState(() {
      if (_selectedFiles.contains(file.fullPath)) {
        _selectedFiles.remove(file.fullPath);
      } else {
        _selectedFiles.add(file.fullPath);
      }
    });

    // Notify parent of selection change
    final selectedLocalFiles =
        _files.where((f) => _selectedFiles.contains(f.fullPath)).toList();
    widget.onFilesSelected?.call(selectedLocalFiles);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DragTarget<DraggedRemoteFiles>(
      onWillAcceptWithDetails: (details) {
        setState(() => _isDragOver = true);
        return true;
      },
      onLeave: (data) {
        setState(() => _isDragOver = false);
      },
      onAcceptWithDetails: (details) {
        setState(() => _isDragOver = false);
        // Handle dropped remote files
        widget.onDownloadFiles?.call(details.data, _currentPath);
      },
      builder: (context, candidateData, rejectedData) {
        return Container(
          decoration: BoxDecoration(
            border: _isDragOver
                ? Border.all(color: colorScheme.primary, width: 2)
                : null,
            color: _isDragOver
                ? colorScheme.primaryContainer.withOpacity(0.1)
                : null,
          ),
          child: Column(
            children: [
              // Header with path breadcrumb
              _buildHeader(colorScheme),

              // Column headers
              _buildColumnHeaders(colorScheme),

              // File list
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? _buildErrorView(colorScheme)
                        : _buildFileList(colorScheme),
              ),

              // Status bar
              _buildStatusBar(colorScheme),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    final pathParts = _currentPath.split('/').where((p) => p.isNotEmpty).toList();

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
            icon: HugeIcon(icon: HugeIcons.strokeRoundedArrowUp01, size: 16, color: colorScheme.onSurface),
            onPressed: _navigateUp,
            tooltip: 'Go up',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 16, color: colorScheme.onSurface),
            onPressed: _loadFiles,
            tooltip: 'Refresh',
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
                  // Root
                  InkWell(
                    onTap: () => _navigateTo('/'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: HugeIcon(icon: HugeIcons.strokeRoundedComputer, size: 14, color: colorScheme.primary),
                    ),
                  ),
                  // Path parts
                  for (var i = 0; i < pathParts.length; i++) ...[
                    HugeIcon(icon: HugeIcons.strokeRoundedArrowRight01, size: 14, color: colorScheme.onSurfaceVariant),
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
            icon: HugeIcon(
              icon: _showHidden ? HugeIcons.strokeRoundedViewOffSlash : HugeIcons.strokeRoundedView,
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
              HugeIcon(icon: HugeIcons.strokeRoundedFolderOpen, size: 48, color: colorScheme.onSurfaceVariant.withOpacity(0.5)),
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
          final isSelected = _selectedFiles.contains(file.fullPath);
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

  Widget _buildFileRow(LocalFile file, bool isSelected, ColorScheme colorScheme) {
    // Get selected files for drag, or just this file
    final filesToDrag = _selectedFiles.isNotEmpty && _selectedFiles.contains(file.fullPath)
        ? _files.where((f) => _selectedFiles.contains(f.fullPath)).toList()
        : [file];

    return Draggable<DraggedLocalFiles>(
      data: DraggedLocalFiles(files: filesToDrag, sourcePath: _currentPath),
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              HugeIcon(
                icon: filesToDrag.length > 1
                    ? HugeIcons.strokeRoundedFiles01
                    : _getFileIcon(file),
                size: 16,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                filesToDrag.length > 1
                    ? '${filesToDrag.length} items'
                    : file.name,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.5,
        child: _buildFileRowContent(file, isSelected, colorScheme),
      ),
      child: GestureDetector(
        onSecondaryTapDown: (details) {
          // Stop propagation to prevent parent context menu from showing
          _showFileContextMenu(context, details.globalPosition, file);
        },
        behavior: HitTestBehavior.opaque,
        child: InkWell(
          onTap: () => _toggleSelection(file),
          onDoubleTap: () => _openItem(file),
          child: _buildFileRowContent(file, isSelected, colorScheme),
        ),
      ),
    );
  }

  Widget _buildFileRowContent(LocalFile file, bool isSelected, ColorScheme colorScheme) {
    return Container(
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
            child: HugeIcon(
              icon: _getFileIcon(file),
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
              file.formattedDate,
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
    );
  }

  /// Show context menu for a file
  void _showFileContextMenu(BuildContext context, Offset position, LocalFile file) async {
    final colorScheme = Theme.of(context).colorScheme;
    final hasUploadCallback = widget.onUploadFiles != null;

    final result = await showMenu<LocalFileAction>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        PopupMenuItem(
          value: LocalFileAction.open,
          child: Row(
            children: [
              HugeIcon(icon: HugeIcons.strokeRoundedLinkSquare02, size: 18, color: colorScheme.onSurface),
              const SizedBox(width: 12),
              const Text('Open'),
            ],
          ),
        ),
        PopupMenuItem(
          value: LocalFileAction.openInFinder,
          child: Row(
            children: [
              HugeIcon(icon: HugeIcons.strokeRoundedFolderOpen, size: 18, color: colorScheme.onSurface),
              const SizedBox(width: 12),
              const Text('Show in Finder'),
            ],
          ),
        ),
        if (hasUploadCallback) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: LocalFileAction.uploadToServer,
            child: Row(
              children: [
                HugeIcon(icon: HugeIcons.strokeRoundedUpload02, size: 18, color: colorScheme.primary),
                const SizedBox(width: 12),
                Text('Upload to Server', style: TextStyle(color: colorScheme.primary)),
              ],
            ),
          ),
        ],
        const PopupMenuDivider(),
        PopupMenuItem(
          value: LocalFileAction.info,
          child: Row(
            children: [
              HugeIcon(icon: HugeIcons.strokeRoundedInformationCircle, size: 18, color: colorScheme.onSurface),
              const SizedBox(width: 12),
              const Text('Info'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: LocalFileAction.rename,
          child: Row(
            children: [
              HugeIcon(icon: HugeIcons.strokeRoundedPencilEdit01, size: 18, color: colorScheme.onSurface),
              const SizedBox(width: 12),
              const Text('Rename'),
            ],
          ),
        ),
        PopupMenuItem(
          value: LocalFileAction.duplicate,
          child: Row(
            children: [
              HugeIcon(icon: HugeIcons.strokeRoundedCopy01, size: 18, color: colorScheme.onSurface),
              const SizedBox(width: 12),
              const Text('Duplicate'),
            ],
          ),
        ),
        PopupMenuItem(
          value: LocalFileAction.move,
          child: Row(
            children: [
              HugeIcon(icon: HugeIcons.strokeRoundedFolderTransfer, size: 18, color: colorScheme.onSurface),
              const SizedBox(width: 12),
              const Text('Move...'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: LocalFileAction.delete,
          child: Row(
            children: [
              HugeIcon(icon: HugeIcons.strokeRoundedDelete02, size: 18, color: colorScheme.error),
              const SizedBox(width: 12),
              Text('Move to Trash', style: TextStyle(color: colorScheme.error)),
            ],
          ),
        ),
      ],
    );

    if (result != null) {
      await _handleFileAction(result, file);
    }
  }

  /// Show context menu for empty space
  void _showEmptySpaceContextMenu(BuildContext context, Offset position) async {
    final colorScheme = Theme.of(context).colorScheme;

    final result = await showMenu<LocalFileAction>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        PopupMenuItem(
          value: LocalFileAction.newFolder,
          child: Row(
            children: [
              HugeIcon(icon: HugeIcons.strokeRoundedFolderAdd, size: 18, color: colorScheme.onSurface),
              const SizedBox(width: 12),
              const Text('New folder'),
            ],
          ),
        ),
        PopupMenuItem(
          value: LocalFileAction.newFile,
          child: Row(
            children: [
              HugeIcon(icon: HugeIcons.strokeRoundedFileAdd, size: 18, color: colorScheme.onSurface),
              const SizedBox(width: 12),
              const Text('New file'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: LocalFileAction.refresh,
          child: Row(
            children: [
              HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 18, color: colorScheme.onSurface),
              const SizedBox(width: 12),
              const Text('Refresh'),
            ],
          ),
        ),
      ],
    );

    if (result != null) {
      await _handleFileAction(result, null);
    }
  }

  /// Handle context menu action
  Future<void> _handleFileAction(LocalFileAction action, LocalFile? file) async {
    switch (action) {
      case LocalFileAction.open:
        if (file != null) {
          _openItem(file);
        }
        break;

      case LocalFileAction.openInFinder:
        if (file != null) {
          await _openInFinder(file);
        }
        break;

      case LocalFileAction.uploadToServer:
        if (file != null) {
          // Get selected files or just this file
          final filesToUpload = _selectedFiles.isNotEmpty && _selectedFiles.contains(file.fullPath)
              ? _files.where((f) => _selectedFiles.contains(f.fullPath)).toList()
              : [file];
          widget.onUploadFiles?.call(filesToUpload);
        }
        break;

      case LocalFileAction.info:
        if (file != null) {
          await _showFileInfo(file);
        }
        break;

      case LocalFileAction.delete:
        if (file != null) {
          await _deleteFile(file);
        }
        break;

      case LocalFileAction.rename:
        if (file != null) {
          await _renameFile(file);
        }
        break;

      case LocalFileAction.duplicate:
        if (file != null) {
          await _duplicateFile(file);
        }
        break;

      case LocalFileAction.move:
        if (file != null) {
          await _moveFile(file);
        }
        break;

      case LocalFileAction.newFolder:
        await _createNewFolder();
        break;

      case LocalFileAction.newFile:
        await _createNewFile();
        break;

      case LocalFileAction.refresh:
        await _loadFiles();
        break;
    }
  }

  /// Open file/folder in Finder
  Future<void> _openInFinder(LocalFile file) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', ['-R', file.fullPath]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [path.dirname(file.fullPath)]);
      } else if (Platform.isWindows) {
        await Process.run('explorer', ['/select,', file.fullPath]);
      }
    } catch (e) {
      _showError('Failed to open in Finder: $e');
    }
  }

  /// Show file info dialog
  Future<void> _showFileInfo(LocalFile file) async {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            HugeIcon(icon: _getFileIcon(file), size: 24, color: _getFileIconColor(file, Theme.of(context).colorScheme)),
            const SizedBox(width: 12),
            Expanded(child: Text(file.name, overflow: TextOverflow.ellipsis)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildInfoRow('Path', file.fullPath),
              _buildInfoRow('Size', file.formattedSize),
              _buildInfoRow('Modified', file.formattedDate),
              _buildInfoRow('Type', file.isDirectory ? 'Folder' : (file.fileExtension.isNotEmpty ? '${file.fileExtension} File' : 'File')),
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
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }

  /// Delete a file or directory (move to trash)
  Future<void> _deleteFile(LocalFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move to Trash'),
        content: Text('Are you sure you want to move "${file.name}" to Trash?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Move to Trash'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      if (Platform.isMacOS) {
        // Use osascript to move to trash on macOS
        final result = await Process.run('osascript', [
          '-e',
          'tell application "Finder" to delete POSIX file "${file.fullPath}"'
        ]);
        if (result.exitCode == 0) {
          _showSuccess('Moved "${file.name}" to Trash');
          await _loadFiles();
        } else {
          _showError('Failed to move to trash: ${result.stderr}');
        }
      } else {
        // Fallback to direct delete
        if (file.isDirectory) {
          await Directory(file.fullPath).delete(recursive: true);
        } else {
          await File(file.fullPath).delete();
        }
        _showSuccess('Deleted "${file.name}"');
        await _loadFiles();
      }
    } catch (e) {
      _showError('Failed to delete: $e');
    }
  }

  /// Rename a file or directory
  Future<void> _renameFile(LocalFile file) async {
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
      final newPath = path.join(_currentPath, newName);
      if (file.isDirectory) {
        await Directory(file.fullPath).rename(newPath);
      } else {
        await File(file.fullPath).rename(newPath);
      }
      _showSuccess('Renamed to "$newName"');
      await _loadFiles();
    } catch (e) {
      _showError('Failed to rename: $e');
    }
  }

  /// Duplicate a file or directory
  Future<void> _duplicateFile(LocalFile file) async {
    try {
      // Generate duplicate name
      final baseName = file.name;
      final ext = path.extension(baseName);
      final nameWithoutExt = ext.isNotEmpty ? baseName.substring(0, baseName.length - ext.length) : baseName;
      final duplicateName = '$nameWithoutExt copy$ext';
      final newPath = path.join(_currentPath, duplicateName);

      if (file.isDirectory) {
        await _copyDirectory(Directory(file.fullPath), Directory(newPath));
      } else {
        await File(file.fullPath).copy(newPath);
      }

      _showSuccess('Created "$duplicateName"');
      await _loadFiles();
    } catch (e) {
      _showError('Failed to duplicate: $e');
    }
  }

  /// Copy directory recursively
  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list()) {
      final newPath = path.join(destination.path, path.basename(entity.path));
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      } else if (entity is File) {
        await entity.copy(newPath);
      }
    }
  }

  /// Move a file (shows path dialog)
  Future<void> _moveFile(LocalFile file) async {
    final controller = TextEditingController(text: file.fullPath);

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

    if (newPath == null || newPath.isEmpty || newPath == file.fullPath) return;

    try {
      if (file.isDirectory) {
        await Directory(file.fullPath).rename(newPath);
      } else {
        await File(file.fullPath).rename(newPath);
      }
      _showSuccess('Moved to "$newPath"');
      await _loadFiles();
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
      final newPath = path.join(_currentPath, folderName);
      await Directory(newPath).create();
      _showSuccess('Created folder "$folderName"');
      await _loadFiles();
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
      final newPath = path.join(_currentPath, fileName);
      await File(newPath).create();
      _showSuccess('Created file "$fileName"');
      await _loadFiles();
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

  List<List<dynamic>> _getFileIcon(LocalFile file) {
    if (file.isDirectory) return HugeIcons.strokeRoundedFolder01;

    final ext = file.fileExtension.toLowerCase();
    switch (ext) {
      case 'pdf':
        return HugeIcons.strokeRoundedPdf01;
      case 'doc':
      case 'docx':
        return HugeIcons.strokeRoundedDoc01;
      case 'xls':
      case 'xlsx':
        return HugeIcons.strokeRoundedXls01;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'svg':
      case 'webp':
        return HugeIcons.strokeRoundedImage01;
      case 'mp3':
      case 'wav':
      case 'flac':
        return HugeIcons.strokeRoundedMusicNote01;
      case 'mp4':
      case 'mkv':
      case 'avi':
      case 'mov':
        return HugeIcons.strokeRoundedVideo01;
      case 'zip':
      case 'tar':
      case 'gz':
      case 'rar':
        return HugeIcons.strokeRoundedFolderZip;
      case 'js':
      case 'ts':
      case 'py':
      case 'dart':
      case 'java':
      case 'c':
      case 'cpp':
      case 'rs':
      case 'go':
        return HugeIcons.strokeRoundedSourceCode;
      case 'json':
      case 'xml':
      case 'yaml':
      case 'yml':
      case 'toml':
        return HugeIcons.strokeRoundedFileScript;
      case 'css':
        return HugeIcons.strokeRoundedCss3;
      case 'html':
        return HugeIcons.strokeRoundedHtml5;
      case 'md':
      case 'txt':
        return HugeIcons.strokeRoundedTxt01;
      default:
        return HugeIcons.strokeRoundedFile01;
    }
  }

  Color _getFileIconColor(LocalFile file, ColorScheme colorScheme) {
    if (file.isDirectory) return Colors.blue;

    final ext = file.fileExtension.toLowerCase();
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
          HugeIcon(icon: HugeIcons.strokeRoundedAlertCircle, size: 48, color: colorScheme.error),
          const SizedBox(height: 8),
          Text(
            'Cannot access folder',
            style: TextStyle(color: colorScheme.error),
          ),
          const SizedBox(height: 4),
          Text(
            _error ?? '',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
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
        .where((f) => _selectedFiles.contains(f.fullPath))
        .fold<int>(0, (sum, f) => sum + f.size);

    String statusText;
    if (selectedCount > 0) {
      final sizeStr = LocalFile(
        name: '',
        fullPath: '',
        isDirectory: false,
        size: selectedSize,
        modified: DateTime.now(),
      ).formattedSize;
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
        ],
      ),
    );
  }
}
