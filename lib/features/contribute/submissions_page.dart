import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../home/home_repository.dart';
import 'submission_detail_page.dart';
import 'submission_editor_page.dart';

/// 我的投稿：文章 / 视频投稿列表，含状态、编辑与删除入口。
class SubmissionsPage extends StatefulWidget {
  const SubmissionsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SubmissionsPage> createState() => _SubmissionsPageState();
}

class _SubmissionsPageState extends State<SubmissionsPage> {
  static const _pageSize = 20;

  var _tab = 0;
  final _scrollController = ScrollController();
  final List<SubmissionItem> _items = [];
  var _nextPage = 1;
  var _hasMore = true;
  var _isLoading = true;
  var _isLoadingMore = false;
  Object? _error;
  Object? _loadMoreError;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < 320) _loadMore();
  }

  Future<void> _loadFirstPage() async {
    final generation = ++_generation;
    final type = _tab;
    final previousNextPage = _nextPage;
    final previousHasMore = _hasMore;
    setState(() {
      _isLoading = true;
      _isLoadingMore = false;
      _error = null;
      _loadMoreError = null;
      _nextPage = 1;
      _hasMore = true;
    });
    try {
      final result = await widget.controller.submissionPage(
        type: type,
        page: 1,
        size: _pageSize,
      );
      if (!mounted || generation != _generation || type != _tab) return;
      setState(() {
        _items
          ..clear()
          ..addAll(result.items);
        _nextPage = 2;
        _hasMore = result.hasMore;
        _isLoading = false;
      });
      _scheduleLoadMoreIfNeeded();
    } catch (error) {
      if (!mounted || generation != _generation || type != _tab) return;
      setState(() {
        if (_items.isEmpty) {
          _error = error;
        } else {
          _nextPage = previousNextPage;
          _hasMore = previousHasMore;
        }
        _isLoading = false;
      });
      if (_items.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('刷新失败：$error')));
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    final generation = _generation;
    final type = _tab;
    final page = _nextPage;
    setState(() {
      _isLoadingMore = true;
      _loadMoreError = null;
    });
    try {
      final result = await widget.controller.submissionPage(
        type: type,
        page: page,
        size: _pageSize,
      );
      if (!mounted || generation != _generation || type != _tab) return;
      final knownIds = _items.map((item) => item.id).toSet();
      setState(() {
        _items.addAll(result.items.where((item) => knownIds.add(item.id)));
        _nextPage = page + 1;
        _hasMore = result.hasMore;
        _isLoadingMore = false;
      });
      _scheduleLoadMoreIfNeeded();
    } catch (error) {
      if (!mounted || generation != _generation || type != _tab) return;
      setState(() {
        _loadMoreError = error;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _reload() => _loadFirstPage();

  void _scheduleLoadMoreIfNeeded() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (_scrollController.position.extentAfter < 320) _loadMore();
    });
  }

  void _selectTab(int value) {
    if (_tab == value) return;
    setState(() {
      _tab = value;
      _items.clear();
    });
    _loadFirstPage();
  }

  void _openEditor() {
    Navigator.of(context)
        .push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) =>
                SubmissionEditorPage(controller: widget.controller, type: _tab),
          ),
        )
        .then((changed) {
          if (changed == true) _reload();
        });
  }

  Widget _buildBody(AppPalette palette) {
    if (_isLoading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '加载失败：$_error',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppPalette.of(context).muted),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.edit_note_outlined,
              color: AppPalette.of(context).muted,
              size: 44,
            ),
            const SizedBox(height: 10),
            Text(
              '还没有投稿',
              style: TextStyle(color: AppPalette.of(context).muted),
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: _openEditor,
              icon: const Icon(Icons.add_rounded),
              label: const Text('发布第一篇投稿'),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: palette.primary,
      onRefresh: _reload,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        itemCount: _items.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == _items.length) {
            return _SubmissionListFooter(
              hasMore: _hasMore,
              loading: _isLoadingMore,
              error: _loadMoreError,
              onRetry: _loadMore,
            );
          }
          return _SubmissionCard(
            item: _items[index],
            type: _tab,
            controller: widget.controller,
            onChanged: _reload,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的投稿'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '发布投稿',
            onPressed: _openEditor,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            TabBar(
              labelColor: palette.primary,
              unselectedLabelColor: AppPalette.of(context).muted,
              tabs: const [
                Tab(text: '文章'),
                Tab(text: '视频'),
              ],
              onTap: _selectTab,
            ),
            Expanded(child: _buildBody(palette)),
          ],
        ),
      ),
    );
  }
}

class _SubmissionListFooter extends StatelessWidget {
  const _SubmissionListFooter({
    required this.hasMore,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final bool hasMore;
  final bool loading;
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final muted = AppPalette.of(context).muted;
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (error != null) {
      return Center(
        child: TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('加载更多失败，点击重试'),
        ),
      );
    }
    if (hasMore) {
      return Center(
        child: TextButton(onPressed: onRetry, child: const Text('加载更多')),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text('已加载全部投稿', style: TextStyle(color: muted)),
      ),
    );
  }
}

