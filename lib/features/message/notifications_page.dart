import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../home/home_repository.dart';
import '../user/user_profile_page.dart';
import '../video/content_detail_page.dart';

const _notifyTypes = <int, String>{
  1: '赞',
  2: '评论',
  3: '提及',
  4: '系统',
};

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({
    super.key,
    required this.controller,
    this.embedded = false,
  });

  final AppController controller;
  final bool embedded;

  @override
  State<NotificationsPage> createState() => NotificationsPageState();
}

class NotificationsPageState extends State<NotificationsPage>
    with SingleTickerProviderStateMixin {
  static final Map<int, UserProfile> _userCache = {};
  late final TabController _notifyTabs;

  @override
  void initState() {
    super.initState();
    _notifyTabs = TabController(length: _notifyTypes.length, vsync: this);
    widget.controller.notifySubTabRequest.addListener(_onNotifyTabRequest);
    // 页面懒加载，晚于通知点击跳转请求构建时，补应用目标子标签。
    if (widget.controller.consumeNotifySubTab()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onNotifyTabRequest();
      });
    }
  }

  @override
  void dispose() {
    widget.controller.notifySubTabRequest.removeListener(_onNotifyTabRequest);
    _notifyTabs.dispose();
    super.dispose();
  }

  /// 通知点击跳转：切到赞/评论/提及对应子标签（消费一次性请求）。
  void _onNotifyTabRequest() {
    widget.controller.consumeNotifySubTab();
    final value = widget.controller.notifySubTabRequest.value;
    if (value != _notifyTabs.index) _notifyTabs.animateTo(value);
  }

  /// 刷新未读明细（与红点同一数据源，保持同步）。
  Future<void> reload() => widget.controller.refreshUnreadCounts();

  void _openUser(BuildContext context, int userId) {
    if (userId == 0) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) =>
            UserProfilePage(controller: widget.controller, userId: userId)));
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody(context);
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('消息通知'), centerTitle: true),
      body: body,
    );
  }

  Widget _buildBody(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      children: [
        // 未读明细直接读取 controller（与小红点同一数据源，保持同步）。
        ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final counts = widget.controller.notifyCountsData;
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Text('未读',
                      style: TextStyle(
                          color: palette.primary, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '赞 ${counts.like} · 评论 ${counts.comment} · 提及 ${counts.mention} · 系统 ${counts.system}',
                      style: TextStyle(
                          color: AppPalette.of(context).muted, fontSize: 13),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        TabBar(
          controller: _notifyTabs,
          labelColor: palette.primary,
          unselectedLabelColor: AppPalette.of(context).muted,
          tabs: _notifyTypes.entries
              .map((entry) => Tab(text: entry.value))
              .toList(growable: false),
        ),
        Expanded(
          child: TabBarView(
            controller: _notifyTabs,
            children: _notifyTypes.entries.map((entry) {
              // 系统通知走独立的 /v1/notify/site 接口，卡片样式也不同。
              if (entry.key == 4) {
                return _SystemNotifyTab(controller: widget.controller);
              }
              return _NotifyTab(
                controller: widget.controller,
                type: entry.key,
                onOpenUser: (userId) => _openUser(context, userId),
                userCache: _userCache,
              );
            }).toList(growable: false),
          ),
        ),
      ],
    );
  }
}

class _NotifyTab extends StatelessWidget {
  const _NotifyTab({
    required this.controller,
    required this.type,
    required this.onOpenUser,
    required this.userCache,
  });

  final AppController controller;
  final int type;
  final ValueChanged<int> onOpenUser;
  final Map<int, UserProfile> userCache;

  @override
  Widget build(BuildContext context) => _PagedNotifyListView(
        loadPage: (page) => controller.notifications(type: type, page: page),
        onLoaded: controller.refreshUnreadCounts,
        emptyMessage: '暂无此类通知',
        itemBuilder: (context, item) => _NotifyCard(
          item: item,
          controller: controller,
          userCache: userCache,
          onOpenUser: onOpenUser,
        ),
      );
}

class _NotifyEmpty extends StatelessWidget {
  const _NotifyEmpty({required this.onRetry, this.message = '暂无此类通知'});

