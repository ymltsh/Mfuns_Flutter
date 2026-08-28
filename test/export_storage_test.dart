import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/features/content/export/article_exporter.dart';
import 'package:mfuns_flutter/features/content/export/export_storage.dart';

void main() {
  late Directory home;

  setUp(() {
    home = Directory.systemTemp.createTempSync('export_home_');
    ExportStorage.debugHomeOverride = home.path;
  });

  tearDown(() {
    ExportStorage.debugHomeOverride = null;
    home.deleteSync(recursive: true);
  });

  group('ExportStorage 桌面端持久化', () {
    test('Markdown 整个目录（含 assets）保存到 Documents/Mfuns Flutter', () async {
      final source = Directory.systemTemp.createTempSync('md_src_');
      addTearDown(() => source.deleteSync(recursive: true));
      final folder = Directory('${source.path}${Platform.pathSeparator}测试文章');
      folder.createSync(recursive: true);
      final assets = Directory('${folder.path}${Platform.pathSeparator}assets');
      assets.createSync();
      File('${folder.path}${Platform.pathSeparator}测试文章.md')
          .writeAsStringSync('# 标题');
      File('${assets.path}${Platform.pathSeparator}image_001.png')
          .writeAsBytesSync([0x89]);

      final result = ExportResult(
        path: '${folder.path}${Platform.pathSeparator}测试文章.md',
        fileName: '测试文章.md',
        mimeType: 'text/markdown',
        directoryPath: folder.path,
      );
      final saved = await ExportStorage.persist([result]);

      final expectedDir = '${home.path}${Platform.pathSeparator}'
          'Documents${Platform.pathSeparator}Mfuns Flutter'
          '${Platform.pathSeparator}测试文章';
      expect(saved.single.path,
          '$expectedDir${Platform.pathSeparator}测试文章.md');
      expect(File(saved.single.path).existsSync(), isTrue);
      expect(saved.single.directoryPath, expectedDir);
      expect(
          File('$expectedDir${Platform.pathSeparator}assets'
                  '${Platform.pathSeparator}image_001.png')
              .existsSync(),
          isTrue);
    });

    test('图片保存到 Pictures/Mfuns Flutter', () async {
      final source = Directory.systemTemp.createTempSync('png_src_');
      addTearDown(() => source.deleteSync(recursive: true));
      final png = File('${source.path}${Platform.pathSeparator}长图.png')
        ..writeAsBytesSync([0x89]);

      final saved = await ExportStorage.persist([
        ExportResult(
          path: png.path,
          fileName: '长图.png',
          mimeType: 'image/png',
        ),
      ]);

      final expected = '${home.path}${Platform.pathSeparator}Pictures'
          '${Platform.pathSeparator}Mfuns Flutter${Platform.pathSeparator}长图.png';
      expect(saved.single.path, expected);
      expect(File(expected).existsSync(), isTrue);
    });

    test('源文件不存在时保留原路径', () async {
      final missing =
          '${Directory.systemTemp.path}${Platform.pathSeparator}not_there.png';
      final result = ExportResult(
        path: missing,
        fileName: 'not_there.png',
        mimeType: 'image/png',
      );
      final saved = await ExportStorage.persist([result]);
      expect(saved.single.path, missing);
    });
  });
}
