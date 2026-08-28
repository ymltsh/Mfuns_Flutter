import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ProbePlayer extends StatefulWidget {
  const _ProbePlayer({super.key});

  @override
  State<_ProbePlayer> createState() => _ProbePlayerState();
}

class _ProbePlayerState extends State<_ProbePlayer> {
  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox(
      width: 300, height: 169, child: ColoredBox(color: Colors.black));
}

/// 复刻视频详情页结构：横竖屏使用不同布局，播放器挂在带 GlobalKey 的
/// `_ProbePlayer` 上。[playerBehindFutureBuilder] 为 true 时复刻旧实现
/// （播放器藏在 FutureBuilder 之后），为 false 时复刻新实现（清晰度列表
/// 缓存在 State 中，播放器直接挂载）。
class _Host extends StatefulWidget {
  const _Host({
    required this.playerKey,
    required this.playerBehindFutureBuilder,
  });

  final GlobalKey<_ProbePlayerState> playerKey;
  final bool playerBehindFutureBuilder;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late final Future<bool> _readyFuture = Future<bool>.value(true);
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _readyFuture.then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget player;
    if (widget.playerBehindFutureBuilder) {
      player = FutureBuilder<bool>(
        future: _readyFuture,
        builder: (context, snapshot) => snapshot.hasData
            ? _ProbePlayer(key: widget.playerKey)
            : const SizedBox(width: 300, height: 169),
      );
    } else {
      player = _ready
          ? _ProbePlayer(key: widget.playerKey)
          : const SizedBox(width: 300, height: 169);
    }

    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    if (isLandscape) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
              width: 200,
              child: ColoredBox(color: Colors.black, child: player)),
          const Expanded(child: Text('info')),
        ],
      );
    }
    return ListView(
      children: [
        player,
        const Text('info'),
      ],
    );
  }
}

void main() {
  testWidgets(
      'new structure: player state survives the landscape layout switch',
      (tester) async {
    final playerKey = GlobalKey<_ProbePlayerState>();
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: _Host(playerKey: playerKey, playerBehindFutureBuilder: false),
    ));
    await tester.pumpAndSettle();
    final before = playerKey.currentState!;
    expect(before.disposed, isFalse);

    // Simulate the device rotating to landscape (as the fullscreen overlay does).
    tester.view.physicalSize = const Size(1600, 800);
    await tester.pumpAndSettle();

    expect(playerKey.currentState, same(before),
        reason: 'player state must survive the layout switch');
    expect(before.disposed, isFalse);
    expect(playerKey.currentState!.disposed, isFalse,
        reason: 'state must not be re-created');
  });

  testWidgets(
      'old structure: FutureBuilder gap destroys the player on layout switch',
      (tester) async {
    final playerKey = GlobalKey<_ProbePlayerState>();
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: _Host(playerKey: playerKey, playerBehindFutureBuilder: true),
    ));
    await tester.pumpAndSettle();
    final before = playerKey.currentState!;
    expect(before.disposed, isFalse);

    tester.view.physicalSize = const Size(1600, 800);
    await tester.pumpAndSettle();

    expect(before.disposed, isTrue,
        reason: 'the old structure disposed the shared player state, which '
            'killed the controller and reset the orientation mid-fullscreen');
    expect(playerKey.currentState, isNot(same(before)));
  });
}

