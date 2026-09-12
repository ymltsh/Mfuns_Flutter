import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/app/app_controller.dart';
import 'package:mfuns_flutter/features/auth/auth_repository.dart';
import 'package:mfuns_flutter/features/home/home_repository.dart';
import 'package:mfuns_flutter/features/settings/settings_page.dart';

class _ProfileEditController extends AppController {
  final List<String> updatedNames = [];
  final List<String> updatedBios = [];
  final List<int> updatedGenders = [];

  @override
  UserSession? get session => const UserSession(
        accessToken: 'test-token',
        userId: 7,
        displayName: '原昵称',
        avatar: '',
      );

  @override
  Future<UserProfile> userProfile(int userId) async => const UserProfile(
        id: 7,
        name: '原昵称',
        avatar: '',
        avatarFrame: '',
        banner: '',
        bio: '原简介',
        gender: 'female',
        level: null,
        exp: null,
        fans: 0,
        follows: 0,
        totalLikes: 0,
      );

  @override
  Future<void> updateUserName(String name) async => updatedNames.add(name);

  @override
  Future<void> updateUserBio(String bio) async => updatedBios.add(bio);

  @override
  Future<void> updateUserGender(int gender) async => updatedGenders.add(gender);

  @override
  Future<void> refreshSession() async {}
}

void main() {
  testWidgets('只修改简介时不会重复提交昵称和性别', (tester) async {
    final controller = _ProfileEditController();
    await tester.pumpWidget(
      MaterialApp(home: ProfileEditPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(1), '新简介');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(controller.updatedBios, ['新简介']);
    expect(controller.updatedNames, isEmpty);
    expect(controller.updatedGenders, isEmpty);
  });
}
