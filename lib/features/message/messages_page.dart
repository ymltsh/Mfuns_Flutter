import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/content_link_handler.dart';
import '../../core/widgets/content_spans.dart';
import '../../core/widgets/image_preview_page.dart';
import '../../core/widgets/inline_emoji_input.dart';
import '../home/home_repository.dart';

class MessageListPage extends StatefulWidget {
  const MessageListPage({
    super.key,
    required this.controller,
    this.embedded = false,
  });

  final AppController controller;
  final bool embedded;

  @override
  State<MessageListPage> createState() => MessageListPageState();
}

class MessageListPageState extends State<MessageListPage> {
  List<MessageConversation>? _items;
  String? _error;
  int _lastDmUnread = -1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    reload();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  /// 私信未读变化（轮询/查看后刷新）时静默刷新会话列表，
  /// 最新一条私信预览与未读角标随之自动更新。
  void _onControllerChanged() {
    final dmUnread = widget.controller.notifyCountsData.message;
    if (dmUnread == _lastDmUnread) return;
    _lastDmUnread = dmUnread;
    reload();
  }

  Future<void> reload() async {
    try {
      final items = await widget.controller.messageConversations();
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (_items == null) _error = '加载会话失败：$error';
      });
    }
  }

  Future<void> _openConversation(MessageConversation item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MessageDetailPage(
          controller: widget.controller,
          peerId: item.userId,
          peerName: item.userName,
        ),
      ),
    );
    if (!mounted) return;
    // 返回会话列表时立即刷新：服务端已将该会话标记已读，
    // 未读小红点随之消失，预览显示最新一条私信。
    widget.controller.refreshUnreadCounts();
    reload();
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody(context);
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('我的消息'), centerTitle: true),
      body: body,
    );
  }

  Widget _buildBody(BuildContext context) {
    final items = _items;
    if (items == null) {
      if (_error != null) {
        return _MessageState(message: _error!, onRetry: reload);
      }
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) {
      return _MessageState(message: '还没有私信会话', onRetry: reload);
    }
    return RefreshIndicator(
      color: AppPalette.of(context).primary,
      onRefresh: reload,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) => _ConversationCard(
          item: items[index],
          onTap: () => _openConversation(items[index]),
        ),
      ),
    );
  }
}

class _ConversationCard extends StatelessWidget {
  const _ConversationCard({required this.item, required this.onTap});

