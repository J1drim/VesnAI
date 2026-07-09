import 'dart:io';

import 'package:cupertino_http/cupertino_http.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Creates the platform [http.Client] used for all VesnAI API traffic.
///
/// - **Android / Linux / Windows:** [IOClient] with a plain [SecurityContext]
///   (system trust roots). Dev builds made via `./scripts/vesnai.sh client`
///   pass `--dart-define=TRUST_DEV_MKCERT_CA=true`, which additionally loads
///   the mkcert root CA from `assets/certs/` so the local HTTPS server is
///   trusted. Validation is normal TLS — no `badCertificateCallback` and no
///   global [HttpOverrides].
/// - **iOS / macOS:** [CupertinoClient] uses the native URLSession trust store
///   (install the mkcert root CA profile once; see `./scripts/vesnai.sh
///   client install --device ios`).
///
/// Release/store builds trust only public CAs by default: expose the server
/// with a publicly trusted certificate (tunnel or reverse proxy — see
/// docs/REMOTE_ACCESS.md) or build with the dart-define above.
Future<http.Client> createPlatformHttpClient() async {
  if (kIsWeb) {
    return http.Client();
  }
  if (Platform.isIOS || Platform.isMacOS) {
    return CupertinoClient.defaultSessionConfiguration();
  }
  return IOClient(await _dartIoClientWithDevCa());
}

/// When true (dev builds only, via --dart-define), also trust the dev mkcert
/// CA bundled under assets/certs/. Off by default so release builds trust
/// only public CAs.
const bool kTrustDevMkcertCa =
    bool.fromEnvironment('TRUST_DEV_MKCERT_CA', defaultValue: false);

Future<HttpClient> _dartIoClientWithDevCa() async {
  final context = SecurityContext(withTrustedRoots: true);
  if (kTrustDevMkcertCa) {
    try {
      final data = await rootBundle.load('assets/certs/mkcert_root_ca.pem');
      context.setTrustedCertificatesBytes(data.buffer.asUint8List());
    } catch (e) {
      debugPrint(
        'TLS: mkcert root CA asset not loaded ($e). '
        'Run ./scripts/vesnai.sh setup-https then rebuild the app.',
      );
    }
  }
  final client = HttpClient(context: context);
  // Camera photos can be several MB; allow slow LAN uploads without idle drops.
  client.connectionTimeout = const Duration(seconds: 60);
  client.idleTimeout = const Duration(minutes: 2);
  return client;
}
