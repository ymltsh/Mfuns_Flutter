import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/content_link_handler.dart';
import '../../core/widgets/content_spans.dart';
import '../../core/widgets/image_preview_page.dart';
import '../home/home_repository.dart';
import '../message/messages_page.dart';
import '../video/content_detail_page.dart';
import 'follow_list_page.dart';

const _profileInk = Colors.blueGrey;
const _profileMuted = Colors.blueGrey;

AppPalette _palette(BuildContext context) => AppPalette.of(context);

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({
    super.key,
    required this.controller,
    required this.userId,
  });

  final AppController controller;
  final int userId;

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  late Future<UserProfile> _profile;
  final _feedTabKey = GlobalKey<_UserFeedTabState>();
  final _articleTabKey = GlobalKey<_UserContentTabState>();
  final _videoTabKey = GlobalKey<_UserContentTabState>();

  @override
  void initState() {
    super.initState();
    _profile = widget.controller.userProfile(widget.userId);
  }

  Future<void> _refresh() async {
    // 刷新个人信息（资料卡）与三个列表的第一页；列表 reload 自身会
    // 回调 onRefresh，这里只重载列表避免递归。
    setState(() => _profile = widget.controller.userProfile(widget.userId));
    await Future.wait([
      _feedTabKey.currentState?.reloadFirstPage() ?? Future.value(),
      _articleTabKey.currentState?.reloadFirstPage() ?? Future.value(),
      _videoTabKey.currentState?.reloadFirstPage() ?? Future.value(),
      _profile,
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('用户主页'),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: '刷新资料',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: FutureBuilder<UserProfile>(
          future: _profile,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _ProfileMessage(
                message: '加载用户资料失败：${snapshot.error}',
                onRetry: _refresh,
              );
            }
            final profile = snapshot.requireData;
            return DefaultTabController(
              length: 3,
              child: NestedScrollView(
                headerSliverBuilder: (context, innerBoxIsScrolled) => [
                  SliverToBoxAdapter(
                    child: _ProfileHeader(
                      profile: profile,
                      controller: widget.controller,
                    ),
                  ),
                  SliverOverlapAbsorber(
                    handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                        context),
                    sliver: SliverAppBar(
                      pinned: true,
                      automaticallyImplyLeading: false,
                      backgroundColor: Colors.white,
                      surfaceTintColor: Colors.transparent,
                      forceElevated: innerBoxIsScrolled,
                      toolbarHeight: 0,
                      bottom: TabBar(
                        labelColor: _palette(context).primary,
                        unselectedLabelColor: _profileMuted,
                        tabs: const [
                          Tab(text: '动态'),
                          Tab(text: '文章'),
                          Tab(text: '视频'),
                        ],
                      ),
                    ),
                  ),
                ],
                body: TabBarView(
                  children: [
                    _UserFeedTab(
                      key: _feedTabKey,
                      controller: widget.controller,
                      userId: widget.userId,
                      onRefresh: _refresh,
                    ),
                    _UserContentTab(
                      key: _articleTabKey,
                      controller: widget.controller,
                      loader: (cursor) => widget.controller
                          .userArticles(userId: widget.userId, cursor: cursor),
                      emptyText: 'TA 还没有发布文章',
                      onRefresh: _refresh,
                    ),
                    _UserContentTab(
                      key: _videoTabKey,
                      controller: widget.controller,
                      loader: (cursor) => widget.controller
                          .userVideos(userId: widget.userId, cursor: cursor),
                      emptyText: 'TA 还没有发布视频',
                      onRefresh: _refresh,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
}

class _ProfileHeader extends StatefulWidget {
  const _ProfileHeader({required this.profile, required this.controller});

  final UserProfile profile;
  final AppController controller;

  @override
  State<_ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends State<_ProfileHeader> {
  bool? _following;
  var _isUpdating = false;

  bool get _isOwnProfile =>
      widget.profile.id != 0 &&
      widget.profile.id == widget.controller.session?.userId;

  @override
  void initState() {
    super.initState();
    _loadFollowStatus();
  }

  Future<void> _loadFollowStatus() async {
    if (_isOwnProfile || widget.controller.session == null) return;
    try {
      final following = await widget.controller.followStatus(widget.profile.id);
      if (mounted) setState(() => _following = following);
    } catch (_) {
      // Keep the action available. The actual follow request will show its error.
    }
  }

  Future<void> _toggleFollow() async {
    if (_isOwnProfile || _isUpdating) return;
    if (widget.controller.session == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先在“我的”页面登录后再关注')));
      return;
    }

    final next = !(_following ?? false);
    setState(() => _isUpdating = true);
    try {
      await widget.controller
          .setFollow(userId: widget.profile.id, follow: next);
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

  void _openMessage() {
    if (widget.controller.session == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先在“我的”页面登录后再发起私信')));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => MessageDetailPage(
              controller: widget.controller,
              peerId: widget.profile.id,
              peerName: widget.profile.name,
            )));
  }

  void _openFollowList(String type) {
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => FollowListPage(
              controller: widget.controller,
              userId: widget.profile.id,
              type: type,
            )));
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final following = _following == true;
    return Column(
      children: [
        SizedBox(
          height: 104,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (profile.banner.isNotEmpty)
                Image.network(profile.banner, fit: BoxFit.cover)
              else
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xff4d5ecc), Color(0xff9f73d7)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              const DecoratedBox(
                decoration: BoxDecoration(color: Color(0x22000000)),
              ),
            ],
          ),
        ),
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 52),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(profile.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: _profileInk,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800)),
                        ),
                        if (profile.gender.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Icon(_genderIcon(profile.gender),
                              color: _genderColor(profile.gender), size: 17),
                        ],
                        if (profile.level != null) ...[
                          const SizedBox(width: 8),
                          _LevelBadge(
                            label: _levelLabel(profile.level),
                            exp: profile.exp,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text('MF ${profile.id}',
                        style: const TextStyle(
                            color: _profileMuted, fontSize: 12)),
                    const SizedBox(height: 8),
                    Text(
                      profile.bio == '暂无简介'
                          ? '这个人很神秘，什么也没写。'
                          : profile.bio,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _profileInk, height: 1.35),
                    ),
                    const SizedBox(height: 13),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _ProfileStat(
                            label: '关注',
                            value: profile.follows,
                            onTap: () => _openFollowList('follow')),
                        const _ProfileDivider(),
                        _ProfileStat(
                            label: '粉丝',
                            value: profile.fans,
                            onTap: () => _openFollowList('fans')),
                        const _ProfileDivider(),
                        _ProfileStat(label: '获赞', value: profile.totalLikes),
                      ],
                    ),
                    const SizedBox(height: 13),
                    if (_isOwnProfile)
                      const Text('我的主页', style: TextStyle(color: _profileMuted))
                    else
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _isUpdating ? null : _toggleFollow,
                            icon: _isUpdating
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : Icon(following
                                    ? Icons.check_rounded
                                    : Icons.person_add_alt_1_outlined),
                            label: Text(following ? '已关注' : '关注'),
                          ),
                          const SizedBox(width: 10),
                          FilledButton.tonalIcon(
                            onPressed: _openMessage,
                            icon: const Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 18),
                            label: const Text('私信'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -42),
              child: _ProfileAvatar(profile: profile),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) => Stack(
        alignment: Alignment.center,
        children: [
          CircleAvatar(
            radius: 43,
            backgroundColor: Colors.white,
            child: CircleAvatar(
              radius: 39,
              foregroundImage:
                  profile.avatar.isEmpty ? null : NetworkImage(profile.avatar),
              backgroundColor: const Color(0xffe8e9f6),
              foregroundColor: _palette(context).primary,
              child: Text(
                  profile.name.isEmpty ? 'M' : profile.name.substring(0, 1),
                  style: const TextStyle(
                      fontSize: 27, fontWeight: FontWeight.w800)),
            ),
          ),
          if (profile.avatarFrame.isNotEmpty)
            IgnorePointer(
              child: Image.network(profile.avatarFrame, width: 94, height: 94),
            ),
        ],
      );
}

