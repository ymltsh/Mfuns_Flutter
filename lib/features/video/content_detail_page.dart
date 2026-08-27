import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show ValueListenable, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/app_controller.dart';
import '../../core/config/user_preferences.dart';
import '../../core/media/media_notification.dart';
import '../../core/media/playback_coordinator.dart';
import '../../core/media/playback_log.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/content_link_handler.dart';
import '../../core/widgets/content_spans.dart';
import '../../core/widgets/image_preview_page.dart';
import '../../core/widgets/inline_emoji_input.dart';
import '../content/export/article_exporter.dart';
import '../content/export/comment_collector.dart';
import '../content/rich_content_card.dart';
import '../home/home_repository.dart';
import '../settings/network_diagnostics_page.dart';
import '../user/user_profile_page.dart';

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
  late final Future<ContentDetail> _detail;
  late final Future<List<VideoQuality>>? _qualities;
  late final Future<List<ContentPreview>> _related;
  late final TabController _tabController;
  var _activeTab = 0;
  var _danmakuOn = true;
  VideoQuality? _selectedQuality;
  List<VideoQuality> _availableQualities = const [];
  var _qualitiesLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(_syncTab);
    _detail = widget.controller.contentDetail(widget.preview);
    _qualities = widget.preview.isVideo
        ? widget.controller.videoQualities(widget.preview.id)
        : null;
    _qualities?.then((items) {
      if (!mounted) return;
      setState(() {
        _qualitiesLoading = false;
        _availableQualities = items;
      });
    }).catchError((Object _) {
      if (!mounted) return;
      setState(() => _qualitiesLoading = false);
    });
    _related = widget.controller.relatedContent(widget.preview);
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('播放器尚未准备完成')));
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
                key: PageStorageKey<String>(
                    'content-intro-${widget.preview.id}'),
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
                key: PageStorageKey<String>(
                    'content-comment-${widget.preview.id}'),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 36),
                child: detail.commentAreaId != null
                    ? _CommentSection(
                        controller: widget.controller,
                        areaId: detail.commentAreaId!,
                      )
                    : const Text('当前内容暂不支持评论'),
              ),
            );
            final tabView = TabBarView(
              controller: _tabController,
              children: [introTab, commentTab],
            );
            // 横屏自动分栏：左侧播放器（黑底），右侧信息与评论独立滚动。
            final isLandscape =
                MediaQuery.orientationOf(context) == Orientation.landscape;
            if (isLandscape) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: MediaQuery.sizeOf(context).width * 0.42,
                    child: ColoredBox(
                      color: Colors.black,
                      child: player,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        tabs,
                        Expanded(child: tabView),
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
                UnconstrainedBox(
                  constrainedAxis: Axis.horizontal,
                  child: player,
                ),
                tabs,
                Expanded(child: tabView),
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

  @override
  void initState() {
    super.initState();
    _detail = widget.controller.feedDetail(widget.feedId);
  }

  void _reload() =>
      setState(() => _detail = widget.controller.feedDetail(widget.feedId));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('动态详情'),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: '刷新动态',
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
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
            return _landscapeCentered(
              context,
              ListView(
                key: PageStorageKey<String>('feed-detail-${feed.id}'),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                children: [
                _FeedAuthorCard(
                  feed: feed,
                  controller: widget.controller,
                ),
                const SizedBox(height: 12),
                RichContentCard(
                    source: detail.rawContent.isEmpty
                        ? feed.content
                        : detail.rawContent,
                    onLinkTap: (url) =>
                        openContentLink(context, widget.controller, url)),
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
                        .map((tag) => Chip(label: Text('#$tag')))
                        .toList(growable: false),
                  ),
                ],
                const SizedBox(height: 24),
                if (detail.commentAreaId != null)
                  _CommentSection(
                    controller: widget.controller,
                    areaId: detail.commentAreaId!,
                  )
                else
                  const _ArticleCommentUnavailable(),
              ],
              ),
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
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) =>
            UserProfilePage(controller: controller, userId: userId)));
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
                  foregroundImage:
                      feed.avatar.isEmpty ? null : NetworkImage(feed.avatar),
                  child: Text(feed.author.isEmpty ? 'M' : feed.author[0]),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: feed.authorId == null
                      ? null
                      : () => _openProfile(context),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            feed.author.isEmpty ? 'Mfuns 用户' : feed.author,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 3),
                        Text(_formatDateTime(feed.createdAt),
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
              ),
              Text('${feed.views} 浏览',
                  style: Theme.of(context).textTheme.bodySmall),
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
                  : () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => ImagePreviewPage(
                          uri: uri,
                          alt: '动态图片',
                          heroTag: 'feed-image-$feedId-$index-$uri',
                          uris: images
                              .map(Uri.parse)
                              .toList(growable: false),
                          initialIndex: index,
                        ),
                      )),
              child: Hero(
                tag: 'feed-image-$feedId-$index-$uri',
                child: Image.network(
                  images[index],
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const ColoredBox(
                    color: Color(0xffefeff7),
                    child: Icon(Icons.broken_image_outlined),
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
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) =>
                  ContentDetailPage(controller: controller, preview: item))),
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
  var _scrollbarEnabled = false;

  @override
  void initState() {
    super.initState();
    _detail = widget.controller.contentDetail(widget.preview);
    _loadScrollbarPreference();
  }

  Future<void> _loadScrollbarPreference() async {
    final enabled = await UserPreferences.loadArticleScrollbar();
    if (mounted) setState(() => _scrollbarEnabled = enabled);
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
        appBar: AppBar(
          title: const Text('文章详情'),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: '刷新文章',
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
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
            final articleList = _landscapeCentered(
              context,
              ListView(
                controller: _scrollController,
                key: PageStorageKey<String>(
                    'article-detail-${detail.preview.id}'),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                children: [
                  _ArticleInfoCard(
                    detail: detail,
                    controller: widget.controller,
                  ),
                  const SizedBox(height: 12),
                  RichContentCard(
                    source: detail.rawContent,
                    onLinkTap: (url) =>
                        openContentLink(context, widget.controller, url),
                  ),
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
                          .map((tag) => Chip(label: Text('#$tag')))
                          .toList(growable: false),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (detail.commentAreaId != null)
                    _CommentSection(
                      controller: widget.controller,
                      areaId: detail.commentAreaId!,
                    )
                  else
                    const _ArticleCommentUnavailable(),
                ],
              ),
            );
            return Stack(
              children: [
                Positioned.fill(child: articleList),
                if (_scrollbarEnabled)
                  _ArticleProgressSlider(controller: _scrollController),
              ],
            );
          },
        ),
      );
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
                  : () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => ImagePreviewPage(
                          uri: cover,
                          alt: '文章封面',
                          heroTag: 'article-cover-${preview.id}-$cover',
                        ),
                      )),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Hero(
                  tag: 'article-cover-${preview.id}-$cover',
                  child: Image.network(
                    preview.cover,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const ColoredBox(
                      color: Color(0xffececf5),
                      child: Icon(Icons.image_outlined,
                          color: Color(0xff8a8a94)),
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
                      '${preview.category.isEmpty ? 'Mfuns' : preview.category} · ${preview.views} 阅读 · ${preview.comments} 评论',
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

/// 长文章阅读进度滑块：竖向拖拽跳转进度，无操作时自动隐藏。
class _ArticleProgressSlider extends StatefulWidget {
  const _ArticleProgressSlider({required this.controller});

  final ScrollController controller;

  @override
  State<_ArticleProgressSlider> createState() => _ArticleProgressSliderState();
}

class _ArticleProgressSliderState extends State<_ArticleProgressSlider> {
  static const _autoHideDelay = Duration(milliseconds: 2500);
  static const _edgeInset = 14.0;
  static const _thumbHeight = 26.0;
  static const _trackWidth = 4.0;

  Timer? _hideTimer;
  var _visible = false;
  var _dragging = false;
  var _progress = 0.0;

  // 拖拽开始时冻结的滚动范围：文章图片/评论在拖拽过程中异步加载会改变
  // maxScrollExtent，若每次更新都用实时范围换算，内容会相对滑块来回跳动。
  double _dragExtent = 0;

  // 待应用的跳转目标，每帧最多应用一次：高刷新率指针（120Hz+、高回报率
  // 鼠标）每个事件都 jumpTo 会迫使懒加载列表反复重建视口造成抖动。
  double? _pendingJumpTarget;
  var _jumpScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScrollChanged);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.controller.removeListener(_onScrollChanged);
    super.dispose();
  }

  bool get _overflowing =>
      widget.controller.hasClients &&
      widget.controller.position.maxScrollExtent > 0;

  void _onScrollChanged() {
    if (_dragging) return;
    if (!_overflowing) {
      _setVisible(false);
      return;
    }
    final position = widget.controller.position;
    _setProgress(position.pixels / position.maxScrollExtent);
    _setVisible(true);
    _restartHideTimer();
  }

  void _restartHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_autoHideDelay, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  void _setVisible(bool value) {
    if (_visible == value) return;
    setState(() => _visible = value);
  }

  void _setProgress(double value) {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    if (_progress == clamped) return;
    setState(() => _progress = clamped);
  }

  double _progressFromY(double y, double height) {
    final usable = height - _edgeInset * 2;
    return usable <= 0
        ? 0.0
        : ((y - _edgeInset) / usable).clamp(0.0, 1.0).toDouble();
  }

  void _seekTo(double y, double height) {
    if (!_overflowing) return;
    final progress = _progressFromY(y, height);
    _setProgress(progress);
    final position = widget.controller.position;
    position.jumpTo(progress * position.maxScrollExtent);
  }

  // 拇指拖动偏移：记录按下点相对拇指中心的偏移，拖动时保持该偏移，
  // 拇指随手指移动（标准滚动条行为）。
  double _grabOffsetY = 0;

  void _startThumbDrag(double localY, double hitHeight) {
    if (!_overflowing) return;
    _dragExtent = widget.controller.position.maxScrollExtent;
    _pendingJumpTarget = null;
    _grabOffsetY = localY - hitHeight / 2;
    _hideTimer?.cancel();
    setState(() => _dragging = true);
  }

  void _updateThumbDrag(double localY, double hitHeight, double height) {
    if (!_dragging) return;
    final usable = height - _edgeInset * 2;
    if (usable <= 0) return;
    final thumbTop =
        (_edgeInset + _progress * usable) - _thumbHeight / 2;
    final fingerY = thumbTop + localY;
    final progress =
        ((fingerY - _grabOffsetY - _edgeInset) / usable)
            .clamp(0.0, 1.0)
            .toDouble();
    _setProgress(progress);
    _scheduleJump(progress * _dragExtent);
  }

  void _scheduleJump(double target) {
    if (_pendingJumpTarget == target) return;
    _pendingJumpTarget = target;
    if (_jumpScheduled) return;
    _jumpScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _jumpScheduled = false;
      final pending = _pendingJumpTarget;
      _pendingJumpTarget = null;
      if (pending == null || !mounted || !_overflowing) return;
      final position = widget.controller.position;
      if ((position.pixels - pending).abs() < 0.5) return;
      position.jumpTo(pending);
    });
  }

  void _endThumbDrag() {
    final pending = _pendingJumpTarget;
    _pendingJumpTarget = null;
    _grabOffsetY = 0;
    if (mounted && pending != null && _overflowing) {
      final position = widget.controller.position;
      if ((position.pixels - pending).abs() >= 0.5) {
        position.jumpTo(pending);
      }
    }
    if (!mounted) return;
    setState(() => _dragging = false);
    // 拖拽期间文章范围可能已变化，结束后以真实位置校正滑块。
    if (_overflowing) {
      final position = widget.controller.position;
      _setProgress(position.pixels / position.maxScrollExtent);
    }
    _restartHideTimer();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 轨道只响应“点击跳转”，不注册拖动识别器，因此不会与列表滚动手势
    // 竞争；只有拇指（含 8px 外扩命中区）可拖动。此前整条竖带参与拖动
    // 竞技场，滑块可见时会吞掉拇指划动的起始位置，表现为“在段落上滑动
    // 页面卡住”。
    return Positioned(
      top: 0,
      bottom: 0,
      right: 0,
      width: 16,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: !_visible,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final height = constraints.maxHeight;
              final usable = height - _edgeInset * 2;
              final thumbCenterY = (_edgeInset + _progress * usable)
                  .clamp(0.0, usable)
                  .toDouble();
              final thumbTop =
                  (thumbCenterY - _thumbHeight / 2).clamp(0.0, usable).toDouble();
              final labelTop =
                  (thumbCenterY - 18).clamp(2.0, height - 38).toDouble();
              const thumbHitHeight = _thumbHeight + 8;
              return Stack(
                children: [
                  // 轨道：点击跳转进度；不参与拖动，滑动交给列表。
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) =>
                          _seekTo(details.localPosition.dy, height),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: _trackWidth,
                            height: height,
                            decoration: BoxDecoration(
                              color:
                                  theme.colorScheme.onSurface.withOpacity(.12),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          Positioned(
                            top: 0,
                            width: _trackWidth,
                            height: thumbCenterY,
                            child: Container(
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 拇指：唯一可拖动的部位，保持按下点相对拇指中心的偏移。
                  Positioned(
                    top: thumbTop - 4,
                    left: 0,
                    right: 0,
                    height: thumbHitHeight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragStart: (details) => _startThumbDrag(
                          details.localPosition.dy, thumbHitHeight),
                      onVerticalDragUpdate: (details) => _updateThumbDrag(
                          details.localPosition.dy, thumbHitHeight, height),
                      onVerticalDragEnd: (_) => _endThumbDrag(),
                      onVerticalDragCancel: _endThumbDrag,
                      child: Center(
                        child: Container(
                          width: 12,
                          height: _thumbHeight,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(.25),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_dragging)
                    Positioned(
                      right: 30,
                      top: labelTop,
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.inverseSurface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${(_progress * 100).round()}%',
                            style: TextStyle(
                              color: theme.colorScheme.onInverseSurface,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
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
            18, 18, 18, MediaQuery.viewInsetsOf(context).bottom + 18),
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
    required this.commentCount,
    required this.onChanged,
    this.onSendDanmaku,
    this.onToggleDanmaku,
    required this.danmakuOn,
  });

  final int activeTab;
  final int commentCount;
  final ValueChanged<int> onChanged;
  final VoidCallback? onSendDanmaku;
  final VoidCallback? onToggleDanmaku;
  final bool danmakuOn;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 2,
        child: SizedBox(
          height: 46,
          child: Row(
            children: [
              _DetailTab(
                label: '简介',
                selected: activeTab == 0,
                onTap: () => onChanged(0),
              ),
              _DetailTab(
                label: '评论 $commentCount',
                selected: activeTab == 1,
                onTap: () => onChanged(1),
              ),
              const Spacer(),
              TextButton(onPressed: onSendDanmaku, child: const Text('发弹幕')),
              IconButton(
                tooltip: danmakuOn ? '关闭弹幕' : '开启弹幕',
                onPressed: onToggleDanmaku,
                icon: Icon(danmakuOn
                    ? Icons.subtitles_rounded
                    : Icons.subtitles_off_rounded),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      );
}

class _DetailTab extends StatelessWidget {
  const _DetailTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: label.startsWith('评论') ? 98 : 70,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(label,
                  style: TextStyle(
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  )),
              const SizedBox(height: 6),
              Container(
                width: 42,
                height: 3,
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
              ),
            ],
          ),
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
          overflow:
              _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
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
            Text(detail.preview.title,
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              '${detail.preview.category.isEmpty ? 'Mfuns' : detail.preview.category} · ${detail.preview.views} 播放 · ${detail.preview.comments} 弹幕',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            _ExpandableDescription(
              text: detail.content,
              onLinkTap: (url) =>
                  openContentLink(context, controller, url),
            ),
            _VideoActions(controller: controller, preview: detail.preview),
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
            _AuthorBar(
              controller: controller,
              preview: detail.preview,
            ),
            if (detail.tags.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text('标签相关'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: detail.tags
                    .map((tag) => Chip(label: Text('#$tag')))
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
                      .map((item) => _RelatedContentTile(
                            controller: controller,
                            item: item,
                          ))
                      .toList(),
                );
              },
            ),
          ],
        ),
      );
}

class _VideoActions extends StatefulWidget {
  const _VideoActions({
    required this.controller,
    required this.preview,
    this.resourceType,
    this.linkPath,
    this.rawContent,
    this.commentAreaId,
  });

  final AppController controller;
  final ContentPreview preview;
  final int? resourceType;
  final String? linkPath;

  /// 文章原始富文本（仅文章详情页提供）；非空时分享面板显示导出入口。
  final String? rawContent;

  /// 文章评论区 areaId（仅文章详情页提供）；为 null 时评论数为 0。
  final int? commentAreaId;

  @override
  State<_VideoActions> createState() => _VideoActionsState();
}

class _VideoActionsState extends State<_VideoActions> {
  ResourceReactionStatus? _reaction;
  var _favorite = false;
  var _busy = false;
  var _rewarding = false;

  int get _resourceType =>
      widget.resourceType ?? (widget.preview.isVideo ? 1 : 0);

  /// 只有文章（0）和视频（1）支持投币，动态等类型不显示投币入口。
  bool get _canReward => _resourceType == 0 || _resourceType == 1;

  @override
  void initState() {
    super.initState();
    _loadStatus();
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
    final active =
        dislike ? _reaction?.disliked == true : _reaction?.liked == true;
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
                leading: const Icon(Icons.monetization_on_outlined,
                    color: Color(0xFFE6A23C)),
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
    if (_favorite) {
      _notice('已收藏，可在“我的收藏”中管理');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.controller.loadFavoriteFolders();
      if (!mounted) return;
      final folders = widget.controller.favoriteFolders;
      if (folders.isEmpty) {
        _notice('请先在“我的收藏”创建收藏夹');
        return;
      }
      final folder = await showModalBottomSheet<FavoriteFolder>(
        context: context,
        useRootNavigator: true,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('选择收藏夹')),
              for (final item in folders)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(item.name),
                  subtitle: Text('${item.count} 个内容'),
                  onTap: () => Navigator.of(sheetContext).pop(item),
                ),
            ],
          ),
        ),
      );
      if (folder == null) return;
      await widget.controller.addFavorite(
        listId: folder.id,
        resourceId: widget.preview.id,
        resourceType: _resourceType,
      );
      if (mounted) {
        setState(() => _favorite = true);
        _notice('已收藏到 ${folder.name}');
      }
    } catch (error) {
      _notice('收藏失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _linkPath =>
      widget.linkPath ?? (widget.preview.isVideo ? 'video' : 'article');

  String get _articleLink => 'https://m.mfuns.net/$_linkPath/${widget.preview.id}';

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _articleLink));
    if (mounted) _notice('链接已复制');
  }

  /// 分享面板：复制链接 + 「更多」（文章提供导出 Markdown / 图片）。
  Future<void> _showSharePanel() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.ios_share_rounded,
                  color: AppPalette.of(context).primary),
              title: const Text('分享',
                  style: TextStyle(
                      color: Colors.blueGrey, fontWeight: FontWeight.w800)),
              subtitle: const Text('复制链接，或查看更多操作',
                  style: TextStyle(color: Colors.blueGrey, fontSize: 12)),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text('复制链接'),
              subtitle: Text(_articleLink,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.of(sheetContext).pop('copy'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.more_horiz_rounded),
              title: const Text('更多'),
              trailing: const Icon(Icons.chevron_right_rounded,
                  color: Colors.blueGrey),
              onTap: () => Navigator.of(sheetContext).pop('more'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'copy') await _copyLink();
    if (action == 'more') await _showMore();
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
            if (_canExportArticle) ...[
              ListTile(
                leading: const Icon(Icons.ios_share_rounded),
                title: const Text('导出文章（Markdown、图片）'),
                subtitle: const Text('导出为 Markdown 或长图，可附带评论',
                    style: TextStyle(color: Colors.blueGrey, fontSize: 12)),
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
                leading: Icon(Icons.delete_outline_rounded,
                    color: Theme.of(context).colorScheme.error),
                title: Text('删除动态',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
                onTap: () => Navigator.of(sheetContext).pop('delete'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
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
        0, (sum, result) => sum + result.failedImageCount);
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
              style: const TextStyle(
                  color: Colors.blueGrey, fontSize: 12, height: 1.5),
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('动态已删除')));
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败：$error')));
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
        _ActionIcon(
          icon: Icons.ios_share_rounded,
          label: '分享',
          onTap: _showSharePanel,
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
          color: const Color(0xfff5f4f9),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('分 P',
                style: TextStyle(
                    color: Colors.blueGrey, fontWeight: FontWeight.w800)),
            const SizedBox(height: 7),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children:
                    (qualities.map((quality) => quality.part).toSet().toList()
                          ..sort())
                        .map((part) {
                  final selected = part == selectedQuality?.part;
                  final target =
                      _matchingPartQuality(qualities, selectedQuality, part);
                  return Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: ChoiceChip(
                      label: Text('P$part'),
                      selected: selected,
                      selectedColor: Theme.of(context).colorScheme.primary,
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : Colors.blueGrey,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                      side: BorderSide.none,
                      backgroundColor: Colors.white,
                      onSelected: selected
                          ? null
                          : (_) {
                              if (target != null) onQualitySelected(target);
                            },
                    ),
                  );
                }).toList(),
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
  const _ExportArticleDialog({
    required this.controller,
    required this.areaId,
  });

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
    Navigator.of(context).pop(_ExportArticleDialogResult(
      options: ArticleExportOptions(
        format: _format,
        includeComments: includeComments,
        includeFooter: _includeFooter,
        imageScale: _imageScale,
      ),
      comments: comments,
    ));
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
              title: const Text('带评论导出',
                  style: TextStyle(
                      color: Colors.blueGrey, fontWeight: FontWeight.w700)),
              subtitle: _includeComments
                  ? Text(_commentSubtitle,
                      style: const TextStyle(
                          color: Colors.blueGrey, fontSize: 12))
                  : null,
            ),
            const SizedBox(height: 6),
            CheckboxListTile(
              value: _includeFooter,
              onChanged: (value) => setState(() => _includeFooter = value ?? true),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('在导出底部加入Mfuns Flutter开源项目说明',
                  style: TextStyle(
                      color: Colors.blueGrey, fontWeight: FontWeight.w700)),
              subtitle: const Text('正文之后附加项目介绍与 GitHub 地址',
                  style: TextStyle(color: Colors.blueGrey, fontSize: 12)),
            ),
            const SizedBox(height: 14),
            const Text('导出格式',
                style: TextStyle(
                    color: Colors.blueGrey,
                    fontSize: 13,
                    fontWeight: FontWeight.w800)),
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
                  const Text('内容大小',
                      style: TextStyle(
                          color: Colors.blueGrey,
                          fontSize: 13,
                          fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Text('×${_imageScale.toStringAsFixed(1)}',
                      style: TextStyle(
                          color: AppPalette.of(context).primary,
                          fontWeight: FontWeight.w700)),
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
              const Text('调整字号相对图片的大小，输出分辨率固定为 1080px',
                  style: TextStyle(color: Colors.blueGrey, fontSize: 12)),
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
                  style: const TextStyle(
                      color: Colors.blueGrey,
                      fontSize: 13,
                      height: 1.4),
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
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: color,
                    )),
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
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) =>
            UserProfilePage(controller: widget.controller, userId: userId)));
  }

  Future<void> _toggleFollow() async {
    final userId = _userId;
    if (userId == null || _isUpdating || _isOwnProfile) return;
    if (widget.controller.session == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先在“我的”页面登录后再关注')));
      return;
    }
    final next = !(_following ?? false);
    setState(() => _isUpdating = true);
    try {
      await widget.controller.setFollow(userId: userId, follow: next);
      if (mounted) setState(() => _following = next);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('操作失败：$error')));
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
                  Text(preview.author.isEmpty ? 'Mfuns 用户' : preview.author,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
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
                      ? const ColoredBox(color: Color(0xffd9d9d9))
                      : Image.network(item.cover,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const ColoredBox(color: Color(0xffd9d9d9))),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 90,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      const Spacer(),
                      Text(item.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall),
                      Text(
                          '${item.likes} 点赞  ${item.comments} 评论  ${item.views} 浏览',
                          style: Theme.of(context).textTheme.bodySmall),
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
    this.onQualityChanged,
    this.onDanmakuChanged,
  });

  final AppController controller;
  final int videoId;
  final String title;
  final String coverUrl;
  final List<VideoQuality> qualities;
  final ValueChanged<VideoQuality>? onQualityChanged;
  final ValueChanged<bool>? onDanmakuChanged;

  @override
  State<MfunsVideoPlayer> createState() => _MfunsVideoPlayerState();
}

