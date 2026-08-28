import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/core/download/download_manager.dart';
import 'package:mfuns_flutter/core/download/download_policy.dart';
import 'package:mfuns_flutter/core/download/download_repository.dart';
import 'package:mfuns_flutter/core/download/download_status.dart';
import 'package:mfuns_flutter/core/download/download_task.dart';
import 'package:mfuns_flutter/features/content/export/export_storage.dart';
import 'package:mfuns_flutter/features/download/download_controller.dart';
import 'package:mfuns_flutter/features/download/download_page.dart';
import 'package:mfuns_flutter/features/download/download_picker_sheet.dart';
import 'package:mfuns_flutter/features/download/local_video_player.dart';
import 'package:mfuns_flutter/features/download/widgets/download_button.dart';
import 'package:mfuns_flutter/features/download/widgets/download_progress.dart';
import 'package:mfuns_flutter/features/download/widgets/download_task_card.dart';
import 'package:mfuns_flutter/features/home/home_repository.dart';

import 'download_test_utils.dart';

/// 记录 enqueue 请求的替身管理器：避免在 Widget 测试的 FakeAsync
/// 环境中执行真实文件 IO（完整下载链路已由单元测试覆盖）。
class _RecordingManager extends DownloadManager {
  _RecordingManager({
    required super.repository,
    required super.transport,
    required super.environment,
    super.initialPolicy,
  });

  final List<DownloadRequest> requests = [];

  @override
  Future<String> enqueue(DownloadRequest request,
      {bool force = false}) async {
    requests.add(request);
    return request.taskId;
  }
}

