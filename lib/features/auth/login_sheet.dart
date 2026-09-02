import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/theme/app_theme.dart';
import 'session_store.dart';

/// 弹出登录面板：已保存的账号可直接一键切换（游客状态），
/// 下方为常规账号密码登录表单。
Future<void> showLoginSheet(BuildContext context, AppController controller) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _LoginSheet(controller: controller),
    );

class _LoginSheet extends StatefulWidget {
  const _LoginSheet({required this.controller});

  final AppController controller;

  @override
  State<_LoginSheet> createState() => _LoginSheetState();
}

class _LoginSheetState extends State<_LoginSheet> {
  final _account = TextEditingController();
  final _password = TextEditingController();
  var _obscurePassword = true;

  @override
  void dispose() {
    _account.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_account.text.trim().isEmpty || _password.text.isEmpty) return;
    final error = await widget.controller.login(_account.text, _password.text);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  /// 一键切换已保存账号：成功即关闭登录面板。
  Future<void> _switchTo(StoredAccount account) async {
    final error = await widget.controller.switchToAccount(account);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final viewInsets = media.viewInsets.bottom;
    final availableHeight = media.size.height - viewInsets;
    final palette = AppPalette.of(context);
    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: viewInsets),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          height: (media.size.height * 0.78).clamp(0.0, availableHeight),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 26),
            child: AnimatedBuilder(
              animation: widget.controller,
              builder: (context, _) {
                final controller = widget.controller;
                final currentKey = controller.activeAccountKey;
                final saved = controller.session == null
                    ? controller.accounts
                    : const <StoredAccount>[];
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: palette.divider,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: palette.chip,
                          foregroundColor: palette.primary,
                          child: const Icon(Icons.pets_rounded),
                        ),
                        const SizedBox(width: 10),
                        Text('登录 Mfuns',
                            style: TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                color: palette.ink)),
                      ],
                    ),
                    if (saved.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text('已保存的账号',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: palette.muted)),
                      const SizedBox(height: 6),
                      for (final account in saved)
                        if (account.key != currentKey)
                          _SavedAccountRow(
                            account: account,
                            expired: controller.isAccountExpired(account),
                            busy: controller.isSwitchingAccount,
                            onTap: () => _switchTo(account),
                          ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: Divider(color: palette.divider)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text('登录其他账号',
                                style: TextStyle(
                                    color: palette.muted, fontSize: 12)),
                          ),
                          Expanded(child: Divider(color: palette.divider)),
                        ],
                      ),
                      const SizedBox(height: 14),
                    ] else
                      const SizedBox(height: 22),
                    TextField(
                      controller: _account,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(
                          labelText: '用户名 / ID / 邮箱 / 手机号'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: _obscurePassword,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _login(),
                      decoration: InputDecoration(
                        labelText: '密码',
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                          icon: Icon(_obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: palette.primary,
                            padding: const EdgeInsets.symmetric(vertical: 14)),
                        onPressed: controller.isLoggingIn ? null : _login,
                        child: controller.isLoggingIn
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('登录'),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// 已保存账号的一键切换行（游客登录面板内）。
class _SavedAccountRow extends StatelessWidget {
  const _SavedAccountRow({
    required this.account,
    required this.expired,
    required this.busy,
    required this.onTap,
  });

  final StoredAccount account;
  final bool expired;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: CircleAvatar(
        radius: 19,
        backgroundColor: palette.primary.withOpacity(.12),
        foregroundImage:
            account.avatar.isEmpty ? null : NetworkImage(account.avatar),
        foregroundColor: palette.primary,
        child: Text(account.displayName.isEmpty ? '?' : account.displayName[0],
            style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      title: Text(account.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: palette.ink, fontWeight: FontWeight.w800, fontSize: 15)),
      subtitle: Text(
        expired
            ? '登录已失效，请重新登录'
            : account.userId == null
                ? '点击切换到此账号'
                : 'UID ${account.userId} · 点击切换到此账号',
        style: TextStyle(
            color: expired ? const Color(0xFFD04A4A) : palette.muted,
            fontSize: 12,
            fontWeight: expired ? FontWeight.w700 : FontWeight.w400),
      ),
      trailing: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(Icons.swap_horiz_rounded, color: palette.primary),
      onTap: busy ? null : onTap,
    );
  }
}
