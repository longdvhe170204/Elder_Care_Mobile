import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/common/auth/secure_store.dart';
import 'package:mobile/common/auth/session_controller.dart';

import '../../support/fake_backend.dart';

// Vai trò của tài khoản (spec 2026-11-20 điều hướng theo vai trò, mục 4 luật 1): đọc `roles` của `GET /me`, lưu trên máy
// để mở app khi mất mạng vẫn dựng được điều hướng; đăng xuất thì xóa để người sau trên máy dùng chung không thừa hưởng.

Map<String, dynamic> _staff(List<String> roles) => {...user('STAFF'), 'roles': roles};

void main() {
  test('roles_docTuMe_luuTrenMay', () async {
    final store = MemoryStore();
    await store.write(SessionController.tokenKey, 'session-1');
    final backend = FakeBackend()..on('GET', '/me', 200, _staff(['AC-02', 'AC-04']));
    final s = session(backend, store, FakeBiometric());

    await s.start();

    expect(s.user!.roles, {'AC-02', 'AC-04'});
    expect(await store.read(SessionController.rolesKey), isNotNull);
  });

  test('roles_matMang_docTuMay', () async {
    final store = MemoryStore();
    await store.write(SessionController.tokenKey, 'session-1');
    await store.write(SessionController.userTypeKey, AccountType.staff.name);
    await store.write(SessionController.rolesKey, 'AC-04');
    final backend = FakeBackend()..down = true;
    final s = session(backend, store, FakeBiometric());

    await s.start();

    expect(s.user!.type, AccountType.staff);
    expect(s.user!.roles, {'AC-04'});
  });

  test('roles_dangXuat_xoaKhoiMay', () async {
    final store = MemoryStore();
    await store.write(SessionController.tokenKey, 'session-1');
    final backend = FakeBackend()
      ..on('GET', '/me', 200, _staff(['AC-05']))
      ..on('POST', '/auth/logout', 204);
    final s = session(backend, store, FakeBiometric());
    await s.start();

    await s.signOut();

    expect(await store.read(SessionController.rolesKey), isNull);
  });
}
