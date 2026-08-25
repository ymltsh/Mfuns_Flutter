import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/core/theme/app_theme.dart';
import 'package:mfuns_flutter/features/content/export/article_exporter.dart';
import 'package:mfuns_flutter/features/content/export/comment_collector.dart';
import 'package:mfuns_flutter/features/content/export/image_downloader.dart';
import 'package:mfuns_flutter/features/content/export/image_exporter.dart';

void main() {
  testWidgets('把短文章渲染为单张 PNG 长图', (tester) async {
    final tempRoot = Directory.systemTemp.createTempSync('export_img_test_');
    addTearDown(() => tempRoot.deleteSync(recursive: true));

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: Text('占位'))),
    ));

    await tester.runAsync(() async {
      final binding = tester.binding;
      var done = false;
      Object? failure;
      final future = ImageExporter.export(
        context: tester.element(find.byType(Scaffold)),
        article: const ArticleExportData(
          title: '长图测试',
          author: '作者A',
          rawContent: '<h2>小标题</h2><p>第一段内容</p><p>第二段内容</p>',
          sourceUrl: 'https://m.mfuns.net/article/1',
        ),
        rootDir: tempRoot,
        downloader: ImageDownloader(),
      );
      future.then((_) => done = true,
          onError: (Object error) {
            done = true;
            failure = error;
          });

      // 手动驱动帧（runAsync 中无法使用 tester.pump），直到导出完成。
      for (var i = 0; i < 300 && !done; i++) {
        binding.handleBeginFrame(Duration.zero);
        binding.handleDrawFrame();
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(done, isTrue, reason: '图片导出应在有限帧内完成：$failure');
      if (failure != null) fail('图片导出失败：$failure');

      final results = await future;
      expect(results, hasLength(1));
      final result = results.first;
      expect(result.mimeType, 'image/png');
      expect(result.fileName, '长图测试.png');
      final file = File(result.path);
      expect(file.existsSync(), isTrue);

      final bytes = await file.readAsBytes();
      expect(bytes.length, greaterThan(100));
      // PNG 魔数。
      expect(bytes.sublist(0, 8),
          [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      expect(frame.image.width,
          (ImageExporter.exportWidth * ImageExporter.pixelRatio).round());
      expect(frame.image.height, greaterThan(200));
      frame.image.dispose();
    });
  });

  testWidgets('导出部件直接渲染标题、作者与正文', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Center(
            child: ExportArticleWidget(
              article: ArticleExportData(
                title: '文章标题',
                author: '作者B',
                rawContent: '',
              ),
              markdown: '# 标题\n\n**加粗**内容',
              decodedImages: {},
            ),
          ),
        ),
      ),
    ));
    expect(find.text('文章标题'), findsOneWidget);
    expect(find.text('作者B'), findsOneWidget);
    expect(find.textContaining('加粗'), findsOneWidget);
  });

  testWidgets('导出部件渲染评论区域与开源项目说明', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Center(
            child: ExportArticleWidget(
              article: ArticleExportData(
                title: '标题',
                author: '作者',
                rawContent: '',
              ),
              markdown: '正文内容',
              decodedImages: {},
              comments: [
                ArticleExportComment(
                  author: '用户A',
                  contentMarkdown: '评论一',
                  replies: [
                    ArticleExportComment(
                      author: '用户B',
                      contentMarkdown: '回复一',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ));
    expect(find.text('评论'), findsOneWidget);
    expect(find.text('用户A'), findsOneWidget);
    expect(find.textContaining('评论一'), findsOneWidget);
    expect(find.textContaining('用户B'), findsOneWidget);
    expect(find.textContaining('回复一'), findsOneWidget);
    expect(find.textContaining('github.com/ymltsh'), findsOneWidget);
    expect(find.textContaining('关于 Mfuns Flutter'), findsOneWidget);
  });

  testWidgets('自定义主题色下导出卡片正常渲染', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const Scaffold(
        body: SingleChildScrollView(
          child: Center(
            child: ExportArticleWidget(
              article: ArticleExportData(
                title: '主题测试',
                author: '作者',
                rawContent: '',
              ),
              markdown: '> 引用内容\n\n[链接](https://m.mfuns.net)\n\n'
                  '```\ncode\n```',
              decodedImages: {},
              comments: [
                ArticleExportComment(
                  author: '用户A',
                  contentMarkdown: '评论内容',
                  replies: [
                    ArticleExportComment(author: '用户B', contentMarkdown: '回复'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ));
    expect(find.textContaining('引用内容'), findsOneWidget);
    expect(find.textContaining('链接'), findsOneWidget);
    expect(find.text('评论'), findsOneWidget);
    expect(find.textContaining('评论内容'), findsOneWidget);
  });

  testWidgets('链接下划线颜色跟随用户自定义主题色', (tester) async {
    const seed = Color(0xFFFDD835); // 黄色主题，便于区分固定色
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(seed),
      home: const Scaffold(
        body: SingleChildScrollView(
          child: Center(
            child: ExportArticleWidget(
              article: ArticleExportData(
                title: '主题测试',
                author: '作者',
                rawContent: '',
              ),
              markdown: '[链接文字](https://m.mfuns.net)',
              decodedImages: {},
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    final onSurface = Theme.of(tester.element(find.byType(ExportArticleWidget)))
        .colorScheme
        .onSurface;
    var found = false;
    for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
      void walk(InlineSpan span) {
        if (span is TextSpan) {
          final style = span.style;
          if (style != null && span.text == '链接文字') {
            found = true;
            expect(style.decoration, TextDecoration.underline,
                reason: '链接应带下划线');
            expect(style.decorationColor, isNotNull,
                reason: '下划线必须显式设置颜色，不能继承固定的 onSurface');
            expect(style.decorationColor, isNot(onSurface),
                reason: '下划线不应是固定 onSurface 色');
            expect(style.decorationColor, style.color,
                reason: '下划线颜色应与链接主题色一致');
          }
          if (span.children != null) {
            for (final child in span.children!) {
              walk(child);
            }
          }
        }
      }

      walk(rt.text as TextSpan);
    }
    expect(found, isTrue, reason: '应找到链接文本节点');
  });

  testWidgets('评论中的图片 Markdown 在长图中只渲染文本', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Center(
            child: ExportArticleWidget(
              article: const ArticleExportData(
                title: '标题',
                rawContent: '',
              ),
              markdown: '正文',
              decodedImages: const {},
              comments: textOnlyComments([
                const ArticleExportComment(
                  author: '用户A',
                  contentMarkdown: '文字内容\n\n'
                      '![评论图片](https://x.com/a.png)',
                ),
              ]),
            ),
          ),
        ),
      ),
    ));
    expect(find.textContaining('文字内容'), findsOneWidget);
    expect(find.textContaining('评论图片'), findsNothing);
  });

  testWidgets('关闭页脚时不渲染开源项目说明', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Center(
            child: ExportArticleWidget(
              article: ArticleExportData(
                title: '标题',
                rawContent: '',
              ),
              markdown: '正文内容',
              decodedImages: {},
              includeFooter: false,
            ),
          ),
        ),
      ),
    ));
    expect(find.textContaining('关于 Mfuns Flutter'), findsNothing);
  });

  testWidgets('超长文章始终输出单张图片', (tester) async {
    final tempRoot = Directory.systemTemp.createTempSync('export_tiles_');
    addTearDown(() => tempRoot.deleteSync(recursive: true));

    // 足够长的纯文本文章（无图片，避免网络），跨越多个分片。
    final paragraphs = List.generate(
      120,
      (i) => '<h2>第 $i 节</h2><p>这是第 $i 节的正文内容，'
          '用于验证分片渲染时不同分片之间不会出现内容重叠。</p>',
    ).join();
    final markdown = '<p>开头段落</p>$paragraphs<p>结尾段落</p>';

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: Text('占位'))),
    ));

    await tester.runAsync(() async {
      final binding = tester.binding;
      var done = false;
      Object? failure;
      final future = ImageExporter.export(
        context: tester.element(find.byType(Scaffold)),
        article: ArticleExportData(
          title: '分片测试',
          rawContent: markdown,
        ),
        rootDir: tempRoot,
        downloader: ImageDownloader(),
      );
      future.then((_) => done = true,
          onError: (Object error) {
            done = true;
            failure = error;
          });
      for (var i = 0; i < 300 && !done; i++) {
        binding.handleBeginFrame(Duration.zero);
        binding.handleDrawFrame();
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(done, isTrue, reason: '导出未完成：$failure');
      if (failure != null) fail('导出失败：$failure');

      final results = await future;
      expect(results, hasLength(1), reason: '超长文章也必须输出一张图');
      final bytes = await File(results.first.path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      addTearDown(image.dispose);
      // 多片拼接成一张：高度应明显超过单片。
      expect(image.height,
          greaterThan((ImageExporter.tileHeight * ImageExporter.pixelRatio * 1.5).round()));
    });
  });

  group('分片几何规划', () {
    const v = 2048.0;

    test('每片无缝覆盖全程，无重叠无空隙', () {
      final plan = ImageExporter.tilePlan(2441, v);
      expect(plan, hasLength(2));
      expect(plan[0], (offset: 0.0, viewport: 2048.0));
      expect(plan[1], (offset: 2048.0, viewport: 393.0));
      // 相邻分片首尾相接。
      for (var i = 1; i < plan.length; i++) {
        expect(plan[i].offset, plan[i - 1].offset + plan[i - 1].viewport);
      }
      // 最后一片正好收尾。
      expect(plan.last.offset + plan.last.viewport, 2441);
    });

    test('恰好整数屏：每片满高，无收紧', () {
      final plan = ImageExporter.tilePlan(4096, v);
      expect(plan, hasLength(2));
      expect(plan[0], (offset: 0.0, viewport: 2048.0));
      expect(plan[1], (offset: 2048.0, viewport: 2048.0));
    });

    test('高度不足一屏：单片收紧', () {
      final plan = ImageExporter.tilePlan(900, v);
      expect(plan, hasLength(1));
      expect(plan[0], (offset: 0.0, viewport: 900.0));
    });

    test('多屏文章每片偏移递增且不重叠', () {
      final plan = ImageExporter.tilePlan(9000, v);
      expect(plan, hasLength(5));
      for (var i = 0; i < plan.length; i++) {
        expect(plan[i].offset, i * v);
        expect(plan[i].viewport, i == plan.length - 1 ? 808.0 : v);
      }
      expect(plan.last.offset + plan.last.viewport, 9000);
    });
  });

  group('内容大小比例（字号缩放）', () {
    testWidgets('输出宽度固定 1080px，与字号比例无关', (tester) async {
      for (final scale in [0.5, 1.0, 2.0]) {
        final width = await _exportWidthFor(tester, scale);
        expect(width, (ImageExporter.exportWidth * ImageExporter.pixelRatio).round(),
            reason: 'scale=$scale 时输出宽度应保持固定');
      }
    });

    testWidgets('字号比例影响内容高度：0.5x 更紧凑，2x 更高', (tester) async {
      final h05 = await _exportHeightFor(tester, 0.5);
      final h10 = await _exportHeightFor(tester, 1.0);
      final h20 = await _exportHeightFor(tester, 2.0);
      expect(h05, lessThan(h10), reason: '0.5x 应比 1x 紧凑');
      expect(h10, lessThan(h20), reason: '2x 应比 1x 更高');
    });
  });
}

