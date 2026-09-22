import 'package:flutter/material.dart';

import '../../app/app_controller.dart';

/// 确认并提交拉黑状态。返回 `true` 表示操作成功，取消或失败返回 `false`。
Future<bool> confirmSetUserBlocked(
  BuildContext context, {
  required AppController controller,
  required int userId,
  required String userName,
  required bool blocked,
}) async {
  final action = blocked ? '拉黑' : '解除拉黑';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('$action用户'),
      content: Text(blocked
          ? '确定要拉黑“$userName”吗？拉黑后可在设置的黑名单中解除。'
          : '确定要将“$userName”移出黑名单吗？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(action),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  try {
    await controller.setBlocked(userId: userId, blocked: blocked);
    if (!context.mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(blocked ? '已拉黑 $userName' : '已解除拉黑 $userName')),
    );
    return true;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$action失败：$error')));
    }
    return false;
  }
}
