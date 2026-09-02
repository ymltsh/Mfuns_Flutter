import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/theme/app_theme.dart';
import 'login_sheet.dart';
import 'session_store.dart';

/// 账号管理页：查看本机保存的账号、一键切换、删除或退出登录。
class AccountManagePage extends StatefulWidget {
  const AccountManagePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<AccountManagePage> createState() => _AccountManagePageState();
}

class _AccountManagePageState extends State<AccountManagePage> {
  Future<void> _switchTo(StoredAccount account) async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await widget.controller.switchToAccount(account);
    if (!mounted) return;
    messenger.showSnackBar(
        SnackBar(content: Text(error ?? '已切换至 ${account.displayName}')));
  }

  Future<void> _confirmDelete(StoredAccount account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: const Text('删除该账号'),
        content: Text('将从本机删除「${account.displayName}」的登录凭证，'
            '删除后需要重新登录才能使用该账号。确定删除吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD04A4A)),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.controller.removeSavedAccount(account);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除「${account.displayName}」的登录凭证')));
    }
  }

  /// 退出当前账号：删除本机凭证并自动切换至最近使用的其他账号。
  Future<void> _confirmLogout() async {
    final controller = widget.controller;
    final name = controller.session?.displayName ?? '当前账号';
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: const Text('退出当前账号'),
        content: Text('将从本机删除「$name」的登录凭证。'
            '若保存了其他账号，将自动切换至最近使用的账号。确定退出吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD04A4A)),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final next = await controller.logoutCurrent();
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
        content:
            Text(next == null ? '已退出登录' : '已退出，当前账号：${next.displayName}')));
  }

  void _openLoginSheet() {
    showLoginSheet(context, widget.controller);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final palette = AppPalette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('账号管理'), centerTitle: true),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final session = controller.session;
          final currentKey = controller.activeAccountKey;
          final others = controller.accounts
              .where((account) => account.key != currentKey)
              .toList(growable: false);
          final busy = controller.isSwitchingAccount;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 36),
            children: [
              if (session != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 15, 8, 15),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: palette.primary.withOpacity(.12),
                          foregroundImage: session.avatar.isEmpty
                              ? null
                              : NetworkImage(session.avatar),
                          foregroundColor: palette.primary,
                          child: Text(
                              session.displayName.isEmpty
                                  ? '?'
                                  : session.displayName[0],
                              style: const TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.w800)),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(session.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: palette.ink,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 3),
                              Text(
                                  session.userId == null
                                      ? '当前账号'
                                      : '当前账号 · UID ${session.userId}',
                                  style: TextStyle(
                                      color: palette.muted, fontSize: 12.5)),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          onPressed: busy ? null : _confirmLogout,
                          style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFD04A4A)),
                          icon: const Icon(Icons.logout_rounded, size: 19),
                          label: const Text('退出登录'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 15),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: palette.primary.withOpacity(.12),
                          foregroundColor: palette.primary,
                          child: const Icon(Icons.pets_rounded, size: 28),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('当前未登录',
                                  style: TextStyle(
                                      color: palette.ink,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 3),
                              Text('登录后可同步浏览记录与消息',
                                  style: TextStyle(
                                      color: palette.muted, fontSize: 12.5)),
                            ],
                          ),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: palette.primary),
                          onPressed: busy ? null : _openLoginSheet,
                          child: const Text('登录'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (others.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text('已保存的账号',
                    style: TextStyle(
                        color: palette.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < others.length; i++) ...[
                        if (i > 0)
                          Divider(
                              height: 1, indent: 60, color: palette.divider),
                        _AccountRow(
                          account: others[i],
                          expired: controller.isAccountExpired(others[i]),
                          busy: busy,
                          onSwitch: () => _switchTo(others[i]),
                          onDelete: () => _confirmDelete(others[i]),
                        ),
                      ],
                    ],
                  ),
                ),
              ] else ...[
                const SizedBox(height: 18),
                Center(
                  child: Text(session == null ? '还没有保存的账号' : '当前仅保存了这一个账号',
                      style: TextStyle(color: palette.muted, fontSize: 13)),
                ),
              ],
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: palette.primary,
                      padding: const EdgeInsets.symmetric(vertical: 13)),
                  onPressed: busy ? null : _openLoginSheet,
                  icon: const Icon(Icons.person_add_alt_rounded),
                  label: Text(session == null ? '登录账号' : '登录其他账号'),
                ),
              ),
              const SizedBox(height: 12),
              Text('账号凭证仅保存在本设备，切换或删除不会影响账号在其他设备的使用。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.muted, fontSize: 11.5)),
            ],
          );
        },
      ),
    );
  }
}

/// 已保存账号行：点击切换；「更多」菜单可删除本机凭证。
class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.account,
    required this.expired,
    required this.busy,
    required this.onSwitch,
    required this.onDelete,
  });

  final StoredAccount account;
  final bool expired;
  final bool busy;
  final VoidCallback onSwitch;
  final VoidCallback onDelete;

  static String _timeLabel(DateTime? time) {
    if (time == null) return '';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final lastUsed = _timeLabel(account.lastUsedAt);
    final trailing = busy
        ? null
        : PopupMenuButton<String>(
            tooltip: '更多操作',
            onSelected: (value) {
              if (value == 'delete') onDelete();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'delete',
                child:
                    Text('删除此账号', style: TextStyle(color: Color(0xFFD04A4A))),
              ),
            ],
            icon: Icon(Icons.more_vert_rounded, color: palette.muted),
          );
    return ListTile(
      onTap: busy ? null : onSwitch,
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: palette.primary.withOpacity(.12),
        foregroundImage:
            account.avatar.isEmpty ? null : NetworkImage(account.avatar),
        foregroundColor: palette.primary,
        child: Text(account.displayName.isEmpty ? '?' : account.displayName[0],
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      ),
      title: Text(account.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: palette.ink, fontWeight: FontWeight.w800, fontSize: 15.5)),
      subtitle: Text(
        expired
            ? '登录已失效，请重新登录'
            : account.userId == null
                ? (lastUsed.isEmpty ? '点击切换到此账号' : '最近使用 $lastUsed')
                : 'UID ${account.userId}'
                    '${lastUsed.isEmpty ? ' · 点击切换到此账号' : ' · 最近使用 $lastUsed'}',
        style: TextStyle(
            color: expired ? const Color(0xFFD04A4A) : palette.muted,
            fontSize: 12,
            fontWeight: expired ? FontWeight.w700 : FontWeight.w400),
      ),
      trailing: trailing,
    );
  }
}
