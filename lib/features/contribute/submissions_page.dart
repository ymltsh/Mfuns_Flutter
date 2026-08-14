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
  var _tab = 0;
  late Future<List<SubmissionItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<SubmissionItem>> _load() =>
      widget.controller.submissions(type: _tab);

  Future<void> _reload() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  void _selectTab(int value) {
    if (_tab == value) return;
    setState(() {
      _tab = value;
      _future = _load();
    });
  }

  void _openEditor() {
    Navigator.of(context)
        .push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => SubmissionEditorPage(
              controller: widget.controller,
              type: _tab,
            ),
          ),
        )
        .then((changed) {
      if (changed == true) _reload();
    });
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
              unselectedLabelColor: Colors.blueGrey,
              tabs: const [
                Tab(text: '文章'),
                Tab(text: '视频'),
              ],
              onTap: _selectTab,
            ),
          Expanded(
            child: FutureBuilder<List<SubmissionItem>>(
              future: _future,
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
                          Text('加载失败：${snapshot.error}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.blueGrey)),
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
                final items =
                    snapshot.data ?? const <SubmissionItem>[];
                if (items.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.edit_note_outlined,
                            color: Colors.blueGrey, size: 44),
                        const SizedBox(height: 10),
                        const Text('还没有投稿',
                            style: TextStyle(color: Colors.blueGrey)),
                        const SizedBox(height: 6),
                        TextButton.icon(
                            onPressed: _openEditor,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('发布第一篇投稿')),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  color: palette.primary,
                  onRefresh: _reload,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => _SubmissionCard(
                      item: items[index],
                      type: _tab,
                      controller: widget.controller,
                      onChanged: _reload,
                    ),
                  ),
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('投稿已删除')));
      await onChanged();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
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
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title.isEmpty ? '未命名投稿' : item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.blueGrey,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: palette.primary.withOpacity(.1),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(item.statusLabel,
                              style: TextStyle(
                                  color: palette.primary, fontSize: 11)),
                        ),
                        const SizedBox(width: 8),
                        if (item.createdAt != null)
                          Text(_submissionTime(item.createdAt!),
                              style: const TextStyle(
                                  color: Colors.blueGrey, fontSize: 11.5)),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '编辑',
                onPressed: () async {
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
                },
                icon: const Icon(Icons.edit_outlined, size: 20),
              ),
              IconButton(
                tooltip: '删除',
                onPressed: () => _confirmDelete(context),
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _submissionTime(DateTime value) {
  final now = DateTime.now();
  if (value.year == now.year && value.month == now.month && value.day == now.day) {
    return '今天 ${_twoDigits(value.hour)}:${_twoDigits(value.minute)}';
  }
  return '${value.year}-${_twoDigits(value.month)}-${_twoDigits(value.day)}';
}

String _twoDigits(int n) => n.toString().padLeft(2, '0');