class _MfunsVideoPlayerState extends State<MfunsVideoPlayer>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
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
  var _showPlaybackOptions = false;
  var _hasStarted = false;
  var _isLongPressSpeed = false;
  var _isSeeking = false;
  double _doubleTapX = 0;
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The player is drawn edge-to-edge: keep the layout consistent across
    // devices (Android <15 legacy vs enforced edge-to-edge) and use light
    // status bar icons over the black player surface.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));
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

  /// 后台播放（Beta）：
  /// - 开启：退后台时由 MfunsPlaybackCoordinator 把音频 handoff 到
  ///   just_audio 后台引擎继续播放，回前台时切回视频。
  /// - 关闭：退后台自动暂停视频，避免静默播放。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      MfunsPlaybackCoordinator.instance
          .onAppBackgrounded(backgroundPlayEnabled: _backgroundPlay);
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
  void _checkAutoNextPart() {
    if (_isFullscreen) return;
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
    if (value.position < value.duration) return;
    final next =
        _matchingPartQuality(widget.qualities, selected, selected.part + 1);
    if (next == null) return;
    _select(next, forcePlay: true);
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
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _controlsTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    if (_wakelockHeld) {
      _wakelockHeld = false;
      WakelockPlus.disable();
    }
    final player = _player;
    if (player != null) {
      final wasBound =
          MfunsPlaybackCoordinator.instance.unbindVideo(player);
      PlaybackLog.d('player dispose id=${identityHashCode(player)} bound=$wasBound');
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
    final resumePosition =
        samePart ? (oldValue?.position ?? Duration.zero) : Duration.zero;
    final wasPlaying = oldValue?.isPlaying ?? false;
    setState(() {
      _selected = quality;
      _player = null;
      _error = null;
      _danmaku = const [];
    });
    widget.onQualityChanged?.call(quality);
    if (oldPlayer != null) {
      MfunsPlaybackCoordinator.instance.unbindVideo(oldPlayer);
    }
    await oldPlayer?.dispose();
    if (!mounted || request != _selectionRequest) return;
    final nextPlayer = VideoPlayerController.networkUrl(
      Uri.parse(quality.url),
      videoPlayerOptions: VideoPlayerOptions(
        // 真正的“是否启用后台播放”由本页 _backgroundPlay 控制；
        // 退后台时由 MfunsPlaybackCoordinator 负责暂停或 handoff。
        allowBackgroundPlayback: _backgroundPlay,
      ),
    );
    PlaybackLog.d(
        'create player id=${identityHashCode(nextPlayer)} url=${quality.url}');
    try {
      await nextPlayer
          .initialize()
          .timeout(videoInitTimeout);
      PlaybackLog.d(
          'initialize ok id=${identityHashCode(nextPlayer)} '
          'duration=${nextPlayer.value.duration}');
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
        url: quality.url,
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
  void _attachMediaNotification(VideoPlayerController player, VideoQuality quality) {
    MfunsAudioHandler.instance.attach(
      player: player,
      title: widget.title,
      subtitle: 'Mfuns',
      artUri: widget.coverUrl,
      url: quality.url,
      part: quality.part,
    );
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

  Future<_FullscreenPlayerUpdate?> _selectForFullscreen(
      VideoQuality quality) async {
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

  void _notice(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

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
    } else {
      _showPlaybackOptions = false;
    }
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
      DragUpdateDetails details, double width, double height) {
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

  Future<void> _seekBy(int seconds) async {
    final player = _player;
    if (player == null) return;
    var target = player.value.position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (target > player.value.duration) target = player.value.duration;
    await player.seekTo(target);
    if (mounted) {
      setState(() {
        _seekNotice = '${seconds > 0 ? '+' : ''}$seconds 秒';
        _controlsVisible = true;
      });
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
    final target = _dragSeekBase +
        Duration(
            milliseconds:
                (deltaDx / width * duration.inMilliseconds).round());
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
    // 常规（横屏比例）视频最多占屏幕高度 2/3；竖屏比例视频（高大于宽）
    // 缩放到正常 16:9 比例的播放框（黑边居中），避免固定播放器占用过多
    // 显示区域、遮挡下方内容。横屏布局中播放器撑满左栏不受影响。
    final aspectRatio = value?.aspectRatio ?? 16 / 9;
    final screenSize = MediaQuery.sizeOf(context);
    final maxHeight = screenSize.height * 2 / 3;
    final portraitCap = screenSize.width * 9 / 16;
    final heightCap =
        aspectRatio < 1 && portraitCap < maxHeight ? portraitCap : maxHeight;
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return LayoutBuilder(
      builder: (context, constraints) {
        final naturalVideoHeight = constraints.maxWidth / aspectRatio;
        final videoHeight =
            naturalVideoHeight > heightCap ? heightCap : naturalVideoHeight;
        final videoWidth = videoHeight * aspectRatio;
        final availableHeight = constraints.maxHeight;
        final surfaceHeight =
            availableHeight.isFinite ? availableHeight : videoHeight;
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
        onDoubleTapDown: (details) => _doubleTapX = details.localPosition.dx,
        onDoubleTap: () {
          final width = MediaQuery.sizeOf(context).width;
          _seekBy(_doubleTapX < width / 2 ? -10 : 10);
        },
        onLongPressStart: (_) => _setLongPressSpeed(true),
        onLongPressEnd: (_) => _setLongPressSpeed(false),
        onLongPressCancel: () => _setLongPressSpeed(false),
        onHorizontalDragStart: _startDragSeek,
        onHorizontalDragUpdate: _updateDragSeek,
        onHorizontalDragEnd: (_) => _finishDragSeek(),
        onHorizontalDragCancel: _finishDragSeek,
        onVerticalDragUpdate: (details) => _handleVerticalSlide(
            details, MediaQuery.sizeOf(context).width, videoHeight),
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
                                  color: Colors.white)
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 24),
                                      child: Text(
                                        _error!,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 13,
                                            height: 1.4),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                          backgroundColor: Colors.white24,
                                          foregroundColor: Colors.white),
                                      onPressed: selected == null
                                          ? null
                                          : () => _select(selected),
                                      icon: const Icon(Icons.refresh_rounded),
                                      label: const Text('点击重试'),
                                    ),
                                    const SizedBox(height: 10),
                                    TextButton.icon(
                                      style: TextButton.styleFrom(
                                          foregroundColor: Colors.white70),
                                      onPressed: () => Navigator.of(context)
                                          .push(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              const NetworkDiagnosticsPage(),
                                        ),
                                      ),
                                      icon: const Icon(
                                          Icons.network_check_rounded,
                                          size: 18),
                                      label: const Text('网络诊断'),
                                    ),
                                  ],
                                ),
                        )
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            if (!_hasStarted && widget.coverUrl.isNotEmpty)
                              Image.network(widget.coverUrl,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                  errorBuilder: (_, __, ___) =>
                                      VideoPlayer(player))
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
                                Color(0xaa000000)
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
                                          Icons.arrow_back_rounded),
                                    ),
                                    // 仅竖屏显示：一键回到首页，
                                    // 避免连续打开多个详情页时需要反复返回。
                                    if (MediaQuery.orientationOf(context) ==
                                        Orientation.portrait)
                                      IconButton(
                                        color: Colors.white,
                                        tooltip: '返回首页',
                                        onPressed: () => Navigator.of(context,
                                                rootNavigator: true)
                                            .popUntil(
                                                (route) => route.isFirst),
                                        icon: const Icon(
                                            Icons.home_rounded),
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
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    PopupMenuButton<VideoQuality>(
                                      tooltip: '清晰度',
                                      initialValue: selected,
                                      onSelected: _select,
                                      itemBuilder: (context) => widget
                                          .qualities
                                          .where((quality) =>
                                              quality.part == selected?.part)
                                          .map((quality) => PopupMenuItem(
                                                value: quality,
                                                child: Text(
                                                    _qualityDisplayLabel(
                                                        quality)),
                                              ))
                                          .toList(),
                                      icon: const Icon(Icons.hd_rounded,
                                          color: Colors.white),
                                    ),
                                    IconButton(
                                      color: Colors.white,
                                      tooltip: '播放器设置',
                                      onPressed: () => setState(() =>
                                          _showPlaybackOptions =
                                              !_showPlaybackOptions),
                                      icon:
                                          const Icon(Icons.settings_rounded),
                                    ),
                                  ],
                                ),
                              ),
                              Center(
                                child: _isSeeking || player.value.isBuffering
                                    ? const CircularProgressIndicator(
                                        color: Colors.white)
                                    : IconButton.filledTonal(
                                        style: IconButton.styleFrom(
                                          backgroundColor: Colors.black54,
                                          foregroundColor: Colors.white,
                                        ),
                                        iconSize: 48,
                                        onPressed: () async {
                                          if (!_hasStarted) {
                                            setState(() => _hasStarted = true);
                                          }
                                          if (player.value.isPlaying) {
                                            await MfunsPlaybackCoordinator
                                                .instance
                                                .requestPause();
                                          } else {
                                            await MfunsPlaybackCoordinator
                                                .instance
                                                .requestPlay();
                                          }
                                          if (mounted) setState(() {});
                                          _scheduleControlsHide();
                                        },
                                        icon: Icon(player.value.isPlaying
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded),
                                      ),
                              ),
                              if (_showPlaybackOptions)
                                Positioned(
                                  right: 12,
                                  bottom: 48 + bottomInset,
                                  child: _FullscreenOptionsPanel(
                                    volume: _volume,
                                    speed: _playbackSpeed,
                                    onVolumeChanged: (next) async {
                                      setState(() => _volume = next);
                                      await _player?.setVolume(next);
                                    },
                                    onSpeedChanged: (next) async {
                                      setState(() => _playbackSpeed = next);
                                      await _player
                                          ?.setPlaybackSpeed(next);
                                    },
                                    defaultQuality: _qualityPreference,
                                    availableQualities: widget.qualities
                                        .map(_qualityDisplayLabel)
                                        .toSet()
                                        .toList(growable: false),
                                    onDefaultQualityChanged: (label) {
                                      setState(
                                          () => _qualityPreference = label);
                                      UserPreferences
                                          .saveDefaultQuality(label);
                                    },
                                    autoPlay: _autoPlay,
                                    onAutoPlayChanged: (value) {
                                      setState(() => _autoPlay = value);
                                      UserPreferences.saveAutoPlay(value);
                                    },
                                  ),
                                ),
                              Positioned(
                                left: 8,
                                right: 8,
                                bottom: 3 + bottomInset,
                                child: Row(
                                  children: [
                                    Text(_formatDuration(position),
                                        style: const TextStyle(
                                            color: Colors.white,
                                              fontSize: 11)),
                                      Expanded(
                                        child: SliderTheme(
                                          data:
                                              SliderTheme.of(context).copyWith(
                                            trackHeight: 2,
                                            thumbShape:
                                                const RoundSliderThumbShape(
                                                    enabledThumbRadius: 5),
                                          ),
                                          child: Slider(
                                            activeColor: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                            inactiveColor: Colors.white38,
                                            value: duration.inMilliseconds == 0
                                                ? 0
                                                : position.inMilliseconds
                                                    .clamp(0,
                                                        duration.inMilliseconds)
                                                    .toDouble(),
                                            max: duration.inMilliseconds == 0
                                                ? 1
                                                : duration.inMilliseconds
                                                    .toDouble(),
                                            onChanged: (milliseconds) {
                                              player.seekTo(Duration(
                                                  milliseconds:
                                                      milliseconds.round()));
                                              _scheduleControlsHide();
                                            },
                                            onChangeStart: (_) =>
                                                setState(() => _isSeeking = true),
                                            onChangeEnd: (_) =>
                                                setState(() => _isSeeking = false),
                                          ),
                                        ),
                                      ),
                                      Text(_formatDuration(duration),
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11)),
                                      IconButton(
                                        color: Colors.white,
                                        tooltip: '全屏',
                                        onPressed: _openFullscreen,
                                        icon: const Icon(
                                            Icons.fullscreen_rounded),
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
                      // 位于中央播放/暂停按钮下方，避免重叠。
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
                                  horizontal: 14, vertical: 8),
                              child: Text(_seekNotice!,
                                  style:
                                      const TextStyle(color: Colors.white)),
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
                                horizontal: 14, vertical: 8),
                            child: Text('2.0× 倍速播放',
                                style: TextStyle(color: Colors.white)),
                          ),
                        ),
                      ),
                    if (_slideFeedback != null)
                      IgnorePointer(
                        child:
                            _VerticalSlideFeedback(feedback: _slideFeedback!),
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

  @override
  State<_FullscreenVideoOverlay> createState() =>
      _FullscreenVideoOverlayState();
}

