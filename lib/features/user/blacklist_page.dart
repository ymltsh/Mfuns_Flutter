import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../home/home_repository.dart';
import 'block_user_action.dart';

class BlacklistPage extends StatefulWidget {
  const BlacklistPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<BlacklistPage> createState() => _BlacklistPageState();
}

class _BlacklistPageState extends State<BlacklistPage> {
  List<UserProfile>? _users;
  String? _error;
  final Set<int> _updating = <int>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.controller.session == null) {
      setState(() {
        _users = const [];
        _error = '请先登录后查看黑名单';
      });
      return;
    }
    try {
      final users = await widget.controller.blacklist();
      if (!mounted) return;
      setState(() {
        _users = users;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _users ??= const [];
        _error = '加载黑名单失败：$error';
      });
    }
  }

  Future<void> _unblock(UserProfile user) async {
    if (_updating.contains(user.id)) return;
    setState(() => _updating.add(user.id));
    final success = await confirmSetUserBlocked(
      context,
      controller: widget.controller,
      userId: user.id,
      userName: user.name,
      blocked: false,
    );
    if (!mounted) return;
    setState(() {
      _updating.remove(user.id);
      if (success) {
        _users = _users?.where((item) => item.id != user.id).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final users = _users;
    return Scaffold(
      appBar: AppBar(title: const Text('黑名单'), centerTitle: true),
      body: RefreshIndicator(
        onRefresh: _load,
        child: users == null
            ? const Center(child: CircularProgressIndicator())
            : users.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 180),
                      Icon(Icons.person_off_outlined,
                          size: 48, color: AppPalette.of(context).muted),
                      const SizedBox(height: 12),
                      Text(
                        _error ?? '黑名单为空',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppPalette.of(context).muted),
                      ),
                      if (_error != null && widget.controller.session != null)
                        Center(
                          child: TextButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('重试'),
                          ),
                        ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: users.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final user = users[index];
                      final updating = _updating.contains(user.id);
                      return ListTile(
                        leading: CircleAvatar(
                          foregroundImage: user.avatar.isEmpty
                              ? null
                              : NetworkImage(user.avatar),
                          child: user.avatar.isEmpty
                              ? const Icon(Icons.person_outline_rounded)
                              : null,
                        ),
                        title: Text(user.name),
                        subtitle: Text('MF ${user.id}'),
                        trailing: TextButton(
                          onPressed: updating ? null : () => _unblock(user),
                          child: updating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('解除'),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
