import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../home/home_repository.dart';
import 'user_profile_page.dart';

/// 用户的关注/粉丝列表（type=follow 关注 / fans 粉丝）。
class FollowListPage extends StatefulWidget {
  const FollowListPage({
    super.key,
    required this.controller,
    required this.userId,
    required this.type,
  });

  final AppController controller;
  final int userId;

  /// 'follow' 关注 / 'fans' 粉丝。
  final String type;

  @override
  State<FollowListPage> createState() => _FollowListPageState();
}

class _FollowListPageState extends State<FollowListPage> {
  List<UserProfile>? _items;
  String? _error;
  var _loadingMore = false;
  var _hasMore = true;

  String get _title => widget.type == 'follow' ? '关注' : '粉丝';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _reload() => _load();

  Future<void> _load() async {
    try {
      final page = await widget.controller.followList(
        userId: widget.userId,
        type: widget.type,
      );
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
        _error = '加载$_title列表失败：$error';
      });
    }
  }

  Future<void> _loadMore() async {
    final items = _items;
    if (items == null || items.isEmpty || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.controller.followList(
        userId: widget.userId,
        type: widget.type,
        lastId: items.last.id,
      );
      if (!mounted) return;
      setState(() {
        final seen = _items!.map((item) => item.id).toSet();
        final additions = page
            .where((item) => !seen.contains(item.id))
            .toList(growable: false);
        _items = [..._items!, ...additions];
        _hasMore = page.isNotEmpty;
      });
    } catch (_) {
      // 滚动到底可再次触发加载。
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _openUser(UserProfile user) {
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) =>
            UserProfilePage(controller: widget.controller, userId: user.id)));
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_title), centerTitle: true),
      body: _buildBody(context, palette),
    );
  }

  Widget _buildBody(BuildContext context, AppPalette palette) {
    final items = _items;
    if (items == null && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && (items?.isEmpty ?? true)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppPalette.of(context).muted)),
              const SizedBox(height: 10),
              TextButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (items == null || items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.type == 'follow'
                  ? Icons.person_outline_rounded
                  : Icons.favorite_outline_rounded,
              color: AppPalette.of(context).muted,
              size: 42,
            ),
            const SizedBox(height: 10),
            Text('还没有$_title',
                style: TextStyle(color: AppPalette.of(context).muted)),
          ],
        ),
      );
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
        color: palette.primary,
        onRefresh: _reload,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          itemCount: items.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            if (index == items.length) {
              if (_loadingMore) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    ),
                  ),
                );
              }
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    _hasMore ? '上拉加载更多' : '没有更多了',
                    style: TextStyle(
                        color: AppPalette.of(context).muted, fontSize: 12),
                  ),
                ),
              );
            }
            final user = items[index];
            return _FollowUserCard(
              user: user,
              palette: palette,
              onTap: () => _openUser(user),
            );
          },
        ),
      ),
    );
  }
}

class _FollowUserCard extends StatelessWidget {
  const _FollowUserCard({
    required this.user,
    required this.palette,
    required this.onTap,
  });

  final UserProfile user;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bio = user.bio == '暂无简介' ? '' : user.bio;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.all(12),
        leading: CircleAvatar(
          radius: 23,
          backgroundColor: palette.primary.withOpacity(.12),
          foregroundImage:
              user.avatar.isEmpty ? null : NetworkImage(user.avatar),
          foregroundColor: palette.primary,
          child: Text(user.name.isEmpty ? 'U' : user.name[0]),
        ),
        title: Text(user.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: AppPalette.of(context).muted,
                fontWeight: FontWeight.w800)),
        subtitle: bio.isEmpty
            ? Text('暂无简介',
                style: TextStyle(
                    color: AppPalette.of(context).muted, fontSize: 12.5))
            : Text(bio,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: AppPalette.of(context).muted, fontSize: 12.5)),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}