/// 桌面端支持窗口级全屏（Windows/macOS/Linux），移动端与 Web 不适用。
final bool _isDesktop = !kIsWeb &&
    (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

class _FullscreenVideoOverlayState extends State<_FullscreenVideoOverlay> {
  var _controlsVisible = true;
  late bool _showDanmaku;
  late double _volume;
  var _brightness = .5;
  var _brightnessAvailable = true;
  late double _playbackSpeed;
  late VideoPlayerController _player;
  late VideoQuality? _selectedQuality;
  late List<DanmakuItem> _danmaku;
  var _showOptions = false;
  var _showDanmakuComposer = false;
  var _switchingQuality = false;
  double _doubleTapX = 0;
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

  @override
  void initState() {
    super.initState();
    _showDanmaku = widget.showDanmaku;
    _volume = widget.volume;
    _playbackSpeed = widget.playbackSpeed;
    _player = widget.player;
    _selectedQuality = widget.selectedQuality;
    _danmaku = widget.danmaku;
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
    if (_switchingQuality) return;
    // App 在后台时不创建新播放器（音频已交接给后台引擎）。
    if (MfunsPlaybackCoordinator.instance.phase.isBackground) return;
    final value = _player.value;
    if (value.duration <= Duration.zero) return;
    if (value.isPlaying) return;
    if (value.position < value.duration) return;
    final selected = _selectedQuality;
    if (selected == null) return;
    final next =
        _matchingPartQuality(widget.qualities, selected, selected.part + 1);
    if (next == null) return;
    await _selectQuality(next);
    if (mounted && !_player.value.isPlaying) {
      await MfunsPlaybackCoordinator.instance.requestPlay();
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _player.value.isPlaying) {
        setState(() => _controlsVisible = false);
      }
    });
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
      DragUpdateDetails details, double width, double height) {
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
        _seekNotice =
            '${seconds > 0 ? '+' : ''}$seconds 秒';
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
    final target = _dragSeekBase +
        Duration(
            milliseconds:
                (deltaDx / width * duration.inMilliseconds).round());
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
          onTap: () {
            setState(() => _controlsVisible = !_controlsVisible);
            if (_controlsVisible) _scheduleHide();
          },
          onDoubleTapDown: (details) => _doubleTapX = details.localPosition.dx,
          onDoubleTap: () {
            final width = MediaQuery.sizeOf(context).width;
            _seekBy(_doubleTapX < width / 2 ? -10 : 10);
          },
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
              MediaQuery.sizeOf(context).height),
          onVerticalDragEnd: (_) => _clearSlideFeedback(),
          onVerticalDragCancel: _clearSlideFeedback,
          child: _switchingQuality
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
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
                                    Color(0xaa000000)
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
                                                Icons.arrow_back_rounded),
                                            onPressed: _close,
                                          ),
                                          Expanded(
                                            child: Text(widget.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight:
                                                        FontWeight.w600)),
                                          ),
                                          IconButton(
                                            color: Colors.white,
                                            tooltip:
                                                _showDanmaku ? '关闭弹幕' : '打开弹幕',
                                            onPressed: () => setState(() =>
                                                _showDanmaku = !_showDanmaku),
                                            icon: Icon(_showDanmaku
                                                ? Icons.subtitles_rounded
                                                : Icons.subtitles_off_rounded),
                                          ),
                                          TextButton(
                                            onPressed: () => setState(() {
                                              _showOptions = false;
                                              _showDanmakuComposer =
                                                  !_showDanmakuComposer;
                                            }),
                                            style: TextButton.styleFrom(
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8),
                                            ),
                                            child: Text(_showDanmakuComposer
                                                ? '收起'
                                                : '发弹幕'),
                                          ),
                                          IconButton(
                                            color: Colors.white,
                                            tooltip: '播放器设置',
                                            onPressed: () => setState(() {
                                              _showDanmakuComposer = false;
                                              _showOptions = !_showOptions;
                                            }),
                                            icon: const Icon(
                                                Icons.settings_rounded),
                                          ),
                                          PopupMenuButton<int>(
                                            tooltip: '分 P',
                                            initialValue:
                                                _selectedQuality?.part,
                                            onSelected: (part) {
                                              final next = _matchingPartQuality(
                                                  widget.qualities,
                                                  _selectedQuality,
                                                  part);
                                              if (next != null) {
                                                _queueQualitySelect(next);
                                              }
                                            },
                                            itemBuilder: (context) {
                                              final parts = widget.qualities
                                                  .map(
                                                      (quality) => quality.part)
                                                  .toSet()
                                                  .toList()
                                                ..sort();
                                              return parts
                                                  .map((part) => PopupMenuItem(
                                                        value: part,
                                                        child: Text('P$part'),
                                                      ))
                                                  .toList();
                                            },
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 9,
                                                      vertical: 8),
                                              child: Text(
                                                'P${_selectedQuality?.part ?? 1}',
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight:
                                                        FontWeight.w800),
                                              ),
                                            ),
                                          ),
                                          PopupMenuButton<VideoQuality>(
                                            tooltip: '清晰度',
                                            initialValue: _selectedQuality,
                                            onSelected: _queueQualitySelect,
                                            itemBuilder: (context) => widget
                                                .qualities
                                                .where((quality) =>
                                                    quality.part ==
                                                    _selectedQuality?.part)
                                                .map((quality) => PopupMenuItem(
                                                      value: quality,
                                                      child: Text(
                                                        _qualityDisplayLabel(
                                                            quality),
                                                      ),
                                                    ))
                                                .toList(),
                                            icon: const Icon(Icons.hd_rounded,
                                                color: Colors.white),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (_showOptions && !_showDanmakuComposer)
                                    Positioned(
                                      top: 58,
                                      right: 16,
                                      child: _FullscreenOptionsPanel(
                                        volume: _volume,
                                        speed: _playbackSpeed,
                                        onVolumeChanged: (next) async {
                                          setState(() => _volume = next);
                                          await _player.setVolume(next);
                                        },
                                        onSpeedChanged: (next) async {
                                          setState(() => _playbackSpeed = next);
                                          await _player
                                              .setPlaybackSpeed(next);
                                        },
                                        defaultQuality:
                                            widget.defaultQuality,
                                        availableQualities: widget.qualities
                                            .map(_qualityDisplayLabel)
                                            .toSet()
                                            .toList(growable: false),
                                        onDefaultQualityChanged: (label) =>
                                            UserPreferences
                                                .saveDefaultQuality(label),
                                        autoPlay: widget.autoPlay,
                                        onAutoPlayChanged: (value) =>
                                            UserPreferences
                                                .saveAutoPlay(value),
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
                                                maxLength: 100,
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 13),
                                                onSubmitted: (_) =>
                                                    _sendDanmaku(),
                                                decoration:
                                                    const InputDecoration(
                                                  isDense: true,
                                                  counterText: '',
                                                  hintText: '发个弹幕…',
                                                  hintStyle: TextStyle(
                                                      color: Colors.white54),
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
                                  Center(
                                    child: _isSeeking || value.isBuffering
                                        ? const CircularProgressIndicator(
                                            color: Colors.white)
                                        : IconButton.filledTonal(
                                            style: IconButton.styleFrom(
                                              backgroundColor: Colors.black54,
                                              foregroundColor: Colors.white,
                                            ),
                                            iconSize: 54,
                                            onPressed: () async {
                                              if (value.isPlaying) {
                                                await MfunsPlaybackCoordinator
                                                    .instance
                                                    .requestPause();
                                              } else {
                                                await MfunsPlaybackCoordinator
                                                    .instance
                                                    .requestPlay();
                                              }
                                              _scheduleHide();
                                            },
                                            icon: Icon(value.isPlaying
                                                ? Icons.pause_rounded
                                                : Icons.play_arrow_rounded),
                                          ),
                                  ),
                                  Positioned(
                                    left: 12,
                                    right: 12,
                                    bottom: 4,
                                    child: SafeArea(
                                      top: false,
                                      child: Row(
                                        children: [
                                          Text(_formatDuration(position),
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11)),
                                          Expanded(
                                            child: Slider(
                                              activeColor: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                              inactiveColor: Colors.white38,
                                              value: duration.inMilliseconds ==
                                                      0
                                                  ? 0
                                                  : position.inMilliseconds
                                                      .clamp(
                                                          0,
                                                          duration
                                                              .inMilliseconds)
                                                      .toDouble(),
                                              max: duration.inMilliseconds == 0
                                                  ? 1
                                                  : duration.inMilliseconds
                                                      .toDouble(),
                                              onChanged: (milliseconds) {
                                                _player.seekTo(Duration(
                                                    milliseconds:
                                                        milliseconds.round()));
                                                _scheduleHide();
                                              },
                                              onChangeStart: (_) => setState(
                                                  () => _isSeeking = true),
                                              onChangeEnd: (_) => setState(
                                                  () => _isSeeking = false),
                                            ),
                                          ),
                                          Text(_formatDuration(duration),
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11)),
                                          IconButton(
                                            color: Colors.white,
                                            icon: const Icon(
                                                Icons.fullscreen_exit_rounded),
                                            onPressed: _close,
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
                                feedback: _slideFeedback!),
                          ),
                        if (_seekNotice != null && _controlsVisible)
                          // 位于中央播放/暂停按钮下方，避免重叠。
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
                                      horizontal: 14, vertical: 8),
                                  child: Text(_seekNotice!,
                                      style: const TextStyle(
                                          color: Colors.white)),
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
                                    horizontal: 14, vertical: 8),
                                child: Text('2.0× 倍速播放',
                                    style: TextStyle(color: Colors.white)),
                              ),
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
                      color: Colors.white, fontWeight: FontWeight.w700),
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
  final sameQuality = choices.where((quality) =>
      quality.name == current?.name && quality.label == current?.label);
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