  final VoidCallback onRetry;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_off_outlined,
                color: AppPalette.of(context).muted, size: 42),
            const SizedBox(height: 10),
            Text(message,
                style: TextStyle(color: AppPalette.of(context).muted)),
            const SizedBox(height: 6),
            TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('刷新')),
          ],
        ),
      );
}

/// 系统通知（站点公告等）：独立接口 `/v1/notify/site`，
/// 卡片只展示系统图标、正文与时间，无发送者、不跳转原内容。
class _SystemNotifyTab extends StatelessWidget {
  const _SystemNotifyTab({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => _PagedNotifyListView(
        loadPage: (page) => controller.siteNotifications(page: page),
        onLoaded: controller.refreshUnreadCounts,
        emptyMessage: '暂无系统通知',
        itemBuilder: (context, item) => _SystemNotifyCard(item: item),
      );
}

/// 通知类列表（赞/评论/提及/系统）的分页加载：
/// 按页拉取、滚动到底自动加载下一页，首屏带下拉刷新。
class _PagedNotifyListView extends StatefulWidget {
  const _PagedNotifyListView({
    required this.loadPage,
    required this.onLoaded,
    required this.itemBuilder,
    this.emptyMessage = '暂无此类通知',
  });

  final Future<List<NotifyItem>> Function(int page) loadPage;

  /// 首屏（或刷新）加载完成后回调，用于同步刷新未读与小红点。
  final VoidCallback onLoaded;

  final Widget Function(BuildContext context, NotifyItem item) itemBuilder;
  final String emptyMessage;

  @override
  State<_PagedNotifyListView> createState() => _PagedNotifyListViewState();
}

class _PagedNotifyListViewState extends State<_PagedNotifyListView> {
  final _scrollController = ScrollController();
  List<NotifyItem> _items = const [];
  var _page = 1;
  var _hasMore = true;
  var _isLoadingMore = false;
  var _initialLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadFirst();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 滚动到底部附近时加载下一页。
  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadFirst() async {
    setState(() {
      _initialLoading = true;
      _error = null;
      _items = const [];
      _page = 1;
      _hasMore = true;
    });
    try {
      final items = await widget.loadPage(1);
      if (!mounted) return;
      setState(() {
        _items = items;
        // 返回条数不足一页即认为没有更多。
        _hasMore = items.length >= messagePageSize;
        _initialLoading = false;
      });
      widget.onLoaded();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _initialLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _items.isEmpty) return;
    setState(() => _isLoadingMore = true);
    try {
      final next = await widget.loadPage(_page + 1);
      if (!mounted) return;
      setState(() {
        final known = _items.map(_notifyKey).toSet();
        final additions = next
            .where((item) => known.add(_notifyKey(item)))
            .toList(growable: false);
        _items = [..._items, ...additions];
        _page++;
        _hasMore = next.isNotEmpty && additions.isNotEmpty;
        _isLoadingMore = false;
      });
    } catch (_) {
      // 滚动到底可再次触发加载。
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  /// 通知项没有唯一 id，用发送者/评论/资源/时间组合去重。
  static String _notifyKey(NotifyItem item) =>
      '${item.senderUserId}|${item.commentId}|${item.resourceId}|${item.createdAt?.millisecondsSinceEpoch}';

  @override
  Widget build(BuildContext context) {
    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('加载失败：$_error',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppPalette.of(context).muted)),
              const SizedBox(height: 10),
              TextButton.icon(
                  onPressed: _loadFirst,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return _NotifyEmpty(onRetry: _loadFirst, message: widget.emptyMessage);
    }
    return RefreshIndicator(
      color: AppPalette.of(context).primary,
      onRefresh: _loadFirst,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        itemCount: _items.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            return _NotifyLoadMoreFooter(
              loading: _isLoadingMore,
              hasMore: _hasMore,
            );
          }
          return widget.itemBuilder(context, _items[index]);
        },
      ),
    );
  }
}

class _NotifyLoadMoreFooter extends StatelessWidget {
  const _NotifyLoadMoreFooter({required this.loading, required this.hasMore});