class _UserFeedTab extends StatefulWidget {
  const _UserFeedTab({
    super.key,
    required this.controller,
    required this.userId,
    required this.onRefresh,
  });

  final AppController controller;
  final int userId;
  final Future<void> Function() onRefresh;

  @override
  State<_UserFeedTab> createState() => _UserFeedTabState();
}

class _UserFeedTabState extends State<_UserFeedTab> {
  List<TimelineFeed>? _items;
  String? _error;
  var _loadingMore = false;
  var _hasMore = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> reload() async {
    await _load();
    await widget.onRefresh();
  }

  /// 仅重载列表第一页（由页面刷新按钮调用，不再回调 onRefresh）。
  Future<void> reloadFirstPage() => _load();

  Future<void> _load() async {
    try {
      final page = await widget.controller
          .userFeeds(userId: widget.userId, startId: -1);
      if (!mounted) return;
      setState(() {
        _items = page;
        _hasMore = page.isNotEmpty;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _items ??= const [];
        _error = '加载动态失败：$error';
      });
    }
  }

  Future<void> _loadMore() async {
    final items = _items;
    if (items == null || items.isEmpty || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.controller
          .userFeeds(userId: widget.userId, startId: items.last.id);
      if (!mounted) return;
      setState(() {
        final seen = _items!.map((item) => item.id).toSet();
        final additions =
            page.where((item) => !seen.contains(item.id)).toList(growable: false);
        _items = [..._items!, ...additions];
        _hasMore = page.isNotEmpty;
      });
    } catch (_) {
      // 滚动到底可再次触发加载。
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && (items?.isEmpty ?? true)) {
      return _ProfileMessage(message: _error!, onRetry: reload);
    }
    if (items == null || items.isEmpty) {
      return _ProfileMessage(message: 'TA 还没有发布动态', onRetry: reload);
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 300 &&
            _hasMore &&
            !_loadingMore) {
          _loadMore();
        }
        return false;
      },
      child: RefreshIndicator(
        color: _palette(context).primary,
        onRefresh: reload,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverOverlapInjector(
              handle:
                  NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              sliver: SliverList.separated(
                itemCount: items.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 9),
                itemBuilder: (context, index) {
                  if (index == items.length) {
                    return _ProfileListFooter(
                      loadingMore: _loadingMore,
                      hasMore: _hasMore,
                      onLoadMore: _loadMore,
                    );
                  }
                  return _UserFeedCard(
                    item: items[index],
                    controller: widget.controller,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserFeedCard extends StatelessWidget {
  const _UserFeedCard({required this.item, required this.controller});

  final TimelineFeed item;
  final AppController controller;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          // 自动同步动态（is_auto_sync）点击直接打开对应的文章/视频页，
          // 与 Web 端 302 跳转行为一致。
          onTap: () {
            final resource = item.resource;
            if (item.isAutoSync && resource != null) {
              Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) =>
                      ContentDetailPage(controller: controller, preview: resource)));
              return;
            }
            if (item.id <= 0) return;
            Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => FeedDetailPage(
                controller: controller,
                feedId: item.id,
              ),
            ));
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.spans.isEmpty && item.resource != null)
                  Text(item.content,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: _profileInk, height: 1.4))
                else
                  item.spans.isEmpty
                      ? Text(item.content,
                          style: const TextStyle(
                              color: _profileInk, height: 1.4))
                      : ContentSpans(
                          spans: item.spans,
                          onLinkTap: (url) =>
                              openContentLink(context, controller, url),
                          textStyle: const TextStyle(
                              color: _profileInk, height: 1.4)),
                if (item.resource != null) ...[
                  const SizedBox(height: 10),
                  _ProfileResourceCard(
                    item: item.resource!,
                    controller: controller,
                  ),
                ],
                if (item.images.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 104,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: item.images.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 7),
                      itemBuilder: (context, index) {
                        final uri = Uri.tryParse(item.images[index]);
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: GestureDetector(
                            onTap: uri == null
                                ? null
                                : () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => ImagePreviewPage(
                                          uri: uri,
                                          alt: '动态图片',
                                          uris: item.images
                                              .map(Uri.parse)
                                              .toList(growable: false),
                                          initialIndex: index,
                                        ),
                                      ),
                                    ),
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: Image.network(item.images[index],
                                  fit: BoxFit.cover),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                          '${item.likes} 赞 · ${item.comments} 评论 · ${_userTime(item.createdAt)}',
                          style: const TextStyle(
                              color: _profileMuted, fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}

