import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/network/network_diagnostics.dart';
import '../../core/theme/app_theme.dart';

/// 设置 → 网络诊断：按优先级逐项检测连接状态、DNS、连通性、
/// 延迟、业务接口、IPv4/IPv6 与多域名可达性。
class NetworkDiagnosticsPage extends StatefulWidget {
  const NetworkDiagnosticsPage({super.key});

  @override
  State<NetworkDiagnosticsPage> createState() => _NetworkDiagnosticsPageState();
}

enum _EntryPhase { pending, running, pass, fail }

class _DiagnosticEntry {
  _DiagnosticEntry({
    required this.title,
    required this.subtitle,
    required this.run,
  });

  final String title;
  final String subtitle;
  final Future<DiagCheckResult> Function(NetworkDiagnostics engine) run;

  var phase = _EntryPhase.pending;
  String detail = '';
  Duration? latency;
}

class _NetworkDiagnosticsPageState extends State<NetworkDiagnosticsPage> {
  final _entries = <_DiagnosticEntry>[
    _DiagnosticEntry(
      title: '网络连接状态',
      subtitle: 'Wi-Fi / 移动网络 / 无网络',
      run: (engine) => engine.connectionStatus(),
    ),
    _DiagnosticEntry(
      title: 'DNS 解析',
      subtitle: '判断 ${AppConfig.apiHost} 域名解析是否正常',
      run: (engine) => engine.dnsResolve(AppConfig.apiHost),
    ),
    _DiagnosticEntry(
      title: 'TCP / HTTPS 连接',
      subtitle: '判断业务服务器（${AppConfig.apiHost}:443）是否真正可达',
      run: (engine) async {
        final tcp = await engine.tcpConnect(AppConfig.apiHost, 443);
        if (!tcp.ok) return tcp;
        final https = await engine.httpsProbe('https://${AppConfig.apiHost}/');
        final total = Duration(
          milliseconds: (tcp.latency?.inMilliseconds ?? 0) +
              (https.latency?.inMilliseconds ?? 0),
        );
        return DiagCheckResult(
          ok: https.ok,
          message: '${tcp.message}；${https.message}',
          latency: total,
        );
      },
    ),
    _DiagnosticEntry(
      title: '网络延迟',
      subtitle: '连续 3 次连接 ${AppConfig.apiHost}，判断网络是否明显卡顿',
      run: (engine) => engine.measureLatency(),
    ),
    _DiagnosticEntry(
      title: '业务 HTTP 请求',
      subtitle: '判断「能上网」还是「能访问目标服务」',
      run: (engine) => engine.businessApiCheck(),
    ),
    _DiagnosticEntry(
      title: 'IPv4 / IPv6',
      subtitle: '分别解析 ${AppConfig.apiHost} 并建连，判断是否存在单栈异常',
      run: (engine) => engine.ipStackCheck(AppConfig.apiHost),
    ),
    _DiagnosticEntry(
      title: '多域名探测',
      subtitle: '探测 API、图片 CDN、更新源等多个域名，排除单个故障',
      run: (engine) => engine.multiDomainProbe(),
    ),
  ];

  var _running = false;
  var _started = false;

  String get _summaryText {
    if (!_started) return '共 ${_entries.length} 项检测';
    final done = _entries
        .where(
            (e) => e.phase == _EntryPhase.pass || e.phase == _EntryPhase.fail)
        .length;
    final failed = _entries.where((e) => e.phase == _EntryPhase.fail).length;
    if (_running) return '正在检测… $done/${_entries.length}';
    return failed == 0
        ? '全部通过（$done 项）'
        : '$failed 项异常（$done/${_entries.length}）';
  }

  Color _phaseColor(_EntryPhase phase) {
    final palette = AppPalette.of(context);
    return switch (phase) {
      _EntryPhase.pending => Colors.blueGrey.shade300,
      _EntryPhase.running => palette.primary,
      _EntryPhase.pass => Colors.green.shade600,
      _EntryPhase.fail => Colors.red.shade600,
    };
  }

  Widget _phaseIcon(_EntryPhase phase, Color color) {
    if (phase == _EntryPhase.running) {
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: color,
        ),
      );
    }
    return Icon(
      switch (phase) {
        _EntryPhase.pending => Icons.radio_button_unchecked_rounded,
        _EntryPhase.pass => Icons.check_circle_rounded,
        _EntryPhase.fail => Icons.error_rounded,
        _EntryPhase.running => Icons.hourglass_top_rounded,
      },
      size: 22,
      color: color,
    );
  }

  Future<void> _runAll() async {
    if (_running) return;
    setState(() {
      _running = true;
      _started = true;
      for (final entry in _entries) {
        entry.phase = _EntryPhase.pending;
        entry.detail = '';
        entry.latency = null;
      }
    });
    final engine = NetworkDiagnostics();
    for (final entry in _entries) {
      if (!mounted) return;
      setState(() => entry.phase = _EntryPhase.running);
      final result = await entry.run(engine);
      if (!mounted) return;
      setState(() {
        entry.phase = result.ok ? _EntryPhase.pass : _EntryPhase.fail;
        entry.detail = result.message;
        entry.latency = result.latency;
      });
    }
    if (!mounted) return;
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('网络诊断'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.network_check_rounded,
                          color: palette.primary, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('检测结果总览',
                            style: TextStyle(
                                color: AppPalette.of(context).muted,
                                fontWeight: FontWeight.w800)),
                      ),
                      Text(_summaryText,
                          style: TextStyle(
                              color: _running
                                  ? palette.primary
                                  : AppPalette.of(context).muted,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Text(
                    '${NetworkDiagnostics.deviceInfoSummary()}\n'
                    'App v${AppConfig.appVersion} · 检测时间 ${_now()}',
                    style: TextStyle(
                        color: AppPalette.of(context).muted,
                        fontSize: 12,
                        height: 1.6),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _running ? null : _runAll,
                      icon: _running
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Icon(
                              _started
                                  ? Icons.refresh_rounded
                                  : Icons.play_arrow_rounded,
                              size: 20,
                            ),
                      label: Text(_running
                          ? '检测中…'
                          : _started
                              ? '重新检测'
                              : '开始检测'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          for (final entry in _entries) ...[
            _EntryCard(entry: entry, colorOf: _phaseColor, iconOf: _phaseIcon),
            if (entry != _entries.last) const SizedBox(height: 10),
          ],
          const SizedBox(height: 16),
          Text('诊断均为只读探测，不收集任何数据；结果仅用于排查网络问题。',
              style:
                  TextStyle(color: AppPalette.of(context).muted, fontSize: 12)),
        ],
      ),
    );
  }

  static String _now() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)} '
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.colorOf,
    required this.iconOf,
  });

  final _DiagnosticEntry entry;
  final Color Function(_EntryPhase phase) colorOf;
  final Widget Function(_EntryPhase phase, Color color) iconOf;

  @override
  Widget build(BuildContext context) {
    final color = colorOf(entry.phase);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(.11),
          foregroundColor: color,
          child: iconOf(entry.phase, color),
        ),
        title: Text(entry.title,
            style: TextStyle(
                color: AppPalette.of(context).muted,
                fontWeight: FontWeight.w700)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry.subtitle,
                style: TextStyle(
                    color: AppPalette.of(context).muted, fontSize: 12)),
            if (entry.detail.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                entry.detail,
                style: TextStyle(
                  color: entry.phase == _EntryPhase.fail
                      ? Colors.red.shade700
                      : AppPalette.of(context).muted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
        trailing: entry.latency == null
            ? null
            : Text(
                formatDuration(entry.latency!),
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w700),
              ),
      ),
    );
  }
}
