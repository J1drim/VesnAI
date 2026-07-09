import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/notifications_feed.dart';
import 'desktop/sticky_board.dart';
import 'features/chat/chat_screen.dart';
import 'features/chat/chat_sessions.dart';
import 'features/graph/graph_screen.dart';
import 'features/notes/notes_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/settings/settings_screen.dart';
import 'l10n/app_localizations.dart';
import 'data/widget_actions.dart';
import 'providers.dart';
import 'theme.dart';

bool get isDesktop =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.linux;

/// Global navigator key so native widget taps (deep links) can push routes.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Notes view adapts: a sticky-notes board on desktop, a list on mobile.
class AdaptiveNotes extends StatelessWidget {
  const AdaptiveNotes({super.key});

  @override
  Widget build(BuildContext context) =>
      isDesktop ? const StickyBoard() : const NotesScreen();
}

class VesnaiApp extends ConsumerWidget {
  const VesnaiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Show onboarding until the user pairs or explicitly continues offline.
    final paired = ref.watch(serverConnectionProvider).isPaired;
    final onboarded = ref.watch(onboardedProvider);
    final appLocale = ref.watch(appLocaleProvider);
    return MaterialApp(
      title: 'VesnAI',
      navigatorKey: appNavigatorKey,
      theme: VesnaiTheme.light(),
      darkTheme: VesnaiTheme.dark(),
      locale: appLocale.languageCode == null
          ? null
          : Locale(appLocale.languageCode!),
      localizationsDelegates: [
        ...AppLocalizations.localizationsDelegates,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: (paired || onboarded) ? const HomeShell() : const OnboardingScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Adaptive shell: a bottom nav on mobile is the simplest cross-platform base;
/// the desktop sticky-notes layout reuses the same screens (see desktop docs).
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  int _index = 0;
  NotificationsService? _feed;

  static const _screens = [
    AdaptiveNotes(),
    ChatScreen(),
    GraphScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _feed = ref.read(notificationsServiceProvider);
    // Start draining the "image ready" feed while foregrounded.
    if (ref.read(serverConnectionProvider).isPaired) {
      _feed!.drain();
      _feed!.startPolling();
      unawaited(_feed!.refreshDueReviewReminder());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_consumeWidgetDeepLinks());
    });
  }

  void _applyHomeTabRequest(HomeTabRequest req) {
    setState(() => _index = req.tabIndex);
    final chat = ref.read(chatControllerProvider.notifier);
    if (req.newChat) {
      unawaited(chat.newChat());
    } else if (req.chatSessionId != null) {
      unawaited(chat.switchTo(req.chatSessionId!));
    }
    ref.read(homeTabRequestProvider.notifier).clear();
  }

  Future<void> _consumeWidgetDeepLinks() async {
    if (!mounted) return;
    final tabReq = ref.read(homeTabRequestProvider);
    if (tabReq != null) {
      _applyHomeTabRequest(tabReq);
    }
    final pending = ref.read(pendingWidgetActionProvider);
    if (pending != null) {
      ref.read(pendingWidgetActionProvider.notifier).clear();
      handleWidgetAction(
        ref.read,
        action: pending.action,
        path: pending.path,
        sessionId: pending.sessionId,
      );
    }
  }

  @override
  void dispose() {
    _feed?.stopPolling();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final feed = ref.read(notificationsServiceProvider);
    if (state == AppLifecycleState.resumed) {
      unawaited(_onResume(feed));
      feed.startPolling();
    } else if (state == AppLifecycleState.paused) {
      feed.stopPolling();
    }
  }

  Future<void> _onResume(NotificationsService feed) async {
    final notes = ref.read(notesProvider.notifier);
    await notes.ingestQuickCaptures();
    if (ref.read(serverConnectionProvider).isPaired) {
      await notes.bootstrap();
      await ref.read(chatControllerProvider.notifier).flushPending();
      if (ref.read(serverConnectionProvider).isPaired) {
        feed.drain();
        unawaited(feed.refreshDueReviewReminder());
      }
    }
    await ref.read(chatControllerProvider.notifier).publishWidgetFromLocalStore();
    await notes.publishFullWidgetSnapshot();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    ref.listen<HomeTabRequest?>(homeTabRequestProvider, (prev, next) {
      if (next == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _applyHomeTabRequest(next);
      });
    });
    return Scaffold(
      // Edge-to-edge on Android 15+: inset content so it clears the system
      // status/navigation bars (the bottom bar handles its own inset).
      body: SafeArea(bottom: false, child: _screens[_index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.notes_outlined), label: l.navNotes),
          NavigationDestination(
              icon: const Icon(Icons.chat_bubble_outline), label: l.navChat),
          NavigationDestination(icon: const Icon(Icons.hub_outlined), label: l.navGraph),
          NavigationDestination(
              icon: const Icon(Icons.settings_outlined), label: l.navSettings),
        ],
      ),
    );
  }
}
