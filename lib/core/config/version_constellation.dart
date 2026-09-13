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

  /// Current 1.5.x releases still use the CAS constellation codename.
  static const current = VersionConstellation(
    releaseLine: '1.5',
    name: '仙后座',
    latinName: 'CAS',
    tagline: '守望北天，于长夜中指引方向。',
  );
}
