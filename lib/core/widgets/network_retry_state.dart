import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 内容无法加载时保留下拉刷新，并为桌面和触控设备提供刷新按钮。
class NetworkRetryState extends StatefulWidget {
  const NetworkRetryState({
    super.key,
    required this.onRefresh,
    this.scrollController,
  });

  final Future<void> Function() onRefresh;
  final ScrollController? scrollController;

  static const message = '似乎有问题，请尝试刷新';

  @override
  State<NetworkRetryState> createState() => _NetworkRetryStateState();
}

class _NetworkRetryStateState extends State<NetworkRetryState> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await widget.onRefresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text(NetworkRetryState.message)),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.hasBoundedWidth ? constraints.maxWidth : 400.0;
      final height = constraints.hasBoundedHeight
          ? constraints.maxHeight
          : 600.0;
      final imageSize = math.min(220.0, math.min(width * .5, height * .38)) / 4;
      return SingleChildScrollView(
        controller: widget.scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: height),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/network_retry.png',
                      width: imageSize,
                      height: imageSize,
                      fit: BoxFit.contain,
                      excludeFromSemantics: true,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      NetworkRetryState.message,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _refreshing ? null : _refresh,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(_refreshing ? '刷新中…' : '刷新'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
