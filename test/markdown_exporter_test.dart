import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/features/content/export/article_exporter.dart';
import 'package:mfuns_flutter/features/content/export/comment_collector.dart';
import 'package:mfuns_flutter/features/content/export/export_footer.dart';
import 'package:mfuns_flutter/features/content/export/image_downloader.dart';
import 'package:mfuns_flutter/features/content/export/markdown_exporter.dart';
import 'package:mfuns_flutter/features/home/home_repository.dart';

/// 1x1 透明 PNG。
final Uint8List _pngBytes = Uint8List.fromList([  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, //
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, //
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, //
  0x42, 0x60, 0x82,
]);

/// 评论时间样本。
final DateTime _date = DateTime(2026, 8, 25, 20, 30);

/// 监听一个返回 PNG 图片的本地 HTTP 服务。
Future<HttpServer> _pngServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType('image', 'png')
      ..add(_pngBytes)
      ..close();
  });
  return server;
}

void main() {
  group('sanitizeFileName', () {
    test('保留中文与常规字符', () {
      expect(sanitizeFileName('我的第一篇 文章'), '我的第一篇 文章');
    });

    test('清理 Windows 非法字符', () {
      expect(sanitizeFileName('a<b>c:d"e/f\\g|h?i*j'), 'a b c d e f g h i j');
    });

    test('去掉结尾的点和空格', () {
      expect(sanitizeFileName('标题...'), '标题');
      expect(sanitizeFileName('标题 '), '标题');
    });

    test('空标题回退为 mfuns_article', () {
      expect(sanitizeFileName(''), 'mfuns_article');
      expect(sanitizeFileName('   '), 'mfuns_article');
      expect(sanitizeFileName('>>>'), 'mfuns_article');
    });

    test('限制长度', () {
      expect(sanitizeFileName('长' * 100).length, 48);
    });
  });

  group('extractImageUrls', () {
    test('提取 http/https 图片链接并去重', () {
      const markdown = '![a](https://x.com/1.png)\n![b](https://x.com/1.png)\n'
          '![c](http://y.com/2.jpg)';
      expect(extractImageUrls(markdown),
          ['https://x.com/1.png', 'http://y.com/2.jpg']);
    });

    test('跳过表情贴纸占位图', () {
      const markdown = '![sticker:s-1](https://resource.mfuns.net/x.png)\n'
          '![图](https://x.com/1.png)';
      expect(extractImageUrls(markdown), ['https://x.com/1.png']);
    });
  });

  group('replaceImageUrls', () {
    test('替换为本地相对路径', () {
      const markdown = '![图](https://x.com/1.png)';
      final result = replaceImageUrls(markdown, {
        'https://x.com/1.png': 'assets/image_001.png',
      });
      expect(result, '![图](assets/image_001.png)');
    });

    test('未下载成功的 URL 保持不变', () {
      const markdown = '![a](https://x.com/1.png) ![b](https://y.com/2.png)';
      final result = replaceImageUrls(markdown, {
        'https://x.com/1.png': 'assets/image_001.png',
      });
      expect(result, '![a](assets/image_001.png) ![b](https://y.com/2.png)');
    });
  });

  group('inferImageExtension', () {
    test('优先使用 URL 扩展名', () {
      expect(inferImageExtension('https://x.com/a.webp', null), 'webp');
      expect(inferImageExtension('https://x.com/a.jpeg?x=1', null), 'jpg');
      expect(inferImageExtension('https://x.com/a.png', 'image/jpeg'), 'png');
    });

    test('按 Content-Type 推断', () {
      expect(
          inferImageExtension('https://x.com/download', 'image/png'), 'png');
      expect(inferImageExtension('https://x.com/download', 'image/webp'),
          'webp');
      expect(inferImageExtension('https://x.com/download', 'image/svg+xml'),
          'svg');
    });

    test('未知类型回退 img', () {
      expect(
          inferImageExtension(
              'https://x.com/download', 'application/octet-stream'),
          'img');
      expect(inferImageExtension('https://x.com/avatar', null), 'img');
    });
  });

  group('MarkdownExporter', () {
    late Directory tempRoot;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('export_test_');
    });

    tearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('正文贴纸导出为 [pack-id] 代号而非图片', () async {
      final result = await MarkdownExporter.export(
        article: const ArticleExportData(
          title: '贴纸文章',
          rawContent: '<p>冲鸭<img class=\'sticker\' '
              'src="https://resource.mfuns.net/image/sticker/family/3.gif" '
              "alt='[family-3]'/>继续</p>",
        ),
        rootDir: tempRoot,
        downloader: ImageDownloader(),
      );
      final content = await File(result.path).readAsString();
      expect(content, contains('冲鸭[family-3]继续'));
      expect(content, isNot(contains('![sticker:')));
      expect(content, isNot(contains('resource.mfuns.net/image/sticker')));
    });

    test('导出 HTML 富文本为 Markdown 并保留排版', () async {      final result = await MarkdownExporter.export(
        article: const ArticleExportData(
          title: '测试文章',
          author: '作者A',
          rawContent: '<h1>标题</h1><p><strong>加粗</strong>与<a '
              'href="https://m.mfuns.net/article/1">链接</a></p>',
        ),
        rootDir: tempRoot,
        downloader: ImageDownloader(),
      );
      expect(result.fileName, '测试文章.md');
      expect(result.mimeType, 'text/markdown');
      expect(result.failedImageCount, 0);
      final content = await File(result.path).readAsString();
      expect(content, contains('# 标题'));
      expect(content, contains('**加粗**'));
      expect(content, contains('[链接](https://m.mfuns.net/article/1)'));
      final folder = Directory(result.directoryPath);
      expect(folder.existsSync(), isTrue);
      expect(
          Directory('${folder.path}${Platform.pathSeparator}assets')
              .existsSync(),
          isFalse);
    });

    test('图片下载成功：写入 assets 并改写相对路径', () async {
      final server = await _pngServer();
      addTearDown(() => server.close(force: true));
      final base = 'http://127.0.0.1:${server.port}';
      final result = await MarkdownExporter.export(
        article: ArticleExportData(
          title: '带图文章',
          author: '作者A',
          rawContent: '![封面]($base/pic.png)\n\n正文段落',
        ),
        rootDir: tempRoot,
        downloader: ImageDownloader(),
      );
      expect(result.failedImageCount, 0);
      final content = await File(result.path).readAsString();
      expect(content, contains('![封面](assets/image_001.png)'));
      final assets = Directory(
          '${result.directoryPath}${Platform.pathSeparator}assets');
      expect(
          assets
              .listSync()
              .map((f) => f.path.split(Platform.pathSeparator).last),
          contains('image_001.png'));
    });

    test('图片下载失败：保留远程 URL 并继续导出', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen(
          (request) => request.response.statusCode = HttpStatus.notFound);
      final base = 'http://127.0.0.1:${server.port}';
      final result = await MarkdownExporter.export(
        article: ArticleExportData(
          title: '失败文章',
          author: '作者A',
          rawContent: '![图]($base/missing.png)\n\n正文',
        ),
        rootDir: tempRoot,
        downloader: ImageDownloader(),
      );
      expect(result.failedImageCount, 1);
      final content = await File(result.path).readAsString();
      expect(content, contains('![图]($base/missing.png)'));
    });

    test('空正文抛出异常', () async {
      expect(
        () => MarkdownExporter.export(
          article: const ArticleExportData(title: '空', rawContent: '  '),
          rootDir: tempRoot,
          downloader: ImageDownloader(),
        ),
        throwsA(isA<ArticleExportException>()),
      );
    });

    test('文件名使用标题并清理非法字符', () async {
      final result = await MarkdownExporter.export(
        article: const ArticleExportData(
          title: 'a<b>c:d',
          rawContent: '正文',
        ),
        rootDir: tempRoot,
        downloader: ImageDownloader(),
      );
      expect(result.fileName, 'a b c d.md');
      expect(File(result.path).existsSync(), isTrue);
    });

    test('底部默认加入开源项目说明，可关闭', () async {
      final withFooter = await MarkdownExporter.export(
        article: const ArticleExportData(title: '页脚', rawContent: '正文'),
        rootDir: tempRoot,
        downloader: ImageDownloader(),
      );
      final content = await File(withFooter.path).readAsString();
      expect(content, contains('## 关于 Mfuns Flutter'));
      expect(content, contains('本文由 Mfuns Flutter 导出。'));
      expect(content, contains(ExportFooter.description));
      expect(content, contains(ExportFooter.repositoryUrl));

      final withoutFooter = await MarkdownExporter.export(
        article: const ArticleExportData(title: '页脚2', rawContent: '正文'),
        rootDir: tempRoot,
        downloader: ImageDownloader(),
        includeFooter: false,
      );
      final content2 = await File(withoutFooter.path).readAsString();
      expect(content2, isNot(contains('关于 Mfuns Flutter')));
    });

    test('带评论导出：评论章节含用户名、内容、时间与回复', () async {
      final result = await MarkdownExporter.export(
        article: const ArticleExportData(title: '评论文章', rawContent: '正文'),
        rootDir: tempRoot,
        downloader: ImageDownloader(),
        comments: [
          ArticleExportComment(
            author: '用户A',
            contentMarkdown: '这是评论内容',
            createdAt: _date,
            replies: [
              ArticleExportComment(
                author: '用户B',
                contentMarkdown: '这是回复',
                createdAt: _date,
              ),
            ],
          ),
        ],
      );
      final content = await File(result.path).readAsString();
      expect(content, contains('## 评论'));
      expect(content, contains('### 评论 1 · 用户A'));
      expect(content, contains('这是评论内容'));
      expect(content, contains('2026-08-25 20:30'));
      expect(content, contains('> 用户B：这是回复（2026-08-25 20:30）'));
      expect(content, contains('## 关于 Mfuns Flutter'));
    });

    test('无评论时不生成空的评论章节', () async {
      final result = await MarkdownExporter.export(
        article: const ArticleExportData(title: '空评论', rawContent: '正文'),
        rootDir: tempRoot,
        downloader: ImageDownloader(),
        comments: const [],
      );
      final content = await File(result.path).readAsString();
      expect(content, isNot(contains('## 评论')));
    });

    test('评论图片下载到 assets/comment_image_* 并改写相对路径', () async {
      final server = await _pngServer();
      addTearDown(() => server.close(force: true));
      final base = 'http://127.0.0.1:${server.port}';
      final result = await MarkdownExporter.export(
        article: const ArticleExportData(title: '评论图片', rawContent: '正文'),
        rootDir: tempRoot,
        downloader: ImageDownloader(),
        comments: [
          ArticleExportComment(
            author: '用户A',
            contentMarkdown: '看图：\n\n![评论图片]($base/c.png)',
          ),
        ],
      );
      expect(result.failedImageCount, 0);
      final content = await File(result.path).readAsString();
      expect(content, contains('assets/comment_image_001.png'));
      final assets = Directory(
          '${result.directoryPath}${Platform.pathSeparator}assets');
      expect(
          assets
              .listSync()
              .map((f) => f.path.split(Platform.pathSeparator).last),
          contains('comment_image_001.png'));
    });
  });

  group('评论内容转换', () {
    test('commentContentMarkdown 保留文本与评论图片', () {
      final comment = CommunityComment.fromJson({
        'id': 1,
        'user': {'id': 100, 'name': '用户A'},
        'content': '{"ops":[{"insert":"赞一个\\n"}]}',
        'content_ext': {'images': ['https://x.com/c1.png']},
      });
      final markdown = commentContentMarkdown(comment);
      expect(markdown, contains('赞一个'));
      expect(markdown, contains('![评论图片](https://x.com/c1.png)'));
    });

    test('commentContentMarkdown 贴纸输出 [pack-id] 代号', () {
      final comment = CommunityComment.fromJson({
        'id': 1,
        'user': {'id': 100, 'name': '用户A'},
        'content': '{"ops":[{"insert":{"sticker":"s-1"}},{"insert":"好"}]}',
      });
      final markdown = commentContentMarkdown(comment);
      expect(markdown, contains('[s-1]'));
      expect(markdown, contains('好'));
      expect(markdown, isNot(contains('![sticker:')));
    });

    test('formatExportDate 输出 yyyy-MM-dd HH:mm', () {
      expect(formatExportDate(DateTime(2026, 8, 25, 20, 30, 45)),
          '2026-08-25 20:30');
    });

    test('buildCommentsMarkdown 空列表返回空串', () {
      expect(buildCommentsMarkdown(const []), '');
    });

    test('textOnlyCommentMarkdown 去掉图片、保留贴纸代号', () {
      const comment = ArticleExportComment(
        author: '用户A',
        contentMarkdown: '看图[s-1]\n\n![评论图片](https://x.com/a.png)'
            '\n\n文字部分',
      );
      expect(textOnlyCommentMarkdown(comment), '看图[s-1]\n\n文字部分');
    });

    test('stickerCodesFromPlaceholders 把贴纸占位转为代号', () {
      expect(
        stickerCodesFromPlaceholders('好棒![sticker:s-2]'
            '(https://resource.mfuns.net/image/sticker/x.png)继续'),
        '好棒[s-2]继续',
      );
    });

    test('textOnlyComments 递归处理回复', () {
      final comments = textOnlyComments([
        const ArticleExportComment(
          author: '用户A',
          contentMarkdown: '评论\n\n![评论图片](https://x.com/a.png)',
          replies: [
            ArticleExportComment(
              author: '用户B',
              contentMarkdown: '回复\n\n![评论图片](https://x.com/b.png)',
            ),
          ],
        ),
      ]);
      expect(comments.single.contentMarkdown, '评论');
      expect(comments.single.replies.single.contentMarkdown, '回复');
    });
  });

  group('评论分页拉取', () {
    CommunityComment sampleComment(int id) => CommunityComment.fromJson({
          'id': id,
          'user': {'id': id * 10, 'name': '用户$id'},
          'content': '内容$id',
        });

    test('按页拉取直到没有更多', () async {
      var calls = 0;
      final result = await ArticleCommentCollector.fetchAllCommentPages(
        (page) async {
          calls++;
          if (page == 1) return [sampleComment(1), sampleComment(2)];
          if (page == 2) return [sampleComment(3)];
          return [];
        },
      );
      expect(calls, 3);
      expect(result.map((c) => c.id), [1, 2, 3]);
    });

    test('取消时抛出 ExportCancelledException', () async {
      final cancellation = ExportCancellation();
      final future = ArticleCommentCollector.fetchAllCommentPages(
        (page) async {
          cancellation.requestCancel();
          return [sampleComment(page)];
        },
        cancellation: cancellation,
      );
      await expectLater(future, throwsA(isA<ExportCancelledException>()));
    });
  });
}