void main() {
  group('DownloadButton 状态', () {
    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('无任务 → 显示“下载”', (tester) async {
      await tester.pumpWidget(wrap(DownloadButton(task: null, onTap: () {})));
      expect(find.text('下载'), findsOneWidget);
    });

    testWidgets('下载中 → 显示进度百分比', (tester) async {
      final task = makeTask(
        status: DownloadStatus.downloading,
        downloadedBytes: 50,
        totalBytes: 100,
      );
      await tester.pumpWidget(wrap(DownloadButton(task: task, onTap: () {})));
      expect(find.textContaining('下载中 50%'), findsOneWidget);
    });

    testWidgets('已暂停 / 下载失败 / 已下载 文案', (tester) async {
      Future<void> expectLabel(DownloadStatus status, String label) async {
        await tester.pumpWidget(wrap(DownloadButton(
            task: makeTask(status: status), onTap: () {})));
        expect(find.text(label), findsOneWidget);
      }

      await expectLabel(DownloadStatus.paused, '已暂停');
      await expectLabel(DownloadStatus.failed, '下载失败');
      await expectLabel(DownloadStatus.completed, '已下载');
      await expectLabel(DownloadStatus.pending, '排队中');
    });
  });

  group('DownloadProgress', () {
    testWidgets('显示大小与百分比', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: DownloadProgress(
            downloadedBytes: 256 * 1024,
            totalBytes: 1024 * 1024,
          ),
        ),
      ));
      expect(find.textContaining('KB'), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);
    });

    testWidgets('未知总大小 → 不显示百分比', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: DownloadProgress(downloadedBytes: 100, totalBytes: 0)),
      ));
      expect(find.text('--'), findsOneWidget);
    });
  });

  group('DownloadTaskCard 操作按钮', () {
    testWidgets('下载中 → 暂停/取消，并显示分P进度', (tester) async {
      final task = makeTask(
        status: DownloadStatus.downloading,
        parts: [
          makePart(part: 1, status: DownloadStatus.completed),
          makePart(part: 2, status: DownloadStatus.downloading,
              downloadedBytes: 50, totalBytes: 100),
          makePart(part: 3, status: DownloadStatus.pending),
        ],
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DownloadTaskCard(
            task: task,
            onPause: () {},
            onResume: () {},
            onRetry: () {},
            onCancel: () {},
            onDelete: () {},
            onPlay: () {},
          ),
        ),
      ));
      expect(find.text('暂停'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('3 个分P'), findsOneWidget);
      expect(find.text('P1 ✓'), findsOneWidget);
      expect(find.text('P2 50%'), findsOneWidget);
      expect(find.text('P3 等待'), findsOneWidget);
    });

    testWidgets('暂停 → 继续/取消', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DownloadTaskCard(
            task: makeTask(status: DownloadStatus.paused),
            onPause: () {},
            onResume: () {},
            onRetry: () {},
            onCancel: () {},
            onDelete: () {},
            onPlay: () {},
          ),
        ),
      ));
      expect(find.text('继续'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
    });

    testWidgets('失败 → 重试/删除，并展示错误信息', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DownloadTaskCard(
            task: makeTask(
              status: DownloadStatus.failed,
              errorMessage: '媒体地址访问被拒绝（403），请稍后重试',
            ),
            onPause: () {},
            onResume: () {},
            onRetry: () {},
            onCancel: () {},
            onDelete: () {},
            onPlay: () {},
          ),
        ),
      ));
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);
      expect(find.textContaining('403'), findsOneWidget);
    });

    testWidgets('已下载 → 播放/删除', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DownloadTaskCard(
            task: makeTask(status: DownloadStatus.completed),
            onPause: () {},
            onResume: () {},
            onRetry: () {},
            onCancel: () {},
            onDelete: () {},
            onPlay: () {},
          ),
        ),
      ));
      expect(find.text('播放'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);
    });
  });

  group('LocalVideoPlayer', () {
    testWidgets('文件打开失败时展示错误状态（不崩溃）', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: LocalVideoPlayer(
          title: '本地视频',
          parts: {1: '/nonexistent/v.mp4'},
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      // 测试环境无 video_player 平台实现，initialize 失败 → 错误 UI。
      expect(find.textContaining('本地视频打开失败'), findsOneWidget);
    });
  });

  group('DownloadPage', () {
    late TestStorage testStorage;
    late DownloadManager manager;
    late DownloadController controller;

    setUp(() async {
      testStorage = await TestStorage.create();
      final store = InMemoryDownloadTaskStore();
      manager = DownloadManager(
        repository: DownloadRepository(
          store: store,
          storage: testStorage.storage(),
        ),
        transport: FakeDownloadTransport(),
        environment: FakeDownloadEnvironment(),
        initialPolicy:
            const DownloadPolicy(wifiOnly: false, maxConcurrent: 2),
      );
      await manager.initialize();
      controller = DownloadController(manager: manager);
    });

    tearDown(() async {
      controller.dispose();
      await manager.dispose();
      await testStorage.cleanup();
    });

    Future<void> seedActiveTask() async {
      final repo = manager.repositoryForTest;
      final task = await repo.createTask(makeRequest(
        videoId: 1,
        title: '正在下载的视频',
        parts: [
          const DownloadPartSource(part: 1, url: 'https://cdn.example.com/a/p1.mp4'),
          const DownloadPartSource(part: 2, url: 'https://cdn.example.com/a/p2.mp4'),
        ],
      ));
      await repo.updatePartProgress(task, 1,
          downloadedBytes: 50, totalBytes: 100, speed: 10);
    }

    Future<void> seedCompletedTask() async {
      final repo = manager.repositoryForTest;
      var task = await repo.createTask(makeRequest(
        videoId: 2,
        title: '已下载的视频',
        quality: '720p',
        qualityLabel: '720P',
        parts: [
          const DownloadPartSource(part: 1, url: 'https://cdn.example.com/b/p1.mp4'),
        ],
      ));
      await repo.setTaskStatus(task, DownloadStatus.completed);
      task = (await repo.task(task.taskId))!;
      final part = task.parts.single;
      await File(part.tempFilePath).create(recursive: true);
      await File(part.tempFilePath).writeAsBytes(List.filled(5, 1));
      await repo.completePart(task, 1);
    }

    testWidgets('展示下载中任务与统计', (tester) async {
      await tester.runAsync(() async => seedActiveTask());
      await tester.pumpWidget(MaterialApp(home: DownloadPage(controller: controller)));
      await tester.pump();
      expect(find.text('正在下载的视频'), findsOneWidget);
      expect(find.text('2 个分P'), findsOneWidget);
    });

    testWidgets('已下载标签展示完成的任务', (tester) async {
      await tester.runAsync(() async => seedCompletedTask());
      await tester.pumpWidget(MaterialApp(home: DownloadPage(controller: controller)));
      await tester.pump();
      await tester.tap(find.text('已下载（1）'));
      await tester.pumpAndSettle();
      expect(find.text('已下载的视频'), findsOneWidget);
      expect(find.text('播放'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);
    });

    testWidgets('已下载任务点击播放 → 进入本地播放器（多分P）', (tester) async {
      await tester.runAsync(() async => seedCompletedTask());
      await tester.pumpWidget(MaterialApp(home: DownloadPage(controller: controller)));
      await tester.pump();
      await tester.tap(find.text('已下载（1）'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('播放'));
      await tester.pumpAndSettle();
      // 进入 LocalVideoPlayer 页面（无平台实现时展示错误态，页面标题仍在）。
      expect(find.byType(LocalVideoPlayer), findsOneWidget);
      expect(find.textContaining('已下载的视频'), findsWidgets);
    });

    testWidgets('已下载任务导出：分P选择 → 保存到系统视频目录', (tester) async {
      // 导出持久化走桌面分支复制到主目录，测试覆盖到临时目录。
      final exportHome = Directory.systemTemp.createTempSync('mfuns_export_home_');
      ExportStorage.debugHomeOverride = exportHome.path;
      addTearDown(() {
        ExportStorage.debugHomeOverride = null;
        try {
          exportHome.deleteSync(recursive: true);
        } catch (_) {}
      });
      await tester.runAsync(() async => seedCompletedTask());

      await tester.pumpWidget(MaterialApp(home: DownloadPage(controller: controller)));
      await tester.pump();
      await tester.tap(find.text('已下载（1）'));
      await tester.pumpAndSettle();

      // 卡片出现「导出」按钮 → 打开分P选择弹窗。
      await tester.tap(find.text('导出'));
      await tester.pumpAndSettle();
      expect(find.text('导出视频'), findsOneWidget);
      expect(find.text('导出选中的 1 个分P'), findsOneWidget);

      // 确认导出（复制文件为真实 IO，在 runAsync 中推进；
      // 分享面板不可用时回退为“已保存到本地”提示）。
      await tester.tap(find.text('导出选中的 1 个分P'));
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 50));
        if (find.textContaining('已保存到本地').evaluate().isNotEmpty) break;
      }
      await tester.pumpAndSettle();

      final exportedDir = Directory(
          '${exportHome.path}${Platform.pathSeparator}Videos'
          '${Platform.pathSeparator}Mfuns Flutter');
      final files = exportedDir.existsSync()
          ? exportedDir.listSync().whereType<File>().toList()
          : <File>[];
      expect(files, hasLength(1));
      expect(files.single.path, endsWith('.mp4'));
      expect(find.textContaining('已保存到本地'), findsOneWidget);
    });

    testWidgets('删除任务（确认弹窗）', (tester) async {
      await tester.runAsync(() async => seedCompletedTask());
      await tester.pumpWidget(MaterialApp(home: DownloadPage(controller: controller)));
      await tester.pump();
      await tester.tap(find.text('已下载（1）'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.text('删除下载'), findsOneWidget);
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('删除'),
      ));
      await tester.pump();
      // 文件删除为真实 IO，放入 runAsync 中完成。
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
      expect((await manager.getTasks()), isEmpty);
      expect(find.text('已下载的视频'), findsNothing);
    });
  });

  group('DownloadPickerSheet', () {
    late TestStorage testStorage;
    late DownloadManager manager;

    late _RecordingManager recordingManager;

    setUp(() async {
      testStorage = await TestStorage.create();
      recordingManager = _RecordingManager(
        repository: DownloadRepository(
          store: InMemoryDownloadTaskStore(),
          storage: testStorage.storage(),
        ),
        transport: FakeDownloadTransport(),
        environment: FakeDownloadEnvironment(),
        initialPolicy:
            const DownloadPolicy(wifiOnly: false, maxConcurrent: 2),
      );
      await recordingManager.initialize();
      manager = recordingManager;
    });

    tearDown(() async {
      await manager.dispose();
      await testStorage.cleanup();
    });

    final qualities = [
      const VideoQuality(
          part: 1, name: '高清', label: '1080p', url: 'https://cdn.example.com/p1_1080.mp4'),
      const VideoQuality(
          part: 1, name: '标清', label: '720p', url: 'https://cdn.example.com/p1_720.mp4'),
      const VideoQuality(
          part: 2, name: '高清', label: '1080p', url: 'https://cdn.example.com/p2_1080.mp4'),
      const VideoQuality(
          part: 2, name: '标清', label: '720p', url: 'https://cdn.example.com/p2_720.mp4'),
    ];

    Future<void> pumpSheet(WidgetTester tester,
        {VideoQuality? selected}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => DownloadPickerSheet.show(
                  context,
                  videoId: 1,
                  title: '测试',
                  cover: '',
                  qualities: qualities,
                  selectedQuality: selected,
                  manager: manager,
                ),
                child: const Text('打开下载面板'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('打开下载面板'));
      await tester.pumpAndSettle();
    }

    testWidgets('默认选中当前播放清晰度，提示下载全部 2 个分P', (tester) async {
      await pumpSheet(tester, selected: qualities[0]); // P1 1080p
      expect(find.text('下载视频'), findsOneWidget);
      expect(find.text('选择分P'), findsOneWidget);
      expect(find.text('下载选中的 2 个分P'), findsOneWidget);
    });

    testWidgets('可取消部分分P → 请求只包含选中的分P', (tester) async {
      await pumpSheet(tester);
      // 取消勾选 P2。
      final p2Chip = find.widgetWithText(FilterChip, 'P2');
      await tester.ensureVisible(p2Chip);
      await tester.pumpAndSettle();
      await tester.tap(p2Chip);
      await tester.pumpAndSettle();
      expect(find.text('下载选中的 1 个分P'), findsOneWidget);
      await tester.ensureVisible(find.text('下载选中的 1 个分P'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下载选中的 1 个分P'));
      await tester.pumpAndSettle();

      expect(recordingManager.requests, hasLength(1));
      final request = recordingManager.requests.single;
      expect(request.parts, hasLength(1));
      expect(request.parts.single.part, 1);
      expect(request.parts.single.url, 'https://cdn.example.com/p1_1080.mp4');
    });

    testWidgets('全不选 / 全选切换', (tester) async {
      await pumpSheet(tester);
      await tester.tap(find.text('全不选'));
      await tester.pumpAndSettle();
      expect(find.text('下载选中的 0 个分P'), findsOneWidget);
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      expect(find.text('下载选中的 2 个分P'), findsOneWidget);
    });

    testWidgets('已存在于任务中的分P锁定显示，任务外分P可勾选（补下）', (tester) async {
      // 预置任务：P1 已下载完成。
      await tester.runAsync(() async {
        final repo = manager.repositoryForTest;
        final task = await repo.createTask(makeRequest(parts: [
          const DownloadPartSource(part: 1, url: 'https://cdn.example.com/p1_1080.mp4'),
        ]));
        await repo.setPartStatus(task, 1, DownloadStatus.completed);
        final latest = (await repo.task(task.taskId))!;
        await repo.setTaskStatus(latest, DownloadStatus.completed);
      });

      await pumpSheet(tester);
      // P1 锁定显示为已下载，P2 可勾选。
      expect(find.text('P1 ✓'), findsOneWidget);
      expect(find.text('补下选中的 1 个分P'), findsOneWidget);
      await tester.tap(find.text('补下选中的 1 个分P'));
      await tester.pumpAndSettle();

      // 补下请求只包含 P2。
      expect(recordingManager.requests, hasLength(1));
      final request = recordingManager.requests.single;
      expect(request.parts, hasLength(1));
      expect(request.parts.single.part, 2);
    });

    testWidgets('切换清晰度', (tester) async {
      await pumpSheet(tester);
      // 默认 1080p，切换到 720p。
      await tester.tap(find.text('720p'));
      await tester.pumpAndSettle();
      expect(find.text('下载选中的 2 个分P'), findsOneWidget);
    });

    testWidgets('确认后创建整个视频任务（构造正确的 DownloadRequest）', (tester) async {
      await pumpSheet(tester, selected: qualities[1]); // P1 720p
      await tester.tap(find.text('下载选中的 2 个分P'));
      await tester.pumpAndSettle();

      expect(recordingManager.requests, hasLength(1));
      final request = recordingManager.requests.single;
      expect(request.videoId, 1);
      expect(request.quality, '720p');
      expect(request.parts, hasLength(2));
      expect(request.parts[0].part, 1);
      expect(request.parts[1].part, 2);
      expect(request.parts[0].url, 'https://cdn.example.com/p1_720.mp4');
      expect(request.parts[1].url, 'https://cdn.example.com/p2_720.mp4');
      expect(request.taskId, 'v1_720p');
    });

    testWidgets('已存在已完成任务 → 按钮显示已下载且不重复创建', (tester) async {
      // 预置一个 completed 任务（模拟此前已下载）。
      await tester.runAsync(() async {
        final repo = manager.repositoryForTest;
        final task = await repo.createTask(makeRequest(parts: [
          const DownloadPartSource(part: 1, url: 'https://cdn.example.com/p1_1080.mp4'),
          const DownloadPartSource(part: 2, url: 'https://cdn.example.com/p2_1080.mp4'),
        ]));
        await repo.setTaskStatus(task, DownloadStatus.completed);
      });

      await pumpSheet(tester);
      expect(find.text('已下载，前往下载管理'), findsOneWidget);
      await tester.tap(find.text('已下载，前往下载管理'));
      await tester.pumpAndSettle();
      // 不产生新任务。
      expect(recordingManager.requests, isEmpty);
    });
  });
}
