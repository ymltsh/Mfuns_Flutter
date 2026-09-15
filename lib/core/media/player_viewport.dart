/// 播放器视口内按原始比例完整显示的视频尺寸。
class PlayerViewportGeometry {
  const PlayerViewportGeometry({
    required this.surfaceHeight,
    required this.videoWidth,
    required this.videoHeight,
  });

  final double surfaceHeight;
  final double videoWidth;
  final double videoHeight;
}

/// 计算竖屏详情页的播放器尺寸。
///
/// 播放器视口限制在 16:9～4:3 之间，避免极宽视频把控制层压扁，也避免
/// 极高视频占据大半个页面。视频本身始终以 contain 方式保持原始比例。
PlayerViewportGeometry calculatePortraitPlayerViewport({
  required double viewportWidth,
  required double screenHeight,
  required double videoAspectRatio,
}) {
  final width =
      viewportWidth.isFinite && viewportWidth > 0 ? viewportWidth : 1.0;
  final height =
      screenHeight.isFinite && screenHeight > 0 ? screenHeight : width;
  final aspect = videoAspectRatio.isFinite && videoAspectRatio > 0
      ? videoAspectRatio
      : 16 / 9;
  final heightLimit = height * .5;
  final minimumHeight = _minimum(width * 9 / 16, heightLimit);
  final preferredMaximum = _minimum(width * 3 / 4, heightLimit);
  final maximumHeight = _maximum(minimumHeight, preferredMaximum);
  final naturalHeight = width / aspect;
  final surfaceHeight = aspect < 1
      ? maximumHeight
      : naturalHeight.clamp(minimumHeight, maximumHeight).toDouble();
  final surfaceAspect = width / surfaceHeight;
  final videoWidth = aspect >= surfaceAspect ? width : surfaceHeight * aspect;
  final videoHeight = aspect >= surfaceAspect ? width / aspect : surfaceHeight;
  return PlayerViewportGeometry(
    surfaceHeight: surfaceHeight,
    videoWidth: videoWidth,
    videoHeight: videoHeight,
  );
}

double _minimum(double a, double b) => a < b ? a : b;

double _maximum(double a, double b) => a > b ? a : b;
