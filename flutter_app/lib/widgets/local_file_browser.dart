import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:intl/intl.dart';

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

/// Local file browser widget - Finder-like design
class LocalFileBrowser extends StatefulWidget {
  final Function(LocalFile)? onFileSelected;
  final Function(List<LocalFile>)? onFilesSelected;

  const LocalFileBrowser({
    super.key,
    this.onFileSelected,
    this.onFilesSelected,
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

    return Column(
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
            icon: const Icon(Icons.arrow_upward, size: 16),
            onPressed: _navigateUp,
            tooltip: 'Go up',
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
                      child: Icon(Icons.computer, size: 14, color: colorScheme.primary),
                    ),
                  ),
                  // Path parts
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 48, color: colorScheme.onSurfaceVariant.withOpacity(0.5)),
            const SizedBox(height: 8),
            Text('Empty folder', style: TextStyle(color: colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _files.length,
      itemBuilder: (context, index) {
        final file = _files[index];
        final isSelected = _selectedFiles.contains(file.fullPath);

        return _buildFileRow(file, isSelected, colorScheme);
      },
    );
  }

  Widget _buildFileRow(LocalFile file, bool isSelected, ColorScheme colorScheme) {
    return InkWell(
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
      ),
    );
  }

  IconData _getFileIcon(LocalFile file) {
    if (file.isDirectory) return Icons.folder;

    final ext = file.fileExtension.toLowerCase();
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
          Icon(Icons.error_outline, size: 48, color: colorScheme.error),
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
