import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_controller.dart';
import '../../core/config/app_config.dart';
import '../../core/config/user_preferences.dart';
import '../../core/emoji/emoji_pack_store.dart';
import '../../core/network/update_checker.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/content_link_handler.dart';
import 'download_settings_page.dart';
import 'network_diagnostics_page.dart';

const _genderOptions = <int, String>{0: '保密', 1: '男', 2: '女', 3: '其他'};

const _qualityOptions = <String>[
  '',
  '360p',
  '480p',
  '540p',
  '720p',
  '1080p',
];

String _qualityLabel(String value) => value.isEmpty ? '自动' : value;

/// 设置页：编辑资料、播放器与弹幕偏好、清除缓存、关于。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  var _danmakuOn = true;
  var _danmakuOpacity = 1.0;
  var _danmakuSize = 20.0;
  var _loaded = false;
  var _checkingUpdate = false;
  String _acceleratorBase = AppConfig.defaultAcceleratorBase;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      UserPreferences.loadDanmakuOn(),
      UserPreferences.loadDanmakuOpacity(),
      UserPreferences.loadDanmakuSize(),
      UserPreferences.loadAcceleratorBase(),
    ]);
    if (!mounted) return;
    setState(() {
      _danmakuOn = results[0] as bool;
      _danmakuOpacity = results[1] as double;
      _danmakuSize = results[2] as double;
      _acceleratorBase = results[3] as String;
      _loaded = true;
    });
  }

  Future<void> _configureAccelerator() async {
    final controller = TextEditingController(text: _acceleratorBase);
    final saved = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: const Text('GitHub 加速地址'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '用于加速更新清单与安装包下载，直接拼接在 GitHub 地址前。',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: AppConfig.defaultAcceleratorBase,
                labelText: '加速地址',
                prefixIcon: Icon(Icons.bolt_rounded),
              ),
              onSubmitted: (_) => Navigator.of(context).pop(true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) return;
    final normalized = UpdateChecker.normalizeBase(controller.text);
    setState(() => _acceleratorBase = normalized);
    await UserPreferences.saveAcceleratorBase(normalized);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('加速地址已更新，检查更新将使用新的地址')));
    }
    controller.dispose();
  }

  Future<void> _checkUpdate() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    try {
      final manifest =
          await UpdateChecker.fetch(acceleratorBase: _acceleratorBase);
      if (!mounted) return;
      final latest = manifest.latest;
      if (latest == null || latest.version.isEmpty) {
        _showUpdateError('更新清单中没有最新版本信息');
        return;
      }
      final hasUpdate = UpdateChecker.isNewer(
        latest.version,
        latest.build,
        AppConfig.appVersion,
        AppConfig.appBuild,
      );
      if (!hasUpdate) {
        _showUpToDate(latest);
        return;
      }
      _showUpdateAvailable(latest);
    } catch (error) {
      if (!mounted) return;
      _showUpdateError('检查更新失败：$error');
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  void _showUpToDate(UpdateRelease latest) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('已是最新版本'),
        content: Text('当前已是最新版本 v${AppConfig.appVersion}。\n'
            '最新发布：${latest.name}'
            '${latest.date.isEmpty ? '' : '（${latest.date}）'}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('好的'),
          ),
        ],
      ),
    );
  }

  void _showUpdateAvailable(UpdateRelease latest) {
    final downloadUrl = _downloadUrl(latest);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('发现新版本 v${latest.version}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (latest.date.isNotEmpty)
                Text(latest.date,
                    style: const TextStyle(
                        color: Colors.blueGrey, fontSize: 12)),
              const SizedBox(height: 8),
              Text(latest.notes.isEmpty ? '暂无更新说明' : latest.notes,
                  style: const TextStyle(height: 1.45, fontSize: 13)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse(latest.page.isEmpty
                  ? AppConfig.releasePageUrl
                  : latest.page),
              mode: LaunchMode.externalApplication,
            ),
            child: const Text('查看发布页'),
          ),
          if (downloadUrl != null)
            FilledButton(
              onPressed: () => launchUrl(
                Uri.parse(UpdateChecker.accelerate(
                    _acceleratorBase, downloadUrl)),
                mode: LaunchMode.externalApplication,
              ),
              child: const Text('下载更新'),
            ),
        ],
      ),
    );
  }

  void _showUpdateError(String message) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('检查更新'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _checkUpdate();
            },
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  /// 按当前平台返回下载地址；未知平台回退到发布页。
  String? _downloadUrl(UpdateRelease release) {
    if (Platform.isAndroid && release.androidUrl.isNotEmpty) {
      return release.androidUrl;
    }
    if (Platform.isWindows && release.windowsUrl.isNotEmpty) {
      return release.windowsUrl;
    }
    return null;
  }

  Future<void> _confirmClearCache(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: const Text('清除缓存'),
        content: const Text('将清除表情包等本地缓存数据，不影响账号与收藏。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    EmojiPackStore.instance.clear();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('缓存已清除')));
  }

  /// 打开反馈帖（站内文章），提示用户在评论区留言。
  void _openFeedback() {
    pushMfunsTarget(context, widget.controller,
        const MfunsLinkTarget(type: 'article', id: 122326));
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Mfuns Flutter',
      applicationVersion: AppConfig.appVersion,
      applicationIcon: Image.asset('assets/logo.png',
          width: 42, height: 42, fit: BoxFit.contain),
      children: [
        const Text('Mfuns Flutter，由社区支持的Material Design风格的Mfuns客户端。'),
        const SizedBox(height: 14),
        Row(
          children: [
            const Icon(Icons.code_rounded, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: InkWell(
                onTap: () => launchUrl(
                  Uri.parse('https://github.com/ymltsh/Mfuns_Flutter'),
                  mode: LaunchMode.externalApplication,
                ),
                child: const Text(
                  'https://github.com/ymltsh/Mfuns_Flutter',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.blue,
                      decoration: TextDecoration.underline),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_rounded, size: 16, color: Color(0xFFE6A23C)),
            SizedBox(width: 6),
            Flexible(
              child: Text('如果喜欢这个项目，欢迎在 GitHub 点个 Star 支持我们！'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('设置'), centerTitle: true),
        // 监听 controller：自动签到等开关变化后立即反映到界面。
        body: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
            children: [
            _SettingsCard(
              children: [
                _SettingsTile(
                  icon: Icons.badge_outlined,
                  title: '编辑资料',
                  subtitle: '修改昵称、性别与个人简介',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ProfileEditPage(controller: widget.controller),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SettingsCard(
              children: [
                _SettingsTile(
                  icon: Icons.play_circle_outline_rounded,
                  title: '播放器配置',
                  subtitle: '默认清晰度与自动播放',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const PlayerSettingsPage(),
                    ),
                  ),
                ),
                const Divider(height: 1, indent: 56),
                _SettingsTile(
                  icon: Icons.subtitles_outlined,
                  title: '弹幕设置',
                  subtitle:
                      '${_danmakuOn ? '开启' : '关闭'} · 透明度 ${(_danmakuOpacity * 100).round()}% · 字号 ${_danmakuSize.round()}',
                  onTap: _loaded
                      ? () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => DanmakuSettingsPage(
                                enabled: _danmakuOn,
                                opacity: _danmakuOpacity,
                                size: _danmakuSize,
                                onChanged: (enabled, opacity, size) {
                                  setState(() {
                                    _danmakuOn = enabled;
                                    _danmakuOpacity = opacity;
                                    _danmakuSize = size;
                                  });
                                },
                              ),
                            ),
                          )
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SettingsCard(
              children: [
                _SettingsTile(
                  icon: Icons.menu_book_outlined,
                  title: '文章阅读设置',
                  subtitle: '阅读进度滑块等长文章阅读选项',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ArticleReaderSettingsPage(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SettingsCard(
              children: [
                SwitchListTile(
                  value: widget.controller.autoSignIn,
                  title: const Text('自动签到',
                      style: TextStyle(
                          color: Colors.blueGrey, fontWeight: FontWeight.w700)),
                  subtitle: const Text(
                      '打开应用时检查签到状态，未签到则自动完成；运行期间每天 00:00 也会自动签到',
                      style: TextStyle(color: Colors.blueGrey, fontSize: 12)),
                  secondary: CircleAvatar(
                    backgroundColor:
                        AppPalette.of(context).primary.withOpacity(.11),
                    foregroundColor: AppPalette.of(context).primary,
                    child: const Icon(Icons.event_repeat_rounded, size: 20),
                  ),
                  onChanged: (value) =>
                      widget.controller.setAutoSignIn(value),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SettingsCard(
              children: [
                _SettingsTile(
                  icon: Icons.download_rounded,
                  title: '下载设置',
                  subtitle: '仅 Wi-Fi 下载、最大并发数与下载空间',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DownloadSettingsPage(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SettingsCard(
              children: [
                _SettingsTile(
                  icon: Icons.network_check_rounded,
                  title: '网络诊断',
                  subtitle: '检测连接状态、DNS、延迟与业务接口连通性',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const NetworkDiagnosticsPage(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SettingsCard(
              children: [
                _SettingsTile(
                  icon: Icons.system_update_alt_rounded,
                  title: '检查更新',
                  subtitle: _checkingUpdate
                      ? '正在检查…'
                      : '当前 v${AppConfig.appVersion}，检查是否有新版本',
                  onTap: _checkingUpdate ? null : _checkUpdate,
                ),
                const Divider(height: 1, indent: 56),
                _SettingsTile(
                  icon: Icons.bolt_rounded,
                  title: '下载加速配置',
                  subtitle: '自定义 GitHub 加速地址，用于更新与下载',
                  onTap: _configureAccelerator,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _SettingsCard(
              children: [
                _SettingsTile(
                  icon: Icons.cleaning_services_outlined,
                  title: '清除缓存',
                  subtitle: '清理表情包等本地缓存数据',
                  onTap: () => _confirmClearCache(context),
                ),
                const Divider(height: 1, indent: 56),
                _SettingsTile(
                  icon: Icons.feedback_outlined,
                  title: '意见反馈',
                  subtitle: '点击打开反馈帖，在评论区留言即可',
                  onTap: _openFeedback,
                ),
                const Divider(height: 1, indent: 56),
                _SettingsTile(
                  icon: Icons.info_outline_rounded,
                  title: '关于',
                  subtitle: '为 Mfuns Flutter 点个Star吧！ v${AppConfig.appVersion}',
                  onTap: () => _showAbout(context),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('登录状态：${widget.controller.session?.displayName ?? '未登录'}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.blueGrey, fontSize: 12)),
          ],
          ),
        ),
      );
}

/// 播放器配置子页面：默认清晰度与自动播放。
class PlayerSettingsPage extends StatefulWidget {
  const PlayerSettingsPage({super.key});

  @override
  State<PlayerSettingsPage> createState() => _PlayerSettingsPageState();
}

class _PlayerSettingsPageState extends State<PlayerSettingsPage> {
  var _quality = '';
  var _autoPlay = true;
  var _backgroundPlay = false;
  var _showDislike = false;
  var _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      UserPreferences.loadDefaultQuality(),
      UserPreferences.loadAutoPlay(),
      UserPreferences.loadBackgroundPlay(),
      UserPreferences.loadShowDislike(),
    ]);
    if (!mounted) return;
    setState(() {
      _quality = results[0] as String;
      _autoPlay = results[1] as bool;
      _backgroundPlay = results[2] as bool;
      _showDislike = results[3] as bool;
      _loaded = true;
    });
  }

  Future<void> _selectQuality() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        // 限制最大高度并允许滚动，保证小屏设备也能看到全部选项。
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.6,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('默认清晰度',
                      style: TextStyle(
                          color: Colors.blueGrey,
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
                ),
              ),
              for (final option in _qualityOptions)
                ListTile(
                  title: Text(_qualityLabel(option)),
                  trailing: option == _quality
                      ? Icon(Icons.check_rounded,
                          color: AppPalette.of(context).primary)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(option),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _quality = selected);
    await UserPreferences.saveDefaultQuality(selected);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('播放器配置'), centerTitle: true),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: [
            _SettingsCard(
              children: [
                _SettingsTile(
                  icon: Icons.high_quality_outlined,
                  title: '默认清晰度',
                  subtitle: '播放视频时优先使用：${_qualityLabel(_quality)}',
                  onTap: _loaded ? () => _selectQuality() : null,
                ),
                const Divider(height: 1, indent: 56),
                SwitchListTile(
                  value: _autoPlay,
                  title: const Text('打开视频自动播放',
                      style: TextStyle(
                          color: Colors.blueGrey,
                          fontWeight: FontWeight.w700)),
                  subtitle: const Text('进入播放页后自动开始播放',
                      style:
                          TextStyle(color: Colors.blueGrey, fontSize: 12)),
                  onChanged: _loaded
                      ? (value) {
                          setState(() => _autoPlay = value);
                          UserPreferences.saveAutoPlay(value);
                        }
                      : null,
                ),
                const Divider(height: 1, indent: 56),
                SwitchListTile(
                  value: _backgroundPlay,
                  title: const Text('后台播放（Beta）',
                      style: TextStyle(
                          color: Colors.blueGrey,
                          fontWeight: FontWeight.w700)),
                  subtitle: const Text('退到后台时视频继续播放声音（Android）',
                      style:
                          TextStyle(color: Colors.blueGrey, fontSize: 12)),
                  onChanged: _loaded
                      ? (value) {
                          setState(() => _backgroundPlay = value);
                          UserPreferences.saveBackgroundPlay(value);
                        }
                      : null,
                ),
                const Divider(height: 1, indent: 56),
                SwitchListTile(
                  value: _showDislike,
                  title: const Text('显示点踩按钮',
                      style: TextStyle(
                          color: Colors.blueGrey,
                          fontWeight: FontWeight.w700)),
                  subtitle: const Text('在竖屏播放页显示点踩按钮',
                      style:
                          TextStyle(color: Colors.blueGrey, fontSize: 12)),
                  onChanged: _loaded
                      ? (value) {
                          setState(() => _showDislike = value);
                          UserPreferences.saveShowDislike(value);
                        }
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(': )',
                style: TextStyle(color: Colors.blueGrey, fontSize: 12)),
          ],
        ),
      );
}

/// 弹幕设置子页面：默认开关、透明度与字号。
class DanmakuSettingsPage extends StatefulWidget {
  const DanmakuSettingsPage({
    super.key,
    required this.enabled,
    required this.opacity,
    required this.size,
    required this.onChanged,
  });

  final bool enabled;
  final double opacity;
  final double size;
  final void Function(bool enabled, double opacity, double size) onChanged;

  @override
  State<DanmakuSettingsPage> createState() => _DanmakuSettingsPageState();
}

class _DanmakuSettingsPageState extends State<DanmakuSettingsPage> {
  late bool _enabled;
  late double _opacity;
  late double _size;

  @override
  void initState() {
    super.initState();
    _enabled = widget.enabled;
    _opacity = widget.opacity;
    _size = widget.size;
  }

  void _update() {
    widget.onChanged(_enabled, _opacity, _size);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('弹幕设置'), centerTitle: true),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: [
            Card(
              clipBehavior: Clip.antiAlias,
              child: SwitchListTile(
                value: _enabled,
                title: const Text('默认显示弹幕',
                    style: TextStyle(
                        color: Colors.blueGrey, fontWeight: FontWeight.w700)),
                subtitle: const Text('播放视频时是否默认开启弹幕',
                    style:
                        TextStyle(color: Colors.blueGrey, fontSize: 12)),
                onChanged: (value) {
                  setState(() => _enabled = value);
                  UserPreferences.saveDanmakuOn(value);
                  _update();
                },
              ),
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('弹幕透明度 ${(_opacity * 100).round()}%',
                        style: const TextStyle(
                            color: Colors.blueGrey,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                    Slider(
                      value: _opacity,
                      min: .2,
                      max: 1,
                      onChanged: (value) {
                        setState(() => _opacity = value);
                        UserPreferences.saveDanmakuOpacity(value);
                        _update();
                      },
                    ),
                    const Divider(height: 12),
                    Text('弹幕字号 ${_size.round()}',
                        style: const TextStyle(
                            color: Colors.blueGrey,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                    Slider(
                      value: _size,
                      min: 14,
                      max: 28,
                      divisions: 14,
                      onChanged: (value) {
                        setState(() => _size = value);
                        UserPreferences.saveDanmakuSize(value);
                        _update();
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text('保持即生效',
                style: TextStyle(color: Colors.blueGrey, fontSize: 12)),
          ],
        ),
      );
}
/// 文章阅读设置子页面：阅读进度滑块开关。
class ArticleReaderSettingsPage extends StatefulWidget {
  const ArticleReaderSettingsPage({super.key});

  @override
  State<ArticleReaderSettingsPage> createState() =>
      _ArticleReaderSettingsPageState();
}

class _ArticleReaderSettingsPageState extends State<ArticleReaderSettingsPage> {
  var _scrollbarEnabled = false;
  var _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await UserPreferences.loadArticleScrollbar();
    if (!mounted) return;
    setState(() {
      _scrollbarEnabled = enabled;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('文章阅读设置'), centerTitle: true),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: [
            _SettingsCard(
              children: [
                SwitchListTile(
                  value: _scrollbarEnabled,
                  title: const Text('阅读进度滑块(Beta)',
                      style: TextStyle(
                          color: Colors.blueGrey, fontWeight: FontWeight.w700)),
                  subtitle: const Text(
                      '长文章右侧显示可拖拽的阅读进度条，滚动时自动出现，无操作自动隐藏',
                      style: TextStyle(color: Colors.blueGrey, fontSize: 12)),
                  secondary: CircleAvatar(
                    backgroundColor:
                        AppPalette.of(context).primary.withOpacity(.11),
                    foregroundColor: AppPalette.of(context).primary,
                    child: const Icon(Icons.drag_indicator_rounded, size: 20),
                  ),
                  onChanged: _loaded
                      ? (value) {
                          setState(() => _scrollbarEnabled = value);
                          UserPreferences.saveArticleScrollbar(value);
                        }
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              '滑块默认关闭。开启后阅读长文章时在右侧出现进度条，可拖拽拇指跳转、点击轨道跳转进度。',
              style: TextStyle(color: Colors.blueGrey, fontSize: 12, height: 1.5),
            ),
          ],
        ),
      );
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: palette.primary.withOpacity(.11),
        foregroundColor: palette.primary,
        child: Icon(icon, size: 20),
      ),
      title: Text(title,
          style: const TextStyle(
              color: Colors.blueGrey, fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: Colors.blueGrey, fontSize: 12)),
      trailing: const Icon(Icons.chevron_right_rounded,
          color: Colors.blueGrey),
    );
  }
}

/// 编辑资料：昵称 / 性别 / 简介。
class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final _name = TextEditingController();
  final _bio = TextEditingController();
  int _gender = 0;
  var _genderInitialized = false;
  var _isSaving = false;
  var _isUploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    final session = widget.controller.session;
    _name.text = session?.displayName ?? '';
    _loadGender();
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _changeAvatar() async {
    if (_isUploadingAvatar) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 90,
    );
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() => _isUploadingAvatar = true);
    try {
      final path = await widget.controller.uploadImage(bytes, picked.name);
      await widget.controller.updateUserAvatar(path);
      await widget.controller.refreshSession();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('头像已更新')));
    } catch (error) {
      if (mounted) {
        _toast('头像上传失败：$error');
      }
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  Future<void> _loadGender() async {
    final session = widget.controller.session;
    final userId = session?.userId;
    if (userId == null) return;
    try {
      final profile = await widget.controller.userProfile(userId);
      if (!mounted) return;
      setState(() {
        _bio.text = profile.bio == '暂无简介' ? '' : profile.bio;
        _gender = switch (profile.gender) {
          'male' || '男' || '1' => 1,
          'female' || '女' || '2' => 2,
          _ => 0,
        };
        _genderInitialized = true;
      });
    } catch (_) {
      if (mounted) setState(() => _genderInitialized = true);
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      _toast('昵称不能为空');
      return;
    }
    setState(() => _isSaving = true);
    try {
      final controller = widget.controller;
      await controller.updateUserName(name);
      await controller.updateUserGender(_gender);
      await controller.updateUserBio(_bio.text.trim());
      await controller.refreshSession();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('资料已更新')));
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _isSaving = false);
        _toast('保存失败：$error');
      }
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('编辑资料'),
          centerTitle: true,
          actions: [
            TextButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  foregroundImage:
                      (widget.controller.session?.avatar.isEmpty ?? true)
                          ? null
                          : NetworkImage(widget.controller.session!.avatar),
                  child: Text(
                      widget.controller.session?.displayName.isEmpty ?? true
                          ? 'U'
                          : widget.controller.session!.displayName[0]),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('头像',
                        style: TextStyle(
                            color: Colors.blueGrey,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    OutlinedButton.icon(
                      onPressed: _isUploadingAvatar ? null : _changeAvatar,
                      icon: _isUploadingAvatar
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.photo_camera_outlined, size: 18),
                      label: Text(_isUploadingAvatar ? '上传中…' : '更换头像'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _name,
              maxLength: 16,
              decoration: const InputDecoration(
                labelText: '昵称',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            if (_genderInitialized)
              DropdownButtonFormField<int>(
                value: _gender,
                decoration: const InputDecoration(labelText: '性别'),
                items: _genderOptions.entries
                    .map((entry) => DropdownMenuItem<int>(
                          value: entry.key,
                          child: Text(entry.value),
                        ))
                    .toList(growable: false),
                onChanged: (value) =>
                    setState(() => _gender = value ?? _gender),
              )
            else
              const LinearProgressIndicator(),
            const SizedBox(height: 12),
            TextField(
              controller: _bio,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: '简介',
                hintText: '介绍一下自己吧',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      );
}
