import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/app/app_controller.dart';
import 'package:mfuns_flutter/features/auth/auth_repository.dart';
import 'package:mfuns_flutter/features/home/home_repository.dart';
import 'package:mfuns_flutter/features/video/content_detail_page.dart';

const _preview = ContentPreview(
  id: 1,
  title: '测试文章',
  summary: '',
  cover: '',
  author: '作者',
  category: '',
  type: 0,
  likes: 0,
  comments: 0,
  views: 0,
);

class _ArticleController extends AppController {
  var commentsCreated = 0;
  var commentLoads = 0;

  @override
  UserSession? get session => const UserSession(
    accessToken: 'test-token',
    userId: 9,
    displayName: '测试用户',
    avatar: '',
  );

  @override
  Future<ContentDetail> contentDetail(ContentPreview preview) async =>
      ContentDetail(
        preview: preview,
        content: '',
        rawContent: List.filled(80, '这是一段测试文章正文。').join('\n'),
        tags: const [],
        commentAreaId: 3,
      );

  @override
  Future<CommunityCommentPage> commentPage(int areaId, {int page = 1}) async {
    commentLoads++;
    return const CommunityCommentPage(comments: []);
  }

  @override
  Future<void> createComment({
    required int areaId,
    required List<CommentSpan> spans,
    List<String> images = const [],
  }) async {
    commentsCreated++;
  }

  @override
  Future<ResourceReactionStatus> reactionStatus({
    required int resourceId,
    required int resourceType,
  }) async => const ResourceReactionStatus(
    liked: false,
    disliked: false,
    likes: 0,
    dislikes: 0,
  );

  @override
  Future<bool> isFavorite({
    required int resourceId,
    required int resourceType,
  }) async => false;
}

class _ImageCommentController extends _ArticleController {
  @override
  Future<ContentDetail> contentDetail(ContentPreview preview) async =>
      ContentDetail(
        preview: preview,
        content: '',
        rawContent: '短正文',
        tags: const [],
        commentAreaId: 3,
      );

  @override
  Future<CommunityCommentPage> commentPage(int areaId, {int page = 1}) async =>
      CommunityCommentPage(
        comments: [
          CommunityComment.fromJson({
            'id': 11,
            'user_id': 10,
            'content': '',
            'user': {'id': 10, 'name': '图片用户'},
            'content_ext': {
              'images': ['https://example.invalid/comment.png'],
            },
          }),
        ],
      );
}

void main() {
  testWidgets('posting a comment reaches the lazy article comment section', (
    tester,
  ) async {
    final controller = _ArticleController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ArticleDetailPage(controller: controller, preview: _preview),
      ),
    );
    await tester.pumpAndSettle();

    final list = tester.widget<ListView>(
      find.byKey(const PageStorageKey<String>('article-detail-1')),
    );
    final scroll = list.controller!;
    expect(scroll.offset, 0);
    expect(controller.commentLoads, 0);

    await tester.tap(find.byTooltip('展开评论输入框'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '测试评论');
    await tester.tap(find.byTooltip('发布评论'));
    await tester.pumpAndSettle();

    expect(controller.commentsCreated, 1);
    expect(scroll.offset, greaterThan(0));
    expect(find.text('评论区'), findsOneWidget);
    expect(controller.commentLoads, greaterThanOrEqualTo(2));
  });

  testWidgets('image-only comment does not show the empty-text message', (
    tester,
  ) async {
    final controller = _ImageCommentController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ArticleDetailPage(controller: controller, preview: _preview),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('图片用户'), findsOneWidget);
    expect(find.text('（该评论没有文本内容）'), findsNothing);
  });
}
