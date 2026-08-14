import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/content_spans.dart';
import '../home/home_repository.dart';
import '../video/content_detail_page.dart';

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
  late Future<List<TimelineFeed>> _feeds;
  late Future<List<ContentPreview>> _articles;
  late Future<List<ContentPreview>> _videos;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _profile = widget.controller.userProfile(widget.userId);
    _feeds = widget.controller.userFeeds(userId: widget.userId);
    _articles = widget.controller.userArticles(userId: widget.userId);
    _videos = widget.controller.userVideos(userId: widget.userId);
  }

  Future<void> _refresh() async {
    setState(_load);
    await _profile;
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
                      feeds: _feeds,
                      controller: widget.controller,
                      onRefresh: _refresh,
                    ),
                    _UserContentTab(
                      contents: _articles,
                      controller: widget.controller,
                      emptyText: 'TA 还没有发布文章',
                      onRefresh: _refresh,
                    ),
                    _UserContentTab(
                      contents: _videos,
                      controller: widget.controller,
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
                        _ProfileStat(label: '关注', value: profile.follows),
                        const _ProfileDivider(),
                        _ProfileStat(label: '粉丝', value: profile.fans),
                        const _ProfileDivider(),
                        _ProfileStat(label: '获赞', value: profile.totalLikes),
                      ],
                    ),
                    const SizedBox(height: 13),
                    if (_isOwnProfile)
                      const Text('我的主页', style: TextStyle(color: _profileMuted))
                    else
                      OutlinedButton.icon(
                        onPressed: _isUpdating ? null : _toggleFollow,
                        icon: _isUpdating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(following
                                ? Icons.check_rounded
                                : Icons.person_add_alt_1_outlined),
                        label: Text(following ? '已关注' : '关注'),
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

class _UserFeedTab extends StatelessWidget {
  const _UserFeedTab({
    required this.feeds,
    required this.controller,
    required this.onRefresh,
  });

  final Future<List<TimelineFeed>> feeds;
  final AppController controller;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<TimelineFeed>>(
        future: feeds,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ProfileMessage(
                message: '加载动态失败：${snapshot.error}', onRetry: onRefresh);
          }
          final items = snapshot.data ?? const <TimelineFeed>[];
          if (items.isEmpty) {
            return _ProfileMessage(message: 'TA 还没有发布动态', onRetry: onRefresh);
          }
          return RefreshIndicator(
            color: _palette(context).primary,
            onRefresh: onRefresh,
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
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 9),
                    itemBuilder: (context, index) => _UserFeedCard(
                      item: items[index],
                      controller: controller,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
}

class _UserFeedCard extends StatelessWidget {
  const _UserFeedCard({required this.item, required this.controller});

  final TimelineFeed item;
  final AppController controller;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: item.id <= 0
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => FeedDetailPage(
                      controller: controller,
                      feedId: item.id,
                    ),
                  )),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                item.spans.isEmpty
                    ? Text(item.content,
                        style: const TextStyle(
                            color: _profileInk, height: 1.4))
                    : ContentSpans(
                        spans: item.spans,
                        textStyle: const TextStyle(
                            color: _profileInk, height: 1.4)),
                if (item.images.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 104,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: item.images.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 7),
                      itemBuilder: (context, index) => ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: Image.network(item.images[index],
                              fit: BoxFit.cover),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                    '${item.likes} 赞 · ${item.comments} 评论 · ${_userTime(item.createdAt)}',
                    style: const TextStyle(color: _profileMuted, fontSize: 12)),
              ],
            ),
          ),
        ),
      );
}

class _UserContentTab extends StatelessWidget {
  const _UserContentTab({
    required this.contents,
    required this.controller,
    required this.emptyText,
    required this.onRefresh,
  });

  final Future<List<ContentPreview>> contents;
  final AppController controller;
  final String emptyText;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ContentPreview>>(
        future: contents,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ProfileMessage(
                message: '加载内容失败：${snapshot.error}', onRetry: onRefresh);
          }
          final items = snapshot.data ?? const <ContentPreview>[];
          if (items.isEmpty) {
            return _ProfileMessage(message: emptyText, onRetry: onRefresh);
          }
          return RefreshIndicator(
            color: _palette(context).primary,
            onRefresh: onRefresh,
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
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 9),
                    itemBuilder: (context, index) => _UserContentCard(
                      item: items[index],
                      controller: controller,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
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
  const _ProfileStat({required this.label, required this.value});

  final String label;
  final int? value;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 72,
        child: Column(
          children: [
            Text(value == null ? '—' : '$value',
                style: const TextStyle(
                    color: _profileInk, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(color: _profileMuted, fontSize: 11)),
          ],
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
