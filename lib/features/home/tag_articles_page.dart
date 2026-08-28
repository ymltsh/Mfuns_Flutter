import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../video/content_detail_page.dart';
import 'home_repository.dart';

const _ink = Color(0xff3a3a45);
const _muted = Color(0xff8a8a94);

AppPalette _palette(BuildContext context) => AppPalette.of(context);

/// 标签文章列表页：展示 `GET /v1/tag/article_list?tag=xxx` 返回的文章。
class TagArticlesPage extends StatefulWidget {
  const TagArticlesPage({
    super.key,
    required this.controller,
    required this.tag,
  });

  final AppController controller;
  final String tag;

  @override
  State<TagArticlesPage> createState() => _TagArticlesPageState();
}

class _TagArticlesPageState extends State<TagArticlesPage> {
  late Future<List<ContentPreview>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.controller.tagArticles(widget.tag);
  }

  void _reload() {
    setState(() => _future = widget.controller.tagArticles(widget.tag));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('#${widget.tag}'), centerTitle: true),
        body: FutureBuilder<List<ContentPreview>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return Center(
                  child: CircularProgressIndicator(
                      color: _palette(context).primary));
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${snapshot.error}',
                        style: const TextStyle(color: _muted, fontSize: 12.5)),
                    TextButton(onPressed: _reload, child: const Text('重试')),
                  ],
                ),
              );
            }
            final items = snapshot.data ?? const <ContentPreview>[];
            if (items.isEmpty) {
              return const Center(
                child: Text('这个标签下还没有文章',
                    style: TextStyle(color: _muted, fontSize: 13)),
              );
            }
            return RefreshIndicator(
              color: _palette(context).accent,
              onRefresh: () async => _reload(),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 9),
                itemBuilder: (context, index) => _TagArticleCard(
                  controller: widget.controller,
                  item: items[index],
                ),
              ),
            );
          },
        ),
      );
}

class _TagArticleCard extends StatelessWidget {
  const _TagArticleCard({required this.controller, required this.item});

  final AppController controller;
  final ContentPreview item;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) =>
                  ContentDetailPage(controller: controller, preview: item))),
          child: SizedBox(
            height: 91,
            child: Row(
              children: [
                const SizedBox(width: 9),
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: SizedBox(
                      width: 107, height: 68, child: _Cover(item: item)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding:
                        const EdgeInsets.only(right: 10, top: 11, bottom: 11),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: _ink, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Text(
                          '${item.author.isEmpty ? 'Mfuns 用户' : item.author} · ${item.likes} 赞 · ${item.comments} 评论 · ${item.views} 浏览',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _muted, fontSize: 11.5),
                        ),
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

class _Cover extends StatelessWidget {
  const _Cover({required this.item});

  final ContentPreview item;

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          if (item.cover.isNotEmpty)
            Image.network(item.cover,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _Fallback(item: item))
          else
            _Fallback(item: item),
          if (item.category.isNotEmpty)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                    color: Colors.black.withOpacity(.48),
                    borderRadius: BorderRadius.circular(4)),
                child: Text(item.category,
                    style: const TextStyle(color: Colors.white, fontSize: 9)),
              ),
            ),
        ],
      );
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.item});

  final ContentPreview item;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xff5e90dd), Color(0xff95b3e6)],
          ),
        ),
        child: Center(
            child: Icon(Icons.article_outlined,
                color: Colors.white.withOpacity(.8), size: 34)),
      );
}
