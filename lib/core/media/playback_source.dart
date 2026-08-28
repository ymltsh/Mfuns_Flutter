/// 统一的播放源抽象：本地文件与网络直链共享同一播放器流程。
sealed class PlaybackSource {
  const PlaybackSource();
}

/// 网络播放源：使用 [VideoPlayerController.networkUrl]。
class NetworkPlaybackSource extends PlaybackSource {
  const NetworkPlaybackSource(this.uri);

  final Uri uri;
}

/// 本地播放源：使用 [VideoPlayerController.file]。
class LocalPlaybackSource extends PlaybackSource {
  const LocalPlaybackSource(this.path);

  final String path;
}

/// 播放源解析：存在可用的本地文件 → [LocalPlaybackSource]，
/// 否则回退到 [NetworkPlaybackSource]。
PlaybackSource resolvePlaybackSource({
  required String? localPath,
  required Uri networkUri,
}) {
  if (localPath != null && localPath.isNotEmpty) {
    return LocalPlaybackSource(localPath);
  }
  return NetworkPlaybackSource(networkUri);
}
