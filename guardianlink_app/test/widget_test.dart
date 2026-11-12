import 'package:flutter_test/flutter_test.dart';

import 'package:guardianlink_app/models/task_model.dart';
import 'package:guardianlink_app/models/user_model.dart';

void main() {
  test('User.fromJson parses backend user', () {
    final user = User.fromJson({
      'id': 'u1',
      'email': 'kid@example.com',
      'full_name': 'Kid',
      'role': 'child',
      'family_id': 'f1',
      'focus_coins': 30,
      'stickers': ['🌟'],
    });
    expect(user.isChild, isTrue);
    expect(user.focusCoins, 30);
    expect(user.stickers, ['🌟']);
  });

  test('Task.fromJson parses UTC timestamps and verified status', () {
    final task = Task.fromJson({
      'id': 't1',
      'title': 'Homework',
      'assigned_to': 'u1',
      'created_by': 'p1',
      'status': 'verified',
      'reward_coins': 10,
      'created_at': '2026-11-12T08:00:00+00:00',
    });
    expect(task.isCompleted, isTrue);
    expect(task.createdAt.isUtc, isTrue);
  });
}
