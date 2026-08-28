import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/core/download/download_status.dart';
import 'package:mfuns_flutter/core/download/download_task.dart';

import 'download_test_utils.dart';

void main() {
  group('DownloadTask.taskId 生成', () {
    test('videoId + quality 精确区分（任务 = 视频）', () {
      expect(
        DownloadTask.buildTaskId(videoId: 42, quality: '1080p'),
        DownloadTask.buildTaskId(videoId: 42, quality: '1080p'),
      );
      expect(
        DownloadTask.buildTaskId(videoId: 42, quality: '1080p'),
        isNot(DownloadTask.buildTaskId(videoId: 42, quality: '720p')),
      );
      expect(
        DownloadTask.buildTaskId(videoId: 42, quality: '1080p'),
        isNot(DownloadTask.buildTaskId(videoId: 43, quality: '1080p')),
      );
    });

    test('清晰度标识归一化', () {
      expect(DownloadTask.normalizeQualityKey('1080P'), '1080p');
      expect(DownloadTask.normalizeQualityKey(' 1080 P '), '1080p');
      expect(DownloadTask.normalizeQualityKey('4K'), '4k');
      expect(DownloadTask.normalizeQualityKey('高清 720p'), '720p');
      expect(DownloadTask.normalizeQualityKey('???'), 'default');
    });

    test('任务 ID 格式稳定', () {
      expect(
        DownloadTask.buildTaskId(videoId: 1, quality: '1080p'),
        'v1_1080p',
      );
    });
  });

  group('DownloadTask 序列化', () {
    test('toMap / fromMap 往返一致（含分P明细）', () {
      final task = makeTask(
        videoId: 7,
        quality: '720p',
        qualityLabel: '720P',
        title: '标题',
        downloadedBytes: 100,
        totalBytes: 200,
        status: DownloadStatus.downloading,
        errorMessage: 'x',
        parts: [
          makePart(part: 1,
              downloadedBytes: 100, totalBytes: 200,
              status: DownloadStatus.downloading),
          makePart(part: 2, status: DownloadStatus.pending),
        ],
      );
      final restored = DownloadTask.fromMap(task.toMap());
      expect(restored.taskId, task.taskId);
      expect(restored.videoId, task.videoId);
      expect(restored.title, task.title);
      expect(restored.cover, task.cover);
      expect(restored.quality, task.quality);
      expect(restored.qualityLabel, task.qualityLabel);
      expect(restored.downloadedBytes, task.downloadedBytes);
      expect(restored.totalBytes, task.totalBytes);
      expect(restored.status, task.status);
      expect(restored.errorMessage, task.errorMessage);
      expect(restored.createdAt, task.createdAt);
      expect(restored.updatedAt, task.updatedAt);
      expect(restored.parts, hasLength(2));
      expect(restored.parts[0].part, 1);
      expect(restored.parts[0].sourceUrl, task.parts[0].sourceUrl);
      expect(restored.parts[0].filePath, task.parts[0].filePath);
      expect(restored.parts[0].tempFilePath, task.parts[0].tempFilePath);
      expect(restored.parts[0].downloadedBytes, 100);
      expect(restored.parts[0].totalBytes, 200);
      expect(restored.parts[0].status, DownloadStatus.downloading);
      expect(restored.parts[1].part, 2);
    });

    test('toJson / fromJson 往返一致', () {
      final task = makeTask(
        videoId: 9,
        status: DownloadStatus.failed,
        errorMessage: '网络错误',
        parts: [makePart(part: 1, status: DownloadStatus.failed)],
      );
      final restored = DownloadTask.fromJson(task.toJson());
      expect(restored.toJson(), task.toJson());
    });

    test('fromMap 对缺失/异常字段有兜底', () {
      final task = DownloadTask.fromMap(const {
        'task_id': 'v1_1080p',
        'video_id': 1,
        'title': 't',
        'quality': '1080p',
        'status': 'no_such_status',
        'created_at': 'not-a-date',
        'updated_at': 'not-a-date',
      });
      expect(task.status, DownloadStatus.pending);
      expect(task.downloadedBytes, 0);
      expect(task.parts, isEmpty);
    });

    test('parts_json 非法时回退为空列表', () {
      final task = DownloadTask.fromMap({
        'task_id': 'v1_1080p',
        'video_id': 1,
        'title': 't',
        'quality': '1080p',
        'status': 'pending',
        'parts_json': '{invalid json',
      });
      expect(task.parts, isEmpty);
    });

    test('状态存储名往返', () {
      for (final status in DownloadStatus.values) {
        expect(DownloadStatus.fromStorageName(status.storageName), status);
      }
    });
  });

  group('DownloadTask 状态与进度', () {
    test('isActive / isTerminal 分组', () {
      expect(DownloadStatus.pending.isActive, isTrue);
      expect(DownloadStatus.downloading.isActive, isTrue);
      expect(DownloadStatus.paused.isActive, isFalse);
      expect(DownloadStatus.completed.isTerminal, isTrue);
      expect(DownloadStatus.failed.isTerminal, isTrue);
      expect(DownloadStatus.canceled.isTerminal, isTrue);
      expect(DownloadStatus.pending.isTerminal, isFalse);
    });

    test('copyWith 状态转换保留关键字段', () {
      final task = makeTask();
      final downloading =
          task.copyWith(status: DownloadStatus.downloading, downloadedBytes: 50);
      expect(downloading.status, DownloadStatus.downloading);
      expect(downloading.downloadedBytes, 50);
      expect(downloading.taskId, task.taskId);
      expect(downloading.videoId, task.videoId);

      final completed = downloading.copyWith(
        status: DownloadStatus.completed,
        downloadedBytes: 100,
      );
      expect(completed.status, DownloadStatus.completed);
      expect(completed.downloadedBytes, 100);
    });

    test('progress 计算与钳制', () {
      expect(makeTask(downloadedBytes: 50, totalBytes: 200).progress, 0.25);
      expect(makeTask(downloadedBytes: 300, totalBytes: 200).progress, 1.0);
      expect(makeTask(downloadedBytes: 0, totalBytes: 0).progress, 0.0);
    });

    test('isPlayable 仅在 completed 为真', () {
      expect(makeTask(status: DownloadStatus.completed).isPlayable, isTrue);
      expect(makeTask(status: DownloadStatus.downloading).isPlayable, isFalse);
      expect(makeTask(status: DownloadStatus.failed).isPlayable, isFalse);
    });

    test('分P统计与本地文件解析', () {
      final task = makeTask(
        status: DownloadStatus.downloading,
        parts: [
          makePart(part: 1, status: DownloadStatus.completed,
              filePath: '/x/p1.mp4'),
          makePart(part: 2, status: DownloadStatus.pending),
        ],
      );
      expect(task.totalPartCount, 2);
      expect(task.completedPartCount, 1);
      expect(task.isPartPlayable(1), isTrue);
      expect(task.isPartPlayable(2), isFalse);
      expect(task.localFileForPart(1), '/x/p1.mp4');
      expect(task.localFileForPart(2), isNull);
    });
  });

  group('DownloadPartTask', () {
    test('序列化往返', () {
      final part = makePart(
        part: 3,
        sourceUrl: 'https://cdn.example.com/x.mp4',
        filePath: '/x/p3.mp4',
        tempFilePath: '/x/p3.mp4.part',
        downloadedBytes: 10,
        totalBytes: 20,
        status: DownloadStatus.paused,
        errorMessage: 'e',
      );
      final restored = DownloadPartTask.fromMap(part.toMap());
      expect(restored.part, 3);
      expect(restored.sourceUrl, part.sourceUrl);
      expect(restored.filePath, part.filePath);
      expect(restored.tempFilePath, part.tempFilePath);
      expect(restored.downloadedBytes, 10);
      expect(restored.totalBytes, 20);
      expect(restored.status, DownloadStatus.paused);
      expect(restored.errorMessage, 'e');
    });

    test('isPlayable 与进度', () {
      expect(makePart(status: DownloadStatus.completed).isPlayable, isTrue);
      expect(makePart(status: DownloadStatus.pending).isPlayable, isFalse);
      expect(makePart(downloadedBytes: 50, totalBytes: 200).progress, 0.25);
    });
  });
}
