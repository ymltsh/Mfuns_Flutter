import 'package:flutter/material.dart';

import '../../core/download/download_manager.dart';
import '../../core/download/download_policy.dart';
import '../../core/theme/app_theme.dart';
import '../download/download_controller.dart';
import '../download/widgets/download_progress.dart';

/// 下载设置：仅 Wi-Fi 下载、最大并发数、当前下载空间信息。
class DownloadSettingsPage extends StatefulWidget {
  const DownloadSettingsPage({super.key, DownloadManager? manager})
      : _manager = manager;

  final DownloadManager? _manager;

  @override
  State<DownloadSettingsPage> createState() => _DownloadSettingsPageState();
}

class _DownloadSettingsPageState extends State<DownloadSettingsPage> {
  late final DownloadManager _manager;
  DownloadPolicy? _policy;
  var _loaded = false;
  DownloadController? _controller;

  @override
  void initState() {
    super.initState();
    _manager = widget._manager ?? DownloadManager.instance;
    _load();
    _controller = DownloadController(manager: _manager);
    _controller!.initialize();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final policy = _manager.policy;
    if (mounted) {
      setState(() {
        _policy = policy;
        _loaded = true;
      });
    }
  }

  Future<void> _updatePolicy(DownloadPolicy policy) async {
    setState(() => _policy = policy);
    await _manager.updatePolicy(policy);
  }

  Future<void> _selectMaxConcurrent() async {
    final current = _policy?.maxConcurrent ?? 2;
    final selected = await showModalBottomSheet<int>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('最大并发下载数',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
            for (var value = 1; value <= 5; value++)
              ListTile(
                title: Text('$value 个'),
                trailing: value == current
                    ? Icon(Icons.check_rounded,
                        color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(value),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    await _updatePolicy(
        (_policy ?? DownloadPolicy.defaults).copyWith(maxConcurrent: selected));
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).colorScheme;
    final policy = _policy;
    return Scaffold(
      appBar: AppBar(title: const Text('下载设置'), centerTitle: true),
      body: ListenableBuilder(
        listenable: _controller!,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: [
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  SwitchListTile(
                    value: policy?.wifiOnly ?? true,
                    title: Text('仅 Wi-Fi 下载',
                        style: TextStyle(
                            color: AppPalette.of(context).muted,
                            fontWeight: FontWeight.w700)),
                    subtitle: Text('开启后移动网络下自动暂停下载，新任务需手动确认',
                        style: TextStyle(
                            color: AppPalette.of(context).muted, fontSize: 12)),
                    secondary: CircleAvatar(
                      backgroundColor: palette.primary.withOpacity(.11),
                      foregroundColor: palette.primary,
                      child: const Icon(Icons.wifi_rounded, size: 20),
                    ),
                    onChanged: _loaded
                        ? (value) => _updatePolicy(
                            (policy ?? DownloadPolicy.defaults)
                                .copyWith(wifiOnly: value))
                        : null,
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: palette.primary.withOpacity(.11),
                      foregroundColor: palette.primary,
                      child: const Icon(Icons.speed_rounded, size: 20),
                    ),
                    title: Text('最大并发下载数',
                        style: TextStyle(
                            color: AppPalette.of(context).muted,
                            fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      '同时下载 ${policy?.maxConcurrent ?? 2} 个任务',
                      style: TextStyle(
                          color: AppPalette.of(context).muted, fontSize: 12),
                    ),
                    trailing: Icon(Icons.chevron_right_rounded,
                        color: AppPalette.of(context).muted),
                    onTap: _loaded ? _selectMaxConcurrent : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('下载空间',
                        style: TextStyle(
                            color: AppPalette.of(context).muted,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(
                      '已下载 ${_controller!.completedCount} 个视频 · '
                      '占用 ${formatBytes(_controller!.usedSpaceBytes)}',
                      style: TextStyle(
                          color: AppPalette.of(context).muted, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '缓存文件保存在 App 私有目录，删除下载任务会同步清理文件。',
                      style: TextStyle(
                          color: AppPalette.of(context).muted,
                          fontSize: 12,
                          height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
