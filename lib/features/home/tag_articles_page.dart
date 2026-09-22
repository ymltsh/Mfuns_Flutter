import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../video/content_detail_page.dart';
import 'home_repository.dart';

AppPalette _palette(BuildContext context) => AppPalette.of(context);

/// 标签内容页：合并展示标签下的文章和视频，并支持连续分页。
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
  List<ContentPreview> _items = const [];
  int? _articleLastId;
  int? _videoLastId;
  var _hasMoreArticles = true;
  var _hasMoreVideos = true;
  var _isInitialLoading = true;
  var _isLoadingMore = false;
  var _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(refresh: true);
  }

  Future<void> _load({bool refresh = false}) async {
    if (_isLoadingMore || (!refresh && !_hasMore)) return;
    setState(() {
      _error = null;
      if (refresh) {
        _isInitialLoading = _items.isEmpty;
      } else {
        _isLoadingMore = true;
      }
    });
    try {
      final result = await widget.controller.tagContents(
        widget.tag,
        articleLastId: refresh ? null : _articleLastId,
        videoLastId: refresh ? null : _videoLastId,
        loadArticles: refresh || _hasMoreArticles,
        loadVideos: refresh || _hasMoreVideos,
      );
      if (!mounted) return;
      setState(() {
        if (refresh) {
          _items = result.items;
        } else {
          final known = _items.map((item) => '${item.type}:${item.id}').toSet();
          _items = [
            ..._items,
            ...result.items
                .where((item) => known.add('${item.type}:${item.id}')),
          ];
        }
        _articleLastId = result.articleLastId;
        _videoLastId = result.videoLastId;
        _hasMoreArticles = result.hasMoreArticles;
        _hasMoreVideos = result.hasMoreVideos;
        _hasMore = result.hasMore;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() {
          _isInitialLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('#${widget.tag}'), centerTitle: true),
        body: _buildBody(),
      );

  Widget _buildBody() {
    if (_isInitialLoading) {
      return Center(
          child: CircularProgressIndicator(color: _palette(context).primary));
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!,
                style: TextStyle(
                    color: AppPalette.of(context).muted, fontSize: 12.5)),
            TextButton(
                onPressed: () => _load(refresh: true), child: const Text('重试')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return RefreshIndicator(
        color: _palette(context).accent,
        onRefresh: () => _load(refresh: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * .65,
              child: Center(
                child: Text('这个标签下还没有内容',
                    style: TextStyle(
                        color: AppPalette.of(context).muted, fontSize: 13)),
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: _palette(context).accent,
      onRefresh: () => _load(refresh: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.extentAfter < 260 &&
              _hasMore &&
              !_isLoadingMore &&
              _error == null) {
            _load();
          }
          return false;
        },
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: _items.length + 1,
          separatorBuilder: (_, index) => index >= _items.length - 1
              ? const SizedBox.shrink()
              : const SizedBox(height: 9),
          itemBuilder: (context, index) {
            if (index < _items.length) {
              return _TagArticleCard(
                controller: widget.controller,
                item: _items[index],
              );
            }
            if (_isLoadingMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child:
                    Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
              );
            }
            if (_error != null) {
              return Center(
                child: TextButton(
                  onPressed: _load,
                  child: Text('$_error，点击重试'),
                ),
              );
            }
            return Center(
              child: TextButton(
                onPressed: _hasMore ? _load : null,
                child: Text(_hasMore ? '加载更多' : '已经到底了'),
              ),
            );
          },
        ),
      ),
    );
  }
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
                            style: TextStyle(
                                color: AppPalette.of(context).ink,
                                fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Text(
                          '${item.isVideo ? '视频' : '文章'} · ${item.author.isEmpty ? 'Mfuns 用户' : item.author} · ${item.likes} 赞 · ${item.views} 浏览',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppPalette.of(context).muted,
                              fontSize: 11.5),
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
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                    color: Colors.black.withOpacity(.48),
                    borderRadius: BorderRadius.circular(4)),
                child: Text(item.category,
                    style: const TextStyle(color: Colors.white, fontSize: 9)),
              ),
            ),
          Positioned(
            left: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.56),
                  borderRadius: BorderRadius.circular(4)),
              child: Text(item.isVideo ? '视频' : '文章',
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
            child: Icon(
                item.isVideo
                    ? Icons.smart_display_outlined
                    : Icons.article_outlined,
                color: Colors.white.withOpacity(.8),
                size: 34)),
      );
}
