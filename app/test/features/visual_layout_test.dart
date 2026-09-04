import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vesnai_app/data/attachment_cache.dart';
import 'package:vesnai_app/data/chat_attachment_cache.dart';
import 'package:vesnai_app/desktop/sticky_board.dart';
import 'package:vesnai_app/features/chat/chat_screen.dart';
import 'package:vesnai_app/features/chat/chat_sessions.dart';
import 'package:vesnai_app/features/note_detail/note_detail_screen.dart';
import 'package:vesnai_app/features/notes/notes_screen.dart';
import 'package:vesnai_app/l10n/app_localizations.dart';
import 'package:vesnai_app/models/note.dart';
import 'package:vesnai_app/providers.dart';
import 'package:vesnai_app/theme.dart';

class PreviewChat extends ChatController {
  @override
  ChatState build() => const ChatState(
    messages: [
      ChatMessageView(
        id: '',
        role: 'user',
        content: 'How can I make more room for creative work?',
      ),
      ChatMessageView(
        id: '',
        role: 'assistant',
        content:
            'Start with a small, protected window.\n\n### A simple experiment\n\n- Choose one idea from your notes.\n- Spend twenty minutes exploring it.\n- Save what surprised you.\n\nYou can build on the rhythm that works for you.',
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const font = String.fromEnvironment('VISUAL_FONT');
  setUpAll(() async {
    if (font.isNotEmpty) {
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      final loader = FontLoader('ReviewFont')
        ..addFont(
          File(font).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
        );
      await loader.load();
    }
  });
  for (final lang in ['en', 'pl']) {
    for (final dark in [false, true]) {
      for (final wide in [false, true]) {
        for (final scene in ['notes', 'detail', 'chat', 'board']) {
          final name =
              '$scene-$lang-${dark ? 'dark' : 'light'}-${wide ? 'wide' : 'phone'}';
          testWidgets('visual layout $name', (tester) async {
            if (font.isNotEmpty) debugDisableShadows = false;
            await tester.binding.setSurfaceSize(Size(wide ? 1280 : 390, 860));
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(() => tester.binding.setSurfaceSize(null));
            final dir = Directory.systemTemp.createTempSync('vesnai-visual-');
            addTearDown(() => dir.deleteSync(recursive: true));
            final container = ProviderContainer(
              overrides: [
                attachmentCacheProvider.overrideWithValue(AttachmentCache(dir)),
                chatAttachmentCacheProvider.overrideWithValue(
                  ChatAttachmentCache(dir),
                ),
                chatControllerProvider.overrideWith(PreviewChat.new),
              ],
            );
            addTearDown(container.dispose);
            final polish = lang == 'pl';
            await container
                .read(localStoreProvider)
                .put(
                  Note(
                    path: 'notes/creative.md',
                    title: polish
                        ? 'Przestrzeń na twórczą pracę'
                        : 'Making room for creative work',
                    body: polish
                        ? '# Mały eksperyment\n\nDwadzieścia minut, czysta kartka i jeden pomysł.\n\n- [ ] Wybierz temat\n- [ ] Zapisz obserwacje'
                        : '# A small experiment\n\nTwenty minutes, a blank page, and one idea worth exploring.\n\n- [ ] Choose a topic\n- [ ] Capture what surprised you',
                    type: 'Idea',
                    tags: const ['creative', 'journal', 'weekend', 'personal'],
                  ),
                );
            await container
                .read(localStoreProvider)
                .put(
                  Note(
                    path: 'notes/walk.md',
                    title: polish ? 'Spacer nad rzeką' : 'A walk by the river',
                    body: polish
                        ? 'Zabrać aparat i poszukać nowej ścieżki.'
                        : 'Bring a camera and explore a new path.',
                    type: 'Task',
                    tags: const ['weekend'],
                  ),
                );
            var theme = dark ? VesnaiTheme.dark() : VesnaiTheme.light();
            if (font.isNotEmpty)
              theme = theme.copyWith(
                textTheme: theme.textTheme.apply(fontFamily: 'ReviewFont'),
              );
            await tester.pumpWidget(
              UncontrolledProviderScope(
                container: container,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: theme,
                  locale: Locale(lang),
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: switch (scene) {
                    'detail' => const NoteDetailScreen(
                      path: 'notes/creative.md',
                    ),
                    'chat' => const ChatScreen(),
                    'board' => const StickyBoard(),
                    _ => const NotesScreen(),
                  },
                ),
              ),
            );
            await tester.pumpAndSettle();
            if (font.isNotEmpty) {
              await tester.runAsync(() async {
                await precacheImage(const AssetImage('assets/branding/vesnai_icon.png'), tester.element(find.byType(Scaffold).first));
              });
              await tester.pumpAndSettle();
            }
            expect(tester.takeException(), isNull);
            if (font.isNotEmpty) {
              await expectLater(
                find.byType(MaterialApp),
                matchesGoldenFile('../../../docs/screenshots/$name.png'),
              );
            }
            // Large text must retain access to controls without overflow.
            tester.platformDispatcher.textScaleFactorTestValue = 1.8;
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            tester.platformDispatcher.clearTextScaleFactorTestValue();
            await tester.pumpWidget(const SizedBox.shrink());
            debugDisableShadows = true;
          });
        }
      }
    }
  }
}
