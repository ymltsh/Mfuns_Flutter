import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/app_controller.dart';
import '../../core/config/user_preferences.dart';
import '../../core/download/download_manager.dart';
import '../../core/download/download_task.dart';
import '../../core/media/android_pip_controller.dart';
import '../../core/media/dlna_cast_controller.dart';
import '../../core/media/media_notification.dart';
import '../../core/media/playback_coordinator.dart';
import '../../core/media/playback_log.dart';
import '../../core/media/playback_source.dart';
import '../../core/media/player_viewport.dart';
import '../../core/navigation/app_route_observer.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/content_link_handler.dart';
import '../../core/widgets/content_spans.dart';
import '../../core/widgets/dlna_cast_widgets.dart';
import '../../core/widgets/image_preview_page.dart';
import '../../core/widgets/inline_emoji_input.dart';
import '../../core/widgets/player_more_overlay.dart';
import '../content/export/article_exporter.dart';
import '../content/export/comment_collector.dart';
import '../content/rich_content_card.dart';
import '../download/download_picker_sheet.dart';
import '../download/widgets/download_button.dart';
import '../feed/feed_compose_page.dart';
import '../home/home_repository.dart';
import '../home/tag_articles_page.dart';
import '../settings/network_diagnostics_page.dart';
import '../user/user_profile_page.dart';
import 'floating_video_controller.dart';

final bool _supportsAndroidVideoExtensions = !kIsWeb && Platform.isAndroid;

/// 当前路由中是否有折叠的评论输入 FAB 可见，供全局悬浮控件避让。
final CommentComposerFabVisibility commentComposerFabVisibility =
    CommentComposerFabVisibility();

class CommentComposerFabVisibility extends ChangeNotifier {
  final Set<Object> _visibleOwners = <Object>{};

  bool get isVisible => _visibleOwners.isNotEmpty;

  void update(Object owner, {required bool visible}) {
    final changed = visible
        ? _visibleOwners.add(owner)
        : _visibleOwners.remove(owner);
    if (changed) notifyListeners();
  }
}

/// Routes content to a type-specific detail page. Article pages never create a
/// video player or request video qualities.
class ContentDetailPage extends StatelessWidget {
  const ContentDetailPage({
    super.key,
    required this.controller,
    required this.preview,
  });

  final AppController controller;
  final ContentPreview preview;

  @override
  Widget build(BuildContext context) => preview.isVideo
      ? VideoDetailPage(controller: controller, preview: preview)
      : ArticleDetailPage(controller: controller, preview: preview);
}

class VideoDetailPage extends StatefulWidget {
  const VideoDetailPage({
    super.key,
    required this.controller,
    required this.preview,
  });

  final AppController controller;
  final ContentPreview preview;

  @override
  State<VideoDetailPage> createState() => _VideoDetailPageState();
}

class _VideoDetailPageState extends State<VideoDetailPage>
    with SingleTickerProviderStateMixin {
  final _playerKey = GlobalKey<_MfunsVideoPlayerState>();
  final _commentSectionKey = GlobalKey<_CommentSectionState>();
  final _commentComposerKey = GlobalKey<CommentComposerBarState>();
  late final Future<ContentDetail> _detail;
  late final Future<List<VideoQuality>>? _qualities;
  late final Future<List<ContentPreview>> _related;
  late final TabController _tabController;
  var _activeTab = 0;
  var _danmakuOn = true;
  VideoQuality? _selectedQuality;
  List<VideoQuality> _availableQualities = const [];
  var _qualitiesLoading = true;
  double _sideRatio = UserPreferences.defaultLandscapeSideRatio;
  var _showFullCommentInput = false;
  var _commentComposerExpanded = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(_syncTab);
    _detail = widget.controller.contentDetail(widget.preview);
    _qualities = widget.preview.isVideo
        ? widget.controller.videoQualities(widget.preview.id)
        : null;
    _qualities
        ?.then((items) {
          if (!mounted) return;
          setState(() {
            _qualitiesLoading = false;
            _availableQualities = items;
          });
        })
        .catchError((Object _) {
          if (!mounted) return;
          setState(() => _qualitiesLoading = false);
        });
    _related = widget.controller.relatedContent(widget.preview);
    // 读取横屏简介/评论栏宽度设置，加载后按新比例重排布局。
    UserPreferences.loadLandscapeSideRatio().then((ratio) {
      if (!mounted) return;
      setState(() => _sideRatio = ratio);
    });
    UserPreferences.loadFullCommentInput().then((enabled) {
      if (!mounted) return;
      setState(() => _showFullCommentInput = enabled);
    });
  }

  void _expandCommentComposer() {
    setState(() => _commentComposerExpanded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _commentComposerKey.currentState?.focusInput();
    });
  }

  /// 滑动切换简介/评论时同步高亮标签。
  void _syncTab() {
    if (_tabController.indexIsChanging) return;
    if (_tabController.index == _activeTab) return;
    setState(() => _activeTab = _tabController.index);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showDanmakuSheet(BuildContext context) {
    final player = _playerKey.currentState;
    if (player == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('播放器尚未准备完成')));
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => _DanmakuComposeSheet(onSend: player.sendDanmakuText),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: FutureBuilder<ContentDetail>(
      future: _detail,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('加载失败：${snapshot.error}'),
            ),
          );
        }
        final detail = snapshot.requireData;
        final showCommentComposer =
            _showFullCommentInput || _commentComposerExpanded;
        // 播放器直接挂在布局树中：避免 FutureBuilder 在横竖屏布局切换的
        // 首帧里渲染加载占位，导致带 GlobalKey 的播放器元素无法在同一帧
        // 内被接管而销毁（全屏时横屏切换会杀掉共享的播放器）。
        final available = _availableQualities;
        final player = _qualitiesLoading
            ? const _InlineLoading(label: '正在获取播放地址')
            : available.isEmpty
            ? const Text('当前没有可用播放地址')
            : MfunsVideoPlayer(
                key: _playerKey,
                controller: widget.controller,
                preview: detail.preview,
                videoId: detail.preview.id,
                title: detail.preview.title,
                coverUrl: detail.preview.cover,
                qualities: available,
                onQualityChanged: (quality) =>
                    setState(() => _selectedQuality = quality),
                onDanmakuChanged: (enabled) =>
                    setState(() => _danmakuOn = enabled),
              );
        final tabs = _DetailTabs(
          activeTab: _activeTab,
          animation: _tabController.animation,
          commentCount: detail.preview.comments,
          onChanged: (value) => _tabController.animateTo(value),
          onSendDanmaku: detail.preview.isVideo
              ? () => _showDanmakuSheet(context)
              : null,
          danmakuOn: _danmakuOn,
          onToggleDanmaku: detail.preview.isVideo
              ? () => _playerKey.currentState?.toggleDanmaku()
              : null,
        );
        // 简介/评论两个标签页各自独立滚动，支持左右滑动切换。
        final introTab = _KeepAliveTab(
          child: SingleChildScrollView(
            key: PageStorageKey<String>('content-intro-${widget.preview.id}'),
            padding: const EdgeInsets.only(bottom: 36),
            child: _VideoDetailPane(
              controller: widget.controller,
              detail: detail,
              related: _related,
              qualities: _availableQualities,
              selectedQuality: _selectedQuality,
              playerKey: _playerKey,
            ),
          ),
        );
        final commentTab = _KeepAliveTab(
          child: SingleChildScrollView(
            key: PageStorageKey<String>('content-comment-${widget.preview.id}'),
            padding: EdgeInsets.fromLTRB(
              16,
              14,
              16,
              showCommentComposer ? 160 : 96,
            ),
            child: detail.commentAreaId != null
                ? _CommentSection(
                    key: _commentSectionKey,
                    controller: widget.controller,
                    areaId: detail.commentAreaId!,
                    canPin:
                        detail.preview.authorId != null &&
                        detail.preview.authorId ==
                            widget.controller.session?.userId,
                  )
                : const Text('当前内容暂不支持评论'),
          ),
        );
        final tabView = TabBarView(
          controller: _tabController,
          children: [introTab, commentTab],
        );
        final commentComposer = detail.commentAreaId == null
            ? null
            : CommentComposerBar(
                key: _commentComposerKey,
                controller: widget.controller,
                areaId: detail.commentAreaId!,
                collapsed: !showCommentComposer,
                visible: _activeTab == 1,
                onExpand: _expandCommentComposer,
                onSubmitted: () => _commentSectionKey.currentState?.reload(),
              );
        Widget tabBody() => Stack(
          children: [
            Positioned.fill(child: tabView),
            if (commentComposer != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Offstage(
                  offstage: _activeTab != 1,
                  child: commentComposer,
                ),
              ),
          ],
        );
        // 横屏自动分栏：左侧播放器（黑底，占剩余宽度），右侧简介/评论
        // 栏宽度按设置占整屏 1/2、1/3、1/4 或 1/5（默认 1/3）。
        final isLandscape =
            MediaQuery.orientationOf(context) == Orientation.landscape;
        if (isLandscape) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ColoredBox(color: Colors.black, child: player),
              ),
              SizedBox(
                width: MediaQuery.sizeOf(context).width * _sideRatio,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    tabs,
                    Expanded(child: tabBody()),
                  ],
                ),
              ),
            ],
          );
        }
        // 竖屏：播放器与标签栏（简介/评论）固定在顶部不随页面滚动，
        // 下方信息与评论独立滚动；播放器高度由自身按视频比例计算
        // （UnconstrainedBox 解除纵向约束）。
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UnconstrainedBox(constrainedAxis: Axis.horizontal, child: player),
            tabs,
            Expanded(child: tabBody()),
          ],
        );
      },
    ),
  );
}

/// TabBarView 子页保活容器：保留滚动位置，避免切换标签重建。
class _KeepAliveTab extends StatefulWidget {
  const _KeepAliveTab({required this.child});

  final Widget child;

  @override
  State<_KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<_KeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class FeedDetailPage extends StatefulWidget {
  const FeedDetailPage({
    super.key,
    required this.controller,
    required this.feedId,
  });

  final AppController controller;
  final int feedId;

  @override
  State<FeedDetailPage> createState() => _FeedDetailPageState();
}

class _FeedDetailPageState extends State<FeedDetailPage> {
  late Future<FeedDetail> _detail;
  final _commentSectionKey = GlobalKey<_CommentSectionState>();
  final _commentComposerKey = GlobalKey<CommentComposerBarState>();
  var _showFullCommentInput = false;
  var _commentComposerExpanded = false;

  @override
  void initState() {
    super.initState();
    _detail = widget.controller.feedDetail(widget.feedId);
    UserPreferences.loadFullCommentInput().then((enabled) {
      if (!mounted) return;
      setState(() => _showFullCommentInput = enabled);
    });
  }

  void _expandCommentComposer() {
    setState(() => _commentComposerExpanded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _commentComposerKey.currentState?.focusInput();
    });
  }

