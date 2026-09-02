import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/theme/app_theme.dart';
import '../home/home_repository.dart';

AppPalette _palette(BuildContext context) => AppPalette.of(context);

/// 我的资产：喵币余额与背包道具（改名卡、补签卡等）。
class AssetsPage extends StatefulWidget {
  const AssetsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<AssetsPage> createState() => _AssetsPageState();
}

class _AssetsPageState extends State<AssetsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 刷新会话获取最新喵币，同时加载背包道具。
      widget.controller.refreshSession();
      widget.controller.loadBackpack();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('我的资产'), centerTitle: true),
        body: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final coin = widget.controller.session?.nekoCoin;
            return ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
              children: [
                _CoinCard(coin: coin),
                const SizedBox(height: 12),
                _BackpackCard(
                  items: widget.controller.backpack,
                  loading: widget.controller.isLoadingBackpack,
                  error: widget.controller.backpackError,
                  onRetry: widget.controller.loadBackpack,
                ),
              ],
            );
          },
        ),
      );
}

class _CoinCard extends StatelessWidget {
  const _CoinCard({required this.coin});

  final double? coin;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: const Color(0xFFE6A23C).withOpacity(.14),
              foregroundColor: const Color(0xFFE6A23C),
              child: const Icon(Icons.monetization_on_rounded, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    coin == null ? '—' : _formatCoin(coin!),
                    style: TextStyle(
                        color: AppPalette.of(context).ink,
                        fontSize: 22,
                        fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  Text('喵币余额',
                      style: TextStyle(
                          color: AppPalette.of(context).muted, fontSize: 12.5)),
                ],
              ),
            ),
            Icon(Icons.pets_rounded, color: palette.primary.withOpacity(.35)),
          ],
        ),
      ),
    );
  }

  static String _formatCoin(double value) =>
      value == value.roundToDouble() ? '${value.round()}' : '$value';
}

class _BackpackCard extends StatelessWidget {
  const _BackpackCard({
    required this.items,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final List<BackpackItem> items;
  final bool loading;
  final String? error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 13, 15, 6),
            child: Text('背包道具',
                style: TextStyle(
                    color: AppPalette.of(context).ink,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800)),
          ),
          if (loading && items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 26),
              child: Center(
                  child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )),
            )
          else if (error != null && items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Column(
                  children: [
                    Text(error!,
                        style: TextStyle(
                            color: AppPalette.of(context).muted,
                            fontSize: 12.5)),
                    TextButton(onPressed: onRetry, child: const Text('重试')),
                  ],
                ),
              ),
            )
          else if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text('背包里还没有道具',
                    style: TextStyle(
                        color: AppPalette.of(context).muted, fontSize: 12.5)),
              ),
            )
          else
            for (final (index, item) in items.indexed) ...[
              if (index > 0)
                const Divider(height: 1, indent: 15, endIndent: 15),
              _BackpackRow(item: item, accent: palette.primary),
            ],
        ],
      ),
    );
  }
}

class _BackpackRow extends StatelessWidget {
  const _BackpackRow({required this.item, required this.accent});

  final BackpackItem item;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final icon = switch (item.tag) {
      'change_name_card' => Icons.badge_outlined,
      'resign_card' => Icons.event_repeat_rounded,
      _ => Icons.inventory_2_outlined,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
      child: Row(
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: accent.withOpacity(.1),
            foregroundColor: accent,
            child: Icon(icon, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name,
                    style: TextStyle(
                        color: AppPalette.of(context).ink,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(item.description.isEmpty ? item.tag : item.description,
                    style: TextStyle(
                        color: AppPalette.of(context).muted, fontSize: 11.5)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: accent.withOpacity(.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('×${item.count}',
                style: TextStyle(
                    color: accent, fontSize: 13, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}
