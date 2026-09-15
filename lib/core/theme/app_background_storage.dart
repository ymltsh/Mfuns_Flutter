import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 将用户选择的背景图保存到应用私有目录，避免图片选择器临时文件被清理。
class AppBackgroundStorage {
  static Future<Directory> _directory() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'theme_backgrounds'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  static Future<String> importImage(XFile image) async {
    final directory = await _directory();
    var extension = p.extension(image.name).toLowerCase();
    if (extension.isEmpty || extension.length > 8) extension = '.jpg';
    final destination = File(p.join(
      directory.path,
      'background_${DateTime.now().microsecondsSinceEpoch}$extension',
    ));
    await image.saveTo(destination.path);
    return destination.path;
  }

  /// 仅删除由本服务管理的背景文件，不触碰用户图库中的原图。
  static Future<void> removeManagedImage(String path) async {
    if (path.trim().isEmpty) return;
    final directory = await _directory();
    final normalized = p.normalize(p.absolute(path));
    if (!p.isWithin(p.normalize(p.absolute(directory.path)), normalized)) {
      return;
    }
    final file = File(normalized);
    if (await file.exists()) await file.delete();
  }
}
