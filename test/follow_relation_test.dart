import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/features/home/home_repository.dart';

void main() {
  test('maps profile follow relations to user-facing labels', () {
    expect(followRelationLabel(FollowRelation.none), '关注');
    expect(followRelationLabel(FollowRelation.following), '已关注');
    expect(followRelationLabel(FollowRelation.mutual), '已互关');
  });
}
