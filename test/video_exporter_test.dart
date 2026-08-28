import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/features/content/export/export_storage.dart';
import 'package:mfuns_flutter/features/download/video_exporter.dart';

void main() {
  group('VideoExporter.fileNameFor', () {
    test('生成 标题_P分P_清晰度.扩展名 并清理非法字符', () {
      const item = VideoExportItem(
        part: 2,
        sourcePath: 'C:\\data\\p2_1080p.mp4',
        title: '测试/视频:标题',
        qualityLabel: '1080P',
      );
      final name = VideoExporter.fileNameFor(item);
      expect(name, '测试 视频 标题_P2_1080P.mp4');
    });

    test('标题过长时间被截断', () {
      const item = VideoExportItem(
        part: 1,
        sourcePath: '/data/p1.mp4',
        title: '这是一个非常非常长的视频标题，用来测试文件名清理逻辑是否正常工作并且被安全截断',
        qualityLabel: '720P',
      );
      final name = VideoExporter.fileNameFor(item);
      expect(name.length, lessThanOrEqualTo(48 + 16));
      expect(name, endsWith('_P1_720P.mp4'));
    });

    test('扩展名从源路径推断，未知扩展名回退 mp4', () {
      expect(
        VideoExporter.fileNameFor(const VideoExportItem(
          part: 1,
          sourcePath: '/data/p1.webm',
          title: 'a',
          qualityLabel: '1080P',
        )),
        'a_P1_1080P.webm',
      );
      expect(
        VideoExporter.fileNameFor(const VideoExportItem(
          part: 1,
          sourcePath: '/data/p1.unknown',
          title: 'a',
          qualityLabel: '1080P',
        )),
        'a_P1_1080P.mp4',
      );
    });
  });

  group('VideoExporter.persist（桌面端持久化）', () {
    late Directory home;
    late Directory sourceDir;

    setUp(() {
      home = Directory.systemTemp.createTempSync('mfuns_video_export_home_');
      sourceDir = Directory.systemTemp.createTempSync('mfuns_video_source_');
      ExportStorage.debugHomeOverride = home.path;
    });

    tearDown(() {
      ExportStorage.debugHomeOverride = null;
      try {
        home.deleteSync(recursive: true);
      } catch (_) {}
      try {
        sourceDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('视频复制到 ~/Videos/Mfuns Flutter', () async {
      final source = File('${sourceDir.path}${Platform.pathSeparator}p1_1080p.mp4');
      source.writeAsBytesSync(List.filled(1024, 1));

      final results = await VideoExporter.persist([
        VideoExportItem(
          part: 1,
          sourcePath: source.path,
          title: '导出测试',
          qualityLabel: '1080P',
        ),
      ]);

      expect(results, hasLength(1));
      final saved = results.first;
      expect(saved.fileName, '导出测试_P1_1080P.mp4');
      expect(saved.mimeType, 'video/mp4');
      expect(saved.path, contains('Videos${Platform.pathSeparator}Mfuns Flutter'));
      expect(File(saved.path).existsSync(), isTrue);
      expect(File(saved.path).lengthSync(), 1024);
    });

    test('多个分P依次导出，源文件缺失的分P被跳过', () async {
      final source = File('${sourceDir.path}${Platform.pathSeparator}p1_1080p.mp4');
      source.writeAsBytesSync(List.filled(64, 1));
      final progress = <String>[];

      final results = await VideoExporter.persist([
        VideoExportItem(
            part: 1, sourcePath: source.path, title: 't', qualityLabel: '1080P'),
        // 源文件不存在 → 跳过。
        VideoExportItem(
            part: 2,
            sourcePath: '${sourceDir.path}${Platform.pathSeparator}missing.mp4',
            title: 't',
            qualityLabel: '1080P'),
      ], onProgress: (message) => progress.add(message));

      expect(results, hasLength(1));
      expect(progress, isNotEmpty);
      expect(progress.first, contains('1/2'));
    });

    test('webm 扩展名映射为 video/webm', () async {
      final source = File('${sourceDir.path}${Platform.pathSeparator}p1.webm');
      source.writeAsBytesSync(List.filled(8, 1));
      final results = await VideoExporter.persist([
        VideoExportItem(
            part: 1, sourcePath: source.path, title: 't', qualityLabel: '4K'),
      ]);
      expect(results.single.mimeType, 'video/webm');
    });
  });
}
