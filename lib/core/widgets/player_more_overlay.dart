import 'package:flutter/material.dart';

enum PlayerMorePresentation { side, bottom }

/// 播放器“播放设置”面板。
///
/// 全屏横屏使用右侧半屏遮罩，内嵌播放器使用底部弹出面板；音量与静音
/// 共用同一行，避免重复入口。
class PlayerMoreOverlay extends StatefulWidget {
  const PlayerMoreOverlay({
    super.key,
    required this.volume,
    required this.speed,
    required this.onVolumeChanged,
    required this.onSpeedChanged,
    required this.onDismiss,
    this.defaultQuality,
    this.availableQualities = const [],
    this.onDefaultQualityChanged,
    this.autoPlay,
    this.onAutoPlayChanged,
    this.onAppMiniPlayer,
    this.onSystemPip,
    this.onCast,
    this.presentation = PlayerMorePresentation.side,
  });

  final double volume;
  final double speed;
  final ValueChanged<double> onVolumeChanged;
  final ValueChanged<double> onSpeedChanged;
  final VoidCallback onDismiss;
  final String? defaultQuality;
  final List<String> availableQualities;
  final ValueChanged<String>? onDefaultQualityChanged;
  final bool? autoPlay;
  final ValueChanged<bool>? onAutoPlayChanged;
  final VoidCallback? onAppMiniPlayer;
  final VoidCallback? onSystemPip;
  final VoidCallback? onCast;
  final PlayerMorePresentation presentation;

  @override
  State<PlayerMoreOverlay> createState() => _PlayerMoreOverlayState();
}

class _PlayerMoreOverlayState extends State<PlayerMoreOverlay> {
  static const _speeds = <double>[.5, .75, 1, 1.25, 1.5, 2];
  late double _lastAudibleVolume;

  @override
  void initState() {
    super.initState();
    _lastAudibleVolume = widget.volume > 0 ? widget.volume : .7;
  }

