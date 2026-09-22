import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/config/version_constellation.dart';

/// Full-screen release constellation sequence shown by the About-page easter egg.
class VersionConstellationDialog extends StatefulWidget {
  const VersionConstellationDialog({super.key});

  @override
  State<VersionConstellationDialog> createState() =>
      _VersionConstellationDialogState();
}

class _VersionConstellationDialogState extends State<VersionConstellationDialog>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final AnimationController _ambientController;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6200),
    )..forward();
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 22),
    )..repeat();
  }

  double _reveal(double start, double end) =>
      Interval(start, end, curve: Curves.easeOut).transform(_controller.value);

  @override
  void dispose() {
    _controller.dispose();
    _ambientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const constellation = VersionConstellation.current;
    return Material(
      color: Colors.black,
      child: AnimatedBuilder(
        animation: Listenable.merge([_controller, _ambientController]),
        builder: (context, _) {
          return Stack(
            fit: StackFit.expand,
            children: [
              _DeepStarfield(
                revealProgress: _reveal(0, 0.24),
                ambientProgress: _ambientController.value,
              ),
              _AnimatedStarfield(
                revealProgress: _reveal(0, 0.28),
                ambientProgress: _ambientController.value,
              ),
              CustomPaint(
                painter: _CygSequencePainter(
                  constellationProgress: _reveal(0.25, 0.5),
                  lineProgress: _reveal(0.48, 0.76),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.topRight,
                        child: Opacity(
                          opacity: _reveal(0.12, 0.22),
                          child: IconButton(
                            tooltip: '关闭星图',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded),
                            color: Colors.white54,
                          ),
                        ),
                      ),
                      const Spacer(),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _FadeUp(
                              progress: _reveal(0.76, 0.84),
                              child: Text(
                                '版本星图  ${constellation.releaseLine}',
                                style: const TextStyle(
                                  color: Color(0xFF89CFF0),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 3,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            _FadeUp(
                              progress: _reveal(0.81, 0.9),
                              child: Column(
                                children: [
                                  Text(
                                    constellation.latinName,
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                      letterSpacing: 8,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    constellation.name,
                                    key: const ValueKey(
                                      'constellation-codename',
                                    ),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 38,
                                      fontWeight: FontWeight.w300,
                                      letterSpacing: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            _FadeUp(
                              progress: _reveal(0.87, 0.96),
                              child: Text(
                                constellation.tagline,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xD9FFFFFF),
                                  fontSize: 15,
                                  height: 1.6,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            _FadeUp(
                              progress: _reveal(0.93, 1),
                              child: const Text(
                                'MFUNS FLUTTER  ·  v${AppConfig.appVersion} '
                                '(${AppConfig.appBuild})',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 10,
                                  letterSpacing: 2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DeepStarfield extends StatelessWidget {
  const _DeepStarfield({
    required this.revealProgress,
    required this.ambientProgress,
  });

  final double revealProgress;
  final double ambientProgress;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _DeepStarfieldPainter(
          revealProgress: revealProgress,
          ambientProgress: ambientProgress,
        ),
      );
}

class _DeepStarfieldPainter extends CustomPainter {
  const _DeepStarfieldPainter({
    required this.revealProgress,
    required this.ambientProgress,
  });

  final double revealProgress;
  final double ambientProgress;

  static final _stars = _generateStars();

  static List<({Offset position, double radius, double phase, double alpha})>
      _generateStars() {
    final random = math.Random(0x435947);
    return List.generate(120, (_) {
      return (
        position: Offset(random.nextDouble(), random.nextDouble()),
        radius: 0.28 + random.nextDouble() * 0.72,
        phase: random.nextDouble() * math.pi * 2,
        alpha: 0.16 + random.nextDouble() * 0.3,
      );
    }, growable: false);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    final cycle = ambientProgress * math.pi * 2;
    final drift = Offset(math.sin(cycle) * -5, math.cos(cycle) * -3);
    for (final star in _stars) {
      final depth = 0.35 + star.radius * 0.45;
      final center = Offset(
        (star.position.dx * size.width + drift.dx * depth) % size.width,
        (star.position.dy * size.height + drift.dy * depth) % size.height,
      );
      final twinkle =
          0.62 + 0.38 * ((math.sin(cycle * 0.7 + star.phase) + 1) / 2);
      canvas.drawCircle(
        center,
        star.radius,
        Paint()
          ..color = Colors.white.withOpacity(
            revealProgress * star.alpha * twinkle,
          ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DeepStarfieldPainter oldDelegate) =>
      revealProgress != oldDelegate.revealProgress ||
      ambientProgress != oldDelegate.ambientProgress;
}

class _AnimatedStarfield extends StatelessWidget {
  const _AnimatedStarfield({
    required this.revealProgress,
    required this.ambientProgress,
  });

  final double revealProgress;
  final double ambientProgress;

  @override
  Widget build(BuildContext context) {
    final cycle = (1 - math.cos(ambientProgress * math.pi * 2)) / 2;
    final brightness = 0.58 + cycle * 0.28;
    final scale = 1.04 + cycle * 0.12;
    return ClipRect(
      child: Opacity(
        opacity: revealProgress * brightness,
        child: Transform.scale(
          scale: scale,
          child: Image.asset(
            'assets/constellation_starfield.png',
            fit: BoxFit.cover,
            alignment: Alignment.center,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
          ),
        ),
      ),
    );
  }
}

class _FadeUp extends StatelessWidget {
  const _FadeUp({required this.progress, required this.child});

  final double progress;
  final Widget child;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: progress,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - progress)),
          child: child,
        ),
      );
}

class _CygSequencePainter extends CustomPainter {
  const _CygSequencePainter({
    required this.constellationProgress,
    required this.lineProgress,
  });

  final double constellationProgress;
  final double lineProgress;

  static const _stars = <Offset>[
    Offset(0.50, 0.04),
    Offset(0.50, 0.46),
    Offset(0.50, 0.94),
    Offset(0.30, 0.47),
    Offset(0.06, 0.55),
    Offset(0.70, 0.45),
    Offset(0.94, 0.36),
  ];
  static const _links = <(int, int)>[
    (0, 1),
    (1, 2),
    (1, 3),
    (3, 4),
    (1, 5),
    (5, 6),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final field = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.32),
      width: math.min(size.width * 0.72, 560),
      height: math.min(size.height * 0.43, 390),
    );
    final points = _stars
        .map((star) => Offset(
              field.left + star.dx * field.width,
              field.top + star.dy * field.height,
            ))
        .toList(growable: false);
    _paintConstellationStars(canvas, points);
    _paintLines(canvas, points);
  }

  void _paintConstellationStars(Canvas canvas, List<Offset> points) {
    final scaledProgress = constellationProgress * points.length;
    for (var i = 0; i < points.length; i++) {
      final opacity = (scaledProgress - i).clamp(0.0, 1.0);
      if (opacity == 0) continue;
      canvas.drawCircle(
        points[i],
        i == 0 ? 13 : 9,
        Paint()
          ..color = const Color(0xFF89CFF0).withOpacity(0.42 * opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
      );
      canvas.drawCircle(
        points[i],
        (i == 0 ? 3.5 : 2.3) * opacity,
        Paint()..color = Colors.white.withOpacity(opacity),
      );
    }
  }

  void _paintLines(Canvas canvas, List<Offset> points) {
    final scaledProgress = lineProgress * _links.length;
    final linePaint = Paint()
      ..color = const Color(0xCC89CFF0)
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < _links.length; i++) {
      final segmentProgress = (scaledProgress - i).clamp(0.0, 1.0);
      if (segmentProgress == 0) continue;
      final (from, to) = _links[i];
      canvas.drawLine(
        points[from],
        Offset.lerp(points[from], points[to], segmentProgress)!,
        linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CygSequencePainter oldDelegate) =>
      constellationProgress != oldDelegate.constellationProgress ||
      lineProgress != oldDelegate.lineProgress;
}
