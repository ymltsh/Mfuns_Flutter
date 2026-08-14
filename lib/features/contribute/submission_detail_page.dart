import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../home/home_repository.dart';
import 'submission_editor_page.dart';

/// 投稿详情：展示标题 / 正文 / 分类 / 标签 / 状态，提供编辑与删除。
class SubmissionDetailPage extends StatefulWidget {
  const SubmissionDetailPage({
    super.key,
    required this.controller,
    required this.contributeId,
    required this.type,
  });

  final AppController controller;
  final int contributeId;
  final int type;

  @override
  State<SubmissionDetailPage> createState() => _SubmissionDetailPageState();
}

class _SubmissionDetailPageState extends State<SubmissionDetailPage> {
  late Future<SubmissionDetail> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.controller.submissionDetail(widget.contributeId);
  }

  Future<void> _reload() async {
    final next = widget.controller.submissionDetail(widget.contributeId);
    setState(() => _future = next);
    await next;
  }

  Future<void> _delete() async {
    final detail = await _future;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: const Text('删除投稿'),
        content: Text('确定删除投稿「${detail.title}」吗？删除后无法恢复。'),
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
      await widget.controller
          .deleteSubmission(type: widget.type, contributeId: widget.contributeId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
    }
  }

  Future<void> _edit() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => SubmissionEditorPage(
          controller: widget.controller,
          type: widget.type,
          contributeId: widget.contributeId,
        ),
      ),
    );
    if (changed == true) {
      await _reload();
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('投稿详情'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '编辑',
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: '删除',
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: FutureBuilder<SubmissionDetail>(
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
          final detail = snapshot.requireData;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: palette.primary.withOpacity(.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(detail.statusLabel,
                        style:
                            TextStyle(color: palette.primary, fontSize: 12)),
                  ),
                  if (detail.resourceId != null) ...[
                    const SizedBox(width: 8),
                    Text('资源 ID ${detail.resourceId}',
                        style: const TextStyle(
                            color: Colors.blueGrey, fontSize: 12)),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Text(detail.title.isEmpty ? '未命名投稿' : detail.title,
                  style: const TextStyle(
                      color: Colors.blueGrey,
                      fontSize: 20,
                      fontWeight: FontWeight.w800)),
              if (detail.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: detail.tags
                      .map((tag) => Chip(
                            label: Text('#$tag',
                                style: const TextStyle(fontSize: 12)),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ))
                      .toList(),
                ),
              ],
              if (detail.cover.isNotEmpty) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(detail.cover,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const ColoredBox(
                          color: Color(0xffefeff7),
                          child: Icon(Icons.image_outlined,
                              color: Colors.blueGrey),
                        )),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                detail.content.isEmpty ? '（暂无简介内容）' : detail.content,
                style: const TextStyle(
                    color: Colors.blueGrey, height: 1.6, fontSize: 15),
              ),
            ],
          );
        },
      ),
    );
  }
}