  void _reload() =>
      setState(() => _detail = widget.controller.feedDetail(widget.feedId));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('动态详情'), centerTitle: true),
    body: FutureBuilder<FeedDetail>(
      future: _detail,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('动态加载失败：${snapshot.error}'),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _reload, child: const Text('重试')),
                ],
              ),
            ),
          );
        }
        final detail = snapshot.requireData;
        final feed = detail.feed;
        final preview = ContentPreview(
          id: feed.id,
          title: '动态',
          summary: feed.content,
          cover: feed.images.isEmpty ? '' : feed.images.first,
          author: feed.author,
          category: '动态',
          type: 0,
          likes: feed.likes,
          comments: feed.comments,
          views: feed.views,
        );
        final commentAreaId = detail.commentAreaId;
        final showCommentComposer =
            _showFullCommentInput || _commentComposerExpanded;
        final content = _landscapeCentered(
          context,
          ListView(
            key: PageStorageKey<String>('feed-detail-${feed.id}'),
            padding: EdgeInsets.fromLTRB(
              16,
              14,
              16,
              commentAreaId == null
                  ? 96
                  : showCommentComposer
                  ? 160
                  : 96,
            ),
            children: [
              _FeedAuthorCard(feed: feed, controller: widget.controller),
              const SizedBox(height: 12),
              RichContentCard(
                source: detail.rawContent.isEmpty
                    ? feed.content
                    : detail.rawContent,
                onLinkTap: (url) =>
                    openContentLink(context, widget.controller, url),
              ),
              if (feed.images.isNotEmpty) ...[
                const SizedBox(height: 12),
                _FeedImageGrid(images: feed.images, feedId: feed.id),
              ],
              if (feed.resource != null) ...[
                const SizedBox(height: 12),
                _FeedResourceCard(
                  item: feed.resource!,
                  controller: widget.controller,
                ),
              ],
              const SizedBox(height: 12),
              _VideoActions(
                controller: widget.controller,
                preview: preview,
                resourceType: 3,
                linkPath: 'feed',
              ),
              if (detail.tags.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: detail.tags
                      .map(
                        (tag) => ActionChip(
                          label: Text('#$tag'),
                          onPressed: () =>
                              _openTagList(context, widget.controller, tag),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
              const SizedBox(height: 24),
              if (commentAreaId != null)
                _CommentSection(
                  key: _commentSectionKey,
                  controller: widget.controller,
                  areaId: commentAreaId,
                  canPin:
                      feed.authorId != null &&
                      feed.authorId == widget.controller.session?.userId,
                )
              else
                const _ArticleCommentUnavailable(),
            ],
          ),
        );
        if (commentAreaId == null) return content;
        return Stack(
          children: [
            Positioned.fill(child: content),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: CommentComposerBar(
                key: _commentComposerKey,
                controller: widget.controller,
                areaId: commentAreaId,
                collapsed: !showCommentComposer,
                onExpand: _expandCommentComposer,
                onSubmitted: () => _commentSectionKey.currentState?.reload(),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _FeedAuthorCard extends StatelessWidget {
  const _FeedAuthorCard({required this.feed, required this.controller});

  final TimelineFeed feed;
  final AppController controller;

  void _openProfile(BuildContext context) {
    final userId = feed.authorId;
    if (userId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UserProfilePage(controller: controller, userId: userId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          InkWell(
            customBorder: const CircleBorder(),
            onTap: feed.authorId == null ? null : () => _openProfile(context),
            child: CircleAvatar(
              radius: 22,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              foregroundImage: feed.avatar.isEmpty
                  ? null
                  : NetworkImage(feed.avatar),
              child: Text(feed.author.isEmpty ? 'M' : feed.author[0]),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: feed.authorId == null ? null : () => _openProfile(context),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      feed.author.isEmpty ? 'Mfuns 用户' : feed.author,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _formatDateTime(feed.createdAt),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Text(
            '${feed.views} 浏览',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}

class _FeedImageGrid extends StatelessWidget {
  const _FeedImageGrid({required this.images, required this.feedId});

  final List<String> images;
  final int feedId;

  @override
  Widget build(BuildContext context) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: images.length,
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: images.length == 1
          ? 1
          : images.length <= 4
          ? 2
          : 3,
      crossAxisSpacing: 6,
      mainAxisSpacing: 6,
      childAspectRatio: 1,
    ),
    itemBuilder: (_, index) {
      final uri = Uri.tryParse(images[index]);
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: GestureDetector(
          onTap: uri == null
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ImagePreviewPage(
                      uri: uri,
                      alt: '动态图片',
                      heroTag: 'feed-image-$feedId-$index-$uri',
                      uris: images.map(Uri.parse).toList(growable: false),
                      initialIndex: index,
                    ),
                  ),
                ),
          child: Hero(
            tag: 'feed-image-$feedId-$index-$uri',
            child: Image.network(
              images[index],
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => ColoredBox(
                color: AppPalette.of(context).placeholder,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _FeedResourceCard extends StatelessWidget {
  const _FeedResourceCard({required this.item, required this.controller});

  final ContentPreview item;
  final AppController controller;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: ListTile(
      leading: SizedBox(
        width: 54,
        height: 54,
        child: item.cover.isEmpty
            ? const Icon(Icons.article_outlined)
            : ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Image.network(item.cover, fit: BoxFit.cover),
              ),
      ),
      title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text('${item.views} 浏览 · ${item.likes} 赞'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => item.isFeed
              ? FeedDetailPage(controller: controller, feedId: item.id)
              : ContentDetailPage(controller: controller, preview: item),
        ),
      ),
    ),
  );
}

class ArticleDetailPage extends StatefulWidget {
  const ArticleDetailPage({
    super.key,
    required this.controller,
    required this.preview,
  });

  final AppController controller;
  final ContentPreview preview;

  @override
  State<ArticleDetailPage> createState() => _ArticleDetailPageState();
}

class _ArticleDetailPageState extends State<ArticleDetailPage> {
  late Future<ContentDetail> _detail;
  final _scrollController = ScrollController();
  final _commentSectionKey = GlobalKey<_CommentSectionState>();
  final _commentComposerKey = GlobalKey<CommentComposerBarState>();
  var _articleToolsEnabled = false;
  var _showFullCommentInput = false;
  var _commentComposerExpanded = false;

  @override
  void initState() {
    super.initState();
    _detail = widget.controller.contentDetail(widget.preview);
    _loadReaderPreferences();
  }

  Future<void> _loadReaderPreferences() async {
    final values = await Future.wait<bool>([
      UserPreferences.loadArticleToolsFab(),
      UserPreferences.loadFullCommentInput(),
    ]);
    if (!mounted) return;
    setState(() {
      _articleToolsEnabled = values[0];
      _showFullCommentInput = values[1];
    });
  }

  void _expandCommentComposer() {
    setState(() => _commentComposerExpanded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _commentComposerKey.currentState?.focusInput();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _reload() =>
      setState(() => _detail = widget.controller.contentDetail(widget.preview));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('文章详情'), centerTitle: true),
    body: FutureBuilder<ContentDetail>(
      future: _detail,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('文章加载失败：${snapshot.error}'),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _reload, child: const Text('重试')),
                ],
              ),
            ),
          );
        }
        final detail = snapshot.requireData;
        final commentAreaId = detail.commentAreaId;
        final showCommentComposer =
            _showFullCommentInput || _commentComposerExpanded;
        final articleList = _landscapeCentered(
          context,
          ListView(
            controller: _scrollController,
            key: PageStorageKey<String>('article-detail-${detail.preview.id}'),
            padding: EdgeInsets.fromLTRB(
              16,
              14,
              16,
              commentAreaId == null
                  ? 32
                  : showCommentComposer
                  ? 160
                  : 96,
            ),
            children: [
              _ArticleInfoCard(detail: detail, controller: widget.controller),
              const SizedBox(height: 12),
              RichContentCard(
                source: detail.rawContent,
                onLinkTap: (url) =>
                    openContentLink(context, widget.controller, url),
              ),
              if (detail.preview.createdAt != null) ...[
                const SizedBox(height: 14),
                Center(
                  child: Text(
                    '发布于 ${formatExportDate(detail.preview.createdAt!)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _VideoActions(
                controller: widget.controller,
                preview: detail.preview,
                rawContent: detail.rawContent,
                commentAreaId: detail.commentAreaId,
              ),
              if (detail.tags.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: detail.tags
                      .map(
                        (tag) => ActionChip(
                          label: Text('#$tag'),
                          onPressed: () =>
                              _openTagList(context, widget.controller, tag),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
              const SizedBox(height: 24),
              if (commentAreaId != null)
                _CommentSection(
                  key: _commentSectionKey,
                  controller: widget.controller,
                  areaId: commentAreaId,
                  canPin:
                      detail.preview.authorId != null &&
                      detail.preview.authorId ==
                          widget.controller.session?.userId,
                )
              else
                const _ArticleCommentUnavailable(),
            ],
          ),
        );
        final articleToolsBottom = switch ((
          commentAreaId != null,
          showCommentComposer,
          MediaQuery.sizeOf(context).width < 440,
        )) {
          (false, _, _) => 16.0,
          (true, false, _) => 80.0,
          (true, true, true) => 152.0,
          (true, true, false) => 88.0,
        };
        return Stack(
          children: [
            Positioned.fill(child: articleList),
            if (_articleToolsEnabled)
              Positioned.fill(
                child: ArticleToolsOverlay(
                  controller: _scrollController,
                  minimumBottom: articleToolsBottom,
                ),
              ),
            if (commentAreaId != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: CommentComposerBar(
                  key: _commentComposerKey,
                  controller: widget.controller,
                  areaId: commentAreaId,
                  collapsed: !showCommentComposer,
                  onExpand: _expandCommentComposer,
                  onSubmitted: () => _commentSectionKey.currentState?.reload(),
                ),
              ),
          ],
        );
      },
    ),
  );
}

/// 在阅读区域内承载可拖动的文章工具，并为底部评论栏预留空间。
class ArticleToolsOverlay extends StatefulWidget {
  const ArticleToolsOverlay({
    super.key,
    required this.controller,
    required this.minimumBottom,
  });

  final ScrollController controller;
  final double minimumBottom;

  @override
  State<ArticleToolsOverlay> createState() => _ArticleToolsOverlayState();
}

class _ArticleToolsOverlayState extends State<ArticleToolsOverlay> {
  double _right = 16;
  double? _bottom;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final maxRight = math.max(8.0, constraints.maxWidth - 64);
      final maxBottom = math.max(
        widget.minimumBottom,
        constraints.maxHeight - 64,
      );
      final right = _right.clamp(8.0, maxRight).toDouble();
      final bottom = (_bottom ?? widget.minimumBottom)
          .clamp(widget.minimumBottom, maxBottom)
          .toDouble();
      return Stack(
        children: [
          Positioned(
            right: right,
            bottom: bottom,
            child: ArticleToolsFab(
              controller: widget.controller,
              onDragUpdate: (details) {
                setState(() {
                  _right = (right - details.delta.dx)
                      .clamp(8.0, maxRight)
                      .toDouble();
                  _bottom = (bottom - details.delta.dy)
                      .clamp(widget.minimumBottom, maxBottom)
                      .toDouble();
                });
              },
            ),
          ),
        ],
      );
    },
  );
}

/// 文章快捷工具：目前提供回到开头和跳到结尾两个定位操作。
class ArticleToolsFab extends StatefulWidget {
  const ArticleToolsFab({
    super.key,
    required this.controller,
    this.onDragUpdate,
  });

  final ScrollController controller;
  final GestureDragUpdateCallback? onDragUpdate;

  @override
  State<ArticleToolsFab> createState() => _ArticleToolsFabState();
}

class _ArticleToolsFabState extends State<ArticleToolsFab> {
  var _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  void _jumpToStart() {
    setState(() => _expanded = false);
    if (!widget.controller.hasClients) return;
    widget.controller.jumpTo(widget.controller.position.minScrollExtent);
  }

  void _jumpToEnd() {
    setState(() => _expanded = false);
    if (!widget.controller.hasClients) return;
    widget.controller.jumpTo(widget.controller.position.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget action({
      required Key key,
      required String label,
      required IconData icon,
      required VoidCallback onPressed,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Theme.of(context).colorScheme.inverseSurface,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onInverseSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FloatingActionButton.small(
            key: key,
            heroTag: key,
            tooltip: label,
            backgroundColor: colors.primaryContainer,
            foregroundColor: colors.onPrimaryContainer,
            onPressed: onPressed,
            child: Icon(icon),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomRight,
          child: _expanded
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    action(
                      key: const ValueKey('article-tools-start'),
                      label: '回到开头',
                      icon: Icons.vertical_align_top_rounded,
                      onPressed: _jumpToStart,
                    ),
                    action(
                      key: const ValueKey('article-tools-end'),
                      label: '跳到结尾',
                      icon: Icons.vertical_align_bottom_rounded,
                      onPressed: _jumpToEnd,
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
        GestureDetector(
          onPanUpdate: widget.onDragUpdate,
          child: FloatingActionButton(
            key: const ValueKey('article-tools-fab'),
            heroTag: 'article-tools-fab',
            tooltip: _expanded ? '收起文章工具' : '文章工具',
            backgroundColor: colors.primaryContainer,
            foregroundColor: colors.onPrimaryContainer,
            onPressed: _toggle,
            child: AnimatedRotation(
              turns: _expanded ? .125 : 0,
              duration: const Duration(milliseconds: 180),
              child: Icon(
                _expanded ? Icons.close_rounded : Icons.article_outlined,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 横屏时限制内容宽度并居中，避免文章/动态行宽过长。
Widget _landscapeCentered(BuildContext context, Widget child) {
  if (MediaQuery.orientationOf(context) != Orientation.landscape) {
    return child;
  }
  return Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: child,
    ),
  );
}

class _ArticleInfoCard extends StatelessWidget {
  const _ArticleInfoCard({required this.detail, required this.controller});

  final ContentDetail detail;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final preview = detail.preview;
    final theme = Theme.of(context);
    final cover = Uri.tryParse(preview.cover);
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 文章封面作为头图显示在标题上方。
          if (preview.cover.isNotEmpty)
            GestureDetector(
              onTap: cover == null
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ImagePreviewPage(
                          uri: cover,
                          alt: '文章封面',
                          heroTag: 'article-cover-${preview.id}-$cover',
                        ),
                      ),
                    ),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Hero(
                  tag: 'article-cover-${preview.id}-$cover',
                  child: Image.network(
                    preview.cover,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => ColoredBox(
                      color: AppPalette.of(context).placeholder,
                      child: Icon(
                        Icons.image_outlined,
                        color: AppPalette.of(context).muted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(preview.title, style: theme.textTheme.headlineSmall),
                const SizedBox(height: 12),
                _AuthorBar(
                  controller: controller,
                  preview: preview,
                  subtitle:
                      '${preview.category.isEmpty ? 'Mfuns' : preview.category} · ${preview.views} 阅读 · ${preview.comments} 评论'
                      '${preview.createdAt == null ? '' : ' · ${formatExportDate(preview.createdAt!)}'}',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ArticleCommentUnavailable extends StatelessWidget {
  const _ArticleCommentUnavailable();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 24),
    child: Center(child: Text('当前文章暂不支持评论')),
  );
}

class _DanmakuComposeSheet extends StatefulWidget {
  const _DanmakuComposeSheet({required this.onSend});

  final Future<void> Function(String text) onSend;

  @override
  State<_DanmakuComposeSheet> createState() => _DanmakuComposeSheetState();
}

class _DanmakuComposeSheetState extends State<_DanmakuComposeSheet> {
  final _input = TextEditingController();
  var _sending = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    await widget.onSend(text);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      18,
      18,
      18,
      MediaQuery.viewInsetsOf(context).bottom + 18,
    ),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: _input,
            autofocus: true,
            maxLength: 100,
            onSubmitted: (_) => _send(),
            decoration: const InputDecoration(
              counterText: '',
              hintText: '发个弹幕…',
              prefixIcon: Icon(Icons.subtitles_outlined),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _sending ? null : _send,
          child: _sending
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('发送'),
        ),
      ],
    ),
  );
}

class _DetailTabs extends StatelessWidget {
  const _DetailTabs({
    required this.activeTab,
    this.animation,
    required this.commentCount,
    required this.onChanged,
    this.onSendDanmaku,
    this.onToggleDanmaku,
    required this.danmakuOn,
  });

  final int activeTab;
  final Animation<double>? animation;
  final int commentCount;
  final ValueChanged<int> onChanged;
  final VoidCallback? onSendDanmaku;
  final VoidCallback? onToggleDanmaku;
  final bool danmakuOn;

  @override
  Widget build(BuildContext context) {
    Widget buildTabs(double position) => Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 2,
      child: SizedBox(
        height: 46,
        child: Row(
          children: [
            _DetailTab(
              label: '简介',
              selectedStrength: (1 - position.abs()).clamp(0.0, 1.0),
              onTap: () => onChanged(0),
            ),
            _DetailTab(
              label: '评论 $commentCount',
              selectedStrength: (1 - (position - 1).abs()).clamp(0.0, 1.0),
              onTap: () => onChanged(1),
            ),
            const Spacer(),
            TextButton(onPressed: onSendDanmaku, child: const Text('发弹幕')),
            IconButton(
              tooltip: danmakuOn ? '关闭弹幕' : '开启弹幕',
              onPressed: onToggleDanmaku,
              icon: Icon(
                danmakuOn
                    ? Icons.subtitles_rounded
                    : Icons.subtitles_off_rounded,
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
    final animation = this.animation;
    if (animation == null) return buildTabs(activeTab.toDouble());
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => buildTabs(animation.value),
    );
  }
}

class _DetailTab extends StatelessWidget {
  const _DetailTab({
    required this.label,
    required this.selectedStrength,
    required this.onTap,
  });

  final String label;
  final double selectedStrength;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: label.startsWith('评论') ? 98 : 70,
    child: InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Color.lerp(
                Theme.of(context).colorScheme.onSurfaceVariant,
                Theme.of(context).colorScheme.primary,
                selectedStrength,
              ),
              fontWeight: FontWeight.lerp(
                FontWeight.w500,
                FontWeight.w700,
                selectedStrength,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: 42,
            height: 3,
            color: Theme.of(
              context,
            ).colorScheme.primary.withOpacity(selectedStrength),
          ),
        ],
      ),
    ),
  );
}

/// 点击标签进入该标签下的文章列表。
void _openTagList(BuildContext context, AppController controller, String tag) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TagArticlesPage(controller: controller, tag: tag),
    ),
  );
}

class _ExpandableDescription extends StatefulWidget {
  const _ExpandableDescription({required this.text, required this.onLinkTap});

  final String text;
  final void Function(String url) onLinkTap;

  @override
  State<_ExpandableDescription> createState() => _ExpandableDescriptionState();
}

class _ExpandableDescriptionState extends State<_ExpandableDescription> {
  var _expanded = false;

  bool get _needsToggle => widget.text.length > 60;

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinkText(
          text: text,
          onLinkTap: widget.onLinkTap,
          maxLines: _expanded ? null : 3,
          overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
        ),
        if (_needsToggle)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(
                _expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 18,
              ),
              label: Text(_expanded ? '收起' : '展开'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
            ),
          ),
      ],
    );
  }
}

class _VideoDetailPane extends StatelessWidget {
  const _VideoDetailPane({
    required this.controller,
    required this.detail,
    required this.related,
    required this.qualities,
    required this.selectedQuality,
    required this.playerKey,
  });

  final AppController controller;
  final ContentDetail detail;
  final Future<List<ContentPreview>> related;
  final List<VideoQuality> qualities;
  final VideoQuality? selectedQuality;
  final GlobalKey<_MfunsVideoPlayerState> playerKey;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          detail.preview.title,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          '${detail.preview.category.isEmpty ? 'Mfuns' : detail.preview.category} · ${detail.preview.views} 播放 · ${detail.preview.comments} 弹幕'
          '${detail.preview.createdAt == null ? '' : ' · ${formatExportDate(detail.preview.createdAt!)}'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        _ExpandableDescription(
          text: detail.content,
          onLinkTap: (url) => openContentLink(context, controller, url),
        ),
        const SizedBox(height: 8),
        _VideoActions(
          controller: controller,
          preview: detail.preview,
          qualities: qualities,
          selectedQuality: selectedQuality,
        ),
        if (detail.preview.isVideo && qualities.isNotEmpty) ...[
          const SizedBox(height: 12),
          _PortraitPartSelector(
            qualities: qualities,
            selectedQuality: selectedQuality,
            onQualitySelected: (quality) =>
                playerKey.currentState?.selectQuality(quality),
          ),
        ],
        const Divider(height: 28),
        _AuthorBar(controller: controller, preview: detail.preview),
        if (detail.tags.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Text('标签相关'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: detail.tags
                .map(
                  (tag) => ActionChip(
                    label: Text('#$tag'),
                    onPressed: () => _openTagList(context, controller, tag),
                  ),
                )
                .toList(),
          ),
        ],
        const SizedBox(height: 24),
        Text('相关内容', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        FutureBuilder<List<ContentPreview>>(
          future: related,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _InlineLoading(label: '正在加载相关推荐');
            }
            final items = snapshot.data ?? const <ContentPreview>[];
            if (items.isEmpty) return const Text('暂时没有相关推荐');
            return Column(
              children: items
                  .map(
                    (item) =>
                        _RelatedContentTile(controller: controller, item: item),
                  )
                  .toList(),
            );
          },
        ),
      ],
    ),
  );
}

/// 视频详情页下载入口：监听当前清晰度（整个视频）的任务状态，
/// 点击打开下载选择弹窗（选择清晰度，整个视频所有分P一起下载）。
class _DownloadEntry extends StatefulWidget {
  const _DownloadEntry({
    required this.videoId,
    required this.title,
    required this.cover,
    required this.qualities,
    required this.selectedQuality,
  });

  final int videoId;
  final String title;
  final String cover;
  final List<VideoQuality> qualities;
  final VideoQuality? selectedQuality;

  @override
  State<_DownloadEntry> createState() => _DownloadEntryState();
}

class _DownloadEntryState extends State<_DownloadEntry> {
  DownloadTask? _task;
  var _listening = false;
  StreamSubscription<List<DownloadTask>>? _subscription;

  String get _qualityKey => DownloadTask.normalizeQualityKey(
    _qualityDisplayLabel(widget.selectedQuality ?? widget.qualities.first),
  );

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(_DownloadEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedQuality?.name != widget.selectedQuality?.name ||
        oldWidget.selectedQuality?.label != widget.selectedQuality?.label) {
      _refresh();
    }
  }

  Future<void> _listen() async {
    if (_listening) return;
    _listening = true;
    _subscription = DownloadManager.instance.watchTasks().listen(
      (_) => _refresh(),
    );
    await _refresh();
  }

  Future<void> _refresh() async {
    final task = await DownloadManager.instance.findTask(
      videoId: widget.videoId,
      quality: _qualityKey,
    );
    if (mounted && task != _task) setState(() => _task = task);
  }

  void _openPicker() {
    DownloadPickerSheet.show(
      context,
      videoId: widget.videoId,
      title: widget.title,
      cover: widget.cover,
      qualities: widget.qualities,
      selectedQuality: widget.selectedQuality ?? widget.qualities.first,
    );
  }

  @override
  Widget build(BuildContext context) =>
      DownloadButton(task: _task, onTap: _openPicker);
}

class _VideoActions extends StatefulWidget {
  const _VideoActions({
    required this.controller,
    required this.preview,
    this.resourceType,
    this.linkPath,
    this.rawContent,
    this.commentAreaId,
    this.qualities,
    this.selectedQuality,
  });

  final AppController controller;
  final ContentPreview preview;
  final int? resourceType;
  final String? linkPath;

  /// 文章原始富文本（仅文章详情页提供）；非空时分享面板显示导出入口。
  final String? rawContent;

  /// 文章评论区 areaId（仅文章详情页提供）；为 null 时评论数为 0。
  final int? commentAreaId;

  /// 视频清晰度列表（仅视频详情页提供）；非空时动作栏显示下载入口。
  final List<VideoQuality>? qualities;
  final VideoQuality? selectedQuality;

  @override
  State<_VideoActions> createState() => _VideoActionsState();
}

class _VideoActionsState extends State<_VideoActions> {
  ResourceReactionStatus? _reaction;
  var _favorite = false;
  var _busy = false;
  var _rewarding = false;
  var _showDislike = false;

  int get _resourceType =>
      widget.resourceType ?? (widget.preview.isVideo ? 1 : 0);

  /// 只有文章（0）和视频（1）支持投币，动态等类型不显示投币入口。
  bool get _canReward => _resourceType == 0 || _resourceType == 1;

  @override
  void initState() {
    super.initState();
    _loadStatus();
    _loadShowDislike();
  }

  Future<void> _loadShowDislike() async {
    final enabled = await UserPreferences.loadShowDislike();
    if (!mounted) return;
    setState(() => _showDislike = enabled);
  }

  Future<void> _loadStatus() async {
    if (widget.controller.session == null) return;
    try {
      final values = await Future.wait<Object>([
        widget.controller.reactionStatus(
          resourceId: widget.preview.id,
          resourceType: _resourceType,
        ),
        widget.controller.isFavorite(
          resourceId: widget.preview.id,
          resourceType: _resourceType,
        ),
      ]);
      if (mounted) {
        setState(() {
          _reaction = values[0] as ResourceReactionStatus;
          _favorite = values[1] as bool;
        });
      }
    } catch (_) {
      // Interaction state is optional; taps will still surface API errors.
    }
  }

  bool _ensureSignedIn() {
    if (widget.controller.session != null) return true;
    _notice('请先在“我的”页面登录');
    return false;
  }

  void _notice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _react({required bool dislike}) async {
    if (!_ensureSignedIn() || _busy) return;
    final active = dislike
        ? _reaction?.disliked == true
        : _reaction?.liked == true;
    setState(() => _busy = true);
    try {
      await widget.controller.setReaction(
        resourceId: widget.preview.id,
        resourceType: _resourceType,
        action: active ? 'cancel' : (dislike ? 'dislike' : 'like'),
      );
      await _loadStatus();
    } catch (error) {
      _notice('操作失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reward() async {
    if (!_canReward || !_ensureSignedIn() || _rewarding) return;
    final count = await showModalBottomSheet<int>(
      context: context,
      useRootNavigator: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              leading: Icon(Icons.monetization_on_rounded),
              title: Text('投币支持'),
              subtitle: Text('为你喜欢的视频投币吧！'),
            ),
            const Divider(height: 1),
            for (final value in const [1, 2, 5])
              ListTile(
                leading: const Icon(
                  Icons.monetization_on_outlined,
                  color: Color(0xFFE6A23C),
                ),
                title: Text('投 $value 枚'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(sheetContext).pop(value),
              ),
          ],
        ),
      ),
    );
    if (count == null || !mounted) return;
    setState(() => _rewarding = true);
    try {
      final message = await widget.controller.reward(
        resourceId: widget.preview.id,
        resourceType: _resourceType,
        count: count,
      );
      if (mounted) _notice(message.isEmpty ? '投币成功' : message);
    } catch (error) {
      if (mounted) _notice('投币失败：$error');
    } finally {
      if (mounted) setState(() => _rewarding = false);
    }
  }

  Future<void> _toggleFavorite() async {
    if (!_ensureSignedIn() || _busy) return;
    setState(() => _busy = true);
    try {
      // 已收藏：选择要移出的收藏夹；未收藏：选择要加入的收藏夹。
      final removing = _favorite;
      await widget.controller.loadFavoriteFolders();
      if (!mounted) return;
      final folders = widget.controller.favoriteFolders;
      if (folders.isEmpty) {
        _notice(removing ? '没有可移出的收藏夹' : '请先在“我的收藏”创建收藏夹');
        return;
      }
      final folder = await showModalBottomSheet<FavoriteFolder>(
        context: context,
        useRootNavigator: true,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(removing ? '取消收藏：选择要移出的收藏夹' : '选择收藏夹'),
                subtitle: Text(
                  removing ? '仅从所选收藏夹移除，其他收藏夹中的收藏不受影响' : '收藏后可在“我的收藏”中查看',
                  style: TextStyle(
                    color: AppPalette.of(context).muted,
                    fontSize: 12,
                  ),
                ),
              ),
              for (final item in folders)
                ListTile(
                  leading: Icon(
                    removing
                        ? Icons.bookmark_remove_outlined
                        : Icons.folder_outlined,
                  ),
                  title: Text(item.name),
                  subtitle: Text('${item.count} 个内容'),
                  onTap: () => Navigator.of(sheetContext).pop(item),
                ),
            ],
          ),
        ),
      );
      if (folder == null) return;
      if (removing) {
        await widget.controller.removeFavorite(
          listId: folder.id,
          resourceId: widget.preview.id,
          resourceType: _resourceType,
        );
      } else {
        await widget.controller.addFavorite(
          listId: folder.id,
          resourceId: widget.preview.id,
          resourceType: _resourceType,
        );
      }
      // 刷新星标状态（内容还在其他收藏夹时星标保持点亮）与收藏夹计数。
      await _loadStatus();
      await widget.controller.loadFavoriteFolders();
      if (!mounted) return;
      _notice(removing ? '已从「${folder.name}」取消收藏' : '已收藏到「${folder.name}」');
    } catch (error) {
      _notice(_favorite ? '取消收藏失败：$error' : '收藏失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _linkPath =>
      widget.linkPath ?? (widget.preview.isVideo ? 'video' : 'article');

  String get _articleLink =>
      'https://m.mfuns.net/$_linkPath/${widget.preview.id}';

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _articleLink));
    if (mounted) _notice('链接已复制');
  }

  Future<void> _forwardToFeed() async {
    if (!_ensureSignedIn()) return;
    final resourceTitle = _resourceType == 3
        ? widget.preview.summary
        : widget.preview.title;
    final forwarded = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => FeedForwardPage(
          controller: widget.controller,
          resourceId: widget.preview.id,
          resourceType: _resourceType,
          resourceTitle: resourceTitle,
          resourceCover: widget.preview.cover,
        ),
      ),
    );
    if (forwarded == true) {
      widget.controller.loadFeeds();
    }
  }

  /// 文章（非动态）且正文非空时，在「更多」中提供导出入口。
  bool get _canExportArticle =>
      !widget.preview.isVideo &&
      widget.rawContent != null &&
      widget.rawContent!.trim().isNotEmpty;

  Future<void> _showMore() async {
    final isFeed = widget.resourceType == 3;
    final action = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.repeat_rounded),
              title: const Text('转发到动态'),
              subtitle: Text(
                '添加转发理由并分享到时间线',
                style: TextStyle(
                  color: AppPalette.of(context).muted,
                  fontSize: 12,
                ),
              ),
              onTap: () => Navigator.of(sheetContext).pop('forward'),
            ),
            if (_canExportArticle) ...[
              ListTile(
                leading: const Icon(Icons.ios_share_rounded),
                title: const Text('导出文章（Markdown、图片）'),
                subtitle: Text(
                  '导出为 Markdown 或长图，可附带评论',
                  style: TextStyle(
                    color: AppPalette.of(context).muted,
                    fontSize: 12,
                  ),
                ),
                onTap: () => Navigator.of(sheetContext).pop('export_article'),
              ),
              const Divider(height: 1),
            ],
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text('复制链接'),
              onTap: () => Navigator.of(sheetContext).pop('copy'),
            ),
            ListTile(
              leading: const Icon(Icons.refresh_rounded),
              title: const Text('刷新互动状态'),
              onTap: () => Navigator.of(sheetContext).pop('refresh'),
            ),
            if (isFeed)
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  '删除动态',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () => Navigator.of(sheetContext).pop('delete'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'forward') await _forwardToFeed();
    if (action == 'copy') await _copyLink();
    if (action == 'refresh') await _loadStatus();
    if (action == 'delete') await _confirmDeleteFeed();
    if (action == 'export_article') await _showExportDialog();
  }

  /// 打开「导出文章」配置弹窗：格式、评论与页脚选项。
  Future<void> _showExportDialog() async {
    final rawContent = widget.rawContent;
    if (rawContent == null || rawContent.trim().isEmpty) {
      _notice('文章内容为空，无法导出');
      return;
    }
    final result = await showDialog<_ExportArticleDialogResult>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _ExportArticleDialog(
        controller: widget.controller,
        areaId: widget.commentAreaId,
      ),
    );
    if (!mounted || result == null) return;
    await _runExport(result.options, comments: result.comments);
  }

  /// 执行导出：进度对话框 → 保存到本地 → 询问是否分享。
  Future<void> _runExport(
    ArticleExportOptions options, {
    required List<ArticleExportComment> comments,
  }) async {
    final rawContent = widget.rawContent ?? '';
    final exporter = ArticleExporter();
    final data = ArticleExportData(
      title: widget.preview.title,
      author: widget.preview.author,
      authorAvatar: widget.preview.authorAvatar,
      rawContent: rawContent,
      sourceUrl: _articleLink,
    );

    final cancellation = ExportCancellation();
    final progress = ValueNotifier<String>('');
    var dialogOpen = true;
    final dialogFuture = showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => _ExportProgressDialog(
        message: options.format == ArticleExportFormat.markdown
            ? '正在导出 Markdown…'
            : '正在生成图片…',
        progress: progress,
        onCancel: cancellation.requestCancel,
      ),
    );
    dialogFuture.whenComplete(() => dialogOpen = false);

    List<ExportResult>? results;
    String? errorNotice;
    try {
      results = await exporter.export(
        context,
        data,
        options,
        comments: comments,
        onProgress: (message) => progress.value = message,
        cancellation: cancellation,
      );
    } on ExportCancelledException {
      errorNotice = '已取消导出';
    } on ArticleExportException catch (error) {
      errorNotice = '导出失败：${error.message}';
    } on Exception {
      errorNotice = '导出失败，请稍后重试';
    } finally {
      if (mounted && dialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      progress.dispose();
    }
    if (!mounted) return;
    if (errorNotice != null) {
      _notice(errorNotice);
      return;
    }
    final completed = results;
    if (completed == null) return;

    // 已保存到本地：询问是否进入系统分享。
    final share = await _confirmShare(completed);
    if (!mounted) return;
    final failed = completed.fold<int>(
      0,
      (sum, result) => sum + result.failedImageCount,
    );
    if (share != true) {
      _notice(failed > 0 ? '文章已导出，但部分图片下载失败' : '导出成功，文件已保存到本地');
      return;
    }
    try {
      await exporter.share(completed);
    } on Exception {
      // 分享面板不可用（如旧版 Windows）：提示文件位置。
      _notice('导出成功：${completed.first.path}');
      return;
    }
    _notice(failed > 0 ? '文章已导出，但部分图片下载失败' : '导出成功，已打开分享面板');
  }

  /// 询问是否分享已导出的文件。
  Future<bool?> _confirmShare(List<ExportResult> results) {
    final paths = results.map((r) => r.path).join('\n');
    return showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('导出完成'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('文章已保存到本地，是否分享？'),
            const SizedBox(height: 10),
            Text(
              paths,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppPalette.of(context).muted,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('不分享'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('分享'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteFeed() async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: const Text('删除动态'),
        content: const Text('删除后无法恢复，确定删除这条动态吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.controller.deleteFeed(widget.preview.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('动态已删除')));
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final reaction = _reaction;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _ActionIcon(
          icon: reaction?.liked == true
              ? Icons.thumb_up_alt_rounded
              : Icons.thumb_up_alt_outlined,
          label: '${reaction?.likes ?? widget.preview.likes} 赞',
          selected: reaction?.liked == true,
          busy: _busy,
          onTap: () => _react(dislike: false),
        ),
        if (_showDislike)
          _ActionIcon(
            icon: reaction?.disliked == true
                ? Icons.thumb_down_alt_rounded
                : Icons.thumb_down_alt_outlined,
            label: '${reaction?.dislikes ?? 0} 踩',
            selected: reaction?.disliked == true,
            busy: _busy,
            onTap: () => _react(dislike: true),
          ),
        _ActionIcon(
          icon: _favorite ? Icons.star_rounded : Icons.star_border_rounded,
          label: _favorite ? '已收藏' : '收藏',
          selected: _favorite,
          busy: _busy,
          onTap: _toggleFavorite,
        ),
        if (_canReward)
          _ActionIcon(
            icon: Icons.monetization_on_outlined,
            label: '投币',
            busy: _rewarding,
            onTap: _reward,
          ),
        if (widget.preview.isVideo && (widget.qualities?.isNotEmpty ?? false))
          _DownloadEntry(
            videoId: widget.preview.id,
            title: widget.preview.title,
            cover: widget.preview.cover,
            qualities: widget.qualities!,
            selectedQuality: widget.selectedQuality,
          ),
        _ActionIcon(
          icon: Icons.more_vert_rounded,
          label: '更多',
          onTap: _showMore,
        ),
      ],
    );
  }
}

class _PortraitPartSelector extends StatelessWidget {
  const _PortraitPartSelector({
    required this.qualities,
    required this.selectedQuality,
    required this.onQualitySelected,
  });

  final List<VideoQuality> qualities;
  final VideoQuality? selectedQuality;
  final ValueChanged<VideoQuality> onQualitySelected;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
    decoration: BoxDecoration(
      color: AppPalette.of(context).chip,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '分 P',
          style: TextStyle(
            color: AppPalette.of(context).muted,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 7),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children:
                (qualities.map((quality) => quality.part).toSet().toList()
                      ..sort())
                    .map((part) {
                      final selected = part == selectedQuality?.part;
                      final target = _matchingPartQuality(
                        qualities,
                        selectedQuality,
                        part,
                      );
                      return Padding(
                        padding: const EdgeInsets.only(right: 7),
                        child: ChoiceChip(
                          label: Text('P$part'),
                          selected: selected,
                          selectedColor: Theme.of(context).colorScheme.primary,
                          labelStyle: TextStyle(
                            color: selected
                                ? Colors.white
                                : AppPalette.of(context).muted,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                          side: BorderSide.none,
                          backgroundColor: AppPalette.of(context).chip,
                          onSelected: selected
                              ? null
                              : (_) {
                                  if (target != null) onQualitySelected(target);
                                },
                        ),
                      );
                    })
                    .toList(),
          ),
        ),
      ],
    ),
  );
}

