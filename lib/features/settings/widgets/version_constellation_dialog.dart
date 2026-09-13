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
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6200),
    )..forward();
  }

  double _reveal(double start, double end) =>
      Interval(start, end, curve: Curves.easeOut).transform(_controller.value);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const constellation = VersionConstellation.current;
    return Material(
      color: Colors.black,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _CasSequencePainter(
                  backgroundProgress: _reveal(0, 0.28),
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

class _CasSequencePainter extends CustomPainter {
  const _CasSequencePainter({
    required this.backgroundProgress,
    required this.constellationProgress,
    required this.lineProgress,
  });

  final double backgroundProgress;
  final double constellationProgress;
  final double lineProgress;

  // Fixed, deliberately irregular field based on the white star language of
  // NASA's meatball mark: mostly pinpoints with a few four-ray flare stars.
  static const _backgroundStars =
      <({Offset position, double radius, bool flare})>[
    (position: Offset(0.08, 0.16), radius: 0.7, flare: false),
    (position: Offset(0.19, 0.08), radius: 0.5, flare: false),
    (position: Offset(0.31, 0.14), radius: 0.8, flare: false),
    (position: Offset(0.46, 0.07), radius: 0.55, flare: false),
    (position: Offset(0.63, 0.12), radius: 0.65, flare: false),
    (position: Offset(0.79, 0.06), radius: 0.45, flare: false),
    (position: Offset(0.91, 0.17), radius: 0.75, flare: false),
    (position: Offset(0.13, 0.29), radius: 0.5, flare: false),
    (position: Offset(0.25, 0.23), radius: 1.1, flare: true),
    (position: Offset(0.39, 0.31), radius: 0.45, flare: false),
    (position: Offset(0.55, 0.21), radius: 0.75, flare: false),
    (position: Offset(0.7, 0.28), radius: 0.5, flare: false),
    (position: Offset(0.84, 0.24), radius: 0.9, flare: false),
    (position: Offset(0.95, 0.34), radius: 0.5, flare: false),
    (position: Offset(0.05, 0.43), radius: 0.45, flare: false),
    (position: Offset(0.17, 0.39), radius: 0.7, flare: false),
    (position: Offset(0.3, 0.46), radius: 0.55, flare: false),
    (position: Offset(0.43, 0.4), radius: 0.45, flare: false),
    (position: Offset(0.58, 0.47), radius: 1.0, flare: true),
    (position: Offset(0.74, 0.38), radius: 0.6, flare: false),
    (position: Offset(0.88, 0.45), radius: 0.45, flare: false),
    (position: Offset(0.1, 0.57), radius: 0.8, flare: false),
    (position: Offset(0.22, 0.53), radius: 0.45, flare: false),
    (position: Offset(0.36, 0.61), radius: 0.6, flare: false),
    (position: Offset(0.49, 0.55), radius: 0.45, flare: false),
    (position: Offset(0.65, 0.63), radius: 0.75, flare: false),
    (position: Offset(0.8, 0.54), radius: 0.5, flare: false),
    (position: Offset(0.93, 0.6), radius: 0.8, flare: false),
    (position: Offset(0.04, 0.72), radius: 0.5, flare: false),
    (position: Offset(0.16, 0.68), radius: 0.45, flare: false),
    (position: Offset(0.28, 0.77), radius: 1.05, flare: true),
    (position: Offset(0.42, 0.7), radius: 0.55, flare: false),
    (position: Offset(0.56, 0.79), radius: 0.45, flare: false),
    (position: Offset(0.71, 0.72), radius: 0.7, flare: false),
    (position: Offset(0.85, 0.8), radius: 0.55, flare: false),
    (position: Offset(0.96, 0.7), radius: 0.45, flare: false),
    (position: Offset(0.09, 0.88), radius: 0.75, flare: false),
    (position: Offset(0.21, 0.94), radius: 0.45, flare: false),
    (position: Offset(0.35, 0.86), radius: 0.6, flare: false),
    (position: Offset(0.5, 0.93), radius: 0.45, flare: false),
    (position: Offset(0.64, 0.87), radius: 0.9, flare: true),
    (position: Offset(0.77, 0.95), radius: 0.5, flare: false),
    (position: Offset(0.9, 0.89), radius: 0.65, flare: false),
  ];

  static const _stars = <Offset>[
    Offset(0.08, 0.28),
    Offset(0.28, 0.67),
    Offset(0.5, 0.34),
    Offset(0.72, 0.7),
    Offset(0.92, 0.18),
  ];
  static const _links = <(int, int)>[
    (0, 1),
    (1, 2),
    (2, 3),
    (3, 4),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    _paintBackgroundStars(canvas, size);

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

  void _paintBackgroundStars(Canvas canvas, Size size) {
    final count = _backgroundStars.length;
    final visible = (backgroundProgress * count).ceil().clamp(0, count);
    for (var i = 0; i < visible; i++) {
      final star = _backgroundStars[i];
      final center = Offset(
        star.position.dx * size.width,
        star.position.dy * size.height,
      );
      final localFade = (backgroundProgress * count - i).clamp(0.0, 1.0);
      canvas.drawCircle(
        center,
        star.radius,
        Paint()..color = Colors.white.withOpacity(0.68 * localFade),
      );
      if (star.flare) _paintFlareStar(canvas, center, star.radius, localFade);
    }
  }

  void _paintFlareStar(
    Canvas canvas,
    Offset center,
    double radius,
    double opacity,
  ) {
    final rayPaint = Paint()
      ..color = Colors.white.withOpacity(0.46 * opacity)
      ..strokeWidth = 0.7
      ..strokeCap = StrokeCap.round;
    final horizontal = radius * 3.6;
    final vertical = radius * 5.2;
    canvas.drawLine(
      center.translate(-horizontal, 0),
      center.translate(horizontal, 0),
      rayPaint,
    );
    canvas.drawLine(
      center.translate(0, -vertical),
      center.translate(0, vertical),
      rayPaint,
    );
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
  bool shouldRepaint(covariant _CasSequencePainter oldDelegate) =>
      backgroundProgress != oldDelegate.backgroundProgress ||
      constellationProgress != oldDelegate.constellationProgress ||
      lineProgress != oldDelegate.lineProgress;
}