/// 自动同步动态的类型标识（文章/视频）。
class _FeedTypeTag extends StatelessWidget {
  const _FeedTypeTag({required this.isVideo});

  final bool isVideo;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: _palette(context).primary.withOpacity(.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(isVideo ? '视频' : '文章',
            style: TextStyle(
                color: _palette(context).primary,
                fontSize: 10.5,
                fontWeight: FontWeight.w700)),
      );
}

/// 动态引用的文章/视频卡片（自动同步动态等）。
class _ProfileResourceCard extends StatelessWidget {
  const _ProfileResourceCard({required this.item, required this.controller});

  final ContentPreview item;
  final AppController controller;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) =>
                ContentDetailPage(controller: controller, preview: item))),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xfff3f2f8),
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 72,
                  height: 48,
                  child: item.cover.isEmpty
                      ? const ColoredBox(
                          color: Color(0xffe4e3ee),
                          child: Icon(Icons.image_outlined,
                              size: 20, color: _profileMuted),
                        )
                      : Image.network(item.cover, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: _profileInk,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        _FeedTypeTag(isVideo: item.isVideo),
                        const SizedBox(width: 6),
                        Text('${item.likes} 赞 · ${item.views} 浏览',
                            style: const TextStyle(
                                color: _profileMuted, fontSize: 11)),
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

class _UserContentTab extends StatefulWidget {
  const _UserContentTab({
    super.key,
    required this.controller,
    required this.loader,
    required this.emptyText,
    required this.onRefresh,
  });

  final AppController controller;
  final Future<List<ContentPreview>> Function(int cursor) loader;
  final String emptyText;
  final Future<void> Function() onRefresh;

  @override
  State<_UserContentTab> createState() => _UserContentTabState();
}

class _UserContentTabState extends State<_UserContentTab> {
  List<ContentPreview>? _items;
  String? _error;
  var _loadingMore = false;
  var _hasMore = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> reload() async {
    await _load();
    await widget.onRefresh();
  }

  /// 仅重载列表第一页（由页面刷新按钮调用，不再回调 onRefresh）。
  Future<void> reloadFirstPage() => _load();

  Future<void> _load() async {
    try {
      final page = await widget.loader(0);
      if (!mounted) return;
      setState(() {
        _items = page;
        _hasMore = page.isNotEmpty;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _items ??= const [];
        _error = '加载内容失败：$error';
      });
    }
  }

  Future<void> _loadMore() async {
    final items = _items;
    if (items == null || items.isEmpty || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.loader(items.last.id);
      if (!mounted) return;
      setState(() {
        final seen = _items!.map((item) => item.id).toSet();
        final additions =
            page.where((item) => !seen.contains(item.id)).toList(growable: false);
        _items = [..._items!, ...additions];
        _hasMore = page.isNotEmpty;
      });
    } catch (_) {
      // 滚动到底可再次触发加载。
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && (items?.isEmpty ?? true)) {
      return _ProfileMessage(message: _error!, onRetry: reload);
    }
    if (items == null || items.isEmpty) {
      return _ProfileMessage(message: widget.emptyText, onRetry: reload);
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 300 &&
            _hasMore &&
            !_loadingMore) {
          _loadMore();
        }
        return false;
      },
      child: RefreshIndicator(
        color: _palette(context).primary,
        onRefresh: reload,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverOverlapInjector(
              handle:
                  NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              sliver: SliverList.separated(
                itemCount: items.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 9),
                itemBuilder: (context, index) {
                  if (index == items.length) {
                    return _ProfileListFooter(
                      loadingMore: _loadingMore,
                      hasMore: _hasMore,
                      onLoadMore: _loadMore,
                    );
                  }
                  return _UserContentCard(
                    item: items[index],
                    controller: widget.controller,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 列表底部状态：加载中 / 没有更多了 / 点击加载更多。
class _ProfileListFooter extends StatelessWidget {
  const _ProfileListFooter({
    required this.loadingMore,
    required this.hasMore,
    required this.onLoadMore,
  });

  final bool loadingMore;
  final bool hasMore;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Center(
            child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        )),
      );
    }
    if (!hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: Text('没有更多了',
              style: TextStyle(color: _profileMuted, fontSize: 12)),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextButton.icon(
          onPressed: onLoadMore,
          icon: const Icon(Icons.expand_more_rounded, size: 18),
          label: const Text('加载更多'),
        ),
      ),
    );
  }
}

class _UserContentCard extends StatelessWidget {
  const _UserContentCard({required this.item, required this.controller});

  final ContentPreview item;
  final AppController controller;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) =>
                  ContentDetailPage(controller: controller, preview: item))),
          child: SizedBox(
            height: 96,
            child: Row(
              children: [
                SizedBox(
                  width: 128,
                  child: item.cover.isEmpty
                      ? const ColoredBox(
                          color: Color(0xffececf5),
                          child:
                              Icon(Icons.image_outlined, color: _profileMuted),
                        )
                      : Image.network(item.cover, fit: BoxFit.cover),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 11, 12, 9),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: _profileInk,
                                fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Text('${item.likes} 赞 · ${item.views} 浏览',
                            style: const TextStyle(
                                color: _profileMuted, fontSize: 11.5)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _ProfileMessage extends StatelessWidget {
  const _ProfileMessage({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _profileMuted)),
              const SizedBox(height: 10),
              TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重试')),
            ],
          ),
        ),
      );
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({required this.label, required this.value, this.onTap});

  final String label;
  final int? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 72,
          child: Column(
            children: [
              Text(value == null ? '—' : '$value',
                  style: const TextStyle(
                      color: _profileInk, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(label,
                  style: const TextStyle(
                      color: _profileMuted, fontSize: 11)),
            ],
          ),
        ),
      );
}

