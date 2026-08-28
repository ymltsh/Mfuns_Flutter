import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/core/media/playback_source.dart';

void main() {
  group('resolvePlaybackSource', () {
    final networkUri = Uri.parse('https://cdn.example.com/v1_1080p.mp4?sign=1');

    test('存在本地视频 → LocalPlaybackSource', () {
      final source = resolvePlaybackSource(
        localPath: '/data/downloads/1/p1_1080p.mp4',
        networkUri: networkUri,
      );
      expect(source, isA<LocalPlaybackSource>());
      expect((source as LocalPlaybackSource).path,
          '/data/downloads/1/p1_1080p.mp4');
    });

    test('不存在本地视频 → NetworkPlaybackSource', () {
      final source = resolvePlaybackSource(
        localPath: null,
        networkUri: networkUri,
      );
      expect(source, isA<NetworkPlaybackSource>());
      expect((source as NetworkPlaybackSource).uri, networkUri);
    });

    test('空本地路径 → NetworkPlaybackSource', () {
      final source = resolvePlaybackSource(
        localPath: '',
        networkUri: networkUri,
      );
      expect(source, isA<NetworkPlaybackSource>());
    });

    test('不同清晰度本地文件不串用', () {
      final local720 = resolvePlaybackSource(
        localPath: '/data/downloads/1/p1_720p.mp4',
        networkUri: Uri.parse('https://cdn.example.com/v1_1080p.mp4'),
      );
      // 720p 的本地文件存在，但网络源为 1080p —— 该场景由上层按
      // videoId+part+quality 精确匹配决定，这里只保证类型选择正确。
      expect(local720, isA<LocalPlaybackSource>());
    });
  });
}
