import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vesnai_app/data/api_client.dart';
import 'package:vesnai_app/l10n/l10n_outside_widgets.dart';

void main() {
  final l = localizationsForLocale(const Locale('en'));

  group('noteAttachmentUploadErrorMessage', () {
    test('maps 413 to friendly message', () {
      expect(
        noteAttachmentUploadErrorMessage(
          ApiException(413, 'too large'),
          'photo.jpg',
          l,
        ),
        contains('too large'),
      );
    });

    test('maps timeout to connection hint', () {
      expect(
        noteAttachmentUploadErrorMessage(
          Exception('TimeoutException after 0:02:00'),
          'photo.jpg',
          l,
        ),
        contains('Connection dropped'),
      );
    });

    test('falls back to generic message', () {
      expect(
        noteAttachmentUploadErrorMessage(Exception('boom'), 'x.png', l),
        'Could not upload x.png: Exception: boom',
      );
    });
  });

  group('ttsErrorMessage', () {
    test('maps 503 API key rejection', () {
      expect(
        ttsErrorMessage(
          ApiException(503, '{"detail":"Voice service rejected the API key."}'),
          l,
        ),
        l.ttsApiKeyRejected,
      );
    });

    test('maps 503 not registered to register hint', () {
      expect(
        ttsErrorMessage(
          ApiException(503, '{"detail":"No voice service registered."}'),
          l,
        ),
        l.ttsRegisterFirst,
      );
    });

    test('includes server detail for 502 sidecar errors', () {
      final msg = ttsErrorMessage(
        ApiException(502, '{"detail":"Voice service error: connection refused"}'),
        l,
      );
      expect(msg, contains('connection refused'));
    });

    test('falls back to generic failure', () {
      expect(ttsErrorMessage(Exception('boom'), l), l.ttsFailed);
    });
  });
}