class _SubmissionCard extends StatelessWidget {
  const _SubmissionCard({
    required this.item,
    required this.type,
    required this.controller,
    required this.onChanged,
  });

  final SubmissionItem item;
  final int type;
  final AppController controller;
  final Future<void> Function() onChanged;

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: const Text('删除投稿'),
        content: Text('确定删除投稿「${item.title}」吗？删除后无法恢复。'),
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
    if (confirmed != true || !context.mounted) return;
    try {
      await controller.deleteSubmission(type: type, contributeId: item.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('投稿已删除')));
      await onChanged();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
    }
  }

  Future<void> _changeVisibility(BuildContext context, int visibility) async {
    final resourceId = item.resourceId;
    if (resourceId == null || resourceId <= 0) return;
    try {
      await controller.updateResourceVisibility(
        resourceType: type,
        resourceId: resourceId,
        visibility: visibility,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已设为${_visibilityLabel(visibility)}')),
      );
      await onChanged();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('修改可见性失败：$error')));
      }
    }
  }

  Future<void> _openEditor(BuildContext context) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => SubmissionEditorPage(
          controller: controller,
          type: type,
          contributeId: item.id,
        ),
      ),
    );
    if (changed == true) await onChanged();
  }

  Future<void> _openDetail(BuildContext context) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => SubmissionDetailPage(
          controller: controller,
          contributeId: item.id,
          type: type,
        ),
      ),
    );
    if (changed == true) await onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => _openDetail(context),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  _SubmissionCover(url: item.cover),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title.isEmpty ? '未命名投稿' : item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppPalette.of(context).muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: palette.primary.withOpacity(.1),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                item.statusLabel,
                                style: TextStyle(
                                  color: palette.primary,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            if (item.createdAt != null)
                              Text(
                                _submissionTime(item.createdAt!),
                                style: TextStyle(
                                  color: AppPalette.of(context).muted,
                                  fontSize: 11.5,
                                ),
                              ),
                          ],
                        ),
                        if (item.resourceId != null &&
                            item.resourceId! > 0) ...[
                          const SizedBox(height: 9),
                          Wrap(
                            spacing: 12,
                            runSpacing: 5,
                            children: [
                              _Interaction(
                                icon: Icons.visibility_outlined,
                                value: item.views,
                              ),
                              _Interaction(
                                icon: Icons.thumb_up_alt_outlined,
                                value: item.likes,
                              ),
                              _Interaction(
                                icon: Icons.chat_bubble_outline_rounded,
                                value: item.comments,
                              ),
                              _Interaction(
                                icon: Icons.star_border_rounded,
                                value: item.favorites,
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _openEditor(context),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('编辑'),
                ),
                if (item.resourceId != null && item.resourceId! > 0)
                  PopupMenuButton<int>(
                    tooltip: '修改可见性',
                    initialValue: item.visibility,
                    onSelected: (value) => _changeVisibility(context, value),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 0, child: Text('所有人可见')),
                      PopupMenuItem(value: 1, child: Text('仅关注可见')),
                      PopupMenuItem(value: 2, child: Text('仅自己可见')),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.visibility_outlined, size: 18),
                          const SizedBox(width: 7),
                          Text(
                            item.visibility == null
                                ? '可见性'
                                : _visibilityLabel(item.visibility!),
                          ),
                        ],
                      ),
                    ),
                  ),
                TextButton.icon(
                  onPressed: () => _confirmDelete(context),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('删除'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Interaction extends StatelessWidget {
  const _Interaction({required this.icon, required this.value});

  final IconData icon;
  final int value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15, color: AppPalette.of(context).muted),
      const SizedBox(width: 3),
      Text(
        '$value',
        style: TextStyle(color: AppPalette.of(context).muted, fontSize: 12),
      ),
    ],
  );
}

String _visibilityLabel(int value) => switch (value) {
  0 => '所有人可见',
  1 => '仅关注可见',
  2 => '仅自己可见',
  _ => '可见性',
};

class _SubmissionCover extends StatelessWidget {
  const _SubmissionCover({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    Widget placeholder() => Container(
      color: AppPalette.of(context).placeholder,
      alignment: Alignment.center,
      child: Icon(Icons.image_outlined, color: AppPalette.of(context).muted),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 96,
        height: 60,
        child: url.isEmpty
            ? placeholder()
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => placeholder(),
              ),
      ),
    );
  }
}

String _submissionTime(DateTime value) {
  final now = DateTime.now();
  if (value.year == now.year &&
      value.month == now.month &&
      value.day == now.day) {
    return '今天 ${_twoDigits(value.hour)}:${_twoDigits(value.minute)}';
  }
  return '${value.year}-${_twoDigits(value.month)}-${_twoDigits(value.day)}';
}

String _twoDigits(int n) => n.toString().padLeft(2, '0');
