/// 下载任务状态机：
///
/// ```text
/// pending ──→ downloading ──→ completed
///    │            │
///    ├──→ paused ←┘
///    └──→ canceled ──→ (retry) pending
/// downloading / paused ──→ failed ──→ (retry) pending
/// ```
///
/// `pending` 表示任务已创建并排队（或 App 重启后等待恢复），
/// `downloading` 表示正在拉取数据，两者都可进入暂停/取消。
enum DownloadStatus {
  pending('等待中'),
  downloading('下载中'),
  paused('已暂停'),
  completed('已下载'),
  failed('下载失败'),
  canceled('已取消');

  const DownloadStatus(this.label);

  /// 界面展示文案。
  final String label;

  /// 是否仍处于“未完成”状态（可继续/重试）。
  bool get isActive =>
      this == DownloadStatus.pending || this == DownloadStatus.downloading;

  /// 是否已经结束（不再占用下载队列）。
  bool get isTerminal =>
      this == DownloadStatus.completed ||
      this == DownloadStatus.failed ||
      this == DownloadStatus.canceled;

  /// 数据库持久化名称。
  String get storageName => name;

  static DownloadStatus fromStorageName(String? name) {
    for (final status in DownloadStatus.values) {
      if (status.name == name) return status;
    }
    return DownloadStatus.pending;
  }
}
