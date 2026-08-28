import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_controller.dart';
import '../../features/home/home_repository.dart';
import '../../features/video/content_detail_page.dart';

/// 站内链接目标。
class MfunsLinkTarget {
  const MfunsLinkTarget({required this.type, required this.id});

  /// video / article / feed。
  final String type;
  final int id;
}

/// 解析 Mfuns 站内链接：`mfuns://` 协议、`mfuns.net`（含 www/m 子域）与
/// `mfuns.wgen.top` 下的 video/article/feed 路径，以及裸 `mv` 号（如 mv60751）。
/// 无法识别时返回 null。
MfunsLinkTarget? parseMfunsLink(String url) {
  final value = url.trim();
  final mv = RegExp(r'^mv(\d+)$', caseSensitive: false).firstMatch(value);
  if (mv != null) {
    final id = int.tryParse(mv.group(1)!);
    if (id != null && id > 0) return MfunsLinkTarget(type: 'video', id: id);
  }
  final uri = Uri.tryParse(value);
  if (uri == null) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'mfuns') {
    // mfuns://video/60751、mfuns://article/122326、mfuns://feed/273061、
    // mfuns://mv60751
    final authority = uri.authority;
    if (authority.startsWith('mv')) {
      final id = int.tryParse(authority.substring(2));
      if (id != null && id > 0) {
        return MfunsLinkTarget(type: 'video', id: id);
      }
    }
    final id = int.tryParse(uri.path.replaceAll('/', ''));
    if (id != null && id > 0 &&
        (authority == 'video' ||
            authority == 'article' ||
            authority == 'feed')) {
      return MfunsLinkTarget(type: authority, id: id);
    }
    return null;
  }
  if (scheme != 'http' && scheme != 'https') return null;
  final host = uri.host.toLowerCase();
  final isMfuns = host == 'mfuns.net' ||
      host == 'www.mfuns.net' ||
      host == 'm.mfuns.net' ||
      host.endsWith('.mfuns.net') ||
      host == 'mfuns.wgen.top' ||
      host == 'www.mfuns.wgen.top';
  if (!isMfuns) return null;
  final segments =
      uri.path.split('/').where((segment) => segment.isNotEmpty).toList();
  int? id;
  String? type;
  if (segments.isNotEmpty && segments.first.startsWith('mv')) {
    id = int.tryParse(segments.first.substring(2));
    type = 'video';
  } else if (segments.length >= 2) {
    type = segments[0].toLowerCase();
    id = int.tryParse(segments[1]);
  }
  if (id == null || id <= 0) return null;
  if (type != 'video' && type != 'article' && type != 'feed') return null;
  return MfunsLinkTarget(type: type!, id: id);
}

/// 在应用内打开站内链接对应的页面；无法识别时返回 false。
bool routeMfunsLink(
  BuildContext context,
  AppController controller,
  String url,
) {
  final target = parseMfunsLink(url);
  if (target == null) return false;
  pushMfunsTarget(context, controller, target);
  return true;
}

void pushMfunsTarget(
  BuildContext context,
  AppController controller,
  MfunsLinkTarget target,
) {
  pushMfunsTargetOnNavigator(Navigator.of(context), controller, target);
}

/// 通过 [NavigatorState] 直接推入目标页面。深链路由使用此版本，
/// 避免 `Navigator.of(rootNavigator.context)` 找不到祖先 Navigator 而失败。
void pushMfunsTargetOnNavigator(
  NavigatorState navigator,
  AppController controller,
  MfunsLinkTarget target,
) {
  switch (target.type) {
    case 'video':
      navigator.push(MaterialPageRoute<void>(
        builder: (_) => ContentDetailPage(
          controller: controller,
          preview: _preview(target.id, type: 1),
        ),
      ));
    case 'article':
      navigator.push(MaterialPageRoute<void>(
        builder: (_) => ContentDetailPage(
          controller: controller,
          preview: _preview(target.id, type: 0),
        ),
      ));
    case 'feed':
      navigator.push(MaterialPageRoute<void>(
        builder: (_) =>
            FeedDetailPage(controller: controller, feedId: target.id),
      ));
  }
}

/// 处理内容中的链接：Mfuns 站内链接在应用内打开对应页面，
/// 其余链接交给系统浏览器。
void openContentLink(
  BuildContext context,
  AppController controller,
  String url,
) {
  if (routeMfunsLink(context, controller, url)) return;
  final target = Uri.tryParse(url);
  if (target != null) {
    launchUrl(target, mode: LaunchMode.externalApplication);
  }
}

ContentPreview _preview(int id, {required int type}) => ContentPreview(
      id: id,
      title: '',
      summary: '',
      cover: '',
      author: '',
      category: '',
      type: type,
      likes: 0,
      comments: 0,
      views: 0,
    );
