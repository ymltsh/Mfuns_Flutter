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

/// 断点续传专项测试（分P粒度）：初始下载、中途断网、恢复下载、
/// App 重启恢复、服务器支持 / 不支持 Range。
void main() {
  late TestStorage testStorage;
  late InMemoryDownloadTaskStore store;
  late FakeDownloadEnvironment environment;

  setUp(() async {
    testStorage = await TestStorage.create();
    store = InMemoryDownloadTaskStore();
    environment = FakeDownloadEnvironment();
  });

  tearDown(() async {
    await testStorage.cleanup();
  });

  Uint8List body(int size) =>
      Uint8List.fromList(List<int>.generate(size, (i) => i % 251));

  Future<DownloadManager> restartedManager(DownloadTransport transport) async {
    final repo = DownloadRepository(
      store: store,
      storage: testStorage.storage(),
    );
    final manager = DownloadManager(
      repository: repo,
      transport: transport,
      environment: environment,
      initialPolicy: const DownloadPolicy(wifiOnly: false, maxConcurrent: 2),
    )..autoRetryBase = const Duration(milliseconds: 5);
    await manager.initialize();
    return manager;
  }

  group('断点续传', () {
    test('初始下载：offset 0 发起，206 完成后文件完整', () async {
      final content = body(128 * 1024);
      final transport = FakeDownloadTransport()
        ..responders = [FakeDownloadTransport.partial(content)];
      final manager = await restartedManager(transport);
      final watcher = TaskWatcher(manager.watchTasks());

      final taskId = await manager.enqueue(makeRequest());
      await waitUntil(() => transport.requestedOffsets.isNotEmpty,
          description: '初始请求已发起');
      expect(transport.requestedOffsets.first, 0);

      final completed = await watcher.waitFor(taskId, DownloadStatus.completed);
      expect(await File(completed.parts.single.filePath).readAsBytes(), content);
      watcher.close();
      await manager.dispose();
    });

    test('中途断网 → 自动恢复续传，最终文件完整', () async {
      final content = body(128 * 1024);
      final half = content.length ~/ 2;
      var calls = 0;
      final transport = FakeDownloadTransport()
        ..responders = [
          (offset) async {
            calls++;
            if (calls == 1) {
              // 第一段返回半程字节后断网（连接失败）。
              return FakeDownloadConnection(
                statusCode: 206,
                contentRangeStart: 0,
                contentRangeEnd: half - 1,
                contentRangeTotal: content.length,
                contentLength: half,
                body: Stream.fromIterable([
                  Uint8List.sublistView(content, 0, half),
                ]),
              );
            }
            return FakeDownloadConnection(
              statusCode: 206,
              contentRangeStart: half,
              contentRangeEnd: content.length - 1,
              contentRangeTotal: content.length,
              contentLength: content.length - half,
              body: Stream.fromIterable([
                Uint8List.sublistView(content, half),
              ]),
            );
          },
        ];
      final manager = await restartedManager(transport);
      final watcher = TaskWatcher(manager.watchTasks());

      final taskId = await manager.enqueue(makeRequest());
      final completed = await watcher.waitFor(taskId, DownloadStatus.completed);
      expect(await File(completed.parts.single.filePath).readAsBytes(), content);
      // 第二次请求从断点发起。
      expect(transport.requestedOffsets, [0, half]);
      watcher.close();
      await manager.dispose();
    });

    test('服务器不支持 Range（返回 200）→ 从头重新下载', () async {
      final content = body(100 * 1024);
      const taskId = 'v1_1080p';
      final repo = DownloadRepository(
        store: store,
        storage: testStorage.storage(),
      );
      // 已有半程 .part（模拟此前下载了一半）。
      final seedTask = await repo.createTask(makeRequest());
      final part = File(seedTask.parts.single.tempFilePath);
      await part.create(recursive: true);
      await part.writeAsBytes(
          Uint8List.sublistView(content, 0, content.length ~/ 2));
      await repo.setPartStatus(
          seedTask, 1, DownloadStatus.downloading,
          // 模拟进行中状态。
          );
      await store.upsert((await repo.task(taskId))!.copyWith(
        status: DownloadStatus.downloading,
        downloadedBytes: content.length ~/ 2,
      ));

      final transport = FakeDownloadTransport()
        ..responders = [
          FakeDownloadTransport.partial(content, ignoreRange: true)
        ];
      final manager = await restartedManager(transport);
      final watcher = TaskWatcher(manager.watchTasks());

      final completed = await watcher.waitFor(taskId, DownloadStatus.completed);
      // 服务器忽略 Range → 结果仍是完整内容。
      expect(await File(completed.parts.single.filePath).readAsBytes(), content);
      expect(transport.requestedOffsets, [content.length ~/ 2]);
      watcher.close();
      await manager.dispose();
    });

    test('服务器 416（Range 不可满足）→ 从头重新下载', () async {
      final content = body(4096);
      const taskId = 'v1_1080p';
      final repo = DownloadRepository(
        store: store,
        storage: testStorage.storage(),
      );
      final seedTask = await repo.createTask(makeRequest());
      final part = File(seedTask.parts.single.tempFilePath);
      await part.create(recursive: true);
      await part.writeAsBytes(
          Uint8List.sublistView(content, 0, content.length ~/ 2));
      await store.upsert(seedTask.copyWith(
        status: DownloadStatus.downloading,
        parts: [
          seedTask.parts.single.copyWith(
            downloadedBytes: content.length ~/ 2,
            totalBytes: content.length,
          ),
        ],
      ));

      final transport = FakeDownloadTransport()
        ..responders = [
          (offset) async => FakeDownloadConnection(
                statusCode: 416,
                contentRangeTotal: content.length,
              ),
          FakeDownloadTransport.partial(content),
        ];
      final manager = await restartedManager(transport);
      final watcher = TaskWatcher(manager.watchTasks());

      final completed = await watcher.waitFor(taskId, DownloadStatus.completed);
      expect(await File(completed.parts.single.filePath).readAsBytes(), content);
      watcher.close();
      await manager.dispose();
    });

    test('App 重启后从 .part 断点继续（完整流程）', () async {
      final content = body(256 * 1024);
      const taskId = 'v1_1080p';

      // 第一次运行：下载到一半“被强杀”。
      final firstRepo = DownloadRepository(
        store: store,
        storage: testStorage.storage(),
      );
      final task = await firstRepo.createTask(makeRequest());
      await firstRepo.setTaskStatus(task, DownloadStatus.downloading);
      final part = File(task.parts.single.tempFilePath);
      await part.create(recursive: true);
      await part.writeAsBytes(
          Uint8List.sublistView(content, 0, content.length ~/ 2));

      // 再次启动：从 50% 位置继续，最终完整。
      final transport = FakeDownloadTransport()
        ..responders = [FakeDownloadTransport.partial(content)];
      final secondManager = await restartedManager(transport);
      final watcher = TaskWatcher(secondManager.watchTasks());

      final completed =
          await watcher.waitFor(taskId, DownloadStatus.completed);
      expect(await File(completed.parts.single.filePath).readAsBytes(), content);
      expect(transport.requestedOffsets.first, content.length ~/ 2);
      watcher.close();
      await secondManager.dispose();
    });

    test('重启后多个分P依次从各自断点续传', () async {
      final content = body(64 * 1024);
      const taskId = 'v1_1080p';

      final firstRepo = DownloadRepository(
        store: store,
        storage: testStorage.storage(),
      );
      final task = await firstRepo.createTask(makeRequest(parts: [
        const DownloadPartSource(part: 1, url: 'https://cdn.example.com/p1.mp4'),
        const DownloadPartSource(part: 2, url: 'https://cdn.example.com/p2.mp4'),
      ]));
      await firstRepo.setTaskStatus(task, DownloadStatus.downloading);
      // P1 下载了一半，P2 未开始。
      final p1Part = File(task.parts[0].tempFilePath);
      await p1Part.create(recursive: true);
      await p1Part.writeAsBytes(
          Uint8List.sublistView(content, 0, content.length ~/ 2));

      final transport = FakeDownloadTransport()
        ..responders = [FakeDownloadTransport.partial(content)];
      final secondManager = await restartedManager(transport);
      final watcher = TaskWatcher(secondManager.watchTasks());

      final completed =
          await watcher.waitFor(taskId, DownloadStatus.completed);
      expect(completed.completedPartCount, 2);
      expect(await File(completed.parts[0].filePath).readAsBytes(), content);
      expect(await File(completed.parts[1].filePath).readAsBytes(), content);
      // P1 从断点续传，P2 从头开始。
      expect(transport.requestedOffsets,
          [content.length ~/ 2, 0]);
      watcher.close();
      await secondManager.dispose();
    });
  });

  group('真实 HttpClient 传输（本地 HTTP 服务器）', () {
    test('发送 Range 头并解析 Content-Range', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      const totalBytes = 1024;
      late int requestedRangeStart;
      server.listen((request) async {
        final range = request.headers.value('range');
        if (range != null && range.startsWith('bytes=')) {
          requestedRangeStart = int.parse(range.substring(6).split('-').first);
        }
        request.response.statusCode = 206;
        request.response.headers.set(
            'Content-Range', 'bytes=$requestedRangeStart-1023/$totalBytes');
        request.response.headers.set(HttpHeaders.contentLengthHeader,
            totalBytes - requestedRangeStart);
        final body = Uint8List(totalBytes - requestedRangeStart);
        request.response.add(body);
        await request.response.close();
      });

      final transport = HttpClientDownloadTransport();
      final uri = Uri.parse('http://127.0.0.1:${server.port}/v.mp4');
      final connection = await transport.connect(uri, headers: {}, offset: 400);
      expect(connection.statusCode, 206);
      expect(requestedRangeStart, 400);
      expect(connection.contentRangeStart, 400);
      expect(connection.contentRangeEnd, 1023);
      expect(connection.contentRangeTotal, totalBytes);
      expect(connection.contentLength, 624);

      var received = 0;
      await for (final chunk in connection.body) {
        received += chunk.length;
      }
      expect(received, 624);
      connection.abort();
      await server.close(force: true);
    });

    test('offset=0 时不携带 Range 头', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      String? seenRange = 'unset';
      server.listen((request) async {
        seenRange = request.headers.value('range');
        request.response.statusCode = 200;
        request.response.headers.set(HttpHeaders.contentLengthHeader, 10);
        request.response.add(List.filled(10, 1));
        await request.response.close();
      });

      final transport = HttpClientDownloadTransport();
      final connection = await transport.connect(
        Uri.parse('http://127.0.0.1:${server.port}/v.mp4'),
        headers: {},
        offset: 0,
      );
      expect(seenRange, isNull);
      expect(connection.statusCode, 200);
      await connection.body.drain<void>();
      connection.abort();
      await server.close(force: true);
    });
  });
}
