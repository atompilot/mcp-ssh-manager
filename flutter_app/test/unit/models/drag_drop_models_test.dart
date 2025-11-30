import 'package:flutter_test/flutter_test.dart';
import 'package:mcp_file_manager/widgets/local_file_browser.dart';

void main() {
  group('LocalFile', () {
    test('should create with all required fields', () {
      final file = LocalFile(
        name: 'test.txt',
        fullPath: '/Users/test/test.txt',
        isDirectory: false,
        size: 1024,
        modified: DateTime(2024, 1, 15, 10, 30),
      );

      expect(file.name, 'test.txt');
      expect(file.fullPath, '/Users/test/test.txt');
      expect(file.isDirectory, isFalse);
      expect(file.size, 1024);
      expect(file.modified, DateTime(2024, 1, 15, 10, 30));
    });

    test('should create directory entry', () {
      final dir = LocalFile(
        name: 'Documents',
        fullPath: '/Users/test/Documents',
        isDirectory: true,
        size: 0,
        modified: DateTime(2024, 1, 15, 10, 30),
      );

      expect(dir.name, 'Documents');
      expect(dir.isDirectory, isTrue);
    });

    group('formattedSize', () {
      test('should return dash for directories', () {
        final dir = LocalFile(
          name: 'folder',
          fullPath: '/folder',
          isDirectory: true,
          size: 4096,
          modified: DateTime.now(),
        );

        expect(dir.formattedSize, '-');
      });

      test('should format bytes correctly', () {
        final file = LocalFile(
          name: 'tiny.txt',
          fullPath: '/tiny.txt',
          isDirectory: false,
          size: 500,
          modified: DateTime.now(),
        );

        expect(file.formattedSize, '500 B');
      });

      test('should format kilobytes correctly', () {
        final file = LocalFile(
          name: 'small.txt',
          fullPath: '/small.txt',
          isDirectory: false,
          size: 2048, // 2 KB
          modified: DateTime.now(),
        );

        expect(file.formattedSize, '2.0 KB');
      });

      test('should format megabytes correctly', () {
        final file = LocalFile(
          name: 'medium.zip',
          fullPath: '/medium.zip',
          isDirectory: false,
          size: 5 * 1024 * 1024, // 5 MB
          modified: DateTime.now(),
        );

        expect(file.formattedSize, '5.0 MB');
      });

      test('should format gigabytes correctly', () {
        final file = LocalFile(
          name: 'large.iso',
          fullPath: '/large.iso',
          isDirectory: false,
          size: 2 * 1024 * 1024 * 1024, // 2 GB
          modified: DateTime.now(),
        );

        expect(file.formattedSize, '2.0 GB');
      });
    });

    group('formattedDate', () {
      test('should format date correctly', () {
        final file = LocalFile(
          name: 'test.txt',
          fullPath: '/test.txt',
          isDirectory: false,
          size: 100,
          modified: DateTime(2024, 3, 15, 14, 30),
        );

        expect(file.formattedDate, '15.03.24 14:30');
      });
    });

    group('fileExtension', () {
      test('should return empty for directories', () {
        final dir = LocalFile(
          name: 'folder',
          fullPath: '/folder',
          isDirectory: true,
          size: 0,
          modified: DateTime.now(),
        );

        expect(dir.fileExtension, '');
      });

      test('should return uppercase extension', () {
        final file = LocalFile(
          name: 'document.pdf',
          fullPath: '/document.pdf',
          isDirectory: false,
          size: 1000,
          modified: DateTime.now(),
        );

        expect(file.fileExtension, 'PDF');
      });

      test('should return empty for files without extension', () {
        final file = LocalFile(
          name: 'README',
          fullPath: '/README',
          isDirectory: false,
          size: 500,
          modified: DateTime.now(),
        );

        expect(file.fileExtension, '');
      });

      test('should handle multiple dots in filename', () {
        final file = LocalFile(
          name: 'archive.tar.gz',
          fullPath: '/archive.tar.gz',
          isDirectory: false,
          size: 1000,
          modified: DateTime.now(),
        );

        expect(file.fileExtension, 'GZ');
      });
    });
  });

  group('DraggedLocalFiles', () {
    test('should create with files and source path', () {
      final files = [
        LocalFile(
          name: 'file1.txt',
          fullPath: '/Users/test/file1.txt',
          isDirectory: false,
          size: 100,
          modified: DateTime.now(),
        ),
        LocalFile(
          name: 'file2.txt',
          fullPath: '/Users/test/file2.txt',
          isDirectory: false,
          size: 200,
          modified: DateTime.now(),
        ),
      ];

      final dragged = DraggedLocalFiles(
        files: files,
        sourcePath: '/Users/test',
      );

      expect(dragged.files.length, 2);
      expect(dragged.files[0].name, 'file1.txt');
      expect(dragged.files[1].name, 'file2.txt');
      expect(dragged.sourcePath, '/Users/test');
    });

    test('should handle empty file list', () {
      final dragged = DraggedLocalFiles(
        files: [],
        sourcePath: '/Users/test',
      );

      expect(dragged.files, isEmpty);
      expect(dragged.sourcePath, '/Users/test');
    });

    test('should handle directories in file list', () {
      final files = [
        LocalFile(
          name: 'Documents',
          fullPath: '/Users/test/Documents',
          isDirectory: true,
          size: 0,
          modified: DateTime.now(),
        ),
      ];

      final dragged = DraggedLocalFiles(
        files: files,
        sourcePath: '/Users/test',
      );

      expect(dragged.files.first.isDirectory, isTrue);
    });
  });

  group('DraggedRemoteFiles', () {
    test('should create with files, server name, and source path', () {
      final files = [
        {'name': 'remote1.txt', 'isDirectory': false},
        {'name': 'remote2.txt', 'isDirectory': false},
      ];

      final dragged = DraggedRemoteFiles(
        files: files,
        serverName: 'production',
        sourcePath: '/var/www/html',
      );

      expect(dragged.files.length, 2);
      expect(dragged.serverName, 'production');
      expect(dragged.sourcePath, '/var/www/html');
    });

    test('should handle empty file list', () {
      final dragged = DraggedRemoteFiles(
        files: [],
        serverName: 'staging',
        sourcePath: '/home/user',
      );

      expect(dragged.files, isEmpty);
      expect(dragged.serverName, 'staging');
      expect(dragged.sourcePath, '/home/user');
    });

    test('should preserve server name for different servers', () {
      final dragged1 = DraggedRemoteFiles(
        files: [],
        serverName: 'server1',
        sourcePath: '/path1',
      );

      final dragged2 = DraggedRemoteFiles(
        files: [],
        serverName: 'server2',
        sourcePath: '/path2',
      );

      expect(dragged1.serverName, 'server1');
      expect(dragged2.serverName, 'server2');
    });
  });

  group('LocalFileAction enum', () {
    test('should contain all expected actions', () {
      expect(LocalFileAction.values, contains(LocalFileAction.open));
      expect(LocalFileAction.values, contains(LocalFileAction.openInFinder));
      expect(LocalFileAction.values, contains(LocalFileAction.uploadToServer));
      expect(LocalFileAction.values, contains(LocalFileAction.info));
      expect(LocalFileAction.values, contains(LocalFileAction.delete));
      expect(LocalFileAction.values, contains(LocalFileAction.rename));
      expect(LocalFileAction.values, contains(LocalFileAction.duplicate));
      expect(LocalFileAction.values, contains(LocalFileAction.move));
      expect(LocalFileAction.values, contains(LocalFileAction.newFolder));
      expect(LocalFileAction.values, contains(LocalFileAction.newFile));
      expect(LocalFileAction.values, contains(LocalFileAction.refresh));
    });

    test('should have correct number of actions', () {
      expect(LocalFileAction.values.length, 11);
    });
  });
}
