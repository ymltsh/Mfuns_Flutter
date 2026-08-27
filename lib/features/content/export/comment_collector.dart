import 'package:flutter/foundation.dart';

import '../../../app/app_controller.dart';
import '../../home/home_repository.dart';
import 'article_exporter.dart';

/// 导出用的评论条目（顶层评论与二级回复共用）。
class ArticleExportComment {
  const ArticleExportComment({
    required this.author,
    required this.contentMarkdown,
    this.createdAt,
    this.replies = const [],
  });

  final String author;

  /// 评论内容（含贴纸占位与图片 Markdown），与正文走同一套渲染逻辑。
  final String contentMarkdown;
  final DateTime? createdAt;
  final List<ArticleExportComment> replies;
}

/// 从 CommunityComment 生成导出用 Markdown 内容：
/// 文本 + 贴纸代号（如 `[s-1]`）+ 评论图片，复用项目贴纸编码约定。
String commentContentMarkdown(CommunityComment comment) {
  final buffer = StringBuffer();
  for (final span in comment.spans) {
    if (span.isSticker) {
      // 贴纸不导出为图片，输出 [pack-id] 代号文本。
      buffer.write('[${span.stickerKey}]');
    } else if (span.isMention) {
      buffer.write('@${span.mentionName}');
    } else {
      final text = span.text.trimRight();
      if (text.isNotEmpty) buffer.write(text);
    }
  }
  for (final image in comment.images) {
    buffer.write('\n\n![评论图片]($image)');
  }
  return buffer.toString().trim();
}

/// 导出时间格式：`2026-08-25 20:30`。
String formatExportDate(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)} '
      '${two(date.hour)}:${two(date.minute)}';
}

/// 评论章节 Markdown：
/// ```md
/// ---
///
/// ## 评论
///
/// ### 评论 1 · 用户名
///
/// 评论内容
///
/// 2026-08-25 20:30
///
/// > 用户 B：这是回复。
/// ```
String buildCommentsMarkdown(List<ArticleExportComment> comments) {
  if (comments.isEmpty) return '';
  final buffer = StringBuffer('---\n\n## 评论\n\n');
  var index = 0;
  for (final comment in comments) {
    index++;
    final author =
        comment.author.trim().isEmpty ? '匿名用户' : comment.author.trim();
    buffer.write('### 评论 $index · $author\n\n');
    if (comment.contentMarkdown.trim().isNotEmpty) {
      buffer.write('${comment.contentMarkdown.trim()}\n\n');
    }
    final date = comment.createdAt;
    if (date != null) buffer.write('${formatExportDate(date)}\n\n');
    for (final reply in comment.replies) {
      final replyAuthor =
          reply.author.trim().isEmpty ? '匿名用户' : reply.author.trim();
      final replyContent = reply.contentMarkdown.trim().replaceAll('\n', '\n> ');
      final replyDate = reply.createdAt == null
          ? ''
          : '（${formatExportDate(reply.createdAt!)}）';
      if (replyContent.isNotEmpty) {
        buffer.write('> $replyAuthor：$replyContent$replyDate\n\n');
      }
    }
  }
  return buffer.toString().trimRight();
}

/// 拉取文章全部评论（含二级回复），直到没有更多或达到安全上限。
///
/// 返回的评论数即“实际会被导出的评论数量”。
/// 评论内容中的图片 / 贴纸占位 Markdown（`![...](url)`）。
final RegExp _commentImagePattern =
    RegExp(r'!\[[^\]]*\]\((?:https?://[^\s)]+)\)');

/// 评论内容的纯文本版：去掉评论图片 Markdown。
///
/// 贴纸已由 [commentContentMarkdown] 转为 `[pack-id]` 代号文本并保留；
/// 长图导出使用（减小单张图片的面积与内存风险），Markdown 导出
/// 仍保留完整评论内容（含图片与贴纸）。
String textOnlyCommentMarkdown(ArticleExportComment comment) {
  return comment.contentMarkdown
      .replaceAll(_commentImagePattern, '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// 递归转换为纯文本版评论（含回复）。
List<ArticleExportComment> textOnlyComments(
  List<ArticleExportComment> comments,
) {
  return [
    for (final comment in comments)
      ArticleExportComment(
        author: comment.author,
        contentMarkdown: textOnlyCommentMarkdown(comment),
        createdAt: comment.createdAt,
        replies: textOnlyComments(comment.replies),
      ),
  ];
}

class ArticleCommentCollector {
  /// 分页安全上限，防止服务端异常导致死循环。
  static const maxPages = 100;

  static Future<List<ArticleExportComment>> collect({
    required AppController controller,
    required int areaId,
    ExportCancellation? cancellation,
    ValueChanged<String>? onProgress,
  }) async {
    final topLevel = await fetchAllCommentPages(
      (page) => controller.comments(areaId, page: page),
      cancellation: cancellation,
      onProgress: onProgress,
      label: '正在获取评论',
    );
    final results = <ArticleExportComment>[];
    for (var i = 0; i < topLevel.length; i++) {
      if (cancellation?.isCancelled == true) {
        throw const ExportCancelledException();
      }
      final comment = topLevel[i];
      onProgress?.call('正在获取评论 ${i + 1}/${topLevel.length}');
      var replies = const <ArticleExportComment>[];
      if (comment.replyCount > 0) {
        final rawReplies = await fetchAllCommentPages(
          (page) => controller.commentReplies(comment.id, page: page),
          cancellation: cancellation,
        );
        replies = [
          for (final reply in rawReplies) _toExportComment(reply),
        ];
      }
      results.add(_toExportComment(comment, replies: replies));
    }
    return results;
  }

  /// 按页拉取，直到某页为空或达到 [maxPages]。
  static Future<List<CommunityComment>> fetchAllCommentPages(
    Future<List<CommunityComment>> Function(int page) fetchPage, {
    ExportCancellation? cancellation,
    ValueChanged<String>? onProgress,
    String? label,
  }) async {
    final all = <CommunityComment>[];
    for (var page = 1; page <= maxPages; page++) {
      if (cancellation?.isCancelled == true) {
        throw const ExportCancelledException();
      }
      onProgress?.call(label == null ? '正在获取…' : '$label…');
      final pageItems = await fetchPage(page);
      if (pageItems.isEmpty) break;
      all.addAll(pageItems);
    }
    return all;
  }

  static ArticleExportComment _toExportComment(
    CommunityComment comment, {
    List<ArticleExportComment> replies = const [],
  }) {
    return ArticleExportComment(
      author: comment.authorName,
      contentMarkdown: commentContentMarkdown(comment),
      createdAt: comment.createdAt,
      replies: replies,
    );
  }
}
