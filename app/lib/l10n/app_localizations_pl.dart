// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Polish (`pl`).
class AppLocalizationsPl extends AppLocalizations {
  AppLocalizationsPl([String locale = 'pl']) : super(locale);

  @override
  String get appTitle => 'VesnAI';

  @override
  String get navNotes => 'Notatki';

  @override
  String get navChat => 'Czat';

  @override
  String get navGraph => 'Graf';

  @override
  String get navSettings => 'Ustawienia';

  @override
  String get capture => 'Zapisz';

  @override
  String get sync => 'Synchronizuj';

  @override
  String get webSearch => 'Wyszukiwanie w sieci';

  @override
  String get notPaired => 'Offline – niesparowano';

  @override
  String get pairedPullToSync => 'Sparowano – pociągnij, aby zsynchronizować';

  @override
  String lastSynced(String when) {
    return 'Ostatnia synchronizacja $when';
  }

  @override
  String get emptyNotes =>
      'Brak notatek. Dotknij +, aby zapisać pierwszą myśl.';

  @override
  String get onboardingTitle => 'Połącz się ze swoim serwerem VesnAI';

  @override
  String get onboardingBody =>
      'Twoje notatki pozostają na Twoich urządzeniach i serwerze. Sparuj to urządzenie, aby synchronizować, rozmawiać, wyszukiwać i więcej – lub kontynuuj offline i sparuj później.';

  @override
  String get foundOnNetwork => 'Znaleziono w Twojej sieci';

  @override
  String get searchingNetwork => 'Szukam w Twojej sieci...';

  @override
  String get serverUrl => 'Adres serwera';

  @override
  String get pairingCode => 'Kod parowania';

  @override
  String get scanQr => 'Skanuj kod QR';

  @override
  String get pair => 'Sparuj';

  @override
  String get continueOffline => 'Kontynuuj offline';

  @override
  String get unpairDevice => 'Rozparuj to urządzenie';

  @override
  String get connection => 'Połączenie';

  @override
  String get invalidCode => 'Nieprawidłowy lub wygasły kod parowania.';

  @override
  String get unreachableServer =>
      'Nie można połączyć się z serwerem. Sprawdź adres i Wi-Fi.';

  @override
  String get pairingErrorTls =>
      'Bezpieczne połączenie nie powiodło się (niezaufany certyfikat). Użyj adresu serwera z zaufanym certyfikatem lub zainstaluj certyfikat serwera na tym urządzeniu.';

  @override
  String get pairingErrorServerUnreachable =>
      'Nie można połączyć się z serwerem pod tym adresem. Sprawdź adres, Wi-Fi i czy serwer jest uruchomiony.';

  @override
  String get typeNote => 'Notatka';

  @override
  String get typeIdea => 'Pomysł';

  @override
  String get typeTask => 'Zadanie';

  @override
  String get typePhoto => 'Zdjęcie';

  @override
  String get typeCritique => 'Krytyka';

  @override
  String get cancel => 'Anuluj';

  @override
  String get retry => 'Spróbuj ponownie';

  @override
  String get open => 'Otwórz';

  @override
  String get ok => 'OK';

  @override
  String get skip => 'Pomiń';

  @override
  String get delete => 'Usuń';

  @override
  String get save => 'Zapisz';

  @override
  String get edit => 'Edytuj';

  @override
  String get view => 'Podgląd';

  @override
  String get dueForReview => 'Do przejrzenia';

  @override
  String get searchNotesHint => 'Szukaj w notatkach…';

  @override
  String get offlineChangesQueued =>
      'Offline – zmiany zostaną zsynchronizowane później.';

