import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/core/download/download_repository.dart';
import 'package:mfuns_flutter/core/download/download_status.dart';
import 'package:mfuns_flutter/core/download/download_task.dart';

import 'download_test_utils.dart';

void main() {
  late TestStorage testStorage;
  late DownloadRepository repository;
  late InMemoryDownloadTaskStore store;

  setUp(() async {
    testStorage = await TestStorage.create();
    store = InMemoryDownloadTaskStore();
    repository = DownloadRepository(
      store: store,
      storage: testStorage.storage(),
    );
    await repository.initialize();
  });

  tearDown(() async {
    await repository.disposeStore();
    await testStorage.cleanup();
  });

  group('创建任务', () {
    test('创建新任务（视频级）并写入存储', () async {
      final task = await repository.createTask(makeRequest(parts: [
        const DownloadPartSource(part: 1, url: 'https://cdn.example.com/p1.mp4'),
        const DownloadPartSource(part: 2, url: 'https://cdn.example.com/p2.mp4'),
      ]));
      expect(task.taskId, 'v1_1080p');
      expect(task.status, DownloadStatus.pending);
      expect(task.parts, hasLength(2));
      expect(task.parts.first.filePath, endsWith('p1_1080p.mp4'));
      expect(task.parts.first.tempFilePath, endsWith('p1_1080p.mp4.part'));
      expect(task.parts.last.filePath, endsWith('p2_1080p.mp4'));
      expect(await store.get(task.taskId), isNotNull);
    });

    test('相同 videoId+quality 复用同一任务（新分P合并追加）', () async {
      final first = await repository.createTask(makeRequest(parts: [
        const DownloadPartSource(part: 1, url: 'https://cdn.example.com/p1.mp4'),
        const DownloadPartSource(part: 2, url: 'https://cdn.example.com/p2.mp4'),
      ]));
      final second = await repository.createTask(makeRequest(parts: [
        const DownloadPartSource(part: 3, url: 'https://cdn.example.com/p3.mp4'),
      ]));
      expect(second.taskId, first.taskId);
      // 同一任务，分P合并：P1/P2（原有）+ P3（追加）。
      expect(repository.tasks, hasLength(1));
      expect(second.parts.map((p) => p.part), [1, 2, 3]);
    });

    test('不同清晰度创建独立任务', () async {
      await repository.createTask(makeRequest(quality: '1080p'));
      await repository.createTask(makeRequest(quality: '720p'));
      expect(repository.tasks, hasLength(2));
    });

    test('失败任务重新创建时重置并返回', () async {
      final task = await repository.createTask(makeRequest());
      await repository.setTaskStatus(task, DownloadStatus.failed,
          errorMessage: '403');
      final again = await repository.createTask(makeRequest());
      expect(again.status, DownloadStatus.pending);
      expect(again.errorMessage, '');
    });

    test('已完成任务不会被重复创建', () async {
      final task = await repository.createTask(makeRequest());
      await File(task.parts.single.tempFilePath).create(recursive: true);
      await repository.completePart(task, 1);
      final again = await repository.createTask(makeRequest());
      expect(again.status, DownloadStatus.completed);
    });

    test('已存在任务时追加新分P（补下）', () async {
      final task = await repository.createTask(makeRequest(parts: [
        const DownloadPartSource(part: 1, url: 'https://cdn.example.com/p1.mp4'),
        const DownloadPartSource(part: 2, url: 'https://cdn.example.com/p2.mp4'),
      ]));
      await File(task.parts[0].tempFilePath).create(recursive: true);
      await File(task.parts[0].tempFilePath).writeAsBytes(List.filled(5, 1));
      await File(task.parts[1].tempFilePath).create(recursive: true);
      await File(task.parts[1].tempFilePath).writeAsBytes(List.filled(5, 1));
      final p1 = await repository.completePart(task, 1);
      final p2 = await repository.completePart(p1!, 2);
      expect(p2!.status, DownloadStatus.completed);

      // 补下 P3：任务合并 P3 并回到 pending，P1/P2 保持 completed。
      final merged = await repository.createTask(makeRequest(parts: [
        const DownloadPartSource(part: 1, url: 'https://cdn.example.com/p1.mp4'),
        const DownloadPartSource(part: 2, url: 'https://cdn.example.com/p2.mp4'),
        const DownloadPartSource(part: 3, url: 'https://cdn.example.com/p3.mp4'),
      ]));
      expect(merged.status, DownloadStatus.pending);
      expect(merged.parts, hasLength(3));
      expect(merged.parts[0].status, DownloadStatus.completed);
      expect(merged.parts[1].status, DownloadStatus.completed);
      expect(merged.parts[2].status, DownloadStatus.pending);
      expect(merged.parts[2].filePath, endsWith('p3_1080p.mp4'));
    });

    test('追加分P不重复添加已存在分P', () async {
      final task = await repository.createTask(makeRequest(parts: [
        const DownloadPartSource(part: 1, url: 'https://cdn.example.com/p1.mp4'),
      ]));
      await File(task.parts.single.tempFilePath).create(recursive: true);
      await File(task.parts.single.tempFilePath).writeAsBytes(List.filled(5, 1));
      await repository.completePart(task, 1);
      final merged = await repository.createTask(makeRequest(parts: [
        const DownloadPartSource(part: 1, url: 'https://cdn.example.com/p1.mp4'),
        const DownloadPartSource(part: 2, url: 'https://cdn.example.com/p2.mp4'),
      ]));
      expect(merged.parts, hasLength(2));
      expect(merged.parts.where((p) => p.part == 1), hasLength(1));
    });
  });

  group('更新与查询', () {
    test('更新分P进度并汇总到任务', () async {
      final task = await repository.createTask(makeRequest(parts: [
        const DownloadPartSource(part: 1, url: 'https://cdn.example.com/p1.mp4'),
        const DownloadPartSource(part: 2, url: 'https://cdn.example.com/p2.mp4'),
      ]));
      await repository.updatePartProgress(task, 1,
          downloadedBytes: 100, totalBytes: 1000, speed: 500.0);
      final stored = await store.get(task.taskId);
      expect(stored!.parts.first.downloadedBytes, 100);
      expect(stored.parts.first.totalBytes, 1000);
      expect(stored.downloadedBytes, 100);
      expect(stored.totalBytes, 1000);
    });

    test('findTask 精确匹配（videoId + quality）', () async {
      await repository.createTask(makeRequest(videoId: 5, quality: '4k'));
      expect(await repository.findTask(videoId: 5, quality: '4k'), isNotNull);
      expect(await repository.findTask(videoId: 5, quality: '1080p'), isNull);
      expect(await repository.findTask(videoId: 6, quality: '4k'), isNull);
    });

    test('watchTasks 流收到更新', () async {
      final seen = <List<DownloadTask>>[];
      final sub = repository.watchTasks().listen(seen.add);
      await repository.createTask(makeRequest());
      await Future<void>.delayed(Duration.zero);
      expect(seen, isNotEmpty);
      expect(seen.last.map((t) => t.taskId), contains('v1_1080p'));
      await sub.cancel();
    });
  });

  group('删除任务', () {
    test('删除记录与本地文件', () async {
      final task = await repository.createTask(makeRequest());
      final part = task.parts.single;
      await File(part.tempFilePath).create(recursive: true);
      await File(part.tempFilePath).writeAsBytes(List.filled(5, 1));
      await repository.completePart(task, 1);
      final finalFile = File(part.filePath);
      expect(await finalFile.exists(), isTrue);

      await repository.deleteTask(task.taskId);
      expect(await store.get(task.taskId), isNull);
      expect(await finalFile.exists(), isFalse);
      expect(await File(part.tempFilePath).exists(), isFalse);
    });
  });

  group('启动恢复', () {
    test('completed 且文件完好 → 保持 completed', () async {
      var task = await repository.createTask(makeRequest(parts: [
        const DownloadPartSource(part: 1, url: 'https://cdn.example.com/p1.mp4'),
        const DownloadPartSource(part: 2, url: 'https://cdn.example.com/p2.mp4'),
      ]));
      for (final part in task.parts) {
        await File(part.tempFilePath).create(recursive: true);
        await File(part.tempFilePath).writeAsBytes(List.filled(5, 1));
      }
      final p1 = await repository.completePart(task, 1);
      final p2 = await repository.completePart(p1!, 2);
      expect(p2!.status, DownloadStatus.completed);

      final restarted = DownloadRepository(
        store: store,
        storage: testStorage.storage(),
      );
      await restarted.initialize();
      expect(restarted.tasks.single.status, DownloadStatus.completed);
      await restarted.disposeStore();
    });

    test('completed 但部分分P文件缺失 → 该分P补下，任务回 pending', () async {
      var task = await repository.createTask(makeRequest(parts: [
        const DownloadPartSource(part: 1, url: 'https://cdn.example.com/p1.mp4'),
        const DownloadPartSource(part: 2, url: 'https://cdn.example.com/p2.mp4'),
      ]));
      for (final part in task.parts) {
        await File(part.tempFilePath).create(recursive: true);
        await File(part.tempFilePath).writeAsBytes(List.filled(5, 1));
      }
      final p1 = await repository.completePart(task, 1);
      final p2 = await repository.completePart(p1!, 2);
      expect(p2!.status, DownloadStatus.completed);
      // 删除 P2 正式文件模拟文件丢失。
      await File(p2.parts[1].filePath).delete();

      final restarted = DownloadRepository(
        store: store,
        storage: testStorage.storage(),
      );
      await restarted.initialize();
      final restored = restarted.tasks.single;
      expect(restored.status, DownloadStatus.pending);
      expect(restored.parts[0].status, DownloadStatus.completed);
      expect(restored.parts[1].status, DownloadStatus.pending);
      await restarted.disposeStore();
    });

    test('completed 但全部文件丢失 → 清理无效记录', () async {
      var task = await repository.createTask(makeRequest(parts: [
        const DownloadPartSource(part: 1, url: 'https://cdn.example.com/p1.mp4'),
        const DownloadPartSource(part: 2, url: 'https://cdn.example.com/p2.mp4'),
      ]));
      for (final part in task.parts) {
        await File(part.tempFilePath).create(recursive: true);
        await File(part.tempFilePath).writeAsBytes(List.filled(5, 1));
      }
      final p1 = await repository.completePart(task, 1);
      final p2 = await repository.completePart(p1!, 2);
      await File(p2!.parts[0].filePath).delete();
      await File(p2.parts[1].filePath).delete();

      final restarted = DownloadRepository(
        store: store,
        storage: testStorage.storage(),
      );
      await restarted.initialize();
      expect(restarted.tasks, isEmpty);
      await restarted.disposeStore();
    });

    test('downloading + 存在 .part → 回填字节并回到 pending', () async {
      final task = await repository.createTask(makeRequest());
      await repository.setTaskStatus(task, DownloadStatus.downloading);
      final part = File(task.parts.single.tempFilePath);
      await part.create(recursive: true);
      await part.writeAsBytes(List.filled(500, 1));

      final restarted = DownloadRepository(
        store: store,
        storage: testStorage.storage(),
      );
      await restarted.initialize();
      final restored = restarted.tasks.single;
      expect(restored.status, DownloadStatus.pending);
      expect(restored.parts.single.downloadedBytes, 500);
      await restarted.disposeStore();
    });

    test('downloading + 无 .part → 归零后回到 pending', () async {
      final task = await repository.createTask(makeRequest());
      await repository.setTaskStatus(task, DownloadStatus.downloading);

      final restarted = DownloadRepository(
        store: store,
        storage: testStorage.storage(),
      );
      await restarted.initialize();
      final restored = restarted.tasks.single;
      expect(restored.status, DownloadStatus.pending);
      expect(restored.parts.single.downloadedBytes, 0);
      await restarted.disposeStore();
    });

    test('paused / failed / canceled 保持原状', () async {
      final paused = await repository.createTask(makeRequest(quality: '720p'));
      await repository.setTaskStatus(paused, DownloadStatus.paused);
      final failed = await repository.createTask(makeRequest(quality: '4k'));
      await repository.setTaskStatus(failed, DownloadStatus.failed,
          errorMessage: 'err');

      final restarted = DownloadRepository(
        store: store,
        storage: testStorage.storage(),
      );
      await restarted.initialize();
      final byId = {for (final t in restarted.tasks) t.taskId: t};
      expect(byId[paused.taskId]!.status, DownloadStatus.paused);
      expect(byId[failed.taskId]!.status, DownloadStatus.failed);
      expect(byId[failed.taskId]!.errorMessage, 'err');
      await restarted.disposeStore();
    });

    test('孤儿文件被清理', () async {
      final task = await repository.createTask(makeRequest());
      await File(task.parts.single.tempFilePath).create(recursive: true);
      await File(task.parts.single.tempFilePath)
          .writeAsBytes(List.filled(10, 1));
      // 手动创建一个不属于任何任务的孤儿文件。
      final orphan = File(
          '${testStorage.root.path}${Platform.pathSeparator}9'
          '${Platform.pathSeparator}ghost.mp4');
      await orphan.create(recursive: true);

      final restarted = DownloadRepository(
        store: store,
        storage: testStorage.storage(),
      );
      await restarted.initialize();
      expect(await orphan.exists(), isFalse);
      expect(await File(task.parts.single.tempFilePath).exists(), isTrue);
      await restarted.disposeStore();
    });
  });

  group('localFileFor', () {
    test('completed 分P且校验通过 → 返回正式文件路径', () async {
      final task = await repository.createTask(makeRequest());
      await File(task.parts.single.tempFilePath).create(recursive: true);
      await File(task.parts.single.tempFilePath)
          .writeAsBytes(List.filled(5, 1));
      await repository.completePart(task, 1);
      final path = await repository.localFileFor(
        videoId: 1,
        part: 1,
        quality: '1080p',
      );
      expect(path, task.parts.single.filePath);
    });

    test('未完成/不存在 → null', () async {
      expect(
        await repository.localFileFor(videoId: 1, part: 1, quality: '1080p'),
        isNull,
      );
      await repository.createTask(makeRequest());
      expect(
        await repository.localFileFor(videoId: 1, part: 1, quality: '1080p'),
        isNull,
      );
    });

    test('部分分P完成时只返回已完成分P的文件', () async {
      final task = await repository.createTask(makeRequest(parts: [
        const DownloadPartSource(part: 1, url: 'https://cdn.example.com/p1.mp4'),
        const DownloadPartSource(part: 2, url: 'https://cdn.example.com/p2.mp4'),
      ]));
      await File(task.parts[0].tempFilePath).create(recursive: true);
      await File(task.parts[0].tempFilePath).writeAsBytes(List.filled(5, 1));
      final updated = await repository.completePart(task, 1);
      expect(updated!.status, DownloadStatus.pending);

      final p1 = await repository.localFileFor(
          videoId: 1, part: 1, quality: '1080p');
      final p2 = await repository.localFileFor(
          videoId: 1, part: 2, quality: '1080p');
      expect(p1, updated.parts[0].filePath);
      expect(p2, isNull);
    });
  });
}
