import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vesnai_app/data/attachment_cache.dart';
import 'package:vesnai_app/data/chat_attachment_cache.dart';
import 'package:vesnai_app/l10n/app_localizations.dart';
import 'package:vesnai_app/providers.dart';
import 'package:vesnai_app/widgets/note_body_editor.dart';

void main() {
  testWidgets('note body editor supports image markdown embeds', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('vesnai_editor_test');
    addTearDown(() => tmp.deleteSync(recursive: true));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWith((ref) => null),
          attachmentCacheProvider.overrideWith(
            (ref) => AttachmentCache(Directory(p.join(tmp.path, 'attachments'))),
          ),
          chatAttachmentCacheProvider.overrideWith(
            (ref) => ChatAttachmentCache(Directory(p.join(tmp.path, 'chat'))),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: NoteBodyEditor(
                fieldKey: const Key('edit-body'),
                initialMarkdown: 'Hello\n\n![photo](attachments/test.png)',
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('edit-body')), findsOneWidget);
    expect(find.textContaining('UnimplementedError'), findsNothing);
    expect(find.textContaining('not supported'), findsNothing);
  });
}
