import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../common/auth/session_controller.dart';
import '../../common/theme/app_theme.dart';
import '../../common/widgets/page_body.dart';
import '../sos/sos_button.dart';
import 'login_messages.dart';

/// Khung quét mã; test thay bằng bản giả gọi thẳng [onCode].
typedef ScannerBuilder = Widget Function(void Function(String code) onCode);

Widget cameraScanner(void Function(String code) onCode) => MobileScanner(
  onDetect: (capture) {
    final value = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (value != null) onCode(value);
  },
);

/// Quét mã đăng nhập do nhân viên cấp cho người cao tuổi (002 T097, FR-069).
class QrLoginScreen extends StatefulWidget {
  const QrLoginScreen({super.key, required this.session, this.scannerBuilder = cameraScanner});

  final SessionController session;
  final ScannerBuilder scannerBuilder;

  @override
  State<QrLoginScreen> createState() => _QrLoginScreenState();
}

class _QrLoginScreenState extends State<QrLoginScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _scan(String code) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.qrLogin(code);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = loginError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final hasPreviousScreen = ModalRoute.isFirstOf(context) == false;
    return Scaffold(
      body: PageBody(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasPreviousScreen)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
                      icon: const Icon(LucideIcons.arrowLeft),
                      label: const Text('Quay lại đăng nhập'),
                    ),
                  ),
                if (_error != null) ...[
                  Text(_error!, style: text.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.error)),
                  const SizedBox(height: 12),
                ],
                Text('Đặt mã QR nhân viên đưa vào trong khung.', style: text.headlineMedium),
                const SizedBox(height: 16),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    child: widget.scannerBuilder(_scan),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      // Máy đã gắn người cao tuổi: nút SOS hiện cả khi chưa có phiên (012 FR-085)
      bottomNavigationBar: widget.session.boundToResident
          ? SosButton(api: widget.session.api, store: widget.session.store)
          : null,
    );
  }
}
