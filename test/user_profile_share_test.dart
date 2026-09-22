import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/features/user/user_profile_page.dart';

void main() {
  test('builds the expected user profile share text', () {
    expect(
      userProfileShareText(name: '微风与少年', userId: 17627),
      '【微风与少年的个人空间 - Mfuns 发射(。゜ω゜)ノ"!】\n'
      'https://mfuns.net/member/17627',
    );
  });
}