class _FullscreenOptionsPanel extends StatelessWidget {
  const _FullscreenOptionsPanel({
    required this.volume,
    required this.speed,
    required this.onVolumeChanged,
    required this.onSpeedChanged,
    this.defaultQuality = '',
    this.availableQualities = const [],
    this.onDefaultQualityChanged,
    this.autoPlay = true,
    this.onAutoPlayChanged,
  });

  final double volume;
  final double speed;
  final ValueChanged<double> onVolumeChanged;
  final ValueChanged<double> onSpeedChanged;
  final String defaultQuality;
  final List<String> availableQualities;
  final ValueChanged<String>? onDefaultQualityChanged;
  final bool autoPlay;
  final ValueChanged<bool>? onAutoPlayChanged;

  String _qualityLabel(String value) => value.isEmpty ? '自动' : value;

  @override
  Widget build(BuildContext context) => Container(
        width: 248,
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: BoxDecoration(
          color: const Color(0xee1d1d23),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.volume_up_rounded,
                    color: Colors.white, size: 19),
                Expanded(
                  child: Slider(
                    activeColor: Theme.of(context).colorScheme.primary,
                    inactiveColor: Colors.white38,
                    value: volume,
                    onChanged: onVolumeChanged,
                  ),
                ),
                PopupMenuButton<double>(
                  initialValue: speed,
                  onSelected: onSpeedChanged,
                  itemBuilder: (context) => [
                    for (final option in [.5, .75, 1.0, 1.25, 1.5, 2.0])
                      PopupMenuItem(value: option, child: Text('${option}x')),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text('${speed}x',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
            if (availableQualities.isNotEmpty) ...[
              const Divider(color: Colors.white24, height: 1),
              Row(
                children: [
                  const Icon(Icons.high_quality_outlined,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('默认清晰度',
                        style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                  PopupMenuButton<String>(
                    initialValue: defaultQuality,
                    onSelected: onDefaultQualityChanged ?? (_) {},
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: '', child: Text('自动')),
                      for (final label in availableQualities)
                        PopupMenuItem(value: label, child: Text(label)),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(_qualityLabel(defaultQuality),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
            const Divider(color: Colors.white24, height: 1),
            Row(
              children: [
                const Icon(Icons.play_circle_outline_rounded,
                    color: Colors.white, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('打开视频自动播放',
                      style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
                Switch(
                  value: autoPlay,
                  onChanged: onAutoPlayChanged ?? (_) {},
                ),
              ],
            ),
          ],
        ),
      );
}

/// 滚动弹幕画布：每条弹幕用独立 AnimationController 从右向左平滑划过
/// 全屏宽度，多轨道并行；动画不依赖父级 350ms 的定时重建，避免卡顿。
class _DanmakuCanvas extends StatefulWidget {
  const _DanmakuCanvas({
    required this.items,
    this.opacity = 1,
    this.size = 20,
  });

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
            milliseconds:
                ((textWidth + 400) / _pixelsPerSecond * 1000).round(),
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
    final scrollEntries =
        _entries.where((e) => e.item.type != 4 && e.item.type != 5).toList();
    final topEntries =
        _entries.where((e) => e.item.type == 5).toList(growable: false);
    final bottomEntries =
        _entries.where((e) => e.item.type == 4).toList(growable: false);

    Widget textOf(_DanmakuEntry entry) {
      final item = entry.item;
      final color =
          Color(0xff000000 | (item.color & 0xffffff)).withOpacity(widget.opacity);
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
                      left: screenWidth -
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
                        padding:
                            EdgeInsets.only(bottom: 8.0 + i * _laneHeight),
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
Future<CommentSpan?> _askMentionUser(BuildContext context, AppController controller) =>
    showDialog<CommentSpan>(
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
    _debounce = Timer(const Duration(milliseconds: 400), () => _runSearch(value));
  }

  void _pick(UserProfile user) => Navigator.of(context)
      .pop(CommentSpan.mention('${user.id}', user.name));

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
            backgroundColor:
                Theme.of(context).colorScheme.primary.withOpacity(.12),
            foregroundImage:
                user.avatar.isEmpty ? null : NetworkImage(user.avatar),
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
  const _CommentSection({required this.controller, required this.areaId});

  final AppController controller;
  final int areaId;

  @override
  State<_CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends State<_CommentSection> {
  late Future<List<CommunityComment>> _comments;
  final _inputKey = GlobalKey<InlineEmojiInputState>();
  var _isSending = false;

  @override
  void initState() {
    super.initState();
    _comments = widget.controller.comments(widget.areaId);
  }

  void _reload() =>
      setState(() => _comments = widget.controller.comments(widget.areaId));

  /// 点击 @ 弹出用户搜索弹窗，把选中的用户以 `[@id:用户名]` 标记插入输入框。
  Future<void> _pickMention() async {
    final mention = await _askMentionUser(context, widget.controller);
    if (mention == null) return;
    _inputKey.currentState
        ?.addMention(mention.mentionName, id: mention.mentionId);
  }

  Future<void> _submit() async {
    final input = _inputKey.currentState;
    if (input == null || input.isEmpty || _isSending) return;
    if (widget.controller.session == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先在“我的”页面登录后再发表评论')));
      return;
    }
    final spans = input.spans;
    final images = input.images;
    setState(() => _isSending = true);
    try {
      await widget.controller.createComment(
          areaId: widget.areaId, spans: spans, images: images);
      input.clear();
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('评论已发布')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('发布失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

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
                onPressed: _reload,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          InlineEmojiInput(
            key: _inputKey,
            hintText: '说点什么…',
            onUploadImage: widget.controller.uploadImage,
            onSearchUser: widget.controller.searchUsers,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              IconButton(
                tooltip: '添加图片',
                onPressed: () => _inputKey.currentState?.pickImage(),
                icon: Icon(
                  Icons.image_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 2),
              IconButton(
                tooltip: '@ 用户',
                onPressed: _pickMention,
                icon: Icon(
                  Icons.alternate_email,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 2),
              IconButton(
                tooltip: '表情包',
                onPressed: () => _inputKey.currentState?.pickEmoji(),
                icon: Icon(
                  Icons.emoji_emotions_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _isSending ? null : _submit,
                child: _isSending
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('发布'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<CommunityComment>>(
            future: _comments,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const _InlineLoading(label: '正在加载评论');
              }
              if (snapshot.hasError) {
                return Text('评论加载失败：${snapshot.error}');
              }
              final comments = snapshot.data ?? const <CommunityComment>[];
              if (comments.isEmpty) return const Text('暂无评论，来抢沙发吧');
              return Column(
                children: comments
                    .map((comment) => _CommentCard(
                          controller: widget.controller,
                          comment: comment,
                          onDeleted: _reload,
                        ))
                    .toList(),
              );
            },
          ),
        ],
      );
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
  });

  final AppController controller;
  final CommunityComment comment;
  final VoidCallback? onDeleted;

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
    _inputKey.currentState
        ?.addMention(mention.mentionName, id: mention.mentionId);
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
        title: const Text('回复评论'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: InlineEmojiInput(
                    key: _inputKey,
                    hintText: '友善交流，理性发言',
                    fontSize: 14,
                    initialText: widget.initialText,
                    onSearchUser: widget.controller.searchUsers,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: '@ 用户',
                  onPressed: _pickMention,
                  icon: Icon(
                    Icons.alternate_email,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                IconButton(
                  tooltip: '表情包',
                  onPressed: () => _inputKey.currentState?.pickEmoji(),
                  icon: Icon(
                    Icons.emoji_emotions_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _isSending ? null : () => Navigator.of(context).pop(),
            child: const Text('取消'),
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先在“我的”页面登录后再点赞')));
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
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) =>
            UserProfilePage(controller: widget.controller, userId: userId)));
  }

  Future<void> _loadReplies() async {
    setState(() => _repliesLoading = true);
    try {
      final list = await widget.controller.commentReplies(widget.comment.id);
      if (!mounted) return;
      setState(() {
        _replies = list;
        _repliesLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _repliesLoading = false);
    }
  }

  /// 展开/收起二级评论列表。
  void _toggleReplies() {
    if (_replies != null) {
      setState(() => _replies = null);
      return;
    }
    _loadReplies();
  }

  /// 打开回复编辑器；[mention] 非空时代表“回复 @xxx”的二级回复，会预填 @名 前缀。
  void _showReplyComposer({String? mention}) {
    if (widget.controller.session == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先在“我的”页面登录后再回复')));
      return;
    }
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _CommentReplyDialog(
        controller: widget.controller,
        initialText: mention == null ? '' : '@$mention ',
        onSubmit: (spans) => widget.controller.createCommentReply(
          commentId: widget.comment.id,
          spans: spans,
        ),
        onSuccess: () {
          if (!mounted) return;
          setState(() => _replyDelta++);
          _loadReplies();
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('回复已发布')));
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
                await Clipboard.setData(
                    ClipboardData(text: comment.content));
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('评论已复制')));
                }
              },
            ),
            if (isMine)
              ListTile(
                leading: Icon(Icons.delete_outline_rounded,
                    color: Theme.of(sheetContext).colorScheme.error),
                title: Text('删除评论',
                    style: TextStyle(
                        color: Theme.of(sheetContext).colorScheme.error)),
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
    final comment = widget.comment;
    final myId = widget.controller.session?.userId;
    if (myId == null || comment.userId != myId) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('只能删除自己的评论')));
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('评论已删除')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
    }
  }

  Widget _userRow(BuildContext context, {
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
            child: Text(letter,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: InkWell(
            onTap: userId == 0 ? null : () => _openUser(context),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
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
              _buildUserHeader(context),
            const SizedBox(height: 6),
            comment.spans.isEmpty
                ? Text(comment.content.isEmpty
                    ? '（该评论没有文本内容）'
                    : comment.content)
                : _CommentSpans(
                    spans: comment.spans,
                    onLinkTap: (url) => openContentLink(
                        context, widget.controller, url),
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
                            tag:
                                'comment-image-${comment.id}-$index-$uri',
                            child: Image.network(
                              comment.images[index],
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const ColoredBox(
                                color: Color(0xffefeff7),
                                child: Icon(Icons.broken_image_outlined,
                                    color: Colors.blueGrey),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
                              : Colors.blueGrey,
                        ),
                        const SizedBox(width: 4),
                        Text('$_likes 赞',
                            style: Theme.of(context).textTheme.bodySmall),
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
                  Text(_formatDate(comment.createdAt!),
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            if (_replies != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xfff4f5fa),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    if (_repliesLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: LinearProgressIndicator(),
                      ),
                    if (_replies!.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('暂无回复',
                            style: TextStyle(
                                color: Colors.blueGrey, fontSize: 12.5)),
                      )
                    else
                      ..._replies!.map((reply) => _CommentReplyTile(
                            controller: widget.controller,
                            rootCommentId: widget.comment.id,
                            reply: reply,
                            onReply: (name) =>
                                _showReplyComposer(mention: name),
                            onDeleted: () {
                              if (!mounted) return;
                              setState(() {
                                _replies?.removeWhere(
                                    (item) => item.id == reply.id);
                                _replyDelta--;
                              });
                            },
                          )),
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

/// 二级评论（回复）：头像 + 昵称 + 内容 + 点赞/回复/删除操作，长按可复制或删除。
class _CommentReplyTile extends StatefulWidget {
  const _CommentReplyTile({
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
  final void Function(String userName)? onReply;

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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先在“我的”页面登录后再点赞')));
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
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => UserProfilePage(
            controller: widget.controller, userId: userId)));
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
                await Clipboard.setData(
                    ClipboardData(text: reply.content));
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('回复已复制')));
                }
              },
            ),
            if (isMine)
              ListTile(
                leading: Icon(Icons.delete_outline_rounded,
                    color: Theme.of(sheetContext).colorScheme.error),
                title: Text('删除回复',
                    style: TextStyle(
                        color: Theme.of(sheetContext).colorScheme.error)),
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('只能删除自己的回复')));
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('回复已删除')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final reply = widget.reply;
    final name =
        reply.authorName.isEmpty ? '用户 ${reply.userId}' : reply.authorName;
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
                backgroundColor:
                    Theme.of(context).colorScheme.primaryContainer,
                foregroundImage:
                    reply.avatar.isEmpty ? null : NetworkImage(reply.avatar),
                child: Text(letter,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
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
                            child: Text(name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                      if (reply.createdAt != null)
                        Text(_formatDate(reply.createdAt!),
                            style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                  const SizedBox(height: 2),
                  if (reply.spans.isEmpty)
                    Text(
                      reply.content.isEmpty ? '（该回复没有文本内容）' : reply.content,
                      style: const TextStyle(
                          color: Colors.blueGrey,
                          fontSize: 13.5,
                          height: 1.4),
                    )
                  else
                    ContentSpans(
                      spans: reply.spans,
                      textStyle: const TextStyle(
                          color: Colors.blueGrey, fontSize: 13.5, height: 1.4),
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
                              horizontal: 4, vertical: 2),
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
                                    : Colors.blueGrey,
                              ),
                              const SizedBox(width: 3),
                              Text('$_likes',
                                  style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => widget.onReply?.call(name),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          child: Text('回复',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary)),
                        ),
                      ),
                      if (isMine) ...[
                        const SizedBox(width: 12),
                        InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: _confirmDelete,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            child: Icon(Icons.delete_outline_rounded,
                                size: 15,
                                color: Theme.of(context).colorScheme.error),
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
