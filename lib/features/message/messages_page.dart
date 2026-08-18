import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/content_link_handler.dart';
import '../../core/widgets/content_spans.dart';
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
  late Future<List<MessageConversation>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.controller.messageConversations();
  }

  Future<void> reload() async {
    final next = widget.controller.messageConversations();
    setState(() => _future = next);
    await next;
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
    return FutureBuilder<List<MessageConversation>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _MessageState(
            message: '加载会话失败：${snapshot.error}',
            onRetry: reload,
          );
        }
        final items = snapshot.data ?? const <MessageConversation>[];
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
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MessageDetailPage(
                    controller: widget.controller,
                    peerId: items[index].userId,
                    peerName: items[index].userName,
                  ),
                ),
              ),
            ),
          ),
        );
      },
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
  final _input = TextEditingController();
  late Future<List<MessageRecord>> _future;
  var _isSending = false;

  int? get _myId => widget.controller.session?.userId;

  @override
  void initState() {
    super.initState();
    _future = widget.controller.messageRecord(widget.peerId);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final next = widget.controller.messageRecord(widget.peerId);
    setState(() => _future = next);
    await next;
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _isSending) return;
    setState(() => _isSending = true);
    try {
      await widget.controller.sendMessage(toUid: widget.peerId, text: text);
      _input.clear();
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
            child: FutureBuilder<List<MessageRecord>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _MessageState(
                    message: '加载聊天记录失败：${snapshot.error}',
                    onRetry: _reload,
                  );
                }
                final items = snapshot.data ?? const <MessageRecord>[];
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
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: '说点什么…',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
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
  });

  final MessageRecord record;
  final bool isMine;
  final AppPalette palette;
  final AppController controller;

  @override
  Widget build(BuildContext context) => Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * .72,
          ),
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
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(12),
                    topRight: const Radius.circular(12),
                    bottomLeft: Radius.circular(isMine ? 12 : 2),
                    bottomRight: Radius.circular(isMine ? 2 : 12),
                  ),
                ),
                child: record.spans.isEmpty
                    ? Text(
                        record.message.isEmpty ? '（空消息）' : record.message,
                        style: TextStyle(
                          color: isMine ? Colors.white : Colors.blueGrey,
                          height: 1.35,
                        ),
                      )
                    : ContentSpans(
                        spans: record.spans,
                        stickerSize: 34,
                        onLinkTap: (url) =>
                            openContentLink(context, controller, url),
                        textStyle: TextStyle(
                          color: isMine ? Colors.white : Colors.blueGrey,
                          height: 1.35,
                        ),
                      ),
              ),
              if (record.time != null) ...[
                const SizedBox(height: 3),
                Text(_msgTime(record.time!),
                    style: const TextStyle(color: Colors.blueGrey, fontSize: 10.5)),
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