/// 「导出文章」配置弹窗的返回结果。
class _ExportArticleDialogResult {
  const _ExportArticleDialogResult({
    required this.options,
    required this.comments,
  });

  final ArticleExportOptions options;

  /// includeComments 为 true 时，评论为已完整获取的评论列表。
  final List<ArticleExportComment> comments;
}

/// 「导出文章」配置弹窗：导出格式、是否带评论、是否带开源项目说明。
class _ExportArticleDialog extends StatefulWidget {
  const _ExportArticleDialog({required this.controller, required this.areaId});

  final AppController controller;

  /// 文章评论区 areaId；为 null 表示无评论区。
  final int? areaId;

  @override
  State<_ExportArticleDialog> createState() => _ExportArticleDialogState();
}

class _ExportArticleDialogState extends State<_ExportArticleDialog> {
  var _format = ArticleExportFormat.image;
  var _includeComments = false;
  var _includeFooter = false;
  var _imageScale = 2.0;

  /// 已完整获取的评论（顶层 + 回复）；null 表示尚未获取或获取失败。
  List<ArticleExportComment>? _comments;
  var _commentsLoading = false;
  var _commentsFailed = false;

  void _toggleComments(bool value) {
    setState(() {
      _includeComments = value;
      _comments = null;
      _commentsLoading = false;
      _commentsFailed = false;
    });
    if (!value) return;
    final areaId = widget.areaId;
    if (areaId == null) {
      setState(() => _comments = const []);
      return;
    }
    setState(() => _commentsLoading = true);
    _loadComments(areaId);
  }

  Future<void> _loadComments(int areaId) async {
    try {
      final comments = await ArticleCommentCollector.collect(
        controller: widget.controller,
        areaId: areaId,
      );
      if (!mounted || !_includeComments) return;
      setState(() {
        _comments = comments;
        _commentsLoading = false;
      });
    } catch (_) {
      if (!mounted || !_includeComments) return;
      setState(() {
        _commentsLoading = false;
        _commentsFailed = true;
      });
    }
  }

  /// 实际会被导出的评论条目数（顶层评论 + 二级回复）。
  int _countAll(List<ArticleExportComment> comments) =>
      comments.fold<int>(0, (sum, comment) => sum + 1 + comment.replies.length);

  String get _commentSubtitle {
    if (_commentsLoading) return '正在获取评论…';
    if (_commentsFailed) return '获取评论失败，导出时可不包含评论';
    final count = _comments == null ? 0 : _countAll(_comments!);
    return '包含评论数量：$count 条';
  }