  @override
  void didUpdateWidget(covariant PlayerMoreOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.volume > 0) _lastAudibleVolume = widget.volume;
  }

  void _toggleMute() {
    if (widget.volume > 0) {
      _lastAudibleVolume = widget.volume;
      widget.onVolumeChanged(0);
    } else {
      widget.onVolumeChanged(_lastAudibleVolume);
    }
  }

  String _speedLabel(double speed) =>
      speed == speed.roundToDouble() ? '${speed.toInt()}x' : '${speed}x';

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final isBottom = widget.presentation == PlayerMorePresentation.bottom;
      final colors = _PlayerMoreColors.resolve(context, themed: isBottom);
      final panelWidth = constraints.maxWidth / 2;
      final panelHeight = isBottom
          ? (MediaQuery.sizeOf(context).height * .72)
                .clamp(360.0, 680.0)
                .toDouble()
          : double.infinity;
      final panel = SizedBox(
        key: const ValueKey('player-more-panel'),
        width: isBottom ? constraints.maxWidth : panelWidth,
        height: panelHeight,
        child: Material(
          key: const ValueKey('player-more-material'),
          color: colors.surface,
          borderRadius: isBottom
              ? const BorderRadius.vertical(top: Radius.circular(24))
              : BorderRadius.zero,
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: !isBottom,
            left: false,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isBottom)
                    Center(
                      child: Container(
                        key: const ValueKey('player-more-drag-handle'),
                        width: 42,
                        height: 4,
                        margin: const EdgeInsets.only(top: 9, bottom: 2),
                        decoration: BoxDecoration(
                          color: colors.muted.withValues(alpha: .3),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            isBottom ? '播放设置' : '更多设置',
                            style: TextStyle(
                              color: colors.foreground,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭',
                          color: colors.muted,
                          onPressed: widget.onDismiss,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Divider(color: colors.divider, height: 1),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                      children: _buildSettings(context, colors),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (isBottom) return panel;
      return Stack(
        key: const ValueKey('player-more-overlay'),
        children: [
          Positioned.fill(
            child: GestureDetector(
              key: const ValueKey('player-more-barrier'),
              behavior: HitTestBehavior.opaque,
              onTap: widget.onDismiss,
              child: const ColoredBox(color: Color(0x99000000)),
            ),
          ),
          Align(alignment: Alignment.centerRight, child: panel),
        ],
      );
    },
  );

  List<Widget> _buildSettings(
    BuildContext context,
    _PlayerMoreColors colors,
  ) => [
    if (widget.onAppMiniPlayer != null ||
        widget.onSystemPip != null ||
        widget.onCast != null) ...[
      _SettingsGroup(
        title: '播放方式',
        colors: colors,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceAround,
            spacing: 12,
            runSpacing: 12,
            children: [
              if (widget.onAppMiniPlayer != null)
                _MoreAction(
                  icon: Icons.picture_in_picture_alt_rounded,
                  label: '应用内小窗',
                  onTap: widget.onAppMiniPlayer!,
                  colors: colors,
                ),
              if (widget.onSystemPip != null)
                _MoreAction(
                  icon: Icons.picture_in_picture_rounded,
                  label: '系统画中画',
                  onTap: widget.onSystemPip!,
                  colors: colors,
                ),
              if (widget.onCast != null)
                _MoreAction(
                  icon: Icons.cast_rounded,
                  label: 'DLNA 投屏',
                  onTap: widget.onCast!,
                  colors: colors,
                ),
            ],
          ),
        ],
      ),
      const SizedBox(height: 14),
    ],
    _SettingsGroup(
      title: '播放',
      colors: colors,
      children: [
        Row(
          children: [
            IconButton(
              key: const ValueKey('player-volume-toggle'),
              tooltip: widget.volume == 0 ? '取消静音' : '静音',
              color: colors.foreground,
              onPressed: _toggleMute,
              icon: Icon(
                widget.volume == 0
                    ? Icons.volume_off_rounded
                    : widget.volume < .5
                    ? Icons.volume_down_rounded
                    : Icons.volume_up_rounded,
              ),
            ),
            const SizedBox(width: 2),
            Text('音量', style: TextStyle(color: colors.foreground)),
            Expanded(
              child: Slider(
                value: widget.volume,
                onChanged: widget.onVolumeChanged,
                activeColor: Theme.of(context).colorScheme.primary,
                inactiveColor: colors.divider,
              ),
            ),
            SizedBox(
              width: 42,
              child: Text(
                '${(widget.volume * 100).round()}%',
                textAlign: TextAlign.end,
                style: TextStyle(color: colors.muted, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('播放速度', style: TextStyle(color: colors.foreground)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final speed in _speeds)
              ChoiceChip(
                label: Text(_speedLabel(speed)),
                selected: widget.speed == speed,
                onSelected: (_) => widget.onSpeedChanged(speed),
              ),
          ],
        ),
      ],
    ),
    if (widget.availableQualities.isNotEmpty || widget.autoPlay != null) ...[
      const SizedBox(height: 14),
      _SettingsGroup(
        title: '播放偏好',
        colors: colors,
        children: [
          if (widget.availableQualities.isNotEmpty) ...[
            Text('默认清晰度', style: TextStyle(color: colors.foreground)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('自动'),
                  selected: (widget.defaultQuality ?? '').isEmpty,
                  onSelected: (_) => widget.onDefaultQualityChanged?.call(''),
                ),
                for (final quality in widget.availableQualities)
                  ChoiceChip(
                    label: Text(quality),
                    selected: widget.defaultQuality == quality,
                    onSelected: (_) =>
                        widget.onDefaultQualityChanged?.call(quality),
                  ),
              ],
            ),
          ],
          if (widget.autoPlay != null) ...[
            if (widget.availableQualities.isNotEmpty)
              Divider(color: colors.divider, height: 28),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(
                Icons.play_circle_outline_rounded,
                color: colors.foreground,
              ),
              title: Text(
                '打开视频自动播放',
                style: TextStyle(color: colors.foreground),
              ),
              value: widget.autoPlay!,
              onChanged: widget.onAutoPlayChanged,
            ),
          ],
        ],
      ),
    ],
  ];
}

class _MoreAction extends StatelessWidget {
  const _MoreAction({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.colors,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final _PlayerMoreColors colors;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: onTap,
    child: SizedBox(
      width: 88,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colors.actionFill,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: colors.foreground),
            ),
            const SizedBox(height: 7),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    required this.title,
    required this.children,
    required this.colors,
  });

  final String title;
  final List<Widget> children;
  final _PlayerMoreColors colors;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(title, style: TextStyle(color: colors.muted, fontSize: 12)),
      ),
      DecoratedBox(
        decoration: BoxDecoration(
          color: colors.group,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    ],
  );
}

class _PlayerMoreColors {
  const _PlayerMoreColors({
    required this.surface,
    required this.group,
    required this.foreground,
    required this.muted,
    required this.divider,
    required this.actionFill,
  });

  factory _PlayerMoreColors.resolve(
    BuildContext context, {
    required bool themed,
  }) {
    if (!themed) {
      return const _PlayerMoreColors(
        surface: Color(0xff1d1d22),
        group: Color(0xff29292f),
        foreground: Colors.white,
        muted: Colors.white70,
        divider: Colors.white12,
        actionFill: Colors.white10,
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return _PlayerMoreColors(
      surface: scheme.surface,
      group: scheme.surfaceContainerHighest,
      foreground: scheme.onSurface,
      muted: scheme.onSurfaceVariant,
      divider: scheme.outlineVariant,
      actionFill: scheme.surfaceContainerHigh,
    );
  }

  final Color surface;
  final Color group;
  final Color foreground;
  final Color muted;
  final Color divider;
  final Color actionFill;
}
