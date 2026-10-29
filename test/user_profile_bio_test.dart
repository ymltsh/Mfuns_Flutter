import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/app/app_controller.dart';
import 'package:mfuns_flutter/core/widgets/content_link_handler.dart';
import 'package:mfuns_flutter/features/home/home_repository.dart';
import 'package:mfuns_flutter/features/user/user_profile_page.dart';

class _ProfileController extends AppController {
  _ProfileController(this.bio);

  final String bio;

  @override
  Future<UserProfile> userProfile(int userId) async => UserProfile(
    id: userId,
    name: '测试用户',
    avatar: '',
    avatarFrame: '',
    banner: '',
    bio: bio,
    gender: '',
    level: null,
    exp: null,
    fans: 0,
    follows: 0,
    totalLikes: 0,
  );

  @override
  Future<List<TimelineFeed>> userFeeds({
    required int userId,
    int startId = -1,
  }) async => const [];

  @override
  Future<List<ContentPreview>> userArticles({
    required int userId,
    int cursor = 0,
  }) async => const [];

  @override
  Future<List<ContentPreview>> userVideos({
    required int userId,
    int cursor = 0,
  }) async => const [];
}

void main() {
  testWidgets('article member link opens the in-app user profile', (
    tester,
  ) async {
    final controller = _ProfileController('简介');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openContentLink(
                context,
                controller,
                'https://m.mfuns.net/member/83597',
              ),
              child: const Text('乙女椿'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('乙女椿'));
    await tester.pumpAndSettle();
    expect(find.byType(UserProfilePage), findsOneWidget);
    expect(find.text('MF 83597'), findsOneWidget);
  });

  testWidgets('user profile shows the full long bio', (tester) async {
    final bio = List.filled(12, '这是一段需要完整展示的用户简介。').join();
    final controller = _ProfileController(bio);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: UserProfilePage(controller: controller, userId: 83597)),
    );
    await tester.pumpAndSettle();

    final text = tester.widget<Text>(find.text(bio));
    expect(text.maxLines, isNull);
    expect(tester.getSize(find.text(bio)).height, greaterThan(40));
  });
}
