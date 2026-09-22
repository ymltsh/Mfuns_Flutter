import 'dart:async';

import 'package:flutter/material.dart';

import '../media/dlna_cast_controller.dart';

final ValueNotifier<bool> _dlnaControlsCollapsed = ValueNotifier(false);

Future<DlnaRenderer?> showDlnaDevicePicker(BuildContext context) async {
  final controller = DlnaCastController.instance;
  unawaited(controller.startDiscovery());
  final selected = await showModalBottomSheet<DlnaRenderer>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (_) => const _DlnaDevicePicker(),
  );
  if (!controller.isConnected) {
    await controller.stopDiscovery();
  }
  return selected;
}

class _DlnaDevicePicker extends StatelessWidget {
  const _DlnaDevicePicker();

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: DlnaCastController.instance,
    builder: (context, _) {
      final controller = DlnaCastController.instance;
      return SafeArea(
        child: SizedBox(
          height: 390,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  '选择 DLNA 设备',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text('请确保手机和电视连接同一 Wi-Fi 网络。'),
              ),
              const SizedBox(height: 8),
              if (controller.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    controller.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Expanded(
                child: controller.devices.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 14),
                            Text('正在搜索电视和盒子…'),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: controller.devices.length,
                        itemBuilder: (context, index) {
                          final device = controller.devices[index];
                          return ListTile(
                            leading: const Icon(Icons.tv_rounded, size: 30),
                            title: Text(device.name),
                            subtitle: const Text('DLNA 播放设备'),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => Navigator.of(context).pop(device),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: OutlinedButton.icon(
                  onPressed: controller.isDiscovering
                      ? null
                      : controller.startDiscovery,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重新搜索'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class DlnaCastStatusOverlay extends StatefulWidget {
  const DlnaCastStatusOverlay({
    super.key,
    this.onOpen,
    this.bottom = 12,
    this.avoidBottomRightFab = false,
  });

  final VoidCallback? onOpen;
  final double bottom;
  final bool avoidBottomRightFab;

  @override
  State<DlnaCastStatusOverlay> createState() => _DlnaCastStatusOverlayState();
}

class _DlnaCastStatusOverlayState extends State<DlnaCastStatusOverlay> {
  static const _collapsedSize = 54.0;
  bool _collapsed = false;
  Offset? _position;
  bool _userMoved = false;

  @override
  void initState() {
    super.initState();
    _collapsed = _dlnaControlsCollapsed.value;
    _dlnaControlsCollapsed.addListener(_handleCollapsedChanged);
  }

  void _handleCollapsedChanged() {
    if (mounted) {
      setState(() => _collapsed = _dlnaControlsCollapsed.value);
    }
  }

  @override
  void dispose() {
    _dlnaControlsCollapsed.removeListener(_handleCollapsedChanged);
    _dlnaControlsCollapsed.value = false;
    super.dispose();
  }

  Offset _initialPosition(Size size, EdgeInsets padding) {
    final avoidance = widget.avoidBottomRightFab ? 68.0 : 0.0;
    return Offset(
      size.width - padding.right - _collapsedSize - 12,
      size.height - padding.bottom - _collapsedSize - widget.bottom - avoidance,
    );
  }

  Offset _clampPosition(Offset value, Size size, EdgeInsets padding) => Offset(
    value.dx
        .clamp(
          padding.left + 8,
          size.width - padding.right - _collapsedSize - 8,
        )
        .toDouble(),
    value.dy
        .clamp(
          padding.top + 8,
          size.height - padding.bottom - _collapsedSize - 8,
        )
        .toDouble(),
  );

  Offset _avoidCommentFab(Offset value, Size size, EdgeInsets padding) {
    if (!widget.avoidBottomRightFab) return value;
    final castRect = value & const Size.square(_collapsedSize);
    final commentRect = Rect.fromLTWH(
      size.width - padding.right - 64,
      size.height - padding.bottom - 64,
      56,
      56,
    ).inflate(6);
    if (!castRect.overlaps(commentRect)) return value;
    return _clampPosition(
      Offset(value.dx, commentRect.top - _collapsedSize - 6),
      size,
      padding,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    if (!_collapsed) {
      return Positioned(
        left: 12,
        right: 12,
        bottom: widget.bottom,
        child: DlnaCastStatusBar(
          onOpen: widget.onOpen,
          onCollapse: () {
            _position = null;
            _userMoved = false;
            _dlnaControlsCollapsed.value = true;
          },
        ),
      );
    }

    final position = _avoidCommentFab(
      _clampPosition(
        _userMoved && _position != null
            ? _position!
            : _initialPosition(size, padding),
        size,
        padding,
      ),
      size,
      padding,
    );
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: GestureDetector(
        key: const ValueKey('dlna-cast-collapsed-control'),
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => setState(() {
          _userMoved = true;
          _position = _clampPosition(position + details.delta, size, padding);
        }),
        child: Material(
          elevation: 12,
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: Tooltip(
            message: '展开投屏控制',
            child: InkWell(
              onTap: () => _dlnaControlsCollapsed.value = false,
              child: SizedBox.square(
                dimension: _collapsedSize,
                child: Icon(
                  Icons.cast_connected_rounded,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DlnaCastStatusBar extends StatelessWidget {
  const DlnaCastStatusBar({super.key, this.onOpen, this.onCollapse});

  final VoidCallback? onOpen;
  final VoidCallback? onCollapse;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: DlnaCastController.instance,
    builder: (context, _) {
      final controller = DlnaCastController.instance;
      if (!controller.isConnected) return const SizedBox.shrink();
      return Material(
        elevation: 12,
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen ?? () => showDlnaRemoteControl(context),
          child: SizedBox(
            height: 62,
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(
                  Icons.cast_connected_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        controller.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '正在投屏到 ${controller.connected?.name ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (onCollapse != null)
                  IconButton(
                    tooltip: '折叠投屏控制',
                    onPressed: onCollapse,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                IconButton(
                  tooltip: controller.isPlaying ? '暂停' : '播放',
                  onPressed: controller.isPlaying
                      ? controller.pause
                      : controller.play,
                  icon: Icon(
                    controller.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
                IconButton(
                  tooltip: '退出投屏',
                  onPressed: controller.disconnect,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

bool _isDlnaRemoteControlOpen = false;

Future<void> showDlnaRemoteControl(BuildContext context) async {
  if (!context.mounted || _isDlnaRemoteControlOpen) return;
  _isDlnaRemoteControlOpen = true;
  try {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 2 / 3,
        child: Material(
          color: Theme.of(sheetContext).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              SizedBox(
                height: 44,
                child: Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        sheetContext,
                      ).colorScheme.onSurfaceVariant.withValues(alpha: .35),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ),
              const Expanded(child: _DlnaRemoteControl()),
            ],
          ),
        ),
      ),
    );
  } finally {
    _isDlnaRemoteControlOpen = false;
  }
}

class _DlnaRemoteControl extends StatefulWidget {
  const _DlnaRemoteControl();

  @override
  State<_DlnaRemoteControl> createState() => _DlnaRemoteControlState();
}

class _DlnaRemoteControlState extends State<_DlnaRemoteControl> {
  double? _dragPosition;

  String _time(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: DlnaCastController.instance,
    builder: (context, _) {
      final controller = DlnaCastController.instance;
      final max = controller.duration.inMilliseconds.toDouble();
      final current =
          _dragPosition ??
          controller.position.inMilliseconds.clamp(0, max).toDouble();
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      controller.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '刷新投屏状态',
                    onPressed: controller.isRefreshing
                        ? null
                        : controller.refreshStatus,
                    icon: controller.isRefreshing
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('投屏设备：${controller.connected?.name ?? ''}'),
              if (controller.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  controller.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (controller.parts.length > 1) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: controller.parts.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final part = controller.parts[index].part;
                      return ChoiceChip(
                        label: Text('P$part'),
                        selected: part == controller.currentPart,
                        onSelected: controller.isSwitchingPart
                            ? null
                            : (_) => controller.selectPart(part),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Slider(
                value: max <= 0 ? 0 : current,
                max: max <= 0 ? 1 : max,
                onChanged: max <= 0
                    ? null
                    : (value) => setState(() => _dragPosition = value),
                onChangeEnd: max <= 0
                    ? null
                    : (value) {
                        _dragPosition = null;
                        controller.seek(Duration(milliseconds: value.round()));
                      },
              ),
              Row(
                children: [
                  Text(_time(Duration(milliseconds: current.round()))),
                  const Spacer(),
                  Text(_time(controller.duration)),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    tooltip: '后退 10 秒',
                    onPressed: () => controller.seek(
                      controller.position - const Duration(seconds: 10),
                    ),
                    icon: const Icon(Icons.replay_10_rounded),
                  ),
                  const SizedBox(width: 16),
                  IconButton.filled(
                    tooltip: controller.isPlaying ? '暂停' : '播放',
                    iconSize: 34,
                    onPressed: controller.isPlaying
                        ? controller.pause
                        : controller.play,
                    icon: Icon(
                      controller.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton.filledTonal(
                    tooltip: '前进 10 秒',
                    onPressed: () => controller.seek(
                      controller.position + const Duration(seconds: 10),
                    ),
                    icon: const Icon(Icons.forward_10_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.volume_down_rounded),
                  Expanded(
                    child: Slider(
                      value: controller.volume / 100,
                      onChanged: controller.setVolume,
                    ),
                  ),
                  Text('${controller.volume}%'),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  await controller.disconnect();
                  if (context.mounted) Navigator.of(context).pop();
                },
                icon: const Icon(Icons.cast_rounded),
                label: const Text('退出投屏'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