  final bool loading;
  final bool hasMore;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }
    if (!hasMore) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text('没有更多了',
              style: TextStyle(
                  color: AppPalette.of(context).muted, fontSize: 12)),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _SystemNotifyCard extends StatelessWidget {
  const _SystemNotifyCard({required this.item});

  final NotifyItem item;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: palette.primary.withOpacity(.12),
              foregroundColor: palette.primary,
              child: const Icon(Icons.campaign_outlined, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('系统通知',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: AppPalette.of(context).muted,
                                fontWeight: FontWeight.w800)),
                      ),
                      if (item.createdAt != null)
                        Text(_notifyTime(item.createdAt!),
                            style: TextStyle(
                                color: AppPalette.of(context).muted,
                                fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.text.isEmpty ? '（空通知）' : item.text,
                    style: TextStyle(
                        color: AppPalette.of(context).muted, height: 1.4),
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

class _NotifyCard extends StatefulWidget {
  const _NotifyCard({
    required this.item,
    required this.controller,
    required this.userCache,
    required this.onOpenUser,
  });

  final NotifyItem item;
  final AppController controller;
  final Map<int, UserProfile> userCache;
  final ValueChanged<int> onOpenUser;

  @override
  State<_NotifyCard> createState() => _NotifyCardState();
}

class _NotifyCardState extends State<_NotifyCard> {
  Future<UserProfile?>? _profile;
  var _openingReference = false;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    if (item.senderName.isEmpty && item.senderUserId != 0) {
      final cached = widget.userCache[item.senderUserId];
      _profile = cached != null
          ? Future.value(cached)
          : _loadProfile(item.senderUserId);
    }
  }

  Future<UserProfile?> _loadProfile(int userId) async {
    try {
      final profile = await widget.controller.userProfile(userId);
      widget.userCache[userId] = profile;
      return profile;
    } catch (_) {
      return null;
    }
  }

  bool get _canOpenReference =>
      widget.item.resourceId != null ||
      widget.item.commentId != null ||
      widget.item.areaId != null;

  /// Tapping the notification body opens the referenced article / video /
  /// feed. The resource is resolved from the comment id via the comment area
  /// when the payload does not carry it; the resolved type is validated
  /// before navigating and falls back across article / feed / video so a
  /// wrong mapping never opens a broken page.
  Future<void> _openReference() async {
    if (_openingReference) return;
    setState(() => _openingReference = true);
    try {
      final resolved = await _resolveResource();
      if (resolved == null || !mounted) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('无法定位原内容')));
        }
        return;
      }
      await _navigateToResource(resolved.$1, resolved.$2);
    } finally {
      if (mounted) setState(() => _openingReference = false);
    }
  }

  Future<(int, int)?> _resolveResource() async {
    final item = widget.item;
    // The payload carries the resource directly: `content_id`/`content_type`
    // (1 = video, 3 = article/feed, 4 = comment id).
    if (item.resourceId != null && item.resourceType != null) {
      if (item.resourceType == 4) {
        final viaResource = await _resolveComment(item.resourceId!);
        if (viaResource != null) return viaResource;
      } else {
        return (item.resourceId!, item.resourceType!);
      }
    }
    // Fall back to resolving the comment from notify_params.
    if (item.commentId != null) {
      final viaComment = await _resolveComment(item.commentId!);
      if (viaComment != null) return viaComment;
    }
    return null;
  }

  Future<(int, int)?> _resolveComment(int commentId) async {
    try {
      final info = await widget.controller.commentResource(commentId);
      if (info != null) return info;
    } catch (_) {
      // Fall through to the comment-area chain below.
    }
    try {
      final areaId = await widget.controller.commentAreaId(commentId);
      if (areaId != null) {
        return widget.controller.commentAreaInfo(areaId);
      }
    } catch (_) {}
    return null;
  }

  Future<void> _navigateToResource(int resourceId, int resourceType) async {
    final attempts = switch (resourceType) {
      1 => const [1, 0, 4], // video -> article -> feed
      4 => const [4, 0, 1], // feed -> article -> video
      _ => const [0, 4, 1], // article -> feed -> video
    };
    for (final type in attempts) {
      if (!mounted) return;
      final opened = await _tryOpen(type, resourceId);
      if (opened) return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('资源不存在或已删除')));
    }
  }

  Future<bool> _tryOpen(int type, int resourceId) async {
    try {
      if (type == 4) {
        await widget.controller.feedDetail(resourceId);
        if (!mounted) return false;
        await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => FeedDetailPage(
                controller: widget.controller, feedId: resourceId)));
        return true;
      }
      final preview = _minimalPreview(resourceId, type);
      await widget.controller.contentDetail(preview);
      if (!mounted) return false;
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ContentDetailPage(
              controller: widget.controller, preview: preview)));
      return true;
    } catch (_) {
      return false;
    }
  }

  ContentPreview _minimalPreview(int resourceId, int type) => ContentPreview(
        id: resourceId,
        title: '通知内容',
        summary: '',
        cover: '',
        author: '',
        category: '',
        type: type,
        likes: 0,
        comments: 0,
        views: 0,
      );

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final palette = AppPalette.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              customBorder: const CircleBorder(),
              onTap: item.senderUserId == 0
                  ? null
                  : () => widget.onOpenUser(item.senderUserId),
              child: FutureBuilder<UserProfile?>(
                future: _profile,
                builder: (context, snapshot) {
                  final profile = snapshot.data;
                  final name = item.senderName.isNotEmpty
                      ? item.senderName
                      : (profile?.name ?? '');
                  return CircleAvatar(
                    radius: 20,
                    backgroundColor: palette.primary.withOpacity(.12),
                    foregroundImage: (item.senderAvatar.isNotEmpty
                        ? NetworkImage(item.senderAvatar)
                        : (profile?.avatar.isEmpty ?? true)
                            ? null
                            : NetworkImage(profile!.avatar)),
                    foregroundColor: palette.primary,
                    child: Text(
                      name.isNotEmpty
                          ? name.substring(0, 1)
                          : item.senderUserId == 0
                              ? 'U'
                              : '${item.senderUserId}'.substring(0, 1),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: _canOpenReference ? _openReference : null,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: item.senderUserId == 0
                                  ? null
                                  : () => widget.onOpenUser(item.senderUserId),
                              borderRadius: BorderRadius.circular(6),
                              child: FutureBuilder<UserProfile?>(
                                future: _profile,
                                builder: (context, snapshot) {
                                  final name = item.senderName.isNotEmpty
                                      ? item.senderName
                                      : (snapshot.data?.name ?? '');
                                  return Text(
                                    name.isEmpty
                                        ? '用户 ${item.senderUserId}'
                                        : name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: AppPalette.of(context).muted,
                                        fontWeight: FontWeight.w800),
                                  );
                                },
                              ),
                            ),
                          ),
                          if (item.createdAt != null)
                            Text(_notifyTime(item.createdAt!),
                                style: TextStyle(
                                    color: AppPalette.of(context).muted,
                                    fontSize: 11)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.text.isEmpty ? '（空通知）' : item.text,
                        style: TextStyle(
                            color: AppPalette.of(context).muted, height: 1.4),
                      ),
                      if (_openingReference) ...[
                        const SizedBox(height: 6),
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ] else if (_canOpenReference) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.open_in_new_rounded,
                                size: 13,
                                color: Theme.of(context).colorScheme.primary),
                            const SizedBox(width: 3),
                            Text('查看原内容',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color:
                                        Theme.of(context).colorScheme.primary)),
                          ],
                        ),
                      ],
                      if (item.commentId != null) ...[
                        const SizedBox(height: 4),
                        Text('评论 ID ${item.commentId}',
                            style: TextStyle(
                                color: AppPalette.of(context).muted,
                                fontSize: 11.5)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _notifyTime(DateTime value) {
  final now = DateTime.now();
  final difference = now.difference(value);
  if (difference.inMinutes < 1) return '刚刚';
  if (difference.inHours < 1) return '${difference.inMinutes} 分钟前';
  if (difference.inDays < 1) return '${difference.inHours} 小时前';
  if (difference.inDays < 7) return '${difference.inDays} 天前';
  return '${value.month}-${value.day} ${_twoDigits(value.hour)}:${_twoDigits(value.minute)}';
}

String _twoDigits(int n) => n.toString().padLeft(2, '0');