class _ProfileDivider extends StatelessWidget {
  const _ProfileDivider();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 26, color: const Color(0xffe2e2ea));
}

/// 等级与经验徽章：按段位着色（S 金 / A 红 / B 蓝 / C 绿 / D 灰）。
class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.label, this.exp});

  final String label;
  final int? exp;

  @override
  Widget build(BuildContext context) {
    final color = _levelColor(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withOpacity(.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .4)),
          if (exp != null) ...[
            Container(
              width: 1,
              height: 11,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: color.withOpacity(.4),
            ),
            Text('经验 $exp',
                style: TextStyle(color: color, fontSize: 11.5)),
          ],
        ],
      ),
    );
  }
}

/// level_id → 段位（1=D, 2=D+, 3=C, 4=C+, 5=B, 6=B+, 7=A, 8=A+, 9=S, 10=S+）。
String _levelLabel(int? levelId) {
  const ranks = ['D', 'D+', 'C', 'C+', 'B', 'B+', 'A', 'A+', 'S', 'S+'];
  if (levelId == null || levelId < 1 || levelId > ranks.length) {
    return levelId == null ? '' : 'Lv.$levelId';
  }
  return ranks[levelId - 1];
}

Color _levelColor(String label) => switch (label) {
      'S' || 'S+' => const Color(0xFFE6A23C),
      'A' || 'A+' => const Color(0xFFE04F4F),
      'B' || 'B+' => const Color(0xFF4F7FE0),
      'C' || 'C+' => const Color(0xFF4FA36C),
      _ => const Color(0xFF8A9096),
    };

IconData _genderIcon(String value) =>
    value == 'female' || value == '女' || value == '2'
        ? Icons.female
        : Icons.male;

Color _genderColor(String value) =>
    value == 'female' || value == '女' || value == '2'
        ? Colors.pink
        : Colors.blue;

String _userTime(DateTime? value) {
  if (value == null) return '刚刚';
  final difference = DateTime.now().difference(value);
  if (difference.isNegative || difference.inMinutes < 1) return '刚刚';
  if (difference.inHours < 1) return '${difference.inMinutes} 分钟前';
  if (difference.inDays < 1) return '${difference.inHours} 小时前';
  return '${difference.inDays} 天前';
}