  final MessageConversation item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.all(12),
        leading: CircleAvatar(
          radius: 23,
          backgroundColor: palette.primary.withOpacity(.12),
          foregroundImage:
              item.userAvatar.isEmpty ? null : NetworkImage(item.userAvatar),
          foregroundColor: palette.primary,
          child: Text(item.userName.isEmpty ? 'U' : item.userName[0]),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(item.userName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.blueGrey, fontWeight: FontWeight.w800)),
            ),
            if (item.lastTime != null)
              Text(_msgTime(item.lastTime!),
                  style: const TextStyle(color: Colors.blueGrey, fontSize: 11)),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  item.lastMessage.isEmpty ? '暂无消息' : item.lastMessage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.blueGrey, fontSize: 12.5),
                ),
              ),
              if (item.unread > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: palette.accent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${item.unread}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class MessageDetailPage extends StatefulWidget {
  const MessageDetailPage({
    super.key,
    required this.controller,
    required this.peerId,
    required this.peerName,
  });

  final AppController controller;
  final int peerId;
  final String peerName;

  @override
  State<MessageDetailPage> createState() => _MessageDetailPageState();
}

class _MessageDetailPageState extends State<MessageDetailPage> {
  final _inputKey = GlobalKey<InlineEmojiInputState>();
  List<MessageRecord>? _items;
  String? _error;
  var _isSending = false;
  int _lastDmUnread = -1;
  UserProfile? _peer;

  int? get _myId => widget.controller.session?.userId;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _reload();
    _loadPeer();
  }

  /// 对方资料（头像等）加载失败时静默，界面不依赖它。
  Future<void> _loadPeer() async {
    try {
      final profile = await widget.controller.userProfile(widget.peerId);
      if (mounted) setState(() => _peer = profile);
    } catch (_) {}
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  /// 私信未读变化（新消息到达）时静默刷新聊天记录，保持在会话内接收最新消息。
  void _onControllerChanged() {
    final dmUnread = widget.controller.notifyCountsData.message;
    if (dmUnread == _lastDmUnread) return;
    _lastDmUnread = dmUnread;
    _reload();
  }

  Future<void> _reload() async {
    try {
      final items = await widget.controller.messageRecord(widget.peerId);
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
      });
      // 拉取会话记录后服务端视为已读，同步刷新未读与小红点。
      widget.controller.refreshUnreadCounts();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (_items == null) _error = '加载聊天记录失败：$error';
      });
    }
  }

  /// 打开表情选择面板：选中表情以 `[pack-id]` 标记插入输入框，
  /// 发送时由 commentQuillJson 转换为带 sticker 的富文本。
  void _pickEmoji() => _inputKey.currentState?.pickEmoji();

  void _pickImage() => _inputKey.currentState?.pickImage();

  Future<void> _send() async {
    final input = _inputKey.currentState;
    if (input == null || input.isEmpty || _isSending) return;
    setState(() => _isSending = true);
    try {
      await widget.controller.sendMessage(
          toUid: widget.peerId,
          spans: input.spans,
          images: input.images);
      input.clear();
      await _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('发送失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.peerName),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: Builder(builder: (context) {
              final items = _items;
              if (items == null) {
                if (_error != null) {
                  return _MessageState(message: _error!, onRetry: _reload);
                }
                return const Center(child: CircularProgressIndicator());
              }
              if (items.isEmpty) {
                return const _MessageState(message: '和 TA 说点什么吧');
              }
              return ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                reverse: true,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final record = items[items.length - 1 - index];
                  final isMine = _myId != null && record.uid == _myId;
                  return _MessageBubble(
                    record: record,
                    isMine: isMine,
                    palette: palette,
                    controller: widget.controller,
                    myAvatar: widget.controller.session?.avatar ?? '',
                    peerAvatar: _peer?.avatar ?? '',
                  );
                },
              );
            }),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: InlineEmojiInput(
                      key: _inputKey,
                      hintText: '说点什么…',
                      onUploadImage: widget.controller.uploadImage,
                    ),
                  ),
                  IconButton(
                    tooltip: '图片',
                    onPressed: _pickImage,
                    icon: const Icon(Icons.image_outlined),
                  ),
                  IconButton(
                    tooltip: '表情',
                    onPressed: _pickEmoji,
                    icon: const Icon(Icons.emoji_emotions_outlined),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filled(
                    tooltip: '发送',
                    onPressed: _isSending ? null : _send,
                    icon: const Icon(Icons.send_rounded, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.record,
    required this.isMine,
    required this.palette,
    required this.controller,
    required this.myAvatar,
    required this.peerAvatar,
  });

  final MessageRecord record;
  final bool isMine;
  final AppPalette palette;
  final AppController controller;
  final String myAvatar;
  final String peerAvatar;

  Widget _avatar(String url) => CircleAvatar(
        radius: 16,
        backgroundColor: palette.primary.withOpacity(.12),
        foregroundImage: url.isEmpty ? null : NetworkImage(url),
        foregroundColor: palette.primary,
        child: const Icon(Icons.person_rounded, size: 18),
      );

  /// 私信图片缩略图（横向滑动，点击进入全屏预览），参考评论区图片实现。
  Widget _buildImages(BuildContext context) => SizedBox(
        height: 76,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: record.images.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final uri = Uri.tryParse(record.images[index]);
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: GestureDetector(
                onTap: uri == null
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ImagePreviewPage(
                              uri: uri,
                              alt: '私信图片',
                              heroTag: 'message-image-$index-$uri',
                            ),
                          ),
                        ),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Hero(
                    tag: 'message-image-$index-$uri',
                    child: Image.network(
                      record.images[index],
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const ColoredBox(
                        color: Color(0xffefeff7),
                        child: Icon(Icons.broken_image_outlined,
                            color: Colors.blueGrey),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );

  @override
  Widget build(BuildContext context) => Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * .72,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMine) ...[
                _avatar(peerAvatar),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Column(
                  crossAxisAlignment:
                      isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isMine
                            ? palette.primary
                            : Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(12),
                          topRight: const Radius.circular(12),
                          bottomLeft: Radius.circular(isMine ? 12 : 2),
                          bottomRight: Radius.circular(isMine ? 2 : 12),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: isMine
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          if (record.spans.isNotEmpty)
                            ContentSpans(
                              spans: record.spans,
                              stickerSize: 34,
                              onLinkTap: (url) =>
                                  openContentLink(context, controller, url),
                              textStyle: TextStyle(
                                color: isMine
                                    ? Colors.white
                                    : Colors.blueGrey,
                                height: 1.35,
                              ),
                            )
                          else if (record.message.isNotEmpty)
                            Text(
                              record.message,
                              style: TextStyle(
                                color: isMine
                                    ? Colors.white
                                    : Colors.blueGrey,
                                height: 1.35,
                              ),
                            )
                          else if (record.images.isEmpty)
                            Text(
                              '（空消息）',
                              style: TextStyle(
                                color: isMine
                                    ? Colors.white
                                    : Colors.blueGrey,
                                height: 1.35,
                              ),
                            ),
                          if (record.images.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _buildImages(context),
                          ],
                        ],
                      ),
                    ),
                    if (record.time != null) ...[
                      const SizedBox(height: 3),
                      Text(_msgTime(record.time!),
                          style: const TextStyle(
                              color: Colors.blueGrey, fontSize: 10.5)),
                    ],
                  ],
                ),
              ),
              if (isMine) ...[
                const SizedBox(width: 8),
                _avatar(myAvatar),
              ],
            ],
          ),
        ),
      );
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.blueGrey)),
              if (onRetry != null) ...[
                const SizedBox(height: 10),
                TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('重试')),
              ],
            ],
          ),
        ),
      );
}

String _msgTime(DateTime value) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(value.year, value.month, value.day);
  final hhmm = '${_twoDigits(value.hour)}:${_twoDigits(value.minute)}';
  if (day == today) return hhmm;
  if (day == today.subtract(const Duration(days: 1))) return '昨天 $hhmm';
  if (value.year == now.year) return '${value.month}-${value.day} $hhmm';
  return '${value.year}-${value.month}-${value.day}';
}

String _twoDigits(int n) => n.toString().padLeft(2, '0');