/// 以指定字号比例导出短文章，返回输出图片物理宽度。
Future<int> _exportWidthFor(WidgetTester tester, double imageScale) async {
  final size = await _exportSizeFor(tester, imageScale);
  return size.width;
}

/// 以指定字号比例导出短文章，返回输出图片物理高度。
Future<int> _exportHeightFor(WidgetTester tester, double imageScale) async {
  final size = await _exportSizeFor(tester, imageScale);
  return size.height;
}

Future<({int width, int height})> _exportSizeFor(
    WidgetTester tester, double imageScale) async {
  final tempRoot = Directory.systemTemp.createTempSync('export_scale_');
  addTearDown(() => tempRoot.deleteSync(recursive: true));

  await tester.pumpWidget(const MaterialApp(
    home: Scaffold(body: Center(child: Text('占位'))),
  ));

  return tester.runAsync<({int width, int height})>(() async {
    final binding = tester.binding;
    var done = false;
    Object? failure;
    final future = ImageExporter.export(
      context: tester.element(find.byType(Scaffold)),
      article: const ArticleExportData(
        title: '缩放测试',
        rawContent: '<p>一段较短的正文内容，用于测试字号缩放比例。</p>',
      ),
      rootDir: tempRoot,
      downloader: ImageDownloader(),
      imageScale: imageScale,
    );
    future.then((_) => done = true,
        onError: (Object error) {
          done = true;
          failure = error;
        });
    for (var i = 0; i < 300 && !done; i++) {
      binding.handleBeginFrame(Duration.zero);
      binding.handleDrawFrame();
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(done, isTrue, reason: '导出未完成：$failure');
    if (failure != null) fail('导出失败：$failure');
    final results = await future;
    expect(results, hasLength(1));
    final bytes = await File(results.first.path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final size = (width: frame.image.width, height: frame.image.height);
    frame.image.dispose();
    return size;
  }).then((size) => size!);
}
