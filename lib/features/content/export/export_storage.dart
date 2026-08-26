import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'article_exporter.dart';

/// 导出文件的公共保存位置。
///
/// Android：内部存储 `Pictures/Mfuns Flutter`（图片）、
/// `Documents/Mfuns Flutter`（Markdown），经 MediaStore 写入；
/// Windows / 桌面：用户目录 `Documents|Pictures/Mfuns Flutter`。
class ExportStorage {
  const ExportStorage._();

  static const folderName = 'Mfuns Flutter';
  static const _channel = MethodChannel('mfuns/export');

  /// 测试用：覆盖桌面端用户主目录。
  @visibleForTesting
  static String? debugHomeOverride;

  /// 把已生成的结果持久化到公共目录。
  ///
  /// 单个文件保存失败时保留原有（临时）路径，不中断整体导出。
  static Future<List<ExportResult>> persist(
    List<ExportResult> results, {
    ValueChanged<String>? onProgress,
  }) async {
    final saved = <ExportResult>[];
    for (var i = 0; i < results.length; i++) {
      onProgress?.call('正在保存到本地（${i + 1}/${results.length}）…');
      saved.add(await _persistOne(results[i]));
    }
    return saved;
  }

  static Future<ExportResult> _persistOne(ExportResult result) async {
    if (Platform.isAndroid) return _persistAndroid(result);
    return _persistDesktop(result);
  }

  /// Android：平台通道逐文件写入 MediaStore。
  static Future<ExportResult> _persistAndroid(ExportResult result) async {
    final isMarkdown = result.mimeType == 'text/markdown';
    final directory = isMarkdown ? 'Documents' : 'Pictures';
    final folder = Directory(result.directoryPath);
    if (isMarkdown && folder.existsSync()) {
      final title = _lastSegment(result.directoryPath);
      final files = <File>[];
      await for (final entity in folder.list(recursive: true)) {
        if (entity is File) files.add(entity);
      }
      if (files.isEmpty) return result;
      String? markdownPath;
      for (final file in files) {
        final relative =
            file.path.substring(folder.path.length + 1).split(Platform.pathSeparator);
        final isMarkdownFile = file.path.endsWith('.md');
        final saved = await _saveAndroidFile(
          sourcePath: file.path,
          fileName: relative.last,
          directory: directory,
          relativePath:
              isMarkdownFile ? title : '$title${relative.length > 1 ? '/${relative.sublist(0, relative.length - 1).join('/')}' : ''}',
          mimeType: isMarkdownFile
              ? 'text/markdown'
              : _mimeForExtension(_extensionOf(file.path)),
        );
        if (isMarkdownFile) markdownPath = saved;
      }
      if (markdownPath == null) return result;
      return result.copyWith(
        path: markdownPath,
        directoryPath: _parentOf(markdownPath),
      );
    }
    final file = File(result.path);
    if (!file.existsSync()) return result;
    final saved = await _saveAndroidFile(
      sourcePath: file.path,
      fileName: result.fileName,
      directory: directory,
      relativePath: '',
      mimeType: result.mimeType,
    );
    return saved == null ? result : result.copyWith(path: saved);
  }

  static Future<String?> _saveAndroidFile({
    required String sourcePath,
    required String fileName,
    required String directory,
    required String relativePath,
    required String mimeType,
  }) async {
    try {
      return await _channel.invokeMethod<String>('saveFile', {
        'sourcePath': sourcePath,
        'fileName': fileName,
        'directory': directory,
        'relativePath': relativePath,
        'mimeType': mimeType,
      });
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// 桌面端：直接复制到用户 Documents / Pictures 目录。
  static Future<ExportResult> _persistDesktop(ExportResult result) async {
    final isMarkdown = result.mimeType == 'text/markdown';
    final base = Directory(
      '${homeDirectory()}${Platform.pathSeparator}'
      '${isMarkdown ? 'Documents' : 'Pictures'}${Platform.pathSeparator}$folderName',
    );
    await base.create(recursive: true);
    final folder = Directory(result.directoryPath);
    if (isMarkdown && folder.existsSync()) {
      final target = Directory(
          '${base.path}${Platform.pathSeparator}${_lastSegment(result.directoryPath)}');
      await _copyDirectory(folder, target);
      final markdownPath =
          '${target.path}${Platform.pathSeparator}${result.fileName}';
      return result.copyWith(path: markdownPath, directoryPath: target.path);
    }
    final file = File(result.path);
    if (!file.existsSync()) return result;
    final target = File('${base.path}${Platform.pathSeparator}${result.fileName}');
    await file.copy(target.path);
    return result.copyWith(path: target.path);
  }

  /// 桌面端用户主目录（测试可用 [debugHomeOverride] 覆盖）。
  static String homeDirectory() {
    final override = debugHomeOverride;
    if (override != null && override.isNotEmpty) return override;
    if (Platform.isWindows) {
      final profile = Platform.environment['USERPROFILE'];
      if (profile != null && profile.isNotEmpty) return profile;
    }
    return Platform.environment['HOME'] ?? Directory.systemTemp.path;
  }

  static Future<void> _copyDirectory(Directory source, Directory target) async {
    await target.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      final name = _lastSegment(entity.path);
      if (name.isEmpty) continue;
      if (entity is Directory) {
        await _copyDirectory(
            entity, Directory('${target.path}${Platform.pathSeparator}$name'));
      } else if (entity is File) {
        await entity.copy('${target.path}${Platform.pathSeparator}$name');
      }
    }
  }

  static String _lastSegment(String path) {
    final trimmed = path.endsWith(Platform.pathSeparator)
        ? path.substring(0, path.length - 1)
        : path;
    final index = trimmed.lastIndexOf(Platform.pathSeparator);
    return index < 0 ? trimmed : trimmed.substring(index + 1);
  }

  static String _parentOf(String path) {
    final index = path.lastIndexOf(Platform.pathSeparator);
    return index < 0 ? path : path.substring(0, index);
  }

  static String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    return dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  }

  static String _mimeForExtension(String extension) => switch (extension) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        'svg' => 'image/svg+xml',
        'bmp' => 'image/bmp',
        _ => 'application/octet-stream',
      };
}
