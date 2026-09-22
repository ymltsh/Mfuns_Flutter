import 'package:flutter/foundation.dart';

/// A constellation identity assigned to an application release line.
@immutable
class VersionConstellation {
  const VersionConstellation({
    required this.releaseLine,
    required this.name,
    required this.latinName,
    required this.tagline,
  });

  final String releaseLine;
  final String name;
  final String latinName;
  final String tagline;

  /// Current 1.6.x releases use the CYG constellation codename.
  static const current = VersionConstellation(
    releaseLine: '1.6',
    name: '天鹅座',
    latinName: 'CYG',
    tagline: '振翼越过长夜，向更远的星河启程。',
  );
}
