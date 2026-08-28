import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'download_task.dart';

/// 下载文件存储：App 私有目录布局。
///
/// ```text
/// <documents>/downloads/
/// └── <videoId>/
///     ├── p1_1080p.mp4
///     ├── p2_1080p.mp4.part   ← 未完成
///     └── ...
/// ```
///
/// 只有重命名后的正式文件（`.part` 移除）才能被识别为可离线播放。
class DownloadStorage {
  DownloadStorage({Future<Directory> Function()? rootProvider})
      : _rootProvider = rootProvider ?? _defaultRootProvider;

  final Future<Directory> Function() _rootProvider;

  static const _downloadsDirName = 'downloads';

  static Future<Directory> _defaultRootProvider() async {
    final base = await getApplicationDocumentsDirectory();
    return Directory(p.join(base.path, _downloadsDirName));
  }

  Future<Directory> root() async {
    final dir = await _rootProvider();
    try {
      dir.createSync(recursive: true);
    } catch (_) {}
    return dir;
  }

  Future<Directory> videoDir(int videoId) async {
    final root = await this.root();
    final dir = Directory(p.join(root.path, '$videoId'));
    try {
      dir.createSync(recursive: true);
    } catch (_) {}
    return dir;
  }

  /// 从媒体 URL 推断文件扩展名；未知时回退为 `mp4`。
  static String _extensionFor(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return 'mp4';
    final path = uri.path;
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot >= path.length - 1) return 'mp4';
    final ext = path.substring(dot + 1).toLowerCase();
    const supported = {
      'mp4', 'flv', 'webm', 'mkv', 'mov', 'ts', 'm4s', 'm3u8', 'mp3', 'm4a', 'aac',
    };
    return supported.contains(ext) ? ext : 'mp4';
  }

  String _fileName(int videoId, int part, String quality, String sourceUrl) {
    final normalized = DownloadTask.normalizeQualityKey(quality);
    return 'p${part}_$normalized.${_extensionFor(sourceUrl)}';
  }

  Future<String> filePathFor(
    int videoId,
    int part,
    String quality,
    String sourceUrl,
  ) async {
    final dir = await videoDir(videoId);
    return p.join(dir.path, _fileName(videoId, part, quality, sourceUrl));
  }

  Future<String> tempFilePathFor(
    int videoId,
    int part,
    String quality,
    String sourceUrl,
  ) async {
    final dir = await videoDir(videoId);
    return '${p.join(dir.path, _fileName(videoId, part, quality, sourceUrl))}.part';
  }

  Future<bool> fileExists(String path) async {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// 已完成分P对应的正式文件（`.part` 之外的文件）路径。
  String? completedFileOf(DownloadPartTask part) {
    if (!part.isPlayable) return null;
    final path = part.filePath;
    if (path.endsWith('.part')) return null;
    return path;
  }

  /// 校验分P正式文件：存在、非空，且（已知总大小时）大小一致。
  Future<bool> verifyCompletedFile(DownloadPartTask part) async {
    final path = completedFileOf(part);
    if (path == null) return false;
    try {
      final file = File(path);
      if (!await file.exists()) return false;
      final length = await file.length();
      if (length <= 0) return false;
      if (part.totalBytes > 0 && length != part.totalBytes) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 分P下载完成后把 `.part` 重命名为正式文件。
  Future<void> completeFile(DownloadPartTask part) async {
    final temp = File(part.tempFilePath);
    final finalFile = File(part.filePath);
    await finalFile.parent.create(recursive: true);
    // 目标已存在（如重复完成）时先移除，避免重命名失败。
    if (await finalFile.exists()) {
      await finalFile.delete();
    }
    if (await temp.exists()) {
      await temp.rename(finalFile.path);
    } else if (!await finalFile.exists()) {
      throw const FileSystemException('临时文件不存在，无法完成下载');
    }
  }

  /// 删除分P相关文件（正式文件 + 临时文件）。
  Future<void> deletePartFiles(DownloadPartTask part) async {
    for (final path in {part.filePath, part.tempFilePath}) {
      try {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      } catch (_) {
        // 文件删除失败不阻断记录清理。
      }
    }
  }

  /// 删除整目录（任务全部被清理后回收目录）。
  Future<void> deleteVideoDirectory(int videoId) async {
    try {
      final root = await this.root();
      final dir = Directory(p.join(root.path, '$videoId'));
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {
      // 忽略目录删除失败。
    }
  }

  /// 统计所有已下载（含未完成临时文件）占用的磁盘空间。
  Future<int> usedSpaceBytes() async {
    var total = 0;
    final root = await this.root();
    try {
      await for (final entity in root.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
    } catch (_) {
      // 目录不存在或不可读时返回已累计值。
    }
    return total;
  }

  /// 清理数据库之外的孤儿文件（被删除任务遗留的正式/临时文件）。
  Future<void> removeOrphanFiles(List<DownloadTask> tasks) async {
    final known = <String>{
      for (final task in tasks)
        for (final part in task.parts) ...[part.filePath, part.tempFilePath],
    };
    final root = await this.root();
    try {
      await for (final entity in root.list(recursive: true, followLinks: false)) {
        if (entity is File && !known.contains(entity.path)) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (_) {
      // 忽略遍历失败。
    }
  }
}
