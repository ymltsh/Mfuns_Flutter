import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 独立的正文复制页面。
///
/// 单个只读文本框同时负责滚动和选择，避免阅读页的 ListView 与多个
/// SelectableText 争抢拖动手势。
class ArticleTextCopyPage extends StatefulWidget {
  const ArticleTextCopyPage({super.key, required this.text});

  final String text;

  @override
  State<ArticleTextCopyPage> createState() => _ArticleTextCopyPageState();
}

class _ArticleTextCopyPageState extends State<ArticleTextCopyPage> {
  late final TextEditingController _textController;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.text);
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正文已复制')),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('选择并复制'),
          actions: [
            IconButton(
              tooltip: '复制全文',
              onPressed: _copyAll,
              icon: const Icon(Icons.copy_all_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              key: const ValueKey('article-copy-text'),
              controller: _textController,
              scrollController: _scrollController,
              readOnly: true,
              expands: true,
              minLines: null,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    height: 1.7,
                  ),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.all(16),
                helperText: '长按文字后拖动选择范围，使用系统菜单复制',
                alignLabelWithHint: true,
              ),
            ),
          ),
        ),
      );
}
