import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/app/app_controller.dart';
import 'package:mfuns_flutter/app/mfuns_app.dart';
import 'package:mfuns_flutter/core/widgets/network_retry_state.dart';
import 'package:mfuns_flutter/features/home/home_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RetryController extends AppController {
  int refreshCount = 0;
  String? error;
  List<ContentPreview> items = [];

  @override
  Future<void> initialize() async {}
  @override
  Future<void> loadFeeds() async {}
  @override
  String? get homeError => error;
  @override
  List<ContentPreview> get recommendations => items;
  @override
  Future<int> refreshHome() async {
    refreshCount++;
    error = null;
    items = [
      ContentPreview.fromJson({'id': 1, 'title': '刷新后的推荐'}),
    ];
    notifyListeners();
    return 1;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final size in [
    const Size(360, 720),
    const Size(720, 280),
    const Size(1280, 720),
    const Size(240, 180),
  ]) {
    testWidgets('提示图和按钮适应视口 $size 及大字体', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(body: NetworkRetryState(onRefresh: () async {})),
        ),
      );
      await tester.pumpAndSettle();
      final image = find.byType(Image);
      final imageSize = tester.getSize(image);
      expect(imageSize.width, lessThanOrEqualTo(55));
      expect(imageSize.height, lessThanOrEqualTo(55));
      final button = find.widgetWithText(FilledButton, '刷新');
      expect(
        tester.getTopLeft(image).dy,
        lessThan(tester.getTopLeft(button).dy),
      );
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      expect(button.hitTestable(), findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('刷新中禁用按钮防止重复请求', (tester) async {
    var count = 0;
    final pending = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NetworkRetryState(
            onRefresh: () {
              count++;
              return pending.future;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('刷新'));
    await tester.pump();
    expect(find.text('刷新中…'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(count, 1);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('刷新'), findsOneWidget);
  });

  testWidgets('刷新异常后仍可再次刷新', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NetworkRetryState(
            onRefresh: () async => throw StateError('模拟请求失败'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('刷新'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  for (final hasError in [false, true]) {
    testWidgets('推荐为空（请求异常：$hasError）显示提示图，刷新成功显示内容', (tester) async {
      final controller = _RetryController()..error = hasError ? '无法连接' : null;
      await tester.pumpWidget(MfunsApp(controller: controller));
      await tester.pumpAndSettle();
      expect(find.text('似乎有问题，请尝试刷新'), findsOneWidget);
      expect(find.text('暂时没有推荐内容'), findsNothing);
      final image = tester.widget<Image>(
        find.descendant(
          of: find.byType(NetworkRetryState),
          matching: find.byType(Image),
        ),
      );
      expect((image.image as AssetImage).assetName, 'assets/network_retry.png');
      await tester.tap(find.text('刷新'));
      await tester.pumpAndSettle();
      expect(controller.refreshCount, 1);
      expect(find.text('刷新后的推荐'), findsOneWidget);
      expect(find.byType(NetworkRetryState), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
