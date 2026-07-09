// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'VesnAI';

  @override
  String get navNotes => 'Notes';

  @override
  String get navChat => 'Chat';

  @override
  String get navGraph => 'Graph';

  @override
  String get navSettings => 'Settings';

  @override
  String get capture => 'Capture';

  @override
  String get sync => 'Sync';

  @override
  String get webSearch => 'Web search';

  @override
  String get notPaired => 'Offline - not paired';

  @override
  String get pairedPullToSync => 'Paired - pull to sync';

  @override
  String lastSynced(String when) {
    return 'Last synced $when';
  }

  @override
  String get emptyNotes => 'No notes yet. Tap + to capture your first thought.';

  @override
  String get onboardingTitle => 'Connect to your VesnAI server';

  @override
  String get onboardingBody =>
      'Your notes stay on your devices and server. Pair this device to sync, chat, search and more - or continue offline and pair later.';

  @override
  String get foundOnNetwork => 'Found on your network';

  @override
  String get searchingNetwork => 'Searching your network...';

  @override
  String get serverUrl => 'Server URL';

  @override
  String get pairingCode => 'Pairing code';

  @override
  String get scanQr => 'Scan QR';

  @override
  String get pair => 'Pair';

  @override
  String get continueOffline => 'Continue offline';

  @override
  String get unpairDevice => 'Unpair this device';

  @override
  String get connection => 'Connection';

  @override
  String get invalidCode => 'Invalid or expired pairing code.';

  @override
  String get unreachableServer =>
      'Could not reach the server. Check the URL and Wi-Fi.';

  @override
  String get pairingErrorTls =>
      'Secure connection failed (certificate not trusted). Use a server address with a trusted certificate, or install the server\'s certificate on this device.';

  @override
  String get pairingErrorServerUnreachable =>
      'Could not reach the server at that address. Check the URL, Wi-Fi, and that the server is running.';

  @override
  String get typeNote => 'Note';

  @override
  String get typeIdea => 'Idea';

  @override
  String get typeTask => 'Task';

  @override
  String get typePhoto => 'Photo';

  @override
  String get typeCritique => 'Critique';

  @override
  String get cancel => 'Cancel';

  @override
  String get retry => 'Retry';

  @override
  String get open => 'Open';

  @override
  String get ok => 'OK';

  @override
  String get skip => 'Skip';

  @override
  String get delete => 'Delete';

  @override
  String get save => 'Save';

  @override
  String get edit => 'Edit';

  @override
  String get view => 'View';

  @override
  String get dueForReview => 'Due for review';

  @override
  String get searchNotesHint => 'Search notes…';

  @override
  String get offlineChangesQueued => 'Offline - changes queued for next sync.';

  @override
  String syncedChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changes',
      one: '1 change',
    );
    return 'Synced ($_temp0 pushed).';
  }

  @override
  String get notesBusySyncing =>
      'Notes are busy syncing. Try again in a moment.';

  @override
  String get couldNotLoadNotes => 'Could not load notes.';

  @override
  String noNotesMatchQuery(String query) {
    return 'No notes match \"$query\".';
  }

  @override
  String get noNotesMatchTypes => 'No notes match the selected types.';

  @override
  String get justNow => 'just now';

  @override
  String minutesAgo(int minutes) {
    return '${minutes}m ago';
  }

  @override
  String hoursAgo(int hours) {
    return '${hours}h ago';
  }

  @override
  String daysAgo(int days) {
    return '${days}d ago';
  }

  @override
  String get noteScreenTitle => 'Note';

  @override
  String get aiGenerated => 'AI-generated';

  @override
  String get critiqueByMarena => 'Critique by Marena';

  @override
  String get critiquedNote => 'Critiqued note';

  @override
  String get critiques => 'Critiques';

  @override
  String get markDone => 'Mark done';

  @override
  String get reopen => 'Reopen';

  @override
  String get done => 'Done';

  @override
  String get showDone => 'Show done';

  @override
  String get markedDone => 'Marked as done';

  @override
  String get noteReopened => 'Reopened';

  @override
  String get filterAll => 'All';

  @override
  String get stopDictation => 'Stop dictation';

  @override
  String get formatting => 'Formatting';

  @override
  String get noteTypeSheetTitle => 'Note type';

  @override
  String get clearFilters => 'Clear filters';

  @override
  String get untitled => '(untitled)';

  @override
  String get titleLabel => 'Title';

  @override
  String get typeLabel => 'Type';

  @override
  String get tagsLabel => 'Tags (comma-separated)';

  @override
  String get bodyHint => 'Body';

  @override
  String get attachments => 'Attachments';

  @override
  String get generatedMemoryAid => 'Generated memory aid';

  @override
  String get enrichWithAi => 'Enrich with AI';

  @override
  String get noteNotFound => 'Note not found.';

  @override
  String get savedLocallyWillSync =>
      'Saved locally — will sync when your VesnAI server is back.';

  @override
  String get enrichRequested =>
      'Enrichment requested - the generated note will sync in.';

  @override
  String get enrichFailed => 'Enrichment failed.';

  @override
  String errorWithDetail(String error) {
    return 'Error: $error';
  }

  @override
  String get talkToVesnai => 'Talk to VesnAI';

  @override
  String get newChat => 'New chat';

  @override
  String get noConversationsYet => 'No conversations yet.';

  @override
  String get chatInputHint => 'Ask, recall, or create...';

  @override
  String get listening => 'Listening…';

  @override
  String get startingNewChat => 'Starting new chat…';

  @override
  String get sendingStatus => 'Sending…';

  @override
  String get vesnaiThinking => 'VesnAI is thinking…';

  @override
  String get thinking => 'Thinking…';

  @override
  String get generatingImage => 'Generating image…';

  @override
  String get imageGenerationFailed => 'Image generation failed';

  @override
  String get retryImage => 'Retry image';

  @override
  String get notSent => 'Not sent';

  @override
  String get attach => 'Attach';

  @override
  String get speak => 'Speak';

  @override
  String get stopAndSend => 'Stop & send';

  @override
  String get replay => 'Replay';

  @override
  String get camera => 'Camera';

  @override
  String get gallery => 'Gallery';

  @override
  String get file => 'File';

  @override
  String get voiceNote => 'Voice note';

  @override
  String get noteSaved => 'Note saved';

  @override
  String couldNotSendMessage(String error) {
    return 'Could not send message: $error';
  }

  @override
  String get speechUnavailable =>
      'Speech recognition is unavailable on this device.';

  @override
  String get addTag => 'Add tag';

  @override
  String get suggestTags => 'Suggest tags';

  @override
  String get photo => 'Photo';

  @override
  String get attachFile => 'Attach file';

  @override
  String get draw => 'Draw';

  @override
  String uploadingPhoto(int current, int total) {
    return 'Uploading photo $current of $total…';
  }

  @override
  String get attachmentsNeedServer =>
      'Attachments need a paired server; saved text only.';

  @override
  String get savedLocallyShort =>
      'Saved locally — will sync when your server is back.';

  @override
  String couldNotSaveNote(String error) {
    return 'Could not save note: $error';
  }

  @override
  String get tagSuggestionsNeedServer =>
      'Tag suggestions need a paired server.';

  @override
  String couldNotSuggestTags(String error) {
    return 'Could not suggest tags: $error';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get sectionServer => 'Server';

  @override
  String get sectionModelsPrivacy => 'Models & privacy';

  @override
  String get sectionAssistant => 'Assistant';

  @override
  String get sectionApp => 'App';

  @override
  String get sectionModels => 'Models';

  @override
  String get sectionSearch => 'Search';

  @override
  String get sectionData => 'Data';

  @override
  String get notPairedShort => 'Not paired';

  @override
  String get localOnlyMode => 'Local-only mode';

  @override
  String get loadingServerSettings => 'Loading server settings...';

  @override
  String get pairToViewPrivacy =>
      'Pair with a server to view privacy settings.';

  @override
  String get localOnlySubtitle =>
      'Never call external APIs (configured on the server).';

  @override
  String get assistantLanguage => 'Assistant language';

  @override
  String get assistantLanguageAuto => 'Auto (from chat)';

  @override
  String get appLanguage => 'App language';

  @override
  String get appLanguageSystem => 'System default';

  @override
  String get readRepliesAloud => 'Read replies aloud';

  @override
  String get readRepliesAloudSubtitle => 'When Chat is open and volume is up';

  @override
  String get shareLocationWithChat => 'Share location with chat';

  @override
  String get shareLocationSubtitle =>
      'Approximate GPS for local queries (weather, nearby). Sent per message only when enabled.';

  @override
  String get voiceService => 'Voice service';

  @override
  String get voiceServicePairFirst => 'Pair a server to register voice.';

  @override
  String voiceServiceRegistered(String provider) {
    return 'Registered ($provider) — Speak enabled';
  }

  @override
  String get voiceServiceNotRegistered =>
      'Register OpenAI or a TTS sidecar to enable Speak';

  @override
  String get externalApiKeys => 'External API keys';

  @override
  String get externalApiKeysSubtitle =>
      'Stored encrypted on the server; never in backups.';

  @override
  String get externalApiKeysPairFirst => 'Pair a server to manage keys.';

  @override
  String get chatModel => 'Chat model';

  @override
  String get languages => 'Languages';

  @override
  String get backUpKnowledge => 'Back up knowledge';

  @override
  String get backUpSubtitle => 'Download an encrypted copy of your notes.';

  @override
  String get restoreFromBackup => 'Restore from backup';

  @override
  String backupFailed(String error) {
    return 'Backup failed: $error';
  }

  @override
  String restoreFailed(String error) {
    return 'Restore failed: $error';
  }

  @override
  String get restoredFromBackup => 'Restored from backup.';

  @override
  String get backupPassphraseOptional => 'Backup passphrase (optional)';

  @override
  String get backupPassphraseRequired => 'Backup passphrase (required)';

  @override
  String get passphrase => 'Passphrase';

  @override
  String get unpairQuestion => 'Unpair device?';

  @override
  String get unpairExplanation =>
      'This removes the saved connection and revokes this device on the server. Your local notes stay on this device.';

  @override
  String get unpair => 'Unpair';

  @override
  String get pairDialogTitle => 'Pair with VesnAI server';

  @override
  String get pairedWithServer => 'Paired with server.';

  @override
  String get enterValidServerUrl => 'Enter a valid server URL.';

  @override
  String get newSticky => 'New sticky';

  @override
  String get newNote => 'New note';

  @override
  String get noNotesYet => 'No notes yet.';

  @override
  String get refresh => 'Refresh';

  @override
  String get unpairedBannerText =>
      'Not paired — pair with your VesnAI server to sync, chat and search.';

  @override
  String get knowledgeGraph => 'Knowledge graph';

  @override
  String get graphOffline => 'Offline — showing local notes only.';

  @override
  String graphRefreshed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changes',
      one: '1 change',
    );
    return 'Graph refreshed ($_temp0 pushed).';
  }

  @override
  String get graphNoNotesMatchFilters => 'No notes match the current filters.';

  @override
  String get graphNoNotes => 'No notes to graph yet.';

  @override
  String get graphSemantics =>
      'Interactive knowledge graph. Drag to move, pinch to zoom, tap a node to open the note.';

  @override
  String get tagsFilterLabel => 'Tags';

  @override
  String tagsFilterLabelCount(int count) {
    return 'Tags ($count)';
  }

  @override
  String get filterMine => 'Mine';

  @override
  String get showAll => 'Show all';

  @override
  String get filterByTag => 'Filter by tag';

  @override
  String get selectedLabel => 'Selected';

  @override
  String get noTagsYet => 'No tags yet';

  @override
  String get allTagsSelected => 'All tags selected';

  @override
  String get clearTags => 'Clear tags';

  @override
  String get searchFailed => 'Search failed.';

  @override
  String searchFailedWithError(String error) {
    return 'Search failed: $error';
  }

  @override
  String get researchReady => 'Research ready';

  @override
  String get researchReadyBody => 'Your search results are saved as a note.';

  @override
  String get pairForWebSearch => 'Pair with your server to run web searches.';

  @override
  String get researchPrompt => 'What do you want to research?';

  @override
  String timeBudget(int seconds) {
    return 'Time budget: ${seconds}s';
  }

  @override
  String get researching => 'Researching...';

  @override
  String get searchAction => 'Search';

  @override
  String get scanPairingQr => 'Scan pairing QR';

  @override
  String get cameraPermissionDenied =>
      'Camera permission was denied. Allow camera access in Settings, then tap Retry.';

  @override
  String get cameraUnavailable => 'Camera unavailable';

  @override
  String get noApiKeysStored => 'No API keys stored.';

  @override
  String get addApiKey => 'Add API key';

  @override
  String get apiKeyNameLabel => 'Name (e.g. openai)';

  @override
  String get apiKeyValueLabel => 'Value';

  @override
  String get providerTtsSidecar => 'TTS sidecar (self-hosted)';

  @override
  String get apiKeyRequired => 'API key is required.';

  @override
  String get sidecarUrlRequired => 'Sidecar URL is required.';

  @override
  String get voiceIdsRequired =>
      'Voice IDs are required (they depend on your TTS engine).';

  @override
  String get voiceServiceRegisteredSnack => 'Voice service registered.';

  @override
  String registrationFailed(String error) {
    return 'Registration failed: $error';
  }

  @override
  String get voiceServiceRemoved => 'Voice service removed.';

  @override
  String removeFailed(String error) {
    return 'Remove failed: $error';
  }

  @override
  String get voiceServiceIntroConfigured =>
      'Speech (Speak) uses the registered provider below. Switch provider anytime — no server reinstall needed.';

  @override
  String get voiceServiceIntroUnconfigured =>
      'Register OpenAI or a self-hosted TTS sidecar to enable Speak in chat.';

  @override
  String get providerLabel => 'Provider';

  @override
  String get sidecarUrl => 'Sidecar URL';

  @override
  String get sidecarContractHelp =>
      'Any HTTP service implementing the VesnAI TTS contract works (see docs/TTS_SIDECAR.md in the project).';

  @override
  String get openaiApiKey => 'OpenAI API key';

  @override
  String get openaiApiKeyUpdate => 'OpenAI API key (re-enter to update)';

  @override
  String get sidecarApiKey => 'Sidecar API key';

  @override
  String get sidecarApiKeyUpdate => 'API key (re-enter to update)';

  @override
  String get openaiModel => 'OpenAI model';

  @override
  String get polishVoiceOpenai => 'Polish voice (OpenAI id)';

  @override
  String get polishVoiceId => 'Polish voice id';

  @override
  String get englishVoiceOpenai => 'English voice (OpenAI id)';

  @override
  String get englishVoiceId => 'English voice id';

  @override
  String get voiceIdHint => 'voice ID from your TTS engine';

  @override
  String get updateRegistration => 'Update registration';

  @override
  String get register => 'Register';

  @override
  String get removeVoiceService => 'Remove voice service';

  @override
  String get deleteNoteQuestion => 'Delete note?';

  @override
  String deleteNoteConfirm(String title) {
    return 'Delete \"$title\"? This cannot be undone.';
  }

  @override
  String get deleteNoteSyncNote =>
      'This note will be removed from this device and synced to the server when online.';

  @override
  String get replyDidNotFinish =>
      'This reply did not finish. Send your message again.';

  @override
  String couldNotSendTapRetryStatus(int status) {
    return 'Could not send message ($status). Tap Retry on the message.';
  }

  @override
  String get couldNotSendTapRetry =>
      'Could not send message. Tap Retry on the message.';

  @override
  String get connectToSendAttachments =>
      'Connect to your VesnAI server to send attachments.';

  @override
  String get connectToChat => 'Connect to your VesnAI server to chat.';

  @override
  String get ttsNeedsServer => 'Speech synthesis needs a paired server.';

  @override
  String get ttsRegisterFirst =>
      'Register a voice service in Settings to use Speak.';

  @override
  String get ttsFailed => 'Speech synthesis failed.';

  @override
  String get ttsApiKeyRejected =>
      'Voice service rejected the API key. Update it in Settings → Voice service.';

  @override
  String ttsVoiceServiceError(String detail) {
    return 'Speech synthesis failed: $detail';
  }

  @override
  String get uploadSessionNotFound =>
      'Chat session not found on the server. Start a new chat and try again.';

  @override
  String get uploadTooLarge =>
      'Photo is too large for the server. Try a smaller image.';

  @override
  String uploadConnectionDropped(String filename) {
    return 'Connection dropped while uploading $filename. Check Wi-Fi and try again.';
  }

  @override
  String uploadFailed(String filename, String error) {
    return 'Could not upload $filename: $error';
  }

  @override
  String get notifMarenaCritique => 'Marena left a critique';

  @override
  String get notifMarenaCritiqueBody =>
      'A critical review of one of your notes is ready.';

  @override
  String get notifVesnaiReplied => 'VesnAI replied';

  @override
  String get notifVesnaiRepliedBody => 'A new message is ready in your chat.';

  @override
  String get notifChatImageReady => 'Chat image ready';

  @override
  String get notifChatImageReadyBody =>
      'A generated image was added to your conversation.';

  @override
  String get notifImageGenFailedBody => 'Could not generate the chat image.';

  @override
  String get notifChatReplyFailed => 'Chat reply failed';

  @override
  String get notifChatReplyFailedBody => 'VesnAI could not complete a reply.';

  @override
  String get notifImageReady => 'Image ready';

  @override
  String get notifImageReadyBody => 'A generated image was added to your note.';

  @override
  String get notifEnrichmentReady => 'Enrichment ready';

  @override
  String get notifEnrichmentReadyBody =>
      'A generated note was added to your graph.';

  @override
  String get dueReviewTitle => 'Notes due for review';

  @override
  String dueReviewSingle(String title) {
    return '\"$title\" is due for review.';
  }

  @override
  String dueReviewMultiple(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notes are',
      one: '1 note is',
    );
    return '$_temp0 due for review.';
  }

  @override
  String get channelBgJobs => 'Background jobs';

  @override
  String get channelBgJobsDesc =>
      'Notifies when searches and enrichment finish.';

  @override
  String get channelReminders => 'Reminders';

  @override
  String get channelRemindersDesc =>
      'Scheduled reminders (notes due for review).';

  @override
  String get openShare => 'Open / Share';

  @override
  String get shareSave => 'Share / Save';

  @override
  String get addToNotes => 'Add to notes';

  @override
  String get connectToSaveToNotes => 'Connect to VesnAI to save to notes.';

  @override
  String get fullscreen => 'Fullscreen';

  @override
  String get savedToNotes => 'Saved to notes';

  @override
  String get couldNotSaveImageToNotes => 'Could not save image to notes.';

  @override
  String couldNotOpenLink(String href) {
    return 'Could not open link: $href';
  }

  @override
  String get clear => 'Clear';

  @override
  String removeAttachment(String name) {
    return 'Remove $name';
  }

  @override
  String get imageLabel => 'Image';

  @override
  String get bodyEditorHint => 'What do you want to remember?';

  @override
  String get yourNote => 'Your note';

  @override
  String get pendingSyncLabel => 'pending sync';

  @override
  String get doneLabel => 'done';

  @override
  String get untitledPlain => 'untitled';
}
