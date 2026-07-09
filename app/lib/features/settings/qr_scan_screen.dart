import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../l10n/app_localizations.dart';

/// Full-screen QR scanner. Pops with the raw scanned string (the pairing
/// payload `{"url": ..., "code": ...}`), or null if cancelled.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  bool _handled = false;
  int _scannerKey = 0;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final raw = capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
    if (raw == null || raw.isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(raw);
  }

  void _retry() => setState(() {
        _handled = false;
        _scannerKey++;
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).scanPairingQr)),
      body: MobileScanner(
        key: ValueKey('qr-scanner-$_scannerKey'),
        onDetect: _onDetect,
        errorBuilder: (context, error) => _ScannerErrorView(
          error: error,
          onRetry: _retry,
        ),
      ),
    );
  }
}

class _ScannerErrorView extends StatelessWidget {
  final MobileScannerException error;
  final VoidCallback onRetry;

  const _ScannerErrorView({required this.error, required this.onRetry});

  String _message(BuildContext context) {
    if (error.errorCode == MobileScannerErrorCode.permissionDenied) {
      return AppLocalizations.of(context).cameraPermissionDenied;
    }
    return error.errorDetails?.message ?? error.errorCode.message;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).cameraUnavailable,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _message(context),
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('qr-retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(AppLocalizations.of(context).retry),
            ),
          ],
        ),
      ),
    );
  }
}
