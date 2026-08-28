import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/core/download/download_manager.dart';
import 'package:mfuns_flutter/core/download/download_policy.dart';
import 'package:mfuns_flutter/core/download/download_repository.dart';
import 'package:mfuns_flutter/core/download/download_status.dart';
import 'package:mfuns_flutter/core/download/download_task.dart';
import 'package:mfuns_flutter/core/download/download_transport.dart';

import 'download_test_utils.dart';

void main() {
  late TestStorage testStorage;
  late InMemoryDownloadTaskStore store;
  late DownloadRepository repository;
  late FakeDownloadEnvironment environment;
  late FakeDownloadTransport transport;
  late DownloadManager manager;

  setUp(() async {
    testStorage = await TestStorage.create();
    store = InMemoryDownloadTaskStore();
    repository = DownloadRepository(
      store: store,
      storage: testStorage.storage(),
    );
    environment = FakeDownloadEnvironment();
    transport = FakeDownloadTransport();
    manager = DownloadManager(
      repository: repository,
      transport: transport,
      environment: environment,
      initialPolicy: const DownloadPolicy(wifiOnly: false, maxConcurrent: 2),
    )..autoRetryBase = const Duration(milliseconds: 5);
    await manager.initialize();
  });

  tearDown(() async {
    await manager.dispose();
    await repository.disposeStore();
    await testStorage.cleanup();
  });

  /// 3 个分P的视频请求。
  DownloadRequest request3Parts({int videoId = 1, String quality = '1080p'}) =>
      makeRequest(
        videoId: videoId,
        quality: quality,
        parts: [
          DownloadPartSource(
              part: 1, url: 'https://cdn.example.com/$videoId/p1.mp4'),
          DownloadPartSource(
              part: 2, url: 'https://cdn.example.com/$videoId/p2.mp4'),
          DownloadPartSource(
              part: 3, url: 'https://cdn.example.com/$videoId/p3.mp4'),
        ],
      );

  Uint8List body(int size) =>
      Uint8List.fromList(List<int>.generate(size, (i) => i % 251));

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  group('enqueue 与完成（视频级）', () {
    test('整个视频所有分P顺序下载 → 任务 completed，各分P文件齐全', () async {
      final content1 = body(100 * 1024);
      final content2 = body(64 * 1024);
      final content3 = body(32 * 1024);
      transport.responders = [
        FakeDownloadTransport.partial(content1),
        FakeDownloadTransport.partial(content2),
        FakeDownloadTransport.partial(content3),
      ];
      final watcher = TaskWatcher(manager.watchTasks());

      final taskId = await manager.enqueue(request3Parts());
      expect(taskId, 'v1_1080p');

      final completed =
          await watcher.waitFor(taskId, DownloadStatus.completed);
      expect(completed.totalPartCount, 3);
      expect(completed.completedPartCount, 3);
      expect(completed.totalBytes, content1.length + content2.length + content3.length);
      expect(completed.isPlayable, isTrue);
      // 各分P正式文件存在且内容一致，临时文件已重命名。
      for (final part in completed.parts) {
        expect(await File(part.filePath).exists(), isTrue);
        expect(await File(part.tempFilePath).exists(), isFalse);
      }
      expect(await File(completed.parts[0].filePath).readAsBytes(), content1);
      expect(await File(completed.parts[1].filePath).readAsBytes(), content2);
      expect(await File(completed.parts[2].filePath).readAsBytes(), content3);
      // 分P顺序下载：请求按 P1 → P2 → P3 发起。
      expect(transport.requestedOffsets, [0, 0, 0]);
      watcher.close();
    });

    test('部分分P完成时任务仍为 downloading，且已完成分P保留', () async {
      final slowTransport = SlowDownloadTransport(fullBody: body(1024));
      final slowManager = DownloadManager(
        repository: repository,
        transport: slowTransport,
        environment: environment,
        initialPolicy:
            const DownloadPolicy(wifiOnly: false, maxConcurrent: 2),
      );
      await slowManager.initialize();
      final watcher = TaskWatcher(slowManager.watchTasks());

      final taskId = await slowManager.enqueue(request3Parts());
      await watcher.waitFor(taskId, DownloadStatus.downloading);
      // 放行 P1。
      await waitUntil(() => slowTransport.connections.isNotEmpty,
          description: 'P1 建立连接');
      slowTransport.connections.first.release();
      final completedPart1 = await waitUntilTask(
          watcher, taskId, (t) => t.completedPartCount >= 1);
      expect(completedPart1.status, DownloadStatus.downloading);
      expect(await File(completedPart1.parts[0].filePath).exists(), isTrue);

      // 依次放行 P2、P3。
      await waitUntil(() => slowTransport.connections.length >= 2,
          description: 'P2 建立连接');
      slowTransport.releaseAll();
      await waitUntil(() => slowTransport.connections.length >= 3,
          description: 'P3 建立连接');
      slowTransport.releaseAll();
      await watcher.waitFor(taskId, DownloadStatus.completed);
      watcher.close();
      await slowManager.dispose();
    });

    test('重复 enqueue 同一视频+清晰度不创建重复任务', () async {
      transport.responders = [FakeDownloadTransport.partial(body(1000))];
      final first = await manager.enqueue(makeRequest());
      final second = await manager.enqueue(makeRequest());
      expect(second, first);
      final tasks = await manager.getTasks();
      expect(tasks.where((t) => t.taskId == first).length, 1);
    });

    test('同一视频不同清晰度创建独立任务', () async {
      transport.responders = [
        FakeDownloadTransport.partial(body(1000)),
        FakeDownloadTransport.partial(body(1000)),
      ];
      await manager.enqueue(makeRequest(quality: '1080p'));
      await manager.enqueue(makeRequest(quality: '720p'));
      final tasks = await manager.getTasks();
      expect(tasks.length, 2);
      expect(tasks.map((t) => t.quality), containsAll(['1080p', '720p']));
    });

    test('总大小未知（无 Content-Length）也能完成', () async {
      transport.responders = [
        (offset) async => FakeDownloadConnection(
              statusCode: 200,
              body: Stream.fromIterable([body(10), body(10)]),
            ),
      ];
      final watcher = TaskWatcher(manager.watchTasks());
      final taskId = await manager.enqueue(makeRequest());
      final completed =
          await watcher.waitFor(taskId, DownloadStatus.completed);
      expect(await File(completed.parts.single.filePath).readAsBytes(),
          Uint8List.fromList([...body(10), ...body(10)]));
      watcher.close();
    });
  });

  group('并发控制（任务级）', () {
    test('最大并发数限制为 policy.maxConcurrent（任务数）', () async {
      final slowTransport = SlowDownloadTransport(fullBody: body(1024));
      final slowManager = DownloadManager(
        repository: repository,
        transport: slowTransport,
        environment: environment,
        initialPolicy:
            const DownloadPolicy(wifiOnly: false, maxConcurrent: 2),
      );
      await slowManager.initialize();
      final watcher = TaskWatcher(slowManager.watchTasks());

      await slowManager.enqueue(makeRequest(videoId: 1));
      await slowManager.enqueue(makeRequest(videoId: 2));
      await slowManager.enqueue(makeRequest(videoId: 3));
      await settle();

      // 只有 2 个任务建立连接，第 3 个排队。
      await waitUntil(() => slowTransport.connections.length == 2,
          description: '前两个任务建立连接');
      var tasks = await slowManager.getTasks();
      expect(
          tasks.where((t) => t.status == DownloadStatus.downloading).length, 2);
      expect(tasks.firstWhere((t) => t.videoId == 3).status,
          DownloadStatus.pending);

      // 放行后第 3 个开始。
      slowTransport.connections[0].release();
      await waitUntil(() => slowTransport.connections.length == 3,
          description: '第 3 个任务建立连接');
      await watcher.waitFor('v3_1080p', DownloadStatus.downloading);

      slowTransport.releaseAll();
      await watcher.waitFor('v3_1080p', DownloadStatus.completed);
      watcher.close();
      await slowManager.dispose();
    });

    test('更新 maxConcurrent 策略生效', () async {
      final slowTransport = SlowDownloadTransport(fullBody: body(1024));
      final policyManager = DownloadManager(
        repository: repository,
        transport: slowTransport,
        environment: environment,
        initialPolicy:
            const DownloadPolicy(wifiOnly: false, maxConcurrent: 1),
      );
      await policyManager.initialize();
      final watcher = TaskWatcher(policyManager.watchTasks());

      await policyManager.enqueue(makeRequest(videoId: 1));
      await policyManager.enqueue(makeRequest(videoId: 2));
      await waitUntil(() => slowTransport.connections.length == 1,
          description: '并发 1 时只有 1 个连接');

      await policyManager.updatePolicy(
          const DownloadPolicy(wifiOnly: false, maxConcurrent: 2));
      await waitUntil(() => slowTransport.connections.length == 2,
          description: '提升并发后第 2 个连接建立');

      slowTransport.releaseAll();
      await watcher.waitFor('v2_1080p', DownloadStatus.completed);
      watcher.close();
      await policyManager.dispose();
    });
  });

  group('暂停 / 恢复 / 取消（任务级）', () {
    test('暂停后当前分P .part 保留，继续后从断点完成', () async {
      final slowTransport = SlowDownloadTransport(fullBody: body(1024));
      final slowManager = DownloadManager(
        repository: repository,
        transport: slowTransport,
        environment: environment,
        initialPolicy:
            const DownloadPolicy(wifiOnly: false, maxConcurrent: 2),
      );
      await slowManager.initialize();
      final watcher = TaskWatcher(slowManager.watchTasks());

      final taskId = await slowManager.enqueue(request3Parts());
      await waitUntil(() => slowTransport.connections.isNotEmpty,
          description: 'P1 建立连接');
      await watcher.waitFor(taskId, DownloadStatus.downloading);

      await slowManager.pause(taskId);
      final paused = await watcher.waitFor(taskId, DownloadStatus.paused);
      // 暂停时当前分P临时文件保留（断点），不被删除。
      final p1Part = paused.parts.first;
      expect(await File(p1Part.tempFilePath).exists(), isTrue);
      expect(p1Part.status, DownloadStatus.paused);

      // 继续下载 → 从断点恢复并完成。
      await slowManager.resume(taskId);
      await watcher.waitFor(taskId, DownloadStatus.downloading);
      await waitUntil(() => slowTransport.connections.length == 2,
          description: '恢复后 P1 建立新连接');
      slowTransport.releaseAll();
      // 依次放行 P2、P3。
      await waitUntil(() => slowTransport.connections.length == 3,
          description: 'P2 建立连接');
      slowTransport.releaseAll();
      await waitUntil(() => slowTransport.connections.length == 4,
          description: 'P3 建立连接');
      slowTransport.releaseAll();
      final completed =
          await watcher.waitFor(taskId, DownloadStatus.completed);
      expect(completed.completedPartCount, 3);
      watcher.close();
      await slowManager.dispose();
    });

    test('任务运行中追加分P → 自动补下', () async {
      final slowTransport = SlowDownloadTransport(fullBody: body(1024));
      final slowManager = DownloadManager(
        repository: repository,
        transport: slowTransport,
        environment: environment,
        initialPolicy:
            const DownloadPolicy(wifiOnly: false, maxConcurrent: 2),
      );
      await slowManager.initialize();
      final watcher = TaskWatcher(slowManager.watchTasks());

      // 先下载 P1、P2（两个分P的任务）。
      final taskId = await slowManager.enqueue(makeRequest(parts: [
        const DownloadPartSource(part: 1, url: 'https://cdn.example.com/p1.mp4'),
        const DownloadPartSource(part: 2, url: 'https://cdn.example.com/p2.mp4'),
      ]));
      await waitUntil(() => slowTransport.connections.isNotEmpty,
          description: 'P1 建立连接');
      // 放行 P1、P2。
      slowTransport.releaseAll();
      await waitUntil(() => slowTransport.connections.length == 2,
          description: 'P2 建立连接');
      slowTransport.releaseAll();
      await watcher.waitFor(taskId, DownloadStatus.completed);
      expect(watcher.current(taskId)!.completedPartCount, 2);

      // 补下 P3：enqueue 合并进任务并回到 pending。
      await slowManager.enqueue(makeRequest(parts: [
        const DownloadPartSource(part: 1, url: 'https://cdn.example.com/p1.mp4'),
        const DownloadPartSource(part: 2, url: 'https://cdn.example.com/p2.mp4'),
        const DownloadPartSource(part: 3, url: 'https://cdn.example.com/p3.mp4'),
      ]));
      await waitUntil(() => slowTransport.connections.length == 3,
          description: 'P3 建立连接');
      slowTransport.releaseAll();
      final completed =
          await watcher.waitFor(taskId, DownloadStatus.completed);
      expect(completed.completedPartCount, 3);
      watcher.close();
      await slowManager.dispose();
    });

    test('取消后任务保留为 canceled，未完成分P临时文件删除、已完成分P保留', () async {
      final slowTransport = SlowDownloadTransport(fullBody: body(1024));
      final slowManager = DownloadManager(
        repository: repository,
        transport: slowTransport,
        environment: environment,
        initialPolicy:
            const DownloadPolicy(wifiOnly: false, maxConcurrent: 2),
      );
      await slowManager.initialize();
      final watcher = TaskWatcher(slowManager.watchTasks());

      final taskId = await slowManager.enqueue(request3Parts());
      await waitUntil(() => slowTransport.connections.isNotEmpty,
          description: 'P1 建立连接');
      await watcher.waitFor(taskId, DownloadStatus.downloading);
      // 放行 P1 使其完成，P2 挂起。
      slowTransport.connections.first.release();
      await waitUntilTask(
          watcher, taskId, (t) => t.completedPartCount >= 1);
      await waitUntil(() => slowTransport.connections.length == 2,
          description: 'P2 建立连接');

      await slowManager.cancel(taskId);
      final canceled =
          await watcher.waitFor(taskId, DownloadStatus.canceled);
      // 已完成 P1 正式文件保留；P2/P3 临时文件被删除。
      expect(await File(canceled.parts[0].filePath).exists(), isTrue);
      expect(canceled.parts[0].status, DownloadStatus.completed);
      expect(await File(canceled.parts[1].tempFilePath).exists(), isFalse);
      expect(canceled.parts[1].status, DownloadStatus.canceled);

      // canceled 任务可重试：跳过已完成 P1，只补 P2/P3。
      final previousConnections = slowTransport.connections.length;
      await slowManager.retry(taskId);
      await watcher.waitFor(taskId, DownloadStatus.downloading);
      await waitUntil(
          () => slowTransport.connections.length == previousConnections + 1,
          description: '重试后 P2 建立连接');
      slowTransport.releaseAll();
      await waitUntil(
          () => slowTransport.connections.length == previousConnections + 2,
          description: 'P3 建立连接');
      slowTransport.releaseAll();
      final completed =
          await watcher.waitFor(taskId, DownloadStatus.completed);
      expect(completed.completedPartCount, 3);
      watcher.close();
      await slowManager.dispose();
    });
  });

  group('失败与重试', () {
    test('分P失败 → 任务 failed 且携带错误信息；retry 后成功', () async {
      transport.responders = [
        (offset) async => FakeDownloadConnection(statusCode: 403),
        FakeDownloadTransport.partial(body(1024)),
      ];
      final watcher = TaskWatcher(manager.watchTasks());
      final taskId = await manager.enqueue(makeRequest());

      final failed = await watcher.waitFor(taskId, DownloadStatus.failed);
      expect(failed.errorMessage, contains('403'));
      expect(failed.parts.single.status, DownloadStatus.pending);

      await manager.retry(taskId);
      final completed =
          await watcher.waitFor(taskId, DownloadStatus.completed);
      expect(completed.isPlayable, isTrue);
      watcher.close();
    });

    test('HTTP 404 → failed', () async {
      transport.responders = [
        (offset) async => FakeDownloadConnection(statusCode: 404),
      ];
      final watcher = TaskWatcher(manager.watchTasks());
      final taskId = await manager.enqueue(makeRequest());
      final failed = await watcher.waitFor(taskId, DownloadStatus.failed);
      expect(failed.errorMessage, contains('404'));
      watcher.close();
    });

    test('HTTP 500 → failed 且不自动重试（非瞬时错误）', () async {
      transport.responders = [
        (offset) async => FakeDownloadConnection(statusCode: 500),
      ];
      final watcher = TaskWatcher(manager.watchTasks());
      final taskId = await manager.enqueue(makeRequest());
      final failed = await watcher.waitFor(taskId, DownloadStatus.failed);
      expect(failed.errorMessage, contains('500'));
      expect(transport.callCount, 1);
      watcher.close();
    });

    test('瞬时网络错误自动重试后成功', () async {
      transport.responders = [FakeDownloadTransport.partial(body(1024))];
      transport.failures = {1}; // 第一次连接模拟断网
      final watcher = TaskWatcher(manager.watchTasks());
      final taskId = await manager.enqueue(makeRequest());
      final completed =
          await watcher.waitFor(taskId, DownloadStatus.completed);
      expect(completed.isPlayable, isTrue);
      expect(transport.callCount, greaterThan(1));
      watcher.close();
    });

    test('连续瞬时错误超过上限 → failed', () async {
      transport.responders = [FakeDownloadTransport.partial(body(1024))];
      transport.failures = {1, 2, 3, 4, 5};
      final watcher = TaskWatcher(manager.watchTasks());
      final taskId = await manager.enqueue(makeRequest());
      final failed = await watcher.waitFor(taskId, DownloadStatus.failed);
      expect(failed.status, DownloadStatus.failed);
      expect(failed.errorMessage, isNotEmpty);
      watcher.close();
    });

    test('响应中途截断 → 自动续传完整', () async {
      final content = body(64 * 1024);
      // 第一次只返回一半字节（截断），第二次返回剩余。
      var calls = 0;
      transport.responders = [
        (offset) async {
          calls++;
          if (calls == 1) {
            return FakeDownloadConnection(
              statusCode: 206,
              contentRangeTotal: content.length,
              contentLength: content.length ~/ 2,
              body: Stream.fromIterable([
                Uint8List.sublistView(content, 0, content.length ~/ 2),
              ]),
            );
          }
          return FakeDownloadConnection(
            statusCode: 206,
            contentRangeStart: content.length ~/ 2,
            contentRangeEnd: content.length - 1,
            contentRangeTotal: content.length,
            contentLength: content.length - content.length ~/ 2,
            body: Stream.fromIterable([
              Uint8List.sublistView(content, content.length ~/ 2),
            ]),
          );
        },
      ];
      final watcher = TaskWatcher(manager.watchTasks());
      final taskId = await manager.enqueue(makeRequest());
      final completed =
          await watcher.waitFor(taskId, DownloadStatus.completed);
      expect(await File(completed.parts.single.filePath).readAsBytes(), content);
      expect(transport.requestedOffsets, [0, content.length ~/ 2]);
      watcher.close();
    });
  });

  group('仅 Wi-Fi 策略', () {
    test('wifiOnly + 移动网络 → enqueue 抛错', () async {
      final wifiManager = DownloadManager(
        repository: repository,
        transport: transport,
        environment: environment,
        initialPolicy:
            const DownloadPolicy(wifiOnly: true, maxConcurrent: 2),
      );
      await wifiManager.initialize();
      environment.setNetwork(DownloadNetworkType.mobile);

      await expectLater(
        wifiManager.enqueue(makeRequest()),
        throwsA(isA<DownloadException>()),
      );
      await wifiManager.dispose();
    });

    test('wifiOnly + 移动网络 + force → 允许下载', () async {
      final wifiManager = DownloadManager(
        repository: repository,
        transport: transport,
        environment: environment,
        initialPolicy:
            const DownloadPolicy(wifiOnly: true, maxConcurrent: 2),
      );
      await wifiManager.initialize();
      environment.setNetwork(DownloadNetworkType.mobile);
      transport.responders = [FakeDownloadTransport.partial(body(1024))];
      final watcher = TaskWatcher(wifiManager.watchTasks());

      final taskId = await wifiManager.enqueue(makeRequest(), force: true);
      await watcher.waitFor(taskId, DownloadStatus.completed);
      watcher.close();
      await wifiManager.dispose();
    });

    test('wifiOnly + Wi-Fi → 正常下载', () async {
      final wifiManager = DownloadManager(
        repository: repository,
        transport: transport,
        environment: environment,
        initialPolicy:
            const DownloadPolicy(wifiOnly: true, maxConcurrent: 2),
      );
      await wifiManager.initialize();
      transport.responders = [FakeDownloadTransport.partial(body(1024))];
      final watcher = TaskWatcher(wifiManager.watchTasks());

      final taskId = await wifiManager.enqueue(makeRequest());
      await watcher.waitFor(taskId, DownloadStatus.completed);
      watcher.close();
      await wifiManager.dispose();
    });

    test('下载中切换到移动网络 → 自动暂停', () async {
      final slowTransport = SlowDownloadTransport(fullBody: body(1024));
      final wifiManager = DownloadManager(
        repository: repository,
        transport: slowTransport,
        environment: environment,
        initialPolicy:
            const DownloadPolicy(wifiOnly: true, maxConcurrent: 2),
      );
      await wifiManager.initialize();
      final watcher = TaskWatcher(wifiManager.watchTasks());

      final taskId = await wifiManager.enqueue(makeRequest());
      await waitUntil(() => slowTransport.connections.isNotEmpty,
          description: '任务建立连接');
      await watcher.waitFor(taskId, DownloadStatus.downloading);
      environment.setNetwork(DownloadNetworkType.mobile);
      await watcher.waitFor(taskId, DownloadStatus.paused);

      environment.setNetwork(DownloadNetworkType.wifi);
      await wifiManager.resume(taskId);
      await waitUntil(() => slowTransport.connections.length == 2,
          description: '恢复下载建立新连接');
      slowTransport.releaseAll();
      await watcher.waitFor(taskId, DownloadStatus.completed);
      watcher.close();
      await wifiManager.dispose();
    });
  });

  group('App 重启恢复', () {
    test('重启后 .part 保留 → 从断点续传完成', () async {
      final content = body(256 * 1024);
      const taskId = 'v1_1080p';
      // 模拟第一次下载到一半时进程被强杀：任务 downloading + 半程 .part。
      final task = await repository.createTask(makeRequest());
      await repository.setTaskStatus(task, DownloadStatus.downloading);
      final part = File(task.parts.single.tempFilePath);
      await part.create(recursive: true);
      await part.writeAsBytes(
          Uint8List.sublistView(content, 0, content.length ~/ 2));
      expect(await part.length(), content.length ~/ 2);

      // “重启”：新 manager + 相同 store/storage，服务器支持 Range 续传。
      final restartedRepo = DownloadRepository(
        store: store,
        storage: testStorage.storage(),
      );
      final restartedTransport = FakeDownloadTransport()
        ..responders = [FakeDownloadTransport.partial(content)];
      final restartedManager = DownloadManager(
        repository: restartedRepo,
        transport: restartedTransport,
        environment: environment,
        initialPolicy:
            const DownloadPolicy(wifiOnly: false, maxConcurrent: 2),
      );
      await restartedManager.initialize();
      final watcher = TaskWatcher(restartedManager.watchTasks());

      final completed =
          await watcher.waitFor(taskId, DownloadStatus.completed);
      expect(await File(completed.parts.single.filePath).readAsBytes(), content);
      // 从断点（而非 0）发起续传请求。
      expect(restartedTransport.requestedOffsets.first, content.length ~/ 2);
      watcher.close();
      await restartedManager.dispose();
      await restartedRepo.disposeStore();
    });

    test('重启后无 .part → 从头下载', () async {
      const taskId = 'v1_1080p';
      // 先创建一个 downloading 状态但无任何文件的任务。
      final task = await repository.createTask(makeRequest());
      await repository.setTaskStatus(task, DownloadStatus.downloading);

      final restartedRepo = DownloadRepository(
        store: store,
        storage: testStorage.storage(),
      );
      final restartedTransport = FakeDownloadTransport()
        ..responders = [FakeDownloadTransport.partial(body(1024))];
      final restartedManager = DownloadManager(
        repository: restartedRepo,
        transport: restartedTransport,
        environment: environment,
        initialPolicy:
            const DownloadPolicy(wifiOnly: false, maxConcurrent: 2),
      );
      await restartedManager.initialize();
      final watcher = TaskWatcher(restartedManager.watchTasks());
      await watcher.waitFor(taskId, DownloadStatus.completed);
      expect(restartedTransport.requestedOffsets.first, 0);
      watcher.close();
      await restartedManager.dispose();
      await restartedRepo.disposeStore();
    });

    test('重启后 paused / failed 任务不自动恢复', () async {
      final pausedTask = await repository.createTask(makeRequest(quality: '720p'));
      await repository.setTaskStatus(pausedTask, DownloadStatus.paused);
      final failedTask =
          await repository.createTask(makeRequest(quality: '4k'));
      await repository.setTaskStatus(failedTask, DownloadStatus.failed);

      final restartedRepo = DownloadRepository(
        store: store,
        storage: testStorage.storage(),
      );
      final restartedManager = DownloadManager(
        repository: restartedRepo,
        transport: transport,
        environment: environment,
        initialPolicy:
            const DownloadPolicy(wifiOnly: false, maxConcurrent: 2),
      );
      await restartedManager.initialize();
      await settle();
      final tasks = await restartedManager.getTasks();
      expect(tasks.firstWhere((t) => t.quality == '720p').status,
          DownloadStatus.paused);
      expect(tasks.firstWhere((t) => t.quality == '4k').status,
          DownloadStatus.failed);
      await restartedManager.dispose();
      await restartedRepo.disposeStore();
    });
  });

  group('大小探测', () {
    test('支持 Range → 返回各分P总大小之和', () async {
      transport.responders = [
        (offset) async => FakeDownloadConnection(
              statusCode: 206,
              contentRangeStart: 0,
              contentRangeEnd: 99,
              contentRangeTotal: 1000,
            ),
        (offset) async => FakeDownloadConnection(
              statusCode: 206,
              contentRangeStart: 0,
              contentRangeEnd: 99,
              contentRangeTotal: 2000,
            ),
        (offset) async => FakeDownloadConnection(
              statusCode: 206,
              contentRangeStart: 0,
              contentRangeEnd: 99,
              contentRangeTotal: 3000,
            ),
      ];
      final size = await manager.probeVideoSize(request3Parts());
      expect(size, 6000);
    });

    test('服务器不支持 Range → 返回 Content-Length 之和', () async {
      transport.responders = [
        (offset) async =>
            FakeDownloadConnection(statusCode: 200, contentLength: 500),
        (offset) async =>
            FakeDownloadConnection(statusCode: 200, contentLength: 700),
        (offset) async =>
            FakeDownloadConnection(statusCode: 200, contentLength: 900),
      ];
      final size = await manager.probeVideoSize(request3Parts());
      expect(size, 2100);
    });

    test('全部探测失败 → null', () async {
      transport.failures = {1, 2, 3};
      final size = await manager.probeVideoSize(request3Parts());
      expect(size, isNull);
    });
  });
}

/// 等待任务满足自定义条件。
Future<DownloadTask> waitUntilTask(
  TaskWatcher watcher,
  String taskId,
  bool Function(DownloadTask task) condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final current = watcher.current(taskId);
    if (current != null && condition(current)) return current;
    if (DateTime.now().isAfter(deadline)) {
      fail('等待条件超时（task=$taskId）');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