  @override
  String syncedChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count zmian',
      few: '$count zmiany',
      one: '1 zmiana',
    );
    return 'Zsynchronizowano ($_temp0).';
  }

  @override
  String get notesBusySyncing =>
      'Trwa synchronizacja notatek. Spróbuj za chwilę.';

  @override
  String get couldNotLoadNotes => 'Nie udało się wczytać notatek.';

  @override
  String noNotesMatchQuery(String query) {
    return 'Brak notatek pasujących do \"$query\".';
  }

  @override
  String get noNotesMatchTypes => 'Brak notatek pasujących do wybranych typów.';

  @override
  String get justNow => 'przed chwilą';

  @override
  String minutesAgo(int minutes) {
    return '$minutes min temu';
  }

  @override
  String hoursAgo(int hours) {
    return '$hours godz. temu';
  }

  @override
  String daysAgo(int days) {
    return '$days dni temu';
  }

  @override
  String get noteScreenTitle => 'Notatka';

  @override
  String get aiGenerated => 'Wygenerowane przez AI';

  @override
  String get critiqueByMarena => 'Krytyka od Mareny';

  @override
  String get critiquedNote => 'Krytykowana notatka';

  @override
  String get critiques => 'Krytyki';

  @override
  String get markDone => 'Oznacz jako ukończone';

  @override
  String get reopen => 'Otwórz ponownie';

  @override
  String get done => 'Ukończone';

  @override
  String get showDone => 'Pokaż ukończone';

  @override
  String get markedDone => 'Oznaczono jako ukończone';

  @override
  String get noteReopened => 'Otwarto ponownie';

  @override
  String get filterAll => 'Wszystkie';

  @override
  String get stopDictation => 'Zatrzymaj dyktowanie';

  @override
  String get formatting => 'Formatowanie';

  @override
  String get noteTypeSheetTitle => 'Typ notatki';

  @override
  String get clearFilters => 'Wyczyść filtry';

  @override
  String get untitled => '(bez tytułu)';

  @override
  String get titleLabel => 'Tytuł';

  @override
  String get typeLabel => 'Typ';

  @override
  String get tagsLabel => 'Tagi (rozdzielone przecinkami)';

  @override
  String get bodyHint => 'Treść';

  @override
  String get attachments => 'Załączniki';

  @override
  String get generatedMemoryAid => 'Wygenerowana ilustracja';

  @override
  String get enrichWithAi => 'Wzbogać z AI';

  @override
  String get noteNotFound => 'Nie znaleziono notatki.';

  @override
  String get savedLocallyWillSync =>
      'Zapisano lokalnie — synchronizacja nastąpi, gdy serwer VesnAI wróci.';

  @override
  String get enrichRequested =>
      'Zlecono wzbogacenie – wygenerowana notatka pojawi się po synchronizacji.';

  @override
  String get enrichFailed => 'Wzbogacenie nie powiodło się.';

  @override
  String errorWithDetail(String error) {
    return 'Błąd: $error';
  }

  @override
  String get talkToVesnai => 'Porozmawiaj z VesnAI';

  @override
  String get newChat => 'Nowy czat';

  @override
  String get noConversationsYet => 'Brak rozmów.';

  @override
  String get chatInputHint => 'Zapytaj, przypomnij lub utwórz...';

  @override
  String get listening => 'Słucham…';

  @override
  String get startingNewChat => 'Rozpoczynam nowy czat…';

  @override
  String get sendingStatus => 'Wysyłam…';

  @override
  String get vesnaiThinking => 'VesnAI myśli…';

  @override
  String get thinking => 'Myślę…';

  @override
  String get generatingImage => 'Generuję obraz…';

  @override
  String get imageGenerationFailed => 'Generowanie obrazu nie powiodło się';

  @override
  String get retryImage => 'Ponów obraz';

  @override
  String get notSent => 'Nie wysłano';

  @override
  String get attach => 'Załącz';

  @override
  String get speak => 'Powiedz';

  @override
  String get stopAndSend => 'Zatrzymaj i wyślij';

  @override
  String get replay => 'Odtwórz ponownie';

  @override
  String get camera => 'Aparat';

  @override
  String get gallery => 'Galeria';

  @override
  String get file => 'Plik';

  @override
  String get voiceNote => 'Notatka głosowa';

  @override
  String get noteSaved => 'Notatka zapisana';

  @override
  String couldNotSendMessage(String error) {
    return 'Nie udało się wysłać wiadomości: $error';
  }

  @override
  String get speechUnavailable =>
      'Rozpoznawanie mowy jest niedostępne na tym urządzeniu.';

  @override
  String get addTag => 'Dodaj tag';

  @override
  String get suggestTags => 'Zaproponuj tagi';

  @override
  String get photo => 'Zdjęcie';

  @override
  String get attachFile => 'Załącz plik';

  @override
  String get draw => 'Rysuj';

  @override
  String uploadingPhoto(int current, int total) {
    return 'Przesyłam zdjęcie $current z $total…';
  }

  @override
  String get attachmentsNeedServer =>
      'Załączniki wymagają sparowanego serwera; zapisano sam tekst.';

  @override
  String get savedLocallyShort =>
      'Zapisano lokalnie — synchronizacja nastąpi, gdy serwer wróci.';

  @override
  String couldNotSaveNote(String error) {
    return 'Nie udało się zapisać notatki: $error';
  }

  @override
  String get tagSuggestionsNeedServer =>
      'Propozycje tagów wymagają sparowanego serwera.';

  @override
  String couldNotSuggestTags(String error) {
    return 'Nie udało się zaproponować tagów: $error';
  }

  @override
  String get settingsTitle => 'Ustawienia';

  @override
  String get sectionServer => 'Serwer';

  @override
  String get sectionModelsPrivacy => 'Modele i prywatność';

  @override
  String get sectionAssistant => 'Asystentka';

  @override
  String get sectionApp => 'Aplikacja';

  @override
  String get sectionModels => 'Modele';

  @override
  String get sectionSearch => 'Wyszukiwanie';

  @override
  String get sectionData => 'Dane';

  @override
  String get notPairedShort => 'Niesparowano';

  @override
  String get localOnlyMode => 'Tryb lokalny';

  @override
  String get loadingServerSettings => 'Wczytuję ustawienia serwera...';

  @override
  String get pairToViewPrivacy =>
      'Sparuj serwer, aby zobaczyć ustawienia prywatności.';

  @override
  String get localOnlySubtitle =>
      'Nigdy nie wywołuj zewnętrznych API (konfigurowane na serwerze).';

  @override
  String get assistantLanguage => 'Język asystentki';

  @override
  String get assistantLanguageAuto => 'Auto (z czatu)';

  @override
  String get appLanguage => 'Język aplikacji';

  @override
  String get appLanguageSystem => 'Domyślny systemu';

  @override
  String get readRepliesAloud => 'Czytaj odpowiedzi na głos';

  @override
  String get readRepliesAloudSubtitle =>
      'Gdy czat jest otwarty i głośność jest włączona';

  @override
  String get shareLocationWithChat => 'Udostępniaj lokalizację w czacie';

  @override
  String get shareLocationSubtitle =>
      'Przybliżony GPS do lokalnych zapytań (pogoda, okolica). Wysyłany z wiadomością tylko gdy włączone.';

  @override
  String get voiceService => 'Usługa głosowa';

  @override
  String get voiceServicePairFirst => 'Sparuj serwer, aby zarejestrować głos.';

  @override
  String voiceServiceRegistered(String provider) {
    return 'Zarejestrowano ($provider) — funkcja mowy włączona';
  }

  @override
  String get voiceServiceNotRegistered =>
      'Zarejestruj OpenAI lub usługę TTS, aby włączyć funkcję mowy';

  @override
  String get externalApiKeys => 'Zewnętrzne klucze API';

  @override
  String get externalApiKeysSubtitle =>
      'Przechowywane zaszyfrowane na serwerze; nigdy w kopiach zapasowych.';

  @override
  String get externalApiKeysPairFirst =>
      'Sparuj serwer, aby zarządzać kluczami.';

  @override
  String get chatModel => 'Model czatu';

  @override
  String get languages => 'Języki';

  @override
  String get backUpKnowledge => 'Kopia zapasowa wiedzy';

  @override
  String get backUpSubtitle => 'Pobierz zaszyfrowaną kopię swoich notatek.';

  @override
  String get restoreFromBackup => 'Przywróć z kopii zapasowej';

  @override
  String backupFailed(String error) {
    return 'Kopia zapasowa nie powiodła się: $error';
  }

  @override
  String restoreFailed(String error) {
    return 'Przywracanie nie powiodło się: $error';
  }

  @override
  String get restoredFromBackup => 'Przywrócono z kopii zapasowej.';

  @override
  String get backupPassphraseOptional => 'Hasło kopii zapasowej (opcjonalne)';

  @override
  String get backupPassphraseRequired => 'Hasło kopii zapasowej (wymagane)';

  @override
  String get passphrase => 'Hasło';

  @override
  String get unpairQuestion => 'Rozparować urządzenie?';

  @override
  String get unpairExplanation =>
      'To usunie zapisane połączenie i unieważni to urządzenie na serwerze. Lokalne notatki pozostaną na tym urządzeniu.';

  @override
  String get unpair => 'Rozparuj';

  @override
  String get pairDialogTitle => 'Sparuj z serwerem VesnAI';

  @override
  String get pairedWithServer => 'Sparowano z serwerem.';

  @override
  String get enterValidServerUrl => 'Podaj prawidłowy adres serwera.';

  @override
  String get newSticky => 'Nowa karteczka';

  @override
  String get newNote => 'Nowa notatka';

  @override
  String get noNotesYet => 'Brak notatek.';

  @override
  String get refresh => 'Odśwież';

  @override
  String get unpairedBannerText =>
      'Nie sparowano — sparuj z serwerem VesnAI, aby synchronizować, czatować i wyszukiwać.';

  @override
  String get knowledgeGraph => 'Graf wiedzy';

  @override
  String get graphOffline => 'Offline — wyświetlane są tylko lokalne notatki.';

  @override
  String graphRefreshed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count zmian',
      few: '$count zmiany',
      one: '1 zmianę',
    );
    return 'Graf odświeżony (wysłano $_temp0).';
  }

  @override
  String get graphNoNotesMatchFilters =>
      'Żadne notatki nie pasują do bieżących filtrów.';

  @override
  String get graphNoNotes => 'Brak notatek do wyświetlenia w grafie.';

  @override
  String get graphSemantics =>
      'Interaktywny graf wiedzy. Przeciągnij, aby przesunąć; uszczypnij, aby przybliżyć; dotknij węzła, aby otworzyć notatkę.';

  @override
  String get tagsFilterLabel => 'Tagi';

  @override
  String tagsFilterLabelCount(int count) {
    return 'Tagi ($count)';
  }

  @override
  String get filterMine => 'Moje';

  @override
  String get showAll => 'Pokaż wszystko';

  @override
  String get filterByTag => 'Filtruj po tagu';

  @override
  String get selectedLabel => 'Wybrane';

  @override
  String get noTagsYet => 'Brak tagów';

  @override
  String get allTagsSelected => 'Wszystkie tagi wybrane';

  @override
  String get clearTags => 'Wyczyść tagi';

  @override
  String get searchFailed => 'Wyszukiwanie nie powiodło się.';

  @override
  String searchFailedWithError(String error) {
    return 'Wyszukiwanie nie powiodło się: $error';
  }

  @override
  String get researchReady => 'Wyniki wyszukiwania gotowe';

  @override
  String get researchReadyBody => 'Wyniki wyszukiwania zapisano jako notatkę.';

  @override
  String get pairForWebSearch =>
      'Sparuj z serwerem, aby wyszukiwać w internecie.';

  @override
  String get researchPrompt => 'Co chcesz zbadać?';

  @override
  String timeBudget(int seconds) {
    return 'Limit czasu: ${seconds}s';
  }

  @override
  String get researching => 'Wyszukiwanie...';

  @override
  String get searchAction => 'Szukaj';

  @override
  String get scanPairingQr => 'Zeskanuj kod QR parowania';

  @override
  String get cameraPermissionDenied =>
      'Odmówiono dostępu do aparatu. Zezwól na dostęp do aparatu w Ustawieniach, a następnie dotknij Ponów.';

  @override
  String get cameraUnavailable => 'Aparat niedostępny';

  @override
  String get noApiKeysStored => 'Brak zapisanych kluczy API.';

  @override
  String get addApiKey => 'Dodaj klucz API';

  @override
  String get apiKeyNameLabel => 'Nazwa (np. openai)';

  @override
  String get apiKeyValueLabel => 'Wartość';

  @override
  String get providerTtsSidecar => 'Usługa TTS (self-hosted)';

  @override
  String get apiKeyRequired => 'Klucz API jest wymagany.';

  @override
  String get sidecarUrlRequired => 'Adres URL usługi TTS jest wymagany.';

  @override
  String get voiceIdsRequired =>
      'Identyfikatory głosów są wymagane (zależą od silnika TTS).';

  @override
  String get voiceServiceRegisteredSnack => 'Usługa głosowa zarejestrowana.';

  @override
  String registrationFailed(String error) {
    return 'Rejestracja nie powiodła się: $error';
  }

  @override
  String get voiceServiceRemoved => 'Usługa głosowa usunięta.';

  @override
  String removeFailed(String error) {
    return 'Usuwanie nie powiodło się: $error';
  }

  @override
  String get voiceServiceIntroConfigured =>
      'Funkcja mowy (Czytaj) korzysta z zarejestrowanego dostawcy poniżej. Dostawcę można zmienić w każdej chwili — bez reinstalacji serwera.';

  @override
  String get voiceServiceIntroUnconfigured =>
      'Zarejestruj OpenAI lub własną usługę TTS, aby włączyć funkcję mowy w czacie.';

  @override
  String get providerLabel => 'Dostawca';

  @override
  String get sidecarUrl => 'Adres URL usługi TTS';

  @override
  String get sidecarContractHelp =>
      'Działa dowolna usługa HTTP realizująca kontrakt TTS VesnAI (zob. docs/TTS_SIDECAR.md w projekcie).';

  @override
  String get openaiApiKey => 'Klucz API OpenAI';

  @override
  String get openaiApiKeyUpdate =>
      'Klucz API OpenAI (wpisz ponownie, aby zaktualizować)';

  @override
  String get sidecarApiKey => 'Klucz API usługi TTS';

  @override
  String get sidecarApiKeyUpdate =>
      'Klucz API (wpisz ponownie, aby zaktualizować)';

  @override
  String get openaiModel => 'Model OpenAI';

  @override
  String get polishVoiceOpenai => 'Głos polski (id OpenAI)';

  @override
  String get polishVoiceId => 'Id głosu polskiego';

  @override
  String get englishVoiceOpenai => 'Głos angielski (id OpenAI)';

  @override
  String get englishVoiceId => 'Id głosu angielskiego';

  @override
  String get voiceIdHint => 'identyfikator głosu z Twojego silnika TTS';

  @override
  String get updateRegistration => 'Zaktualizuj rejestrację';

  @override
  String get register => 'Zarejestruj';

  @override
  String get removeVoiceService => 'Usuń usługę głosową';

  @override
  String get deleteNoteQuestion => 'Usunąć notatkę?';

  @override
  String deleteNoteConfirm(String title) {
    return 'Usunąć \"$title\"? Tej operacji nie można cofnąć.';
  }

  @override
  String get deleteNoteSyncNote =>
      'Notatka zostanie usunięta z tego urządzenia i zsynchronizowana z serwerem po połączeniu.';

  @override
  String get replyDidNotFinish =>
      'Ta odpowiedź nie została ukończona. Wyślij wiadomość ponownie.';

  @override
  String couldNotSendTapRetryStatus(int status) {
    return 'Nie udało się wysłać wiadomości ($status). Dotknij Ponów przy wiadomości.';
  }

  @override
  String get couldNotSendTapRetry =>
      'Nie udało się wysłać wiadomości. Dotknij Ponów przy wiadomości.';

  @override
  String get connectToSendAttachments =>
      'Połącz się z serwerem VesnAI, aby wysyłać załączniki.';

  @override
  String get connectToChat => 'Połącz się z serwerem VesnAI, aby czatować.';

  @override
  String get ttsNeedsServer => 'Synteza mowy wymaga sparowanego serwera.';

  @override
  String get ttsRegisterFirst =>
      'Zarejestruj usługę głosową w Ustawieniach, aby używać funkcji mowy.';

  @override
  String get ttsFailed => 'Synteza mowy nie powiodła się.';

  @override
  String get ttsApiKeyRejected =>
      'Usługa głosowa odrzuciła klucz API. Zaktualizuj go w Ustawieniach → Usługa głosowa.';

  @override
  String ttsVoiceServiceError(String detail) {
    return 'Synteza mowy nie powiodła się: $detail';
  }

  @override
  String get uploadSessionNotFound =>
      'Nie znaleziono sesji czatu na serwerze. Rozpocznij nowy czat i spróbuj ponownie.';

  @override
  String get uploadTooLarge =>
      'Zdjęcie jest zbyt duże dla serwera. Spróbuj użyć mniejszego obrazu.';

  @override
  String uploadConnectionDropped(String filename) {
    return 'Połączenie przerwane podczas przesyłania $filename. Sprawdź Wi-Fi i spróbuj ponownie.';
  }

  @override
  String uploadFailed(String filename, String error) {
    return 'Nie udało się przesłać $filename: $error';
  }

  @override
  String get notifMarenaCritique => 'Marena zostawiła krytykę';

  @override
  String get notifMarenaCritiqueBody =>
      'Krytyczna recenzja jednej z Twoich notatek jest gotowa.';

  @override
  String get notifVesnaiReplied => 'VesnAI odpowiedziała';

  @override
  String get notifVesnaiRepliedBody => 'Nowa wiadomość czeka w czacie.';

  @override
  String get notifChatImageReady => 'Obraz w czacie gotowy';

  @override
  String get notifChatImageReadyBody => 'Wygenerowany obraz dodano do rozmowy.';

  @override
  String get notifImageGenFailedBody =>
      'Nie udało się wygenerować obrazu w czacie.';

  @override
  String get notifChatReplyFailed => 'Odpowiedź czatu nie powiodła się';

  @override
  String get notifChatReplyFailedBody =>
      'VesnAI nie mogła ukończyć odpowiedzi.';

  @override
  String get notifImageReady => 'Obraz gotowy';

  @override
  String get notifImageReadyBody => 'Wygenerowany obraz dodano do notatki.';

  @override
  String get notifEnrichmentReady => 'Wzbogacenie gotowe';

  @override
  String get notifEnrichmentReadyBody =>
      'Wygenerowaną notatkę dodano do grafu.';

  @override
  String get dueReviewTitle => 'Notatki do przejrzenia';

  @override
  String dueReviewSingle(String title) {
    return '\"$title\" czeka na przejrzenie.';
  }

  @override
  String dueReviewMultiple(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notatek czeka',
      few: '$count notatki czekają',
      one: '1 notatka czeka',
    );
    return '$_temp0 na przejrzenie.';
  }

  @override
  String get channelBgJobs => 'Zadania w tle';

  @override
  String get channelBgJobsDesc =>
      'Powiadamia o zakończeniu wyszukiwań i wzbogacania.';

  @override
  String get channelReminders => 'Przypomnienia';

  @override
  String get channelRemindersDesc =>
      'Zaplanowane przypomnienia (notatki do przejrzenia).';

  @override
  String get openShare => 'Otwórz / Udostępnij';

  @override
  String get shareSave => 'Udostępnij / Zapisz';

  @override
  String get addToNotes => 'Dodaj do notatek';

  @override
  String get connectToSaveToNotes =>
      'Połącz się z VesnAI, aby zapisać do notatek.';

  @override
  String get fullscreen => 'Pełny ekran';

  @override
  String get savedToNotes => 'Zapisano do notatek';

  @override
  String get couldNotSaveImageToNotes =>
      'Nie udało się zapisać obrazu do notatek.';

  @override
  String couldNotOpenLink(String href) {
    return 'Nie udało się otworzyć linku: $href';
  }

  @override
  String get clear => 'Wyczyść';

  @override
  String removeAttachment(String name) {
    return 'Usuń $name';
  }

  @override
  String get imageLabel => 'Obraz';

  @override
  String get bodyEditorHint => 'Co chcesz zapamiętać?';

  @override
  String get yourNote => 'Twoja notatka';

  @override
  String get pendingSyncLabel => 'oczekuje na synchronizację';

  @override
  String get doneLabel => 'ukończona';

  @override
  String get untitledPlain => 'bez tytułu';
}