  Future<void> _submit() async {
    var includeComments = _includeComments;
    var comments = _comments ?? const <ArticleExportComment>[];
    if (includeComments && _commentsFailed) {
      final proceed = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (dialogContext) => AlertDialog(
          title: const Text('获取评论失败'),
          content: const Text('无法获取评论，是否仍然导出文章？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('继续导出'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
      // 继续导出时不带评论，也不生成空的评论章节。
      includeComments = false;
      comments = const [];
    }
    Navigator.of(context).pop(
      _ExportArticleDialogResult(
        options: ArticleExportOptions(
          format: _format,
          includeComments: includeComments,
          includeFooter: _includeFooter,
          imageScale: _imageScale,
        ),
        comments: comments,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('导出文章'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              value: _includeComments,
              onChanged: (value) => _toggleComments(value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                '带评论导出',
                style: TextStyle(
                  color: AppPalette.of(context).muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: _includeComments
                  ? Text(
                      _commentSubtitle,
                      style: TextStyle(
                        color: AppPalette.of(context).muted,
                        fontSize: 12,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 6),
            CheckboxListTile(
              value: _includeFooter,
              onChanged: (value) =>
                  setState(() => _includeFooter = value ?? true),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                '在导出底部加入Mfuns Flutter开源项目说明',
                style: TextStyle(
                  color: AppPalette.of(context).muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                '正文之后附加项目介绍与 GitHub 地址',
                style: TextStyle(
                  color: AppPalette.of(context).muted,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '导出格式',
              style: TextStyle(
                color: AppPalette.of(context).muted,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            SegmentedButton<ArticleExportFormat>(
              segments: const [
                ButtonSegment(
                  value: ArticleExportFormat.markdown,
                  label: Text('Markdown'),
                  icon: Icon(Icons.notes_rounded),
                ),
                ButtonSegment(
                  value: ArticleExportFormat.image,
                  label: Text('图片'),
                  icon: Icon(Icons.image_outlined),
                ),
              ],
              selected: {_format},
              onSelectionChanged: (selection) =>
                  setState(() => _format = selection.first),
            ),
            if (_format == ArticleExportFormat.image) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    '内容大小',
                    style: TextStyle(
                      color: AppPalette.of(context).muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '×${_imageScale.toStringAsFixed(1)}',
                    style: TextStyle(
                      color: AppPalette.of(context).primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _imageScale,
                min: 0.5,
                max: 2.0,
                divisions: 15,
                label: '×${_imageScale.toStringAsFixed(1)}',
                onChanged: (value) => setState(() => _imageScale = value),
              ),
              Text(
                '调整字号相对图片的大小，输出分辨率固定为 1080px',
                style: TextStyle(
                  color: AppPalette.of(context).muted,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _commentsLoading ? null : _submit,
          child: const Text('导出'),
        ),
      ],
    );
  }
}

/// 导出进度对话框：展示当前进度与取消按钮，阻止系统返回与误触关闭。
class _ExportProgressDialog extends StatelessWidget {
  const _ExportProgressDialog({
    required this.message,
    required this.progress,
    required this.onCancel,
  });

  final String message;
  final ValueListenable<String> progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<String>(
            valueListenable: progress,
            builder: (context, value, _) => Text(
              value.isEmpty ? message : value,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppPalette.of(context).muted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(onPressed: onCancel, child: const Text('取消')),
        ],
      ),
    ),
  );
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return InkResponse(
      onTap: busy ? null : onTap,
      radius: 28,
      child: SizedBox(
        width: 56,
        child: Column(
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthorBar extends StatefulWidget {
  const _AuthorBar({
    required this.controller,
    required this.preview,
    this.subtitle = '作者',
  });

  final AppController controller;
  final ContentPreview preview;
  final String subtitle;

  @override
  State<_AuthorBar> createState() => _AuthorBarState();
}

class _AuthorBarState extends State<_AuthorBar> {
  bool? _following;
  var _isUpdating = false;

  int? get _userId => widget.preview.authorId;
  bool get _isOwnProfile =>
      _userId != null && _userId == widget.controller.session?.userId;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final userId = _userId;
    if (userId == null || _isOwnProfile || widget.controller.session == null) {
      return;
    }
    try {
      final following = await widget.controller.followStatus(userId);
      if (mounted) setState(() => _following = following);
    } catch (_) {
      // The action remains available; a follow request will surface its error.
    }
  }

  void _openProfile() {
    final userId = _userId;
    if (userId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            UserProfilePage(controller: widget.controller, userId: userId),
      ),
    );
  }

  Future<void> _toggleFollow() async {
    final userId = _userId;
    if (userId == null || _isUpdating || _isOwnProfile) return;
    if (widget.controller.session == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先在“我的”页面登录后再关注')));
      return;
    }
    final next = !(_following ?? false);
    setState(() => _isUpdating = true);
    try {
      await widget.controller.setFollow(userId: userId, follow: next);
      if (mounted) setState(() => _following = next);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('操作失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final userId = _userId;
    final canOpen = userId != null;
    final following = _following == true;
    return Row(
      children: [
        InkResponse(
          onTap: canOpen ? _openProfile : null,
          radius: 30,
          child: CircleAvatar(
            radius: 22,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            foregroundImage: preview.authorAvatar.isEmpty
                ? null
                : NetworkImage(preview.authorAvatar),
            child: Text(preview.author.isEmpty ? '?' : preview.author[0]),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: InkWell(
            onTap: canOpen ? _openProfile : null,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preview.author.isEmpty ? 'Mfuns 用户' : preview.author,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(widget.subtitle),
                ],
              ),
            ),
          ),
        ),
        if (_isOwnProfile)
          const Text('我的投稿')
        else
          OutlinedButton.icon(
            onPressed: userId == null || _isUpdating ? null : _toggleFollow,
            icon: _isUpdating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(following ? Icons.check_rounded : Icons.add_rounded),
            label: Text(following ? '已关注' : '关注'),
          ),
      ],
    );
  }
}

class _RelatedContentTile extends StatelessWidget {
  const _RelatedContentTile({required this.controller, required this.item});

  final AppController controller;
  final ContentPreview item;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ContentDetailPage(controller: controller, preview: item),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: SizedBox(
              width: 130,
              height: 90,
              child: item.cover.isEmpty
                  ? ColoredBox(color: AppPalette.of(context).placeholder)
                  : Image.network(
                      item.cover,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          ColoredBox(color: AppPalette.of(context).placeholder),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 90,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Spacer(),
                  Text(
                    item.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    '${item.likes} 点赞  ${item.comments} 评论  ${item.views} 浏览',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _InlineLoading extends StatelessWidget {
  const _InlineLoading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    ),
  );
}

class MfunsVideoPlayer extends StatefulWidget {
  const MfunsVideoPlayer({
    super.key,
    required this.controller,
    required this.videoId,
    required this.title,
    required this.coverUrl,
    required this.qualities,
    this.preview,
    this.onQualityChanged,
    this.onDanmakuChanged,
  });

  final AppController controller;
  final int videoId;
  final String title;
  final String coverUrl;
  final List<VideoQuality> qualities;
  final ContentPreview? preview;
  final ValueChanged<VideoQuality>? onQualityChanged;
  final ValueChanged<bool>? onDanmakuChanged;

  @override
  State<MfunsVideoPlayer> createState() => _MfunsVideoPlayerState();
}

class _MfunsVideoPlayerState extends State<MfunsVideoPlayer>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver, RouteAware {
  VideoPlayerController? _player;
  VideoQuality? _selected;
  List<DanmakuItem> _danmaku = const [];
  String? _error;
  var _showDanmaku = true;
  var _playbackSpeed = 1.0;
  var _volume = .7;
  var _brightness = .5;
  var _brightnessAvailable = true;
  var _controlsVisible = true;
  var _hasStarted = false;
  var _isLongPressSpeed = false;
  var _isSeeking = false;
  String? _seekNotice;
  _SlideFeedback? _slideFeedback;
  Timer? _ticker;
  Timer? _controlsTimer;
  var _selectionRequest = 0;
  double _danmakuOpacity = 1.0;
  double _danmakuSize = 20.0;
  var _autoPlay = true;
  var _autoPlayed = false;
  double _dragSeekStartDx = 0;
  Duration _dragSeekBase = Duration.zero;
  var _wakelockHeld = false;
  var _isFullscreen = false;
  var _backgroundPlay = false;
  var _isAutoAdvancingPart = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The player is drawn edge-to-edge: keep the layout consistent across
    // devices (Android <15 legacy vs enforced edge-to-edge) and use light
    // status bar icons over the black player surface.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemStatusBarContrastEnforced: false,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
      ),
    );
    _loadPreferences();
    _ticker = Timer.periodic(const Duration(milliseconds: 350), (_) {
      if (mounted &&
          (_player?.value.isPlaying == true ||
              _player?.value.isBuffering == true)) {
        setState(() {});
      }
      _syncWakelock();
      _checkAutoNextPart();
    });
    _scheduleControlsHide();
    _loadBrightness();
  }

  /// 订阅路由可见性：当本页面被上层路由覆盖 / 重新可见时收到通知，
  /// 用于在返回本页时把播放器重新登记为全局 owner（reclaim）。
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      appRouteObserver.subscribe(this, route);
    }
  }

  /// 本页面重新成为当前路由（上层页面被 pop）。
  ///
  /// 只重新登记播放控制权，**不自动播放**：B 返回 A 时 A 保持暂停，
  /// 由用户点击播放按钮触发 `requestPlay()` 才真正恢复播放。
  @override
  void didPopNext() {
    _reclaimPlayback();
  }

  Future<void> _reclaimPlayback() async {
    final player = _player;
    final selected = _selected;
    if (!mounted || player == null || selected == null) return;
    await MfunsPlaybackCoordinator.instance.claimExistingVideo(
      player,
      url: selected.url,
      part: selected.part,
      title: widget.title,
      subtitle: 'Mfuns',
      artUri: widget.coverUrl,
    );
    if (!mounted) return;
    setState(() {});
  }

  /// 后台播放（Beta）：
  /// - 开启：退后台时由 MfunsPlaybackCoordinator 把音频 handoff 到
  ///   just_audio 后台引擎继续播放，回前台时切回视频。
  /// - 关闭：退后台自动暂停视频，避免静默播放。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (AndroidPipController.instance.isActive ||
          AndroidPipController.instance.isEntering) {
        return;
      }
      MfunsPlaybackCoordinator.instance.onAppBackgrounded(
        backgroundPlayEnabled: _backgroundPlay,
      );
    } else if (state == AppLifecycleState.resumed) {
      MfunsPlaybackCoordinator.instance.onAppForegrounded();
    }
  }

  /// 播放时保持屏幕唤醒（wakelock_plus），暂停/停止/销毁时释放，
  /// 避免自动锁屏；全屏共用同一控制器，由本状态统一维护。
  void _syncWakelock() {
    final playing = _player?.value.isPlaying == true;
    if (playing == _wakelockHeld) return;
    _wakelockHeld = playing;
    if (playing) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  /// 当前分P播放结束后自动连播下一分P（竖屏时由本状态检测；
  /// 全屏时由全屏层自己检测，避免共享控制器被本状态替换）。
  Future<void> _checkAutoNextPart() async {
    if (_isFullscreen || _isAutoAdvancingPart) return;
    // 页面被上层路由覆盖（例如从相关视频进入 B 页）时不做自动连播，
    // 避免不可见页面的自动切换抢走当前页面的播放权（全局单播放器仲裁）。
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    // App 在后台（音频已交接给后台引擎）时不创建新播放器。
    if (MfunsPlaybackCoordinator.instance.phase.isBackground) return;
    final player = _player;
    final selected = _selected;
    if (player == null || selected == null) return;
    final value = player.value;
    if (value.duration <= Duration.zero) return;
    if (value.isPlaying) return;
    if (!value.isCompleted && value.position < value.duration) return;
    final next = _matchingPartQuality(
      widget.qualities,
      selected,
      selected.part + 1,
    );
    if (next == null) return;
    _isAutoAdvancingPart = true;
    try {
      await _select(next, forcePlay: true);
    } finally {
      _isAutoAdvancingPart = false;
    }
  }

  Future<void> _loadPreferences() async {
    final results = await Future.wait([
      UserPreferences.loadDanmakuOn(),
      UserPreferences.loadDanmakuOpacity(),
      UserPreferences.loadDanmakuSize(),
      UserPreferences.loadDefaultQuality(),
      UserPreferences.loadAutoPlay(),
      UserPreferences.loadBackgroundPlay(),
    ]);
    if (!mounted) return;
    final qualityPreference = results[3] as String;
    setState(() {
      _showDanmaku = results[0] as bool;
      _danmakuOpacity = results[1] as double;
      _danmakuSize = results[2] as double;
      _qualityPreference = qualityPreference;
      _autoPlay = results[4] as bool;
      _backgroundPlay = results[5] as bool;
    });
    widget.onDanmakuChanged?.call(_showDanmaku);
    final adopted = FloatingVideoController.instance.takeFor(widget.videoId);
    if (adopted != null && adopted.player.value.isInitialized) {
      final quality = widget.qualities.cast<VideoQuality?>().firstWhere(
        (item) =>
            item?.url == adopted.quality.url &&
            item?.part == adopted.quality.part,
        orElse: () => adopted.quality,
      )!;
      setState(() {
        _player = adopted.player;
        _selected = quality;
        _volume = adopted.player.value.volume;
        _playbackSpeed = adopted.player.value.playbackSpeed;
        _hasStarted = adopted.player.value.position > Duration.zero;
      });
      await MfunsPlaybackCoordinator.instance.claimExistingVideo(
        adopted.player,
        url: quality.url,
        part: quality.part,
        title: widget.title,
        subtitle: 'Mfuns',
        artUri: widget.coverUrl,
      );
      _attachFloatingSession(adopted.player, quality);
      _attachMediaNotification(adopted.player, quality);
      await _loadDanmaku(quality.part);
      return;
    }
    // 首次加载完成后按偏好选择清晰度；开启自动播放时直接开始播放。
    _select(_preferredQuality(), autoPlay: _autoPlay);
  }

  /// 按设置的默认清晰度选择；"自动"时选择当前视频可用的最高清晰度。
  VideoQuality _preferredQuality() {
    final label = _qualityPreference;
    if (label.isEmpty) {
      VideoQuality? best;
      var bestPixels = -1;
      for (final quality in widget.qualities) {
        final pixels = _qualityPixels(quality);
        if (pixels > bestPixels) {
          bestPixels = pixels;
          best = quality;
        }
      }
      return best ?? widget.qualities.last;
    }
    for (final quality in widget.qualities) {
      if (_qualityDisplayLabel(quality).toLowerCase() == label) {
        return quality;
      }
    }
    return widget.qualities.last;
  }

  /// 解析清晰度的近似像素高度，用于"自动"选择最高清晰度。
  int _qualityPixels(VideoQuality quality) {
    final label = _qualityDisplayLabel(quality).toLowerCase();
    final match = RegExp(r'(\d{3,4})').firstMatch(label);
    if (match != null) return int.parse(match.group(1)!);
    if (label.contains('4k')) return 2160;
    if (label.contains('2k')) return 1440;
    if (label.contains('hd')) return 720;
    if (label.contains('sd')) return 480;
    return 0;
  }

  String _qualityPreference = '';

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _controlsTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // 返回页面后由路由树中的 AnnotatedRegion 恢复当前主题的系统栏样式。
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    if (_wakelockHeld) {
      _wakelockHeld = false;
      WakelockPlus.disable();
    }
    final player = _player;
    if (player != null) {
      if (FloatingVideoController.instance.owns(player)) {
        super.dispose();
        return;
      }
      FloatingVideoController.instance.detach(player);
      final wasBound = MfunsPlaybackCoordinator.instance.unbindVideo(player);
      PlaybackLog.d(
        'player dispose id=${identityHashCode(player)} bound=$wasBound',
      );
      player.dispose();
      if (wasBound) {
        MfunsAudioHandler.instance.detach();
      }
    }
    super.dispose();
  }

  /// 播放器初始化（拉取视频数据）的超时上限，超时后提示用户排查网络。
  static const videoInitTimeout = Duration(seconds: 10);

  Future<void> _select(
    VideoQuality quality, {
    bool retrySameSource = true,
    bool allowFallback = true,
    bool autoPlay = false,
    bool forcePlay = false,
  }) async {
    final request = ++_selectionRequest;
    final oldPlayer = _player;
    final oldValue = oldPlayer?.value;
    // 同一分P内切换清晰度时保留播放进度；切换分P则从头开始。
    final samePart = (_selected?.part ?? quality.part) == quality.part;
    final resumePosition = samePart
        ? (oldValue?.position ?? Duration.zero)
        : Duration.zero;
    final wasPlaying = oldValue?.isPlaying ?? false;
    setState(() {
      _selected = quality;
      _player = null;
      _error = null;
      _danmaku = const [];
    });
    widget.onQualityChanged?.call(quality);
    if (oldPlayer != null) {
      FloatingVideoController.instance.detach(oldPlayer);
      MfunsPlaybackCoordinator.instance.unbindVideo(oldPlayer);
    }
    await oldPlayer?.dispose();
    if (!mounted || request != _selectionRequest) return;
    final options = VideoPlayerOptions(
      // 真正的“是否启用后台播放”由本页 _backgroundPlay 控制；
      // 退后台时由 MfunsPlaybackCoordinator 负责暂停或 handoff。
      allowBackgroundPlayback: _backgroundPlay,
    );
    // 统一播放源：已下载完成且与 videoId+part+quality 精确匹配时优先本地播放。
    final PlaybackSource source = await _resolveSource(quality);
    final nextPlayer = switch (source) {
      NetworkPlaybackSource(:final uri) => VideoPlayerController.networkUrl(
        uri,
        videoPlayerOptions: options,
      ),
      LocalPlaybackSource(:final path) => VideoPlayerController.file(
        File(path),
        videoPlayerOptions: options,
      ),
    };
    // 本地文件无法交给后台引擎续播（无网络地址），传 null 让协调器退后台即暂停。
    final bindUrl = source is LocalPlaybackSource ? null : quality.url;
    PlaybackLog.d(
      'create player id=${identityHashCode(nextPlayer)} url=${quality.url} '
      'local=${source is LocalPlaybackSource}',
    );
    try {
      await nextPlayer.initialize().timeout(videoInitTimeout);
      PlaybackLog.d(
        'initialize ok id=${identityHashCode(nextPlayer)} '
        'duration=${nextPlayer.value.duration}',
      );
      await nextPlayer.setVolume(_volume);
      await nextPlayer.setPlaybackSpeed(_playbackSpeed);
      if (resumePosition > Duration.zero) {
        final target = resumePosition > nextPlayer.value.duration
            ? nextPlayer.value.duration
            : resumePosition;
        await nextPlayer.seekTo(target);
      }
      await MfunsPlaybackCoordinator.instance.bindVideo(
        nextPlayer,
        url: bindUrl,
        part: quality.part,
      );
      if (wasPlaying || forcePlay) {
        await MfunsPlaybackCoordinator.instance.requestPlay();
      }
      if (!mounted || request != _selectionRequest) {
        MfunsPlaybackCoordinator.instance.unbindVideo(nextPlayer);
        await nextPlayer.dispose();
        return;
      }
      setState(() => _player = nextPlayer);
      _attachFloatingSession(nextPlayer, quality);
      _attachMediaNotification(nextPlayer, quality);
      // 打开视频自动播放：仅在首次初始化时生效。
      if (autoPlay && !_autoPlayed) {
        _autoPlayed = true;
        _hasStarted = true;
        await MfunsPlaybackCoordinator.instance.requestPlay();
      }
      await _loadDanmaku(quality.part);
    } catch (error) {
      MfunsPlaybackCoordinator.instance.unbindVideo(nextPlayer);
      await nextPlayer.dispose();
      if (!mounted || request != _selectionRequest) return;
      if (retrySameSource) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (mounted && request == _selectionRequest) {
          await _select(quality, retrySameSource: false, allowFallback: true);
        }
        return;
      }
      if (allowFallback) {
        final alternatives = widget.qualities
            .where((candidate) => candidate != quality)
            .toList(growable: false);
        if (alternatives.isNotEmpty) {
          await _select(
            alternatives.first,
            retrySameSource: false,
            allowFallback: false,
          );
          return;
        }
      }
      setState(() {
        _error = error is TimeoutException
            ? '视频加载超时（${videoInitTimeout.inSeconds} 秒），请检查网络后重试'
            : '播放地址加载失败，请点击重试';
      });
    }
  }

  Future<void> _loadDanmaku(int part) async {
    try {
      final items = await widget.controller.danmaku(widget.videoId, part);
      if (mounted && _selected?.part == part) setState(() => _danmaku = items);
    } catch (_) {
      // Video playback must remain usable when the optional danmaku endpoint fails.
    }
  }

  /// 绑定媒体通知：在系统通知栏展示当前视频并同步播放/暂停/进度。
  void _attachMediaNotification(
    VideoPlayerController player,
    VideoQuality quality,
  ) {
    MfunsAudioHandler.instance.attach(
      player: player,
      title: widget.title,
      subtitle: 'Mfuns',
      artUri: widget.coverUrl,
      url: quality.url,
      part: quality.part,
    );
  }

  void _attachFloatingSession(
    VideoPlayerController player,
    VideoQuality quality,
  ) {
    final preview = widget.preview;
    if (preview == null) return;
    FloatingVideoController.instance.attach(
      FloatingVideoSession(player: player, preview: preview, quality: quality),
    );
  }

  void _startAppMiniPlayer() {
    final player = _player;
    if (player == null || widget.preview == null) return;
    if (!FloatingVideoController.instance.startFloating(player)) return;
    Navigator.of(
      context,
      rootNavigator: true,
    ).popUntil((route) => route.isFirst);
  }

  Future<void> _enterSystemPip() async {
    final player = _player;
    if (player == null || !player.value.isInitialized) return;
    final available = await AndroidPipController.instance.isAvailable;
    if (!available) {
      _notice('当前设备或系统版本不支持画中画');
      return;
    }
    final ratio = player.value.aspectRatio;
    final width = ratio > 0 ? (ratio * 1000).round() : 16;
    final entered = await AndroidPipController.instance.enter(
      width: width,
      height: ratio > 0 ? 1000 : 9,
    );
    if (!entered && mounted) _notice('无法进入系统画中画');
  }

  Future<void> _startDlnaCast() async {
    final player = _player;
    final quality = _selected;
    if (player == null || quality == null) return;
    final wasPlaying = player.value.isPlaying;
    if (wasPlaying) await MfunsPlaybackCoordinator.instance.requestPause();
    if (!mounted) return;
    final renderer = await showDlnaDevicePicker(context);
    if (!mounted) return;
    if (renderer == null) {
      if (wasPlaying) await MfunsPlaybackCoordinator.instance.requestPlay();
      return;
    }
    // 投屏始终重新向服务端申请一组签名播放地址，不复用 VideoPlayer
    // 已经打开过的 URL。这样电视拿到的是独立的新签名链接。
    late final List<VideoQuality> castQualities;
    late final VideoQuality castQuality;
    try {
      castQualities = await widget.controller.videoQualities(widget.videoId);
      final refreshed = _matchingPartQuality(
        castQualities,
        quality,
        quality.part,
      );
      if (refreshed == null) {
        throw StateError('刷新结果缺少当前分 P');
      }
      castQuality = refreshed;
    } catch (_) {
      if (!mounted) return;
      _notice('无法获取新的投屏播放地址，请稍后重试');
      if (wasPlaying) await MfunsPlaybackCoordinator.instance.requestPlay();
      return;
    }
    if (!mounted || !identical(_player, player)) return;
    final success = await DlnaCastController.instance.cast(
      renderer: renderer,
      parts: castQualities
          .map((item) => item.part)
          .toSet()
          .map((part) => _matchingPartQuality(castQualities, castQuality, part))
          .whereType<VideoQuality>()
          .map(
            (item) => DlnaCastPart(
              part: item.part,
              url: item.url,
              duration: item.part == castQuality.part
                  ? player.value.duration
                  : Duration.zero,
            ),
          )
          .toList(growable: false),
      initialPart: castQuality.part,
      title: widget.title,
      position: player.value.position,
    );
    if (!mounted) return;
    if (!success) {
      _notice(DlnaCastController.instance.error ?? '投屏失败');
      if (wasPlaying) await MfunsPlaybackCoordinator.instance.requestPlay();
    } else {
      _notice('已投屏到 ${renderer.name}');
    }
  }

  Future<void> sendDanmakuText(String rawText) async {
    final text = rawText.trim();
    final player = _player;
    final selected = _selected;
    if (text.isEmpty || player == null || selected == null) return;
    if (widget.controller.session == null) {
      _notice('请先在“我的”页面登录后再发送弹幕');
      return;
    }
    try {
      await widget.controller.sendDanmaku(
        videoId: widget.videoId,
        part: selected.part,
        seconds: player.value.position.inMilliseconds / 1000,
        content: text,
      );
      await _loadDanmaku(selected.part);
      _notice('弹幕已发送');
    } catch (error) {
      _notice('发送失败：$error');
    }
  }

  void toggleDanmaku() {
    setState(() => _showDanmaku = !_showDanmaku);
    widget.onDanmakuChanged?.call(_showDanmaku);
  }

  Future<void> selectQuality(VideoQuality quality) => _select(quality);

  /// 解析播放源：查询是否已有与 `videoId + part + quality` 精确匹配的
  /// 已完成本地文件，存在则优先本地播放，否则使用网络直链。
  Future<PlaybackSource> _resolveSource(VideoQuality quality) async {
    final localPath = await DownloadManager.instance.localFileFor(
      videoId: widget.videoId,
      part: quality.part,
      quality: _qualityKey(quality),
    );
    return resolvePlaybackSource(
      localPath: localPath,
      networkUri: Uri.parse(quality.url),
    );
  }

  /// 清晰度标识（与下载任务去重规则一致）。
  String _qualityKey(VideoQuality quality) =>
      DownloadTask.normalizeQualityKey(_qualityDisplayLabel(quality));

  Future<_FullscreenPlayerUpdate?> _selectForFullscreen(
    VideoQuality quality,
  ) async {
    await _select(quality);
    final player = _player;
    final selected = _selected;
    if (!mounted || player == null || selected == null) return null;
    return _FullscreenPlayerUpdate(
      player: player,
      quality: selected,
      danmaku: _danmaku,
    );
  }

  void _notice(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  void _scheduleControlsHide() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _player?.value.isPlaying == true) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) {
      _scheduleControlsHide();
    }
  }

  Future<void> _openPlaybackSettings() async {
    _controlsTimer?.cancel();
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => PlayerMoreOverlay(
          presentation: PlayerMorePresentation.bottom,
          volume: _volume,
          speed: _playbackSpeed,
          onDismiss: () => Navigator.of(sheetContext).pop(),
          onVolumeChanged: (next) {
            if (mounted) setState(() => _volume = next);
            setSheetState(() {});
            _player?.setVolume(next);
          },
          onSpeedChanged: (next) {
            if (mounted) setState(() => _playbackSpeed = next);
            setSheetState(() {});
            _player?.setPlaybackSpeed(next);
          },
          defaultQuality: _qualityPreference,
          availableQualities: widget.qualities
              .map(_qualityDisplayLabel)
              .toSet()
              .toList(growable: false),
          onDefaultQualityChanged: (label) {
            if (mounted) setState(() => _qualityPreference = label);
            setSheetState(() {});
            UserPreferences.saveDefaultQuality(label);
          },
          autoPlay: _autoPlay,
          onAutoPlayChanged: (value) {
            if (mounted) setState(() => _autoPlay = value);
            setSheetState(() {});
            UserPreferences.saveAutoPlay(value);
          },
          onAppMiniPlayer: !_supportsAndroidVideoExtensions
              ? null
              : () {
                  Navigator.of(sheetContext).pop();
                  _startAppMiniPlayer();
                },
          onSystemPip: !_supportsAndroidVideoExtensions
              ? null
              : () {
                  Navigator.of(sheetContext).pop();
                  _enterSystemPip();
                },
          onCast: !_supportsAndroidVideoExtensions
              ? null
              : () {
                  Navigator.of(sheetContext).pop();
                  _startDlnaCast();
                },
        ),
      ),
    );
    if (mounted) _scheduleControlsHide();
  }

  Future<void> _loadBrightness() async {
    try {
      final value = await ScreenBrightness().application;
      if (mounted) {
        setState(() => _brightness = value.clamp(0.0, 1.0).toDouble());
      }
    } catch (_) {
      if (mounted) setState(() => _brightnessAvailable = false);
    }
  }

  void _handleVerticalSlide(
    DragUpdateDetails details,
    double width,
    double height,
  ) {
    final delta = -details.delta.dy / height;
    if (details.localPosition.dx < width / 2 && _brightnessAvailable) {
      final next = (_brightness + delta).clamp(0.0, 1.0).toDouble();
      setState(() {
        _brightness = next;
        _slideFeedback = _SlideFeedback(brightness: true, value: next);
        _controlsVisible = true;
      });
      _setBrightness(next);
    } else {
      final next = (_volume + delta).clamp(0.0, 1.0).toDouble();
      setState(() {
        _volume = next;
        _slideFeedback = _SlideFeedback(brightness: false, value: next);
        _controlsVisible = true;
      });
      _player?.setVolume(next);
    }
    _scheduleControlsHide();
  }

  Future<void> _setBrightness(double value) async {
    try {
      await ScreenBrightness().setApplicationScreenBrightness(value);
    } catch (_) {
      if (mounted) setState(() => _brightnessAvailable = false);
    }
  }

  void _clearSlideFeedback() => setState(() => _slideFeedback = null);

  Future<void> _setLongPressSpeed(bool active) async {
    if (_isLongPressSpeed == active) return;
    setState(() => _isLongPressSpeed = active);
    await _player?.setPlaybackSpeed(active ? 2 : _playbackSpeed);
  }

  Future<void> _togglePlayback() async {
    final player = _player;
    if (player == null) return;
    if (!_hasStarted) setState(() => _hasStarted = true);
    if (player.value.isPlaying) {
      await MfunsPlaybackCoordinator.instance.requestPause();
    } else {
      await MfunsPlaybackCoordinator.instance.requestPlay();
    }
    if (mounted) {
      setState(() => _controlsVisible = true);
      _scheduleControlsHide();
    }
  }

  /// 左右拖动调整进度：记录按下时的播放位置，随横向位移比例式拖动。
  void _startDragSeek(DragStartDetails details) {
    final player = _player;
    if (player == null) return;
    _dragSeekStartDx = details.globalPosition.dx;
    _dragSeekBase = player.value.position;
    setState(() => _isSeeking = true);
  }

  void _finishDragSeek() => setState(() => _isSeeking = false);

  void _updateDragSeek(DragUpdateDetails details) {
    final player = _player;
    if (player == null) return;
    final duration = player.value.duration;
    if (duration <= Duration.zero) return;
    final width = MediaQuery.sizeOf(context).width;
    final deltaDx = details.globalPosition.dx - _dragSeekStartDx;
    final target =
        _dragSeekBase +
        Duration(
          milliseconds: (deltaDx / width * duration.inMilliseconds).round(),
        );
    var clamped = target;
    if (clamped < Duration.zero) clamped = Duration.zero;
    if (clamped > duration) clamped = duration;
    player.seekTo(clamped);
    if (mounted) {
      setState(() {
        _seekNotice =
            '${_formatDuration(clamped)} / ${_formatDuration(duration)}';
        _controlsVisible = true;
      });
      _scheduleControlsHide();
    }
  }

  Future<void> _openFullscreen() async {
    final player = _player;
    if (player == null) return;
    _isFullscreen = true;
    try {
      final result = await Navigator.of(context, rootNavigator: true)
          .push<_FullscreenResult>(
            PageRouteBuilder<_FullscreenResult>(
              opaque: true,
              pageBuilder: (_, __, ___) => _FullscreenVideoOverlay(
                player: player,
                title: widget.title,
                danmaku: _danmaku,
                qualities: widget.qualities,
                selectedQuality: _selected,
                showDanmaku: _showDanmaku,
                danmakuOpacity: _danmakuOpacity,
                danmakuSize: _danmakuSize,
                defaultQuality: _qualityPreference,
                autoPlay: _autoPlay,
                volume: _volume,
                playbackSpeed: _playbackSpeed,
                onSendDanmaku: sendDanmakuText,
                onSelectQuality: _selectForFullscreen,
                onAppMiniPlayer: _supportsAndroidVideoExtensions
                    ? _startAppMiniPlayer
                    : null,
                onSystemPip: _supportsAndroidVideoExtensions
                    ? _enterSystemPip
                    : null,
                onCast: _supportsAndroidVideoExtensions ? _startDlnaCast : null,
              ),
            ),
          );
      if (!mounted) return;
      if (result != null) {
        setState(() {
          _controlsVisible = true;
          _showDanmaku = result.showDanmaku;
          _volume = result.volume;
          _playbackSpeed = result.playbackSpeed;
        });
        widget.onDanmakuChanged?.call(_showDanmaku);
        if (result.quality != null && result.quality != _selected) {
          await _select(result.quality!);
        }
      } else {
        setState(() => _controlsVisible = true);
      }
    } finally {
      _isFullscreen = false;
    }
  }

  Widget _buildPlayerSurface() {
    final player = _player;
    final selected = _selected;
    final value = player?.value;
    final duration = value?.duration ?? Duration.zero;
    final position = value?.position ?? Duration.zero;
    final visibleDanmaku = _showDanmaku
        ? _danmaku
              .where((item) {
                final delta = position - item.time;
                return delta >= Duration.zero &&
                    delta < const Duration(seconds: 4);
              })
              .take(12)
              .toList(growable: false)
        : const <DanmakuItem>[];
    final rawAspectRatio = value?.aspectRatio ?? 16 / 9;
    final aspectRatio = rawAspectRatio.isFinite && rawAspectRatio > 0
        ? rawAspectRatio
        : 16 / 9;
    final screenSize = MediaQuery.sizeOf(context);
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        late final double surfaceHeight;
        late final double videoWidth;
        late final double videoHeight;
        if (availableHeight.isFinite) {
          // 横屏分栏时播放器视口由左栏约束决定，画面只做 contain 适配。
          surfaceHeight = availableHeight;
          final surfaceAspect = constraints.maxWidth / surfaceHeight;
          videoWidth = aspectRatio >= surfaceAspect
              ? constraints.maxWidth
              : surfaceHeight * aspectRatio;
          videoHeight = aspectRatio >= surfaceAspect
              ? constraints.maxWidth / aspectRatio
              : surfaceHeight;
        } else {
          // 竖屏详情页没有纵向约束：为极宽/极高视频创建稳定的控制视口，
          // 视频画面保持原始比例并在黑色背景中居中。
          final geometry = calculatePortraitPlayerViewport(
            viewportWidth: constraints.maxWidth,
            screenHeight: screenSize.height,
            videoAspectRatio: aspectRatio,
          );
          surfaceHeight = geometry.surfaceHeight;
          videoWidth = geometry.videoWidth;
          videoHeight = geometry.videoHeight;
        }
        return ColoredBox(
          color: Colors.black,
          child: Padding(
            padding: EdgeInsets.only(top: topInset),
            child: SizedBox(
              width: double.infinity,
              height: surfaceHeight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleControls,
                onDoubleTap: _togglePlayback,
                onLongPressStart: (_) => _setLongPressSpeed(true),
                onLongPressEnd: (_) => _setLongPressSpeed(false),
                onLongPressCancel: () => _setLongPressSpeed(false),
                onHorizontalDragStart: _startDragSeek,
                onHorizontalDragUpdate: _updateDragSeek,
                onHorizontalDragEnd: (_) => _finishDragSeek(),
                onHorizontalDragCancel: _finishDragSeek,
                onVerticalDragUpdate: (details) => _handleVerticalSlide(
                  details,
                  MediaQuery.sizeOf(context).width,
                  surfaceHeight,
                ),
                onVerticalDragEnd: (_) => _clearSlideFeedback(),
                onVerticalDragCancel: _clearSlideFeedback,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Center(
                      child: SizedBox(
                        width: videoWidth,
                        height: videoHeight,
                        child: player == null
                            ? Center(
                                child: _error == null
                                    ? const CircularProgressIndicator(
                                        color: Colors.white,
                                      )
                                    : Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 24,
                                            ),
                                            child: Text(
                                              _error!,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                                height: 1.4,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 14),
                                          FilledButton.icon(
                                            style: FilledButton.styleFrom(
                                              backgroundColor: Colors.white24,
                                              foregroundColor: Colors.white,
                                            ),
                                            onPressed: selected == null
                                                ? null
                                                : () => _select(selected),
                                            icon: const Icon(
                                              Icons.refresh_rounded,
                                            ),
                                            label: const Text('点击重试'),
                                          ),
                                          const SizedBox(height: 10),
                                          TextButton.icon(
                                            style: TextButton.styleFrom(
                                              foregroundColor: Colors.white70,
                                            ),
                                            onPressed: () =>
                                                Navigator.of(context).push(
                                                  MaterialPageRoute<void>(
                                                    builder: (_) =>
                                                        const NetworkDiagnosticsPage(),
                                                  ),
                                                ),
                                            icon: const Icon(
                                              Icons.network_check_rounded,
                                              size: 18,
                                            ),
                                            label: const Text('网络诊断'),
                                          ),
                                        ],
                                      ),
                              )
                            : Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (!_hasStarted &&
                                      widget.coverUrl.isNotEmpty)
                                    Image.network(
                                      widget.coverUrl,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      height: double.infinity,
                                      errorBuilder: (_, __, ___) =>
                                          VideoPlayer(player),
                                    )
                                  else
                                    VideoPlayer(player),
                                  _DanmakuCanvas(
                                    items: visibleDanmaku,
                                    opacity: _danmakuOpacity,
                                    size: _danmakuSize,
                                  ),
                                ],
                              ),
                      ),
                    ),
                    if (player == null)
                      Positioned(
                        key: const ValueKey('video-player-fallback-header'),
                        top: 4,
                        left: 0,
                        right: 0,
                        child: Row(
                          children: [
                            IconButton(
                              color: Colors.white,
                              tooltip: '返回',
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.arrow_back_rounded),
                            ),
                            IconButton(
                              color: Colors.white,
                              tooltip: '返回首页',
                              onPressed: () => Navigator.of(
                                context,
                                rootNavigator: true,
                              ).popUntil((route) => route.isFirst),
                              icon: const Icon(Icons.home_rounded),
                            ),
                            Expanded(
                              child: Text(
                                selected == null
                                    ? widget.title
                                    : '${widget.title} · P${selected.part}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                        ),
                      ),
                    if (player != null)
                      AnimatedOpacity(
                        opacity: _controlsVisible ? 1 : 0,
                        duration: const Duration(milliseconds: 180),
                        child: IgnorePointer(
                          ignoring: !_controlsVisible,
                          child: DecoratedBox(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0x99000000),
                                  Colors.transparent,
                                  Color(0xaa000000),
                                ],
                              ),
                            ),
                            child: Stack(
                              children: [
                                Positioned(
                                  top: 4,
                                  left: 0,
                                  right: 0,
                                  child: Row(
                                    children: [
                                      IconButton(
                                        color: Colors.white,
                                        tooltip: '返回',
                                        onPressed: () =>
                                            Navigator.of(context).pop(),
                                        icon: const Icon(
                                          Icons.arrow_back_rounded,
                                        ),
                                      ),
                                      // 一键回到首页，避免连续打开多个详情页时
                                      // 需要反复返回；横竖屏内嵌播放器均显示。
                                      IconButton(
                                        color: Colors.white,
                                        tooltip: '返回首页',
                                        onPressed: () => Navigator.of(
                                          context,
                                          rootNavigator: true,
                                        ).popUntil((route) => route.isFirst),
                                        icon: const Icon(Icons.home_rounded),
                                      ),
                                      Expanded(
                                        child: Text(
                                          selected == null
                                              ? widget.title
                                              : '${widget.title} · P${selected.part}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      PopupMenuButton<VideoQuality>(
                                        tooltip: '清晰度',
                                        initialValue: selected,
                                        onSelected: _select,
                                        itemBuilder: (context) => widget
                                            .qualities
                                            .where(
                                              (quality) =>
                                                  quality.part ==
                                                  selected?.part,
                                            )
                                            .map(
                                              (quality) => PopupMenuItem(
                                                value: quality,
                                                child: Text(
                                                  _qualityDisplayLabel(quality),
                                                ),
                                              ),
                                            )
                                            .toList(),
                                        icon: const Icon(
                                          Icons.hd_rounded,
                                          color: Colors.white,
                                        ),
                                      ),
                                      IconButton(
                                        color: Colors.white,
                                        tooltip: '播放器设置',
                                        onPressed: _openPlaybackSettings,
                                        icon: const Icon(
                                          Icons.settings_rounded,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_isSeeking || player.value.isBuffering)
                                  const Center(
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                    ),
                                  ),
                                Positioned(
                                  left: 8,
                                  right: 8,
                                  bottom: 3 + bottomInset,
                                  child: Row(
                                    children: [
                                      IconButton(
                                        color: Colors.white,
                                        tooltip: player.value.isPlaying
                                            ? '暂停'
                                            : '播放',
                                        onPressed: _togglePlayback,
                                        icon: Icon(
                                          player.value.isPlaying
                                              ? Icons.pause_rounded
                                              : Icons.play_arrow_rounded,
                                        ),
                                      ),
                                      Text(
                                        _formatDuration(position),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                        ),
                                      ),
                                      Expanded(
                                        child: SliderTheme(
                                          data: SliderTheme.of(context)
                                              .copyWith(
                                                trackHeight: 2,
                                                thumbShape:
                                                    const RoundSliderThumbShape(
                                                      enabledThumbRadius: 5,
                                                    ),
                                              ),
                                          child: Slider(
                                            activeColor: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                            inactiveColor: Colors.white38,
                                            value: duration.inMilliseconds == 0
                                                ? 0
                                                : position.inMilliseconds
                                                      .clamp(
                                                        0,
                                                        duration.inMilliseconds,
                                                      )
                                                      .toDouble(),
                                            max: duration.inMilliseconds == 0
                                                ? 1
                                                : duration.inMilliseconds
                                                      .toDouble(),
                                            onChanged: (milliseconds) {
                                              player.seekTo(
                                                Duration(
                                                  milliseconds: milliseconds
                                                      .round(),
                                                ),
                                              );
                                              _scheduleControlsHide();
                                            },
                                            onChangeStart: (_) => setState(
                                              () => _isSeeking = true,
                                            ),
                                            onChangeEnd: (_) => setState(
                                              () => _isSeeking = false,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Text(
                                        _formatDuration(duration),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                        ),
                                      ),
                                      IconButton(
                                        color: Colors.white,
                                        tooltip: '全屏',
                                        onPressed: _openFullscreen,
                                        icon: const Icon(
                                          Icons.fullscreen_rounded,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (_seekNotice != null && _controlsVisible)
                      // 位于画面偏下方，避免遮挡主要内容。
                      Align(
                        alignment: const Alignment(0, 0.38),
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              child: Text(
                                _seekNotice!,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_isLongPressSpeed)
                      IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            child: Text(
                              '2.0× 倍速播放',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    if (_slideFeedback != null)
                      IgnorePointer(
                        child: _VerticalSlideFeedback(
                          feedback: _slideFeedback!,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _buildPlayerSurface();
  }

  @override
  bool get wantKeepAlive => true;
}

class _FullscreenVideoOverlay extends StatefulWidget {
  const _FullscreenVideoOverlay({
    required this.player,
    required this.title,
    required this.danmaku,
    required this.qualities,
    required this.selectedQuality,
    required this.showDanmaku,
    this.danmakuOpacity = 1,
    this.danmakuSize = 20,
    this.defaultQuality = '',
    this.autoPlay = true,
    required this.volume,
    required this.playbackSpeed,
    required this.onSendDanmaku,
    required this.onSelectQuality,
    this.onAppMiniPlayer,
    this.onSystemPip,
    this.onCast,
  });

  final VideoPlayerController player;
  final String title;
  final List<DanmakuItem> danmaku;
  final List<VideoQuality> qualities;
  final VideoQuality? selectedQuality;
  final bool showDanmaku;
  final double danmakuOpacity;
  final double danmakuSize;
  final String defaultQuality;
  final bool autoPlay;
  final double volume;
  final double playbackSpeed;
  final Future<void> Function(String text) onSendDanmaku;
  final Future<_FullscreenPlayerUpdate?> Function(VideoQuality quality)
  onSelectQuality;
  final VoidCallback? onAppMiniPlayer;
  final VoidCallback? onSystemPip;
  final VoidCallback? onCast;

  @override
  State<_FullscreenVideoOverlay> createState() =>
      _FullscreenVideoOverlayState();
}

/// 桌面端支持窗口级全屏（Windows/macOS/Linux），移动端与 Web 不适用。
final bool _isDesktop =
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

class _FullscreenVideoOverlayState extends State<_FullscreenVideoOverlay> {
  var _controlsVisible = true;
  late bool _showDanmaku;
  late double _volume;
  var _brightness = .5;
  var _brightnessAvailable = true;
  late double _playbackSpeed;
  late String _defaultQuality;
  late bool _autoPlay;
  late VideoPlayerController _player;
  late VideoQuality? _selectedQuality;
  late List<DanmakuItem> _danmaku;
  var _showOptions = false;
  var _showDanmakuComposer = false;
  var _switchingQuality = false;
  Timer? _hideTimer;
  Timer? _ticker;
  final _danmakuInput = TextEditingController();
  var _sendingDanmaku = false;
  _SlideFeedback? _slideFeedback;
  String? _seekNotice;
  double _dragSeekStartDx = 0;
  Duration _dragSeekBase = Duration.zero;
  var _isLongPressSpeed = false;
  var _isSeeking = false;
  var _isAutoAdvancingPart = false;

  @override
  void initState() {
    super.initState();
    _showDanmaku = widget.showDanmaku;
    _volume = widget.volume;
    _playbackSpeed = widget.playbackSpeed;
    _defaultQuality = widget.defaultQuality;
    _autoPlay = widget.autoPlay;
    _player = widget.player;
    _selectedQuality = widget.selectedQuality;
    _danmaku = widget.danmaku;
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    _loadBrightness();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // 桌面端（Windows/macOS/Linux）把窗口切入真全屏，移动端只旋转方向。
    if (_isDesktop) {
      windowManager.setFullScreen(true).catchError((_) {});
    }
    _scheduleHide();
    _ticker = Timer.periodic(const Duration(milliseconds: 350), (_) {
      if (mounted && _player.value.isPlaying) setState(() {});
      _checkAutoNextPart();
    });
  }

  void _close([VideoQuality? quality]) => Navigator.of(context).pop(
    _FullscreenResult(
      quality: quality,
      showDanmaku: _showDanmaku,
      volume: _volume,
      playbackSpeed: _playbackSpeed,
    ),
  );

  @override
  void dispose() {
    _hideTimer?.cancel();
    _ticker?.cancel();
    _danmakuInput.dispose();
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    if (_isDesktop) {
      windowManager.setFullScreen(false).catchError((_) {});
    }
    super.dispose();
  }

  Future<void> _sendDanmaku() async {
    final text = _danmakuInput.text.trim();
    if (text.isEmpty || _sendingDanmaku) return;
    setState(() => _sendingDanmaku = true);
    await widget.onSendDanmaku(text);
    if (mounted) {
      _danmakuInput.clear();
      setState(() => _sendingDanmaku = false);
    }
  }

  Future<void> _selectQuality(VideoQuality quality) async {
    if (_switchingQuality || quality == _selectedQuality) return;
    setState(() => _switchingQuality = true);
    // Detach the old VideoPlayerController from the fullscreen widget tree
    // before the portrait player disposes and replaces it.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final update = await widget.onSelectQuality(quality);
    if (!mounted) return;
    if (update == null) {
      setState(() => _switchingQuality = false);
      return;
    }
    setState(() {
      _player = update.player;
      _selectedQuality = update.quality;
      _danmaku = update.danmaku;
      _switchingQuality = false;
      _showOptions = false;
      _controlsVisible = true;
    });
    _scheduleHide();
  }

  void _queueQualitySelect(VideoQuality quality) {
    // PopupMenu is still removing its inherited route while onSelected runs.
    // Deferring avoids changing the fullscreen subtree during that teardown.
    Future<void>.delayed(Duration.zero, () {
      if (mounted) _selectQuality(quality);
    });
  }

  /// 当前分P播放结束后自动连播下一分P（全屏层自己替换共享控制器）。
  Future<void> _checkAutoNextPart() async {
    if (_switchingQuality || _isAutoAdvancingPart) return;
    // App 在后台时不创建新播放器（音频已交接给后台引擎）。
    if (MfunsPlaybackCoordinator.instance.phase.isBackground) return;
    final value = _player.value;
    if (value.duration <= Duration.zero) return;
    if (value.isPlaying) return;
    if (!value.isCompleted && value.position < value.duration) return;
    final selected = _selectedQuality;
    if (selected == null) return;
    final next = _matchingPartQuality(
      widget.qualities,
      selected,
      selected.part + 1,
    );
    if (next == null) return;
    _isAutoAdvancingPart = true;
    try {
      await _selectQuality(next);
      if (mounted && !_player.value.isPlaying) {
        await MfunsPlaybackCoordinator.instance.requestPlay();
      }
    } finally {
      _isAutoAdvancingPart = false;
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted &&
          _player.value.isPlaying &&
          !_showOptions &&
          !_showDanmakuComposer &&
          !_isSeeking) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _showControls({bool restartTimer = true}) {
    if (!_controlsVisible && mounted) {
      setState(() => _controlsVisible = true);
    }
    if (restartTimer) _scheduleHide();
  }

  void _toggleControls() {
    setState(() {
      _controlsVisible = !_controlsVisible;
      if (!_controlsVisible) {
        _showOptions = false;
        _showDanmakuComposer = false;
      }
    });
    if (_controlsVisible) _scheduleHide();
  }

  void _toggleOptions() {
    final opening = !_showOptions;
    setState(() {
      _showDanmakuComposer = false;
      _showOptions = opening;
      _controlsVisible = true;
    });
    if (opening) {
      _hideTimer?.cancel();
    } else {
      _scheduleHide();
    }
  }

  void _toggleDanmakuComposer() {
    final opening = !_showDanmakuComposer;
    setState(() {
      _showOptions = false;
      _showDanmakuComposer = opening;
      _controlsVisible = true;
    });
    if (opening) {
      _hideTimer?.cancel();
    } else {
      _scheduleHide();
    }
  }

  Future<void> _togglePlayback() async {
    if (_player.value.isPlaying) {
      await MfunsPlaybackCoordinator.instance.requestPause();
    } else {
      await MfunsPlaybackCoordinator.instance.requestPlay();
    }
    if (mounted) _showControls();
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (_showOptions || _showDanmakuComposer) {
        setState(() {
          _showOptions = false;
          _showDanmakuComposer = false;
        });
        _scheduleHide();
      } else {
        _close();
      }
      return true;
    }
    // 输入弹幕时保留空格、方向键和字母键的文本编辑语义。
    if (_showDanmakuComposer) return false;
    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      if (event is KeyDownEvent) _togglePlayback();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _seekBy(-10);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _seekBy(10);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _changeVolume(.05);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _changeVolume(-.05);
    } else if (key == LogicalKeyboardKey.keyM) {
      if (event is KeyDownEvent) {
        _setVolume(_volume == 0 ? .7 : 0);
      }
    } else {
      return false;
    }
    return true;
  }

  Future<void> _changeVolume(double delta) => _setVolume(_volume + delta);

  Future<void> _setVolume(double value) async {
    final next = value.clamp(0.0, 1.0).toDouble();
    setState(() {
      _volume = next;
      _controlsVisible = true;
      _slideFeedback = _SlideFeedback(brightness: false, value: next);
    });
    await _player.setVolume(next);
    _scheduleHide();
  }

  Future<void> _loadBrightness() async {
    try {
      final value = await ScreenBrightness().application;
      if (mounted) {
        setState(() => _brightness = value.clamp(0.0, 1.0).toDouble());
      }
    } catch (_) {
      if (mounted) setState(() => _brightnessAvailable = false);
    }
  }

  void _handleVerticalSlide(
    DragUpdateDetails details,
    double width,
    double height,
  ) {
    final delta = -details.delta.dy / height;
    if (details.localPosition.dx < width / 2 && _brightnessAvailable) {
      final next = (_brightness + delta).clamp(0.0, 1.0).toDouble();
      setState(() {
        _brightness = next;
        _slideFeedback = _SlideFeedback(brightness: true, value: next);
        _controlsVisible = true;
      });
      _setBrightness(next);
    } else {
      final next = (_volume + delta).clamp(0.0, 1.0).toDouble();
      setState(() {
        _volume = next;
        _slideFeedback = _SlideFeedback(brightness: false, value: next);
        _controlsVisible = true;
      });
      _player.setVolume(next);
    }
    _scheduleHide();
  }

  Future<void> _setBrightness(double value) async {
    try {
      await ScreenBrightness().setApplicationScreenBrightness(value);
    } catch (_) {
      if (mounted) setState(() => _brightnessAvailable = false);
    }
  }

  void _clearSlideFeedback() => setState(() => _slideFeedback = null);

  Future<void> _setLongPressSpeed(bool active) async {
    if (_isLongPressSpeed == active) return;
    setState(() => _isLongPressSpeed = active);
    await _player.setPlaybackSpeed(active ? 2 : _playbackSpeed);
  }

  Future<void> _seekBy(int seconds) async {
    var target = _player.value.position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (target > _player.value.duration) {
      target = _player.value.duration;
    }
    await _player.seekTo(target);
    if (mounted) {
      setState(() {
        _controlsVisible = true;
        _seekNotice = '${seconds > 0 ? '+' : ''}$seconds 秒';
      });
      _scheduleHide();
    }
  }

  /// 左右拖动调整进度：记录按下时的播放位置，随横向位移比例式拖动。
  void _startDragSeek(DragStartDetails details) {
    _dragSeekStartDx = details.globalPosition.dx;
    _dragSeekBase = _player.value.position;
    setState(() => _isSeeking = true);
  }

  void _finishDragSeek() => setState(() => _isSeeking = false);

  void _updateDragSeek(DragUpdateDetails details) {
    final duration = _player.value.duration;
    if (duration <= Duration.zero) return;
    final width = MediaQuery.sizeOf(context).width;
    final deltaDx = details.globalPosition.dx - _dragSeekStartDx;
    final target =
        _dragSeekBase +
        Duration(
          milliseconds: (deltaDx / width * duration.inMilliseconds).round(),
        );
    var clamped = target;
    if (clamped < Duration.zero) clamped = Duration.zero;
    if (clamped > duration) clamped = duration;
    _player.seekTo(clamped);
    if (mounted) {
      setState(() {
        _seekNotice =
            '${_formatDuration(clamped)} / ${_formatDuration(duration)}';
        _controlsVisible = true;
      });
      _scheduleHide();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleControls,
      onDoubleTap: _togglePlayback,
      onLongPressStart: (_) => _setLongPressSpeed(true),
      onLongPressEnd: (_) => _setLongPressSpeed(false),
      onLongPressCancel: () => _setLongPressSpeed(false),
      onHorizontalDragStart: _startDragSeek,
      onHorizontalDragUpdate: _updateDragSeek,
      onHorizontalDragEnd: (_) => _finishDragSeek(),
      onHorizontalDragCancel: _finishDragSeek,
      onVerticalDragUpdate: (details) => _handleVerticalSlide(
        details,
        MediaQuery.sizeOf(context).width,
        MediaQuery.sizeOf(context).height,
      ),
      onVerticalDragEnd: (_) => _clearSlideFeedback(),
      onVerticalDragCancel: _clearSlideFeedback,
      child: _switchingQuality
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: _player,
              builder: (context, value, _) {
                final duration = value.duration;
                final position = value.position;
                final danmaku = !_showDanmaku
                    ? const <DanmakuItem>[]
                    : _danmaku
                          .where((item) {
                            final delta = position - item.time;
                            return delta >= Duration.zero &&
                                delta < const Duration(seconds: 4);
                          })
                          .take(12)
                          .toList(growable: false);
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Center(
                      child: AspectRatio(
                        aspectRatio: value.aspectRatio == 0
                            ? 16 / 9
                            : value.aspectRatio,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            VideoPlayer(_player),
                            _DanmakuCanvas(
                              items: danmaku,
                              opacity: widget.danmakuOpacity,
                              size: widget.danmakuSize,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_controlsVisible)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0x99000000),
                                Colors.transparent,
                                Color(0xaa000000),
                              ],
                            ),
                          ),
                          child: Stack(
                            children: [
                              Positioned(
                                top: 8,
                                left: 8,
                                right: 8,
                                child: SafeArea(
                                  bottom: false,
                                  child: Row(
                                    children: [
                                      IconButton(
                                        color: Colors.white,
                                        tooltip: '退出全屏',
                                        icon: const Icon(
                                          Icons.arrow_back_rounded,
                                        ),
                                        onPressed: _close,
                                      ),
                                      Expanded(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              widget.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 15,
                                              ),
                                            ),
                                            Text(
                                              'P${_selectedQuality?.part ?? 1} · ${_selectedQuality == null ? '默认' : _qualityDisplayLabel(_selectedQuality!)}',
                                              maxLines: 1,
                                              style: const TextStyle(
                                                color: Colors.white60,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        color: Colors.white,
                                        tooltip: _showDanmaku ? '关闭弹幕' : '打开弹幕',
                                        onPressed: () => setState(
                                          () => _showDanmaku = !_showDanmaku,
                                        ),
                                        icon: Icon(
                                          _showDanmaku
                                              ? Icons.subtitles_rounded
                                              : Icons.subtitles_off_rounded,
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: _toggleDanmakuComposer,
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                        ),
                                        child: Text(
                                          _showDanmakuComposer ? '收起' : '发弹幕',
                                        ),
                                      ),
                                      if (widget.qualities
                                              .map((quality) => quality.part)
                                              .toSet()
                                              .length >
                                          1)
                                        PopupMenuButton<int>(
                                          tooltip: '分 P',
                                          initialValue: _selectedQuality?.part,
                                          onSelected: (part) {
                                            final next = _matchingPartQuality(
                                              widget.qualities,
                                              _selectedQuality,
                                              part,
                                            );
                                            if (next != null) {
                                              _queueQualitySelect(next);
                                            }
                                          },
                                          itemBuilder: (context) {
                                            final parts =
                                                widget.qualities
                                                    .map(
                                                      (quality) => quality.part,
                                                    )
                                                    .toSet()
                                                    .toList()
                                                  ..sort();
                                            return parts
                                                .map(
                                                  (part) => PopupMenuItem(
                                                    value: part,
                                                    child: Text('P$part'),
                                                  ),
                                                )
                                                .toList();
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 9,
                                              vertical: 8,
                                            ),
                                            child: Text(
                                              'P${_selectedQuality?.part ?? 1}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ),
                                      PopupMenuButton<VideoQuality>(
                                        tooltip: '清晰度',
                                        initialValue: _selectedQuality,
                                        onSelected: _queueQualitySelect,
                                        itemBuilder: (context) => widget
                                            .qualities
                                            .where(
                                              (quality) =>
                                                  quality.part ==
                                                  _selectedQuality?.part,
                                            )
                                            .map(
                                              (quality) => PopupMenuItem(
                                                value: quality,
                                                child: Text(
                                                  _qualityDisplayLabel(quality),
                                                ),
                                              ),
                                            )
                                            .toList(),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 9,
                                            vertical: 8,
                                          ),
                                          child: Text(
                                            _selectedQuality == null
                                                ? '默认'
                                                : _qualityDisplayLabel(
                                                    _selectedQuality!,
                                                  ),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        color: Colors.white,
                                        tooltip: '播放器设置',
                                        onPressed: _toggleOptions,
                                        icon: const Icon(
                                          Icons.settings_rounded,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (_showDanmakuComposer)
                                Positioned(
                                  top: 58,
                                  right: 16,
                                  child: SizedBox(
                                    width: 320,
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: _danmakuInput,
                                            autofocus: true,
                                            maxLength: 100,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                            ),
                                            onSubmitted: (_) => _sendDanmaku(),
                                            decoration: const InputDecoration(
                                              isDense: true,
                                              counterText: '',
                                              hintText: '发个弹幕…',
                                              hintStyle: TextStyle(
                                                color: Colors.white54,
                                              ),
                                              fillColor: Color(0xaa202025),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 7),
                                        FilledButton(
                                          onPressed: _sendingDanmaku
                                              ? null
                                              : _sendDanmaku,
                                          child: _sendingDanmaku
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white,
                                                      ),
                                                )
                                              : const Text('发送'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              if (_isSeeking || value.isBuffering)
                                const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                  ),
                                ),
                              Positioned(
                                left: 12,
                                right: 12,
                                bottom: 4,
                                child: SafeArea(
                                  top: false,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          trackHeight: 3,
                                          thumbShape:
                                              const RoundSliderThumbShape(
                                                enabledThumbRadius: 6,
                                              ),
                                          overlayShape:
                                              const RoundSliderOverlayShape(
                                                overlayRadius: 15,
                                              ),
                                        ),
                                        child: Slider(
                                          activeColor: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                          inactiveColor: Colors.white30,
                                          value: duration.inMilliseconds == 0
                                              ? 0
                                              : position.inMilliseconds
                                                    .clamp(
                                                      0,
                                                      duration.inMilliseconds,
                                                    )
                                                    .toDouble(),
                                          max: duration.inMilliseconds == 0
                                              ? 1
                                              : duration.inMilliseconds
                                                    .toDouble(),
                                          onChanged: (milliseconds) {
                                            _player.seekTo(
                                              Duration(
                                                milliseconds: milliseconds
                                                    .round(),
                                              ),
                                            );
                                          },
                                          onChangeStart: (_) {
                                            _hideTimer?.cancel();
                                            setState(() => _isSeeking = true);
                                          },
                                          onChangeEnd: (_) {
                                            setState(() => _isSeeking = false);
                                            _scheduleHide();
                                          },
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          IconButton(
                                            color: Colors.white,
                                            tooltip: value.isPlaying
                                                ? '暂停（空格）'
                                                : '播放（空格）',
                                            onPressed: _togglePlayback,
                                            icon: Icon(
                                              value.isPlaying
                                                  ? Icons.pause_rounded
                                                  : Icons.play_arrow_rounded,
                                            ),
                                          ),
                                          IconButton(
                                            color: Colors.white,
                                            tooltip: '后退 10 秒（←）',
                                            onPressed: () => _seekBy(-10),
                                            icon: const Icon(
                                              Icons.replay_10_rounded,
                                            ),
                                          ),
                                          IconButton(
                                            color: Colors.white,
                                            tooltip: '前进 10 秒（→）',
                                            onPressed: () => _seekBy(10),
                                            icon: const Icon(
                                              Icons.forward_10_rounded,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${_formatDuration(position)} / ${_formatDuration(duration)}',
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const Spacer(),
                                          PopupMenuButton<double>(
                                            tooltip: '播放速度',
                                            initialValue: _playbackSpeed,
                                            onSelected: (next) async {
                                              setState(
                                                () => _playbackSpeed = next,
                                              );
                                              await _player.setPlaybackSpeed(
                                                next,
                                              );
                                              _scheduleHide();
                                            },
                                            itemBuilder: (context) => [
                                              for (final speed in [
                                                .5,
                                                .75,
                                                1.0,
                                                1.25,
                                                1.5,
                                                2.0,
                                              ])
                                                PopupMenuItem(
                                                  value: speed,
                                                  child: Text('${speed}x'),
                                                ),
                                            ],
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 8,
                                                  ),
                                              child: Text(
                                                '${_playbackSpeed}x',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            color: Colors.white,
                                            tooltip: '退出全屏（Esc）',
                                            icon: const Icon(
                                              Icons.fullscreen_exit_rounded,
                                            ),
                                            onPressed: _close,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_slideFeedback != null)
                      IgnorePointer(
                        child: _VerticalSlideFeedback(
                          feedback: _slideFeedback!,
                        ),
                      ),
                    if (_seekNotice != null && _controlsVisible)
                      // 位于画面偏下方，避免遮挡主要内容。
                      Align(
                        alignment: const Alignment(0, 0.38),
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              child: Text(
                                _seekNotice!,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_isLongPressSpeed)
                      IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            child: Text(
                              '2.0× 倍速播放',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    if (_showOptions && !_showDanmakuComposer)
                      Positioned.fill(
                        child: PlayerMoreOverlay(
                          volume: _volume,
                          speed: _playbackSpeed,
                          onDismiss: _toggleOptions,
                          onVolumeChanged: _setVolume,
                          onSpeedChanged: (next) async {
                            setState(() => _playbackSpeed = next);
                            await _player.setPlaybackSpeed(next);
                          },
                          defaultQuality: _defaultQuality,
                          availableQualities: widget.qualities
                              .map(_qualityDisplayLabel)
                              .toSet()
                              .toList(growable: false),
                          onDefaultQualityChanged: (label) {
                            setState(() => _defaultQuality = label);
                            UserPreferences.saveDefaultQuality(label);
                          },
                          autoPlay: _autoPlay,
                          onAutoPlayChanged: (value) {
                            setState(() => _autoPlay = value);
                            UserPreferences.saveAutoPlay(value);
                          },
                          onAppMiniPlayer: widget.onAppMiniPlayer,
                          onSystemPip: widget.onSystemPip,
                          onCast: widget.onCast,
                        ),
                      ),
                  ],
                );
              },
            ),
    ),
  );
}

class _FullscreenResult {
  const _FullscreenResult({
    required this.quality,
    required this.showDanmaku,
    required this.volume,
    required this.playbackSpeed,
  });

  final VideoQuality? quality;
  final bool showDanmaku;
  final double volume;
  final double playbackSpeed;
}

class _SlideFeedback {
  const _SlideFeedback({required this.brightness, required this.value});

  final bool brightness;
  final double value;
}

class _VerticalSlideFeedback extends StatelessWidget {
  const _VerticalSlideFeedback({required this.feedback});

  final _SlideFeedback feedback;

  @override
  Widget build(BuildContext context) => Center(
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              feedback.brightness
                  ? Icons.brightness_6_rounded
                  : feedback.value == 0
                  ? Icons.volume_off_rounded
                  : Icons.volume_up_rounded,
              color: Colors.white,
              size: 28,
            ),
            const SizedBox(height: 7),
            Text(
              '${feedback.brightness ? '亮度' : '音量'} ${(feedback.value * 100).round()}%',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _FullscreenPlayerUpdate {
  const _FullscreenPlayerUpdate({
    required this.player,
    required this.quality,
    required this.danmaku,
  });

  final VideoPlayerController player;
  final VideoQuality quality;
  final List<DanmakuItem> danmaku;
}

VideoQuality? _matchingPartQuality(
  List<VideoQuality> qualities,
  VideoQuality? current,
  int part,
) {
  final choices = qualities.where((quality) => quality.part == part).toList();
  if (choices.isEmpty) return null;
  final sameQuality = choices.where(
    (quality) =>
        quality.name == current?.name && quality.label == current?.label,
  );
  return sameQuality.isEmpty ? choices.first : sameQuality.first;
}

String _qualityDisplayLabel(VideoQuality quality) {
  final source = '${quality.name} ${quality.label}';
  final match = RegExp(r'(?<!\d)(\d{3,4})\s*[pP]?(?!\d)').firstMatch(source);
  if (match != null) return '${match.group(1)}p';
  if (quality.name.isNotEmpty) return quality.name;
  if (quality.label.isNotEmpty) return quality.label;
  return '默认';
}

/// 滚动弹幕画布：每条弹幕用独立 AnimationController 从右向左平滑划过
/// 全屏宽度，多轨道并行；动画不依赖父级 350ms 的定时重建，避免卡顿。
class _DanmakuCanvas extends StatefulWidget {
  const _DanmakuCanvas({required this.items, this.opacity = 1, this.size = 20});

  final List<DanmakuItem> items;
  final double opacity;
  final double size;

  @override
  State<_DanmakuCanvas> createState() => _DanmakuCanvasState();
}

class _DanmakuEntry {
  _DanmakuEntry({
    required this.item,
    required this.controller,
    required this.textWidth,
    required this.lane,
  });

  final DanmakuItem item;
  final AnimationController controller;
  final double textWidth;
  final int lane;
}

class _DanmakuCanvasState extends State<_DanmakuCanvas>
    with TickerProviderStateMixin {
  static const _lanes = 6;
  static const _laneHeight = 30.0;
  static const _pixelsPerSecond = 140.0;

  final List<_DanmakuEntry> _entries = [];

  String _key(DanmakuItem item) =>
      '${item.time.inMilliseconds}-${item.type}-${item.content}';

  @override
  void didUpdateWidget(_DanmakuCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 清除已播完的弹幕。
    _entries.removeWhere((entry) => !entry.controller.isAnimating);
    // 新出现的弹幕逐条入轨。
    final active = _entries.map((entry) => _key(entry.item)).toSet();
    for (final item in widget.items) {
      if (!active.contains(_key(item))) {
        _addEntry(item);
      }
    }
    if (_entries.isEmpty) return;
    setState(() {});
  }

  void _addEntry(DanmakuItem item) {
    final isFixed = item.type == 4 || item.type == 5;
    final textWidth = item.content.length * widget.size * 1.05;
    final duration = isFixed
        ? const Duration(milliseconds: 4000)
        : Duration(
            milliseconds: ((textWidth + 400) / _pixelsPerSecond * 1000).round(),
          );
    final controller = AnimationController(vsync: this, duration: duration);
    final entry = _DanmakuEntry(
      item: item,
      controller: controller,
      textWidth: textWidth,
      lane: _nextLane(),
    );
    _entries.add(entry);
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _entries.remove(entry));
      }
    });
    controller.forward();
  }

  /// 选择当前最空闲的轨道（该轨道上最靠前的弹幕进度最大）。
  int _nextLane() {
    var bestLane = 0;
    var bestProgress = -1.0;
    for (var lane = 0; lane < _lanes; lane++) {
      var laneProgress = 1.0;
      for (final entry in _entries) {
        if (entry.lane == lane && entry.controller.value < laneProgress) {
          laneProgress = entry.controller.value;
        }
      }
      if (laneProgress > bestProgress) {
        bestProgress = laneProgress;
        bestLane = lane;
      }
    }
    return bestLane;
  }

  @override
  void dispose() {
    for (final entry in _entries) {
      entry.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_entries.isEmpty) return const SizedBox.shrink();
    // 置顶（type 5）与底部（type 4）固定弹幕渲染在滚动弹幕之上，且同一
    // 时间段的多条固定弹幕纵向并排，互不重叠。
    final scrollEntries = _entries
        .where((e) => e.item.type != 4 && e.item.type != 5)
        .toList();
    final topEntries = _entries
        .where((e) => e.item.type == 5)
        .toList(growable: false);
    final bottomEntries = _entries
        .where((e) => e.item.type == 4)
        .toList(growable: false);

    Widget textOf(_DanmakuEntry entry) {
      final item = entry.item;
      final color = Color(
        0xff000000 | (item.color & 0xffffff),
      ).withOpacity(widget.opacity);
      return Text(
        item.content,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: TextStyle(
          color: color,
          fontSize: (item.size.clamp(16, 36)) * (widget.size / 20),
          shadows: const [Shadow(color: Colors.black, blurRadius: 2)],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        return IgnorePointer(
          child: ClipRect(
            child: Stack(
              children: [
                // 底层：滚动弹幕，从右侧进入，横贯整个播放区。
                for (final entry in scrollEntries)
                  AnimatedBuilder(
                    animation: entry.controller,
                    builder: (context, _) => Positioned(
                      top: 8.0 + entry.lane * _laneHeight,
                      left:
                          screenWidth -
                          entry.controller.value *
                              (screenWidth + entry.textWidth),
                      child: textOf(entry),
                    ),
                  ),
                // 顶层：置顶弹幕，从上往下纵向并排。
                for (var i = 0; i < topEntries.length; i++)
                  AnimatedBuilder(
                    animation: topEntries[i].controller,
                    builder: (context, _) => Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: EdgeInsets.only(top: 8.0 + i * _laneHeight),
                        child: textOf(topEntries[i]),
                      ),
                    ),
                  ),
                // 顶层：底部弹幕，从下往上纵向并排。
                for (var i = 0; i < bottomEntries.length; i++)
                  AnimatedBuilder(
                    animation: bottomEntries[i].controller,
                    builder: (context, _) => Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: EdgeInsets.only(bottom: 8.0 + i * _laneHeight),
                        child: textOf(bottomEntries[i]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 打开 @ 用户搜索弹窗，选择用户后返回带 id 的 mention span；取消返回 null。
Future<CommentSpan?> _askMentionUser(
  BuildContext context,
  AppController controller,
) => showDialog<CommentSpan>(
  context: context,
  builder: (_) => _MentionUserDialog(controller: controller),
);

class _MentionUserDialog extends StatefulWidget {
  const _MentionUserDialog({required this.controller});

  final AppController controller;

  @override
  State<_MentionUserDialog> createState() => _MentionUserDialogState();
}

class _MentionUserDialogState extends State<_MentionUserDialog> {
  final _search = TextEditingController();
  final _results = <UserProfile>[];
  Timer? _debounce;
  var _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _runSearch(String keyword) async {
    final text = keyword.trim();
    if (text.isEmpty) {
      setState(() {
        _results.clear();
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await widget.controller.searchUsers(text);
      if (!mounted) return;
      setState(() {
        _results
          ..clear()
          ..addAll(users);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _results.clear();
        _loading = false;
        _error = '搜索失败：$error';
      });
    }
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _runSearch(value),
    );
  }

  void _pick(UserProfile user) =>
      Navigator.of(context).pop(CommentSpan.mention('${user.id}', user.name));

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('@ 用户'),
    content: SizedBox(
      width: 340,
      height: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _search,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '搜索用户名',
              prefixIcon: Icon(Icons.search_rounded),
              isDense: true,
            ),
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: _runSearch,
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildResults()),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
    ],
  );

  Widget _buildResults() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!, textAlign: TextAlign.center));
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(_search.text.trim().isEmpty ? '输入用户名开始搜索' : '没有找到相关用户'),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final user = _results[index];
        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.primary.withOpacity(.12),
            foregroundImage: user.avatar.isEmpty
                ? null
                : NetworkImage(user.avatar),
            foregroundColor: Theme.of(context).colorScheme.primary,
            child: Text(user.name.isEmpty ? 'U' : user.name[0]),
          ),
          title: Text(user.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => _pick(user),
        );
      },
    );
  }
}

class _CommentSection extends StatefulWidget {
  const _CommentSection({
    super.key,
    required this.controller,
    required this.areaId,
    this.canPin = false,
  });

  final AppController controller;
  final int areaId;
  final bool canPin;

  @override
  State<_CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends State<_CommentSection> {
  late Future<CommunityCommentPage> _comments;

  @override
  void initState() {
    super.initState();
    _comments = widget.controller.commentPage(widget.areaId);
  }

  void reload() =>
      setState(() => _comments = widget.controller.commentPage(widget.areaId));

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Text('评论区', style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          IconButton(
            tooltip: '刷新评论',
            onPressed: reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      FutureBuilder<CommunityCommentPage>(
        future: _comments,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _InlineLoading(label: '正在加载评论');
          }
          if (snapshot.hasError) {
            return Text('评论加载失败：${snapshot.error}');
          }
          final page =
              snapshot.data ??
              const CommunityCommentPage(comments: <CommunityComment>[]);
          final comments = page.displayComments;
          if (comments.isEmpty) return const Text('暂无评论，来抢沙发吧');
          return Column(
            children: comments
                .map(
                  (comment) => _CommentCard(
                    controller: widget.controller,
                    comment: comment,
                    onDeleted: reload,
                    canPin: widget.canPin,
                    onPinned: reload,
                    isPinned: comment.id == page.pinnedCommentId,
                  ),
                )
                .toList(),
          );
        },
      ),
    ],
  );
}

/// 固定在详情页底部的评论编辑器，与可滚动的评论列表分离。
class CommentComposerBar extends StatefulWidget {
  const CommentComposerBar({
    super.key,
    required this.controller,
    required this.areaId,
    required this.collapsed,
    this.visible = true,
    required this.onExpand,
    required this.onSubmitted,
  });

  final AppController controller;
  final int areaId;
  final bool collapsed;
  final bool visible;
  final VoidCallback onExpand;
  final VoidCallback onSubmitted;

  @override
  State<CommentComposerBar> createState() => CommentComposerBarState();
}

class CommentComposerBarState extends State<CommentComposerBar>
    with RouteAware {
  final _inputKey = GlobalKey<InlineEmojiInputState>();
  var _isSending = false;
  var _isInputFocused = false;
  ModalRoute<dynamic>? _route;

  void _publishFabVisibility() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      commentComposerFabVisibility.update(
        this,
        visible:
            widget.visible && widget.collapsed && (_route?.isCurrent ?? true),
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route) {
      if (_route != null) appRouteObserver.unsubscribe(this);
      _route = route;
      if (route != null) appRouteObserver.subscribe(this, route);
    }
    _publishFabVisibility();
  }

  @override
  void didUpdateWidget(CommentComposerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible ||
        oldWidget.collapsed != widget.collapsed) {
      _publishFabVisibility();
    }
  }

  @override
  void didPushNext() => _publishFabVisibility();

  @override
  void didPopNext() => _publishFabVisibility();

  @override
  void dispose() {
    if (_route != null) appRouteObserver.unsubscribe(this);
    commentComposerFabVisibility.update(this, visible: false);
    super.dispose();
  }

  void focusInput() => _inputKey.currentState?.requestFocus();

  Future<void> _pickMention() async {
    final mention = await _askMentionUser(context, widget.controller);
    if (mention == null) return;
    _inputKey.currentState?.addMention(
      mention.mentionName,
      id: mention.mentionId,
    );
  }

  Future<void> _submit() async {
    final input = _inputKey.currentState;
    if (input == null || input.isEmpty || _isSending) return;
    if (widget.controller.session == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先在“我的”页面登录后再发表评论')));
      return;
    }
    final spans = input.spans;
    final images = input.images;
    setState(() => _isSending = true);
    try {
      await widget.controller.createComment(
        areaId: widget.areaId,
        spans: spans,
        images: images,
      );
      input.clear();
      widget.onSubmitted();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('评论已发布')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('发布失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final input = Focus(
      onFocusChange: (focused) {
        if (focused == _isInputFocused) return;
        setState(() => _isInputFocused = focused);
      },
      child: InlineEmojiInput(
        key: _inputKey,
        hintText: '说点什么…',
        onUploadImage: widget.controller.uploadImage,
        onSearchUser: widget.controller.searchUsers,
      ),
    );
    Widget imageButton() => IconButton(
      tooltip: '添加图片',
      onPressed: () => _inputKey.currentState?.pickImage(),
      icon: Icon(Icons.image_outlined, color: primary),
    );
    Widget mentionButton() => IconButton(
      tooltip: '@ 用户',
      onPressed: _pickMention,
      icon: Icon(Icons.alternate_email, color: primary),
    );
    Widget emojiButton() => IconButton(
      tooltip: '表情包',
      onPressed: () => _inputKey.currentState?.pickEmoji(),
      icon: Icon(Icons.emoji_emotions_outlined, color: primary),
    );
    Widget sendButton() => SizedBox.square(
      dimension: 56,
      child: Center(
        child: IconButton.filled(
          key: const ValueKey('comment-composer-send'),
          style: IconButton.styleFrom(
            fixedSize: const Size.square(48),
            padding: EdgeInsets.zero,
            alignment: Alignment.center,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          tooltip: widget.collapsed ? '展开评论输入框' : '发布评论',
          onPressed: widget.collapsed
              ? widget.onExpand
              : (_isSending ? null : _submit),
          icon: _isSending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_rounded),
        ),
      ),
    );
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: LayoutBuilder(
        builder: (context, outerConstraints) {
          final expandedWidth = outerConstraints.maxWidth > 760
              ? 760.0
              : outerConstraints.maxWidth;
          return TweenAnimationBuilder<double>(
            key: const ValueKey('comment-composer-surface'),
            tween: Tween<double>(end: widget.collapsed ? 0 : 1),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            builder: (context, progress, child) => CustomPaint(
              painter: _CommentComposerSurfacePainter(
                progress: progress,
                expandedWidth: expandedWidth,
                fillColor: colors.surface,
                borderColor: colors.outlineVariant.withAlpha(179),
              ),
              child: ClipPath(
                key: const ValueKey('comment-composer-clip'),
                clipper: _CommentComposerSurfaceClipper(
                  progress: progress,
                  expandedWidth: expandedWidth,
                ),
                child: child,
              ),
            ),
            child: AnimatedAlign(
              alignment: widget.collapsed
                  ? Alignment.bottomRight
                  : Alignment.bottomCenter,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              child: SizedBox(
                width: expandedWidth,
                child: Material(
                  color: Colors.transparent,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth < 440) {
                          return AnimatedSize(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.bottomCenter,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Expanded(child: input),
                                    const SizedBox(width: 6),
                                    sendButton(),
                                  ],
                                ),
                                if (_isInputFocused && !widget.collapsed)
                                  Row(
                                    children: [
                                      imageButton(),
                                      mentionButton(),
                                      emojiButton(),
                                    ],
                                  ),
                              ],
                            ),
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            imageButton(),
                            mentionButton(),
                            emojiButton(),
                            Expanded(child: input),
                            const SizedBox(width: 6),
                            sendButton(),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

Path _commentComposerPath(Size size, double progress, double expandedWidth) {
  final width = 56 + (expandedWidth - 56) * progress;
  final expandedLeft = (size.width - expandedWidth) / 2;
  final left =
      (size.width - 56) + (expandedLeft - (size.width - 56)) * progress;
  final height = 56 + (size.height - 56) * progress;
  final top = size.height - height;
  final radius = 28 + (18 - 28) * progress;
  return Path()..addRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, width, height),
      Radius.circular(radius),
    ),
  );
}

class _CommentComposerSurfaceClipper extends CustomClipper<Path> {
  const _CommentComposerSurfaceClipper({
    required this.progress,
    required this.expandedWidth,
  });

  final double progress;
  final double expandedWidth;

  @override
  Path getClip(Size size) =>
      _commentComposerPath(size, progress, expandedWidth);

  @override
  bool shouldReclip(_CommentComposerSurfaceClipper oldClipper) =>
      progress != oldClipper.progress ||
      expandedWidth != oldClipper.expandedWidth;
}

class _CommentComposerSurfacePainter extends CustomPainter {
  const _CommentComposerSurfacePainter({
    required this.progress,
    required this.expandedWidth,
    required this.fillColor,
    required this.borderColor,
  });

  final double progress;
  final double expandedWidth;
  final Color fillColor;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _commentComposerPath(size, progress, expandedWidth);
    canvas.drawShadow(path, Colors.black38, 8, true);
    canvas.drawPath(path, Paint()..color = fillColor);
    canvas.drawPath(
      path,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_CommentComposerSurfacePainter oldDelegate) =>
      progress != oldDelegate.progress ||
      expandedWidth != oldDelegate.expandedWidth ||
      fillColor != oldDelegate.fillColor ||
      borderColor != oldDelegate.borderColor;
}

class _CommentSpans extends StatelessWidget {
  const _CommentSpans({required this.spans, required this.onLinkTap});

  final List<CommentSpan> spans;
  final void Function(String url) onLinkTap;

  @override
  Widget build(BuildContext context) =>
      ContentSpans(spans: spans, onLinkTap: onLinkTap);
}

class _CommentCard extends StatefulWidget {
  const _CommentCard({
    required this.controller,
    required this.comment,
    this.onDeleted,
    this.canPin = false,
    this.onPinned,
    this.isPinned = false,
  });

  final AppController controller;
  final CommunityComment comment;
  final VoidCallback? onDeleted;
  final bool canPin;
  final VoidCallback? onPinned;
  final bool isPinned;

  @override
  State<_CommentCard> createState() => _CommentCardState();
}

class _CommentReplyDialog extends StatefulWidget {
  const _CommentReplyDialog({
    required this.controller,
    required this.onSubmit,
    required this.onSuccess,
    this.initialText = '',
  });

  final AppController controller;
  final Future<void> Function(List<CommentSpan> spans) onSubmit;
  final VoidCallback onSuccess;

  /// 预填文本（如“回复 @xxx ”前缀）。
  final String initialText;

  @override
  State<_CommentReplyDialog> createState() => _CommentReplyDialogState();
}

class _CommentReplyDialogState extends State<_CommentReplyDialog> {
  final _inputKey = GlobalKey<InlineEmojiInputState>();
  var _isSending = false;
  String? _error;

  /// 点击 @ 弹出用户搜索弹窗，把选中的用户以 `[@id:用户名]` 标记插入输入框。
  Future<void> _pickMention() async {
    final mention = await _askMentionUser(context, widget.controller);
    if (mention == null) return;
    _inputKey.currentState?.addMention(
      mention.mentionName,
      id: mention.mentionId,
    );
  }

  Future<void> _submit() async {
    final input = _inputKey.currentState;
    if (input == null || input.isEmpty || _isSending) return;
    setState(() {
      _isSending = true;
      _error = null;
    });
    try {
      await widget.onSubmit(input.spans);
      if (!mounted) return;
      widget.onSuccess();
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _isSending = false;
          _error = '回复失败：$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    titlePadding: const EdgeInsets.fromLTRB(24, 12, 8, 0),
    title: Row(
      children: [
        const Expanded(child: Text('回复评论')),
        IconButton(
          tooltip: '关闭',
          onPressed: _isSending ? null : () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InlineEmojiInput(
          key: _inputKey,
          hintText: '友善交流，理性发言',
          fontSize: 14,
          initialText: widget.initialText,
          onSearchUser: widget.controller.searchUsers,
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        ],
      ],
    ),
    actions: [
      IconButton(
        tooltip: '@ 用户',
        onPressed: _isSending ? null : _pickMention,
        icon: Icon(
          Icons.alternate_email,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      IconButton(
        tooltip: '表情包',
        onPressed: _isSending
            ? null
            : () => _inputKey.currentState?.pickEmoji(),
        icon: Icon(
          Icons.emoji_emotions_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      FilledButton(
        onPressed: _isSending ? null : _submit,
        child: _isSending
            ? const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('发布'),
      ),
    ],
  );
}

class _CommentCardState extends State<_CommentCard> {
  static final Map<int, UserProfile> _userCache = {};

  List<CommunityComment>? _replies;
  var _repliesLoading = false;
  var _repliesLoadingMore = false;
  var _replyPage = 0;
  var _hasMoreReplies = false;
  String? _repliesError;

  /// 本地新增/删除回复的数量，用于修正顶部“N 条回复”计数。
  int _replyDelta = 0;

  Future<UserProfile?>? _profile;
  late int _likes;
  late bool _liked;
  var _likeBusy = false;

  @override
  void initState() {
    super.initState();
    final comment = widget.comment;
    _likes = comment.likes;
    _liked = comment.liked;
    if (comment.authorName.isEmpty && comment.userId != 0) {
      final cached = _userCache[comment.userId];
      _profile = cached != null
          ? Future.value(cached)
          : _loadProfile(comment.userId);
    }
  }

  Future<void> _toggleLike() async {
    if (_likeBusy) return;
    if (widget.controller.session == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先在“我的”页面登录后再点赞')));
      return;
    }
    final target = !_liked;
    setState(() {
      _likeBusy = true;
      _liked = target;
      _likes += target ? 1 : -1;
    });
    try {
      await widget.controller.setCommentReaction(
        commentId: widget.comment.id,
        like: target,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _liked = !target;
          _likes += target ? -1 : 1;
        });
      }
    } finally {
      if (mounted) setState(() => _likeBusy = false);
    }
  }

  Future<UserProfile?> _loadProfile(int userId) async {
    try {
      final profile = await widget.controller.userProfile(userId);
      _userCache[userId] = profile;
      return profile;
    } catch (_) {
      return null;
    }
  }

  void _openUser(BuildContext context) {
    final userId = widget.comment.userId;
    if (userId == 0) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            UserProfilePage(controller: widget.controller, userId: userId),
      ),
    );
  }

  int get _replyTotal {
    final total = widget.comment.replyCount + _replyDelta;
    return total < 0 ? 0 : total;
  }

  Future<void> _loadReplies({bool loadMore = false}) async {
    if (_repliesLoading || _repliesLoadingMore) return;
    final page = loadMore ? _replyPage + 1 : 1;
    setState(() {
      if (loadMore) {
        _repliesLoadingMore = true;
      } else {
        _repliesLoading = true;
        _replies = const [];
        _replyPage = 0;
        _hasMoreReplies = false;
      }
      _repliesError = null;
    });
    try {
      final list = await widget.controller.commentReplies(
        widget.comment.id,
        page: page,
      );
      if (!mounted) return;
      setState(() {
        final previous = loadMore
            ? (_replies ?? const <CommunityComment>[])
            : const <CommunityComment>[];
        final merged = mergeCommentReplyPages(previous, list);
        final addedCount = merged.length - previous.length;
        _replies = merged;
        _replyPage = page;
        _hasMoreReplies = addedCount > 0 && merged.length < _replyTotal;
        _repliesLoading = false;
        _repliesLoadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _repliesLoading = false;
        _repliesLoadingMore = false;
        _repliesError = '回复加载失败：$error';
      });
    }
  }

  /// 展开/收起二级评论列表。
  void _toggleReplies() {
    if (_replies != null) {
      setState(() {
        _replies = null;
        _repliesError = null;
        _replyPage = 0;
        _hasMoreReplies = false;
      });
      return;
    }
    _loadReplies();
  }

  /// 打开回复编辑器；回复二级评论时把“回复 + mention + ：”真实预填进
  /// 正文，提交后服务端也能保存完整的回复对象，而不是只由 UI 补样式。
  void _showReplyComposer({String? mention, int? mentionId}) {
    if (widget.controller.session == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先在“我的”页面登录后再回复')));
      return;
    }
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _CommentReplyDialog(
        controller: widget.controller,
        initialText: mention == null
            ? ''
            : commentReplyInitialText(
                userName: mention,
                userId: mentionId ?? 0,
              ),
        onSubmit: (spans) => widget.controller.createCommentReply(
          commentId: widget.comment.id,
          spans: spans,
        ),
        onSuccess: () {
          if (!mounted) return;
          setState(() => _replyDelta++);
          _loadReplies();
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('回复已发布')));
        },
      ),
    );
  }

  /// 长按菜单：复制评论（所有人可用）、删除评论（仅自己）。
  Future<void> _showActions() async {
    final comment = widget.comment;
    final myId = widget.controller.session?.userId;
    final isMine = myId != null && comment.userId == myId;
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('复制评论'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await Clipboard.setData(ClipboardData(text: comment.content));
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('评论已复制')));
                }
              },
            ),
            if (widget.canPin)
              ListTile(
                leading: const Icon(Icons.push_pin_outlined),
                title: const Text('置顶评论'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _pinComment();
                },
              ),
            if (isMine)
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
                title: Text(
                  '删除评论',
                  style: TextStyle(
                    color: Theme.of(sheetContext).colorScheme.error,
                  ),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _confirmDelete();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pinComment() async {
    try {
      await widget.controller.pinComment(widget.comment.id);
      if (!mounted) return;
      widget.onPinned?.call();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('评论已置顶')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('置顶失败：$error')));
      }
    }
  }

  Future<void> _confirmDelete() async {
    final comment = widget.comment;
    final myId = widget.controller.session?.userId;
    if (myId == null || comment.userId != myId) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('只能删除自己的评论')));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: const Text('删除评论'),
        content: const Text('删除后无法恢复，确定删除这条评论吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.controller.deleteComment(comment.id);
      if (!mounted) return;
      widget.onDeleted?.call();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('评论已删除')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
    }
  }

  Widget _userRow(
    BuildContext context, {
    required int userId,
    required String name,
    required String avatar,
    bool loading = false,
  }) {
    final displayName = name.isNotEmpty
        ? name
        : loading
        ? '加载中…'
        : '用户 $userId';
    final letter = name.isNotEmpty ? name.substring(0, 1) : 'U';
    return Row(
      children: [
        InkWell(
          customBorder: const CircleBorder(),
          onTap: userId == 0 ? null : () => _openUser(context),
          child: CircleAvatar(
            radius: 15,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            foregroundImage: avatar.isEmpty ? null : NetworkImage(avatar),
            child: Text(
              letter,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: InkWell(
            onTap: userId == 0 ? null : () => _openUser(context),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUserHeader(BuildContext context) {
    final comment = widget.comment;
    if (comment.authorName.isNotEmpty ||
        comment.avatar.isNotEmpty ||
        _profile == null) {
      return _userRow(
        context,
        userId: comment.userId,
        name: comment.authorName,
        avatar: comment.avatar,
      );
    }
    return FutureBuilder<UserProfile?>(
      future: _profile,
      builder: (context, snapshot) => _userRow(
        context,
        userId: comment.userId,
        name: snapshot.data?.name ?? '',
        avatar: snapshot.data?.avatar ?? '',
        loading: snapshot.connectionState != ConnectionState.done,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final comment = widget.comment;
    return GestureDetector(
      onLongPress: _showActions,
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.isPinned) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.push_pin_rounded,
                        size: 14,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '置顶评论',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              _buildUserHeader(context),
              const SizedBox(height: 6),
              comment.spans.isEmpty
                  ? Text(
                      comment.content.isEmpty ? '（该评论没有文本内容）' : comment.content,
                    )
                  : _CommentSpans(
                      spans: comment.spans,
                      onLinkTap: (url) =>
                          openContentLink(context, widget.controller, url),
                    ),
              if (comment.images.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 76,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: comment.images.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final uri = Uri.tryParse(comment.images[index]);
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: GestureDetector(
                          onTap: uri == null
                              ? null
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => ImagePreviewPage(
                                      uri: uri,
                                      alt: '评论图片',
                                      heroTag:
                                          'comment-image-${comment.id}-$index-$uri',
                                    ),
                                  ),
                                ),
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: Hero(
                              tag: 'comment-image-${comment.id}-$index-$uri',
                              child: Image.network(
                                comment.images[index],
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => ColoredBox(
                                  color: AppPalette.of(context).placeholder,
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    color: AppPalette.of(context).muted,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: _toggleLike,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _liked
                                ? Icons.thumb_up_alt_rounded
                                : Icons.thumb_up_alt_outlined,
                            size: 15,
                            color: _liked
                                ? Theme.of(context).colorScheme.primary
                                : AppPalette.of(context).muted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$_likes 赞',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  if (comment.replyCount + _replyDelta > 0)
                    TextButton(
                      onPressed: _toggleReplies,
                      child: Text('${comment.replyCount + _replyDelta} 条回复'),
                    ),
                  TextButton(
                    onPressed: _showReplyComposer,
                    child: const Text('回复'),
                  ),
                  const Spacer(),
                  if (comment.createdAt != null)
                    Text(
                      _formatDate(comment.createdAt!),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
              if (_replies != null)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppPalette.of(context).chip,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      if (_repliesLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: LinearProgressIndicator(),
                        ),
                      if (_replies!.isEmpty &&
                          !_repliesLoading &&
                          _repliesError == null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            '暂无回复',
                            style: TextStyle(
                              color: AppPalette.of(context).muted,
                              fontSize: 12.5,
                            ),
                          ),
                        )
                      else if (_replies!.isNotEmpty)
                        ..._replies!.map(
                          (reply) => _CommentReplyTile(
                            key: ValueKey('comment-reply-${reply.id}'),
                            controller: widget.controller,
                            rootCommentId: widget.comment.id,
                            reply: reply,
                            onReply: (name, userId) => _showReplyComposer(
                              mention: name,
                              mentionId: userId,
                            ),
                            onDeleted: () {
                              if (!mounted) return;
                              setState(() {
                                _replies = removeCommentReply(
                                  _replies ?? const <CommunityComment>[],
                                  reply.id,
                                );
                                _replyDelta--;
                                _hasMoreReplies =
                                    _replies!.length < _replyTotal;
                              });
                            },
                          ),
                        ),
                      if (_repliesError != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _repliesError!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () =>
                                    _loadReplies(loadMore: _replyPage > 0),
                                child: const Text('重试'),
                              ),
                            ],
                          ),
                        ),
                      if (_repliesLoadingMore)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else if (_hasMoreReplies)
                        TextButton.icon(
                          onPressed: () => _loadReplies(loadMore: true),
                          icon: const Icon(Icons.expand_more_rounded),
                          label: Text(
                            '加载更多回复（已显示 ${_replies!.length}/$_replyTotal）',
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 合并楼中楼分页结果并按评论 ID 去重。返回新列表，调用方无需依赖源列表
/// 是否可增长。
List<CommunityComment> mergeCommentReplyPages(
  List<CommunityComment> existing,
  List<CommunityComment> incoming,
) {
  final ids = existing.map((comment) => comment.id).toSet();
  return [...existing, ...incoming.where((comment) => ids.add(comment.id))];
}

/// 删除成功后以不可变方式替换楼中楼列表，避免对 Repository 返回的
/// fixed-length list 调用 remove/removeWhere。
List<CommunityComment> removeCommentReply(
  List<CommunityComment> replies,
  int commentId,
) =>
    replies.where((comment) => comment.id != commentId).toList(growable: false);

/// 编辑器使用的结构化标记会在提交时转换成真实 mention Quill 节点。
String commentReplyInitialText({
  required String userName,
  required int userId,
}) {
  final id = userId > 0 ? '$userId' : '';
  return '回复[@$id:$userName]：';
}

/// 二级评论（回复）：头像 + 昵称 + 内容 + 点赞/回复/删除操作，长按可复制或删除。
class _CommentReplyTile extends StatefulWidget {
  const _CommentReplyTile({
    super.key,
    required this.controller,
    required this.rootCommentId,
    required this.reply,
    this.onReply,
    this.onDeleted,
  });

  final AppController controller;
  final int rootCommentId;
  final CommunityComment reply;

  /// 回复该二级评论（预填 @昵称 前缀）。
  final void Function(String userName, int userId)? onReply;

  /// 删除成功后回调（供父级移除列表项并修正计数）。
  final VoidCallback? onDeleted;

  @override
  State<_CommentReplyTile> createState() => _CommentReplyTileState();
}

class _CommentReplyTileState extends State<_CommentReplyTile> {
  late int _likes;
  late bool _liked;
  var _likeBusy = false;

  @override
  void initState() {
    super.initState();
    _likes = widget.reply.likes;
    _liked = widget.reply.liked;
  }

  Future<void> _toggleLike() async {
    if (_likeBusy) return;
    if (widget.controller.session == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先在“我的”页面登录后再点赞')));
      return;
    }
    final target = !_liked;
    setState(() {
      _likeBusy = true;
      _liked = target;
      _likes += target ? 1 : -1;
    });
    try {
      await widget.controller.setCommentReaction(
        commentId: widget.reply.id,
        like: target,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _liked = !target;
          _likes += target ? -1 : 1;
        });
      }
    } finally {
      if (mounted) setState(() => _likeBusy = false);
    }
  }

  void _openUser() {
    final userId = widget.reply.userId;
    if (userId == 0) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            UserProfilePage(controller: widget.controller, userId: userId),
      ),
    );
  }

  /// 长按菜单：复制回复（所有人可用）、删除回复（仅自己）。
  Future<void> _showActions() async {
    final reply = widget.reply;
    final myId = widget.controller.session?.userId;
    final isMine = myId != null && reply.userId == myId;
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('复制回复'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await Clipboard.setData(ClipboardData(text: reply.content));
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('回复已复制')));
                }
              },
            ),
            if (isMine)
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
                title: Text(
                  '删除回复',
                  style: TextStyle(
                    color: Theme.of(sheetContext).colorScheme.error,
                  ),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _confirmDelete();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final reply = widget.reply;
    final myId = widget.controller.session?.userId;
    if (myId == null || reply.userId != myId) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('只能删除自己的回复')));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: const Text('删除回复'),
        content: const Text('删除后无法恢复，确定删除这条回复吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.controller.deleteComment(reply.id);
      if (!mounted) return;
      widget.onDeleted?.call();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('回复已删除')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final reply = widget.reply;
    final name = reply.authorName.isEmpty
        ? '用户 ${reply.userId}'
        : reply.authorName;
    final letter = name.isEmpty ? 'U' : name.substring(0, 1);
    final myId = widget.controller.session?.userId;
    final isMine = myId != null && reply.userId == myId;
    return GestureDetector(
      onLongPress: _showActions,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              customBorder: const CircleBorder(),
              onTap: reply.userId == 0 ? null : _openUser,
              child: CircleAvatar(
                radius: 13,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                foregroundImage: reply.avatar.isEmpty
                    ? null
                    : NetworkImage(reply.avatar),
                child: Text(
                  letter,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: reply.userId == 0 ? null : _openUser,
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (reply.createdAt != null)
                        Text(
                          _formatDate(reply.createdAt!),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  if (reply.spans.isEmpty)
                    Text(
                      reply.content.isEmpty ? '（该回复没有文本内容）' : reply.content,
                      style: TextStyle(
                        color: AppPalette.of(context).muted,
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    )
                  else
                    ContentSpans(
                      spans: reply.spans,
                      textStyle: TextStyle(
                        color: AppPalette.of(context).muted,
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                      stickerSize: 26,
                      onLinkTap: (url) =>
                          openContentLink(context, widget.controller, url),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: _toggleLike,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _liked
                                    ? Icons.thumb_up_alt_rounded
                                    : Icons.thumb_up_alt_outlined,
                                size: 13,
                                color: _liked
                                    ? Theme.of(context).colorScheme.primary
                                    : AppPalette.of(context).muted,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '$_likes',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => widget.onReply?.call(name, reply.userId),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          child: Text(
                            '回复',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                          ),
                        ),
                      ),
                      if (isMine) ...[
                        const SizedBox(width: 12),
                        InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: _confirmDelete,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            child: Icon(
                              Icons.delete_outline_rounded,
                              size: 15,
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _formatDateTime(DateTime? value) =>
    value == null ? '刚刚' : _formatDate(value);

String _formatDuration(Duration value) {
  String two(int number) => number.toString().padLeft(2, '0');
  final hours = value.inHours;
  final minutes = two(value.inMinutes.remainder(60));
  final seconds = two(value.inSeconds.remainder(60));
  if (hours > 0) return '$hours:$minutes:$seconds';
  return '$minutes:$seconds';
}
