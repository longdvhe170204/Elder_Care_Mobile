import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/common/api/api_client.dart';
import 'package:mobile/common/auth/biometric_auth.dart';
import 'package:mobile/common/auth/secure_store.dart';
import 'package:mobile/common/auth/session_controller.dart';
import 'package:mobile/common/offline/offline_database.dart';
import 'package:mobile/common/offline/offline_queue.dart';

/// Backend giả cho test app: trả theo (phương thức, đường dẫn sau `/api/v1`), ghi lại mọi yêu cầu.
class FakeBackend {
  final Map<String, http.Response Function(http.Request)> _routes = {};
  final List<http.Request> requests = [];

  /// Mất mạng: mọi yêu cầu lỗi kết nối.
  bool down = false;

  void onResponse(String method, String path, http.Response Function(http.Request) response) {
    _routes['$method $path'] = response;
  }

  /// `headers`: header phản hồi thêm, ví dụ `etag` của `GET /assessments/{id}`.
  /// Phản hồi 200 tính theo yêu cầu (ví dụ khác nhau theo tham số truy vấn).
  void onRequest(String method, String path, Object? Function(http.Request request) body) {
    _routes['$method $path'] = (request) =>
        http.Response.bytes(utf8.encode(jsonEncode(body(request))), 200, headers: {'content-type': 'application/json'});
  }

  void on(String method, String path, int status, [Object? body, Map<String, String> headers = const {}]) {
    _routes['$method $path'] = (_) => http.Response.bytes(
      body == null ? const [] : utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': status >= 400 ? 'application/problem+json' : 'application/json', ...headers},
    );
  }

  List<http.Request> calls(String method, String path) =>
      requests.where((r) => r.method == method && r.url.path == '/api/v1$path').toList();

  ApiClient client() => ApiClient(
    baseUrl: 'http://backend.test',
    httpClient: MockClient((request) async {
      requests.add(request);
      if (down) throw http.ClientException('offline');
      final route = _routes['${request.method} ${request.url.path.replaceFirst('/api/v1', '')}'];
      return route == null ? http.Response('', 404) : route(request);
    }),
  );
}

class FakeBiometric implements BiometricAuth {
  FakeBiometric({this.available = true, this.succeeds = true});

  bool available;
  bool succeeds;
  int prompts = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    return succeeds;
  }
}

Map<String, dynamic> residentUser({bool mustChangePassword = false}) => {
  'accountId': 41,
  'type': 'RESIDENT',
  'fullName': 'Nguyễn Thị Hoa',
  'roles': ['AC-16'],
  'mustChangePassword': mustChangePassword,
};

/// Người dùng của `/me`, `/auth/login` theo loại tài khoản (`STAFF`, `FAMILY_MEMBER`, `RESIDENT`). Nhân viên mặc định có
/// vai trò Điều dưỡng (`AC-04`) để vào được phần nhân viên (điều hướng theo vai trò, spec 2026-11-20); test cần vai trò
/// khác truyền [roles].
Map<String, dynamic> user(String type, {bool mustChangePassword = false, List<String>? roles}) => {
  'accountId': 7,
  'type': type,
  'fullName': '[Họ tên 1]',
  'roles': roles ?? (type == 'STAFF' ? ['AC-04'] : <String>[]),
  'mustChangePassword': mustChangePassword,
};

Map<String, dynamic> loginResponse({bool mustChangePassword = false}) => {
  'token': 'session-1',
  'deviceToken': 'device-token-1',
  'mustChangePassword': mustChangePassword,
  'user': residentUser(mustChangePassword: mustChangePassword),
};

/// Hàng đợi ngoại tuyến trên SQLite trong bộ nhớ, dùng client của phiên.
OfflineQueue memoryQueue(SessionController s) {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return OfflineQueue(OfflineDatabase(NativeDatabase.memory()), s.api);
}

/// Từ màn đăng nhập chung, bấm nút người cao tuổi để tới màn quét mã.
Future<void> openResidentLogin(WidgetTester tester) async {
  final choice = find.text('Quét mã QR cho người cao tuổi');
  if (choice.evaluate().isEmpty) return;
  await tester.ensureVisible(choice);
  await tester.pumpAndSettle();
  await tester.tap(choice);
  await tester.pumpAndSettle();
}

SessionController session(FakeBackend backend, MemoryStore store, FakeBiometric biometric) =>
    SessionController(api: backend.client(), store: store, biometric: biometric);
