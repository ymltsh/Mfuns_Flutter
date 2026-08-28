import '../../core/network/mfuns_api_client.dart';

class EmojiSticker {
  const EmojiSticker({required this.id, required this.url, required this.size});

  final String id;
  final String url;
  final int size;
}

class EmojiPack {
  const EmojiPack({required this.key, required this.name, required this.stickers});

  final String key;
  final String name;
  final Map<String, EmojiSticker> stickers;
}

class EmojiData {
  const EmojiData({required this.packs, required this.faceTexts});

  final List<EmojiPack> packs;
  final List<String> faceTexts;

  /// Looks up a sticker URL for a Quill key like `s-1` (`<pack>-<id>`).
  String? stickerUrl(String key) {
    final separator = key.indexOf('-');
    if (separator <= 0 || separator == key.length - 1) return null;
    final packKey = key.substring(0, separator);
    final stickerId = key.substring(separator + 1);
    for (final pack in packs) {
      if (pack.key == packKey) {
        return pack.stickers[stickerId]?.url;
      }
    }
    return null;
  }

  static EmojiData fromJson(Object? packData, Object? faceData) {
    final root = packData is Map<String, dynamic> ? packData : const {};
    final packs = <EmojiPack>[];
    for (final entry in root.entries) {
      final pack = _asMap(entry.value);
      final list = _asMap(pack['list']);
      final stickers = <String, EmojiSticker>{
        for (final stickerEntry in list.entries)
          stickerEntry.key: EmojiSticker(
            id: stickerEntry.key,
            url: '${_asMap(stickerEntry.value)['url'] ?? ''}',
            size: _asInt(_asMap(stickerEntry.value)['size']) ?? 50,
          ),
      };
      packs.add(EmojiPack(
        key: entry.key,
        name: '${pack['name'] ?? entry.key}',
        stickers: stickers,
      ));
    }
    final faces = <String>[];
    if (faceData is List) {
      faces.addAll(faceData.whereType<String>().map((item) => item.trim()).where((item) => item.isNotEmpty));
    }
    return EmojiData(packs: packs, faceTexts: faces);
  }
}

/// Singleton store for the private emoji packs used in comments
/// (`/v1/emoji_pack/list` + `/v1/emoji_pack/face_text`). Loaded once and
/// cached for the app lifetime; images come from resource.mfuns.net.
class EmojiPackStore {
  EmojiPackStore._();

  static final EmojiPackStore instance = EmojiPackStore._();

  final MfunsApiClient _client = MfunsApiClient();
  Future<EmojiData>? _future;

  Future<EmojiData> load() => _future ??= _fetch();

  /// Drops the cached pack list so the next load refetches from the server
  /// (used by the settings "clear cache" action).
  void clear() {
    _future = null;
  }

  Future<EmojiData> _fetch() async {
    final responses = await Future.wait([
      // with_vip=1 会额外返回 VIP 专属表情包（如 simplevip）。
      _client.get('/v1/emoji_pack/list', query: {'with_vip': 1}),
      _client.get('/v1/emoji_pack/face_text'),
    ]);
    return EmojiData.fromJson(responses[0].data, responses[1].data);
  }
}

Map<String, dynamic> _asMap(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

int? _asInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value');
