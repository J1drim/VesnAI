import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_pl.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('pl'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'VesnAI'**
  String get appTitle;

  /// No description provided for @navNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get navNotes;

  /// No description provided for @navChat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get navChat;

  /// No description provided for @navGraph.
  ///
  /// In en, this message translates to:
  /// **'Graph'**
  String get navGraph;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @capture.
  ///
  /// In en, this message translates to:
  /// **'Capture'**
  String get capture;

  /// No description provided for @sync.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get sync;

  /// No description provided for @webSearch.
  ///
  /// In en, this message translates to:
  /// **'Web search'**
  String get webSearch;

  /// No description provided for @notPaired.
  ///
  /// In en, this message translates to:
  /// **'Offline - not paired'**
  String get notPaired;

  /// No description provided for @pairedPullToSync.
  ///
  /// In en, this message translates to:
  /// **'Paired - pull to sync'**
  String get pairedPullToSync;

  /// No description provided for @lastSynced.
  ///
  /// In en, this message translates to:
  /// **'Last synced {when}'**
  String lastSynced(String when);

  /// No description provided for @emptyNotes.
  ///
  /// In en, this message translates to:
  /// **'No notes yet. Tap + to capture your first thought.'**
  String get emptyNotes;

  /// No description provided for @onboardingTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect to your VesnAI server'**
  String get onboardingTitle;

  /// No description provided for @onboardingBody.
  ///
  /// In en, this message translates to:
  /// **'Your notes stay on your devices and server. Pair this device to sync, chat, search and more - or continue offline and pair later.'**
  String get onboardingBody;

  /// No description provided for @foundOnNetwork.
  ///
  /// In en, this message translates to:
  /// **'Found on your network'**
  String get foundOnNetwork;

  /// No description provided for @searchingNetwork.
  ///
  /// In en, this message translates to:
  /// **'Searching your network...'**
  String get searchingNetwork;

  /// No description provided for @serverUrl.
  ///
  /// In en, this message translates to:
  /// **'Server URL'**
  String get serverUrl;

  /// No description provided for @pairingCode.
  ///
  /// In en, this message translates to:
  /// **'Pairing code'**
  String get pairingCode;

  /// No description provided for @scanQr.
  ///
  /// In en, this message translates to:
  /// **'Scan QR'**
  String get scanQr;

  /// No description provided for @pair.
  ///
  /// In en, this message translates to:
  /// **'Pair'**
  String get pair;

  /// No description provided for @continueOffline.
  ///
  /// In en, this message translates to:
  /// **'Continue offline'**
  String get continueOffline;

  /// No description provided for @unpairDevice.
  ///
  /// In en, this message translates to:
  /// **'Unpair this device'**
  String get unpairDevice;

  /// No description provided for @connection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get connection;

  /// No description provided for @invalidCode.
  ///
  /// In en, this message translates to:
  /// **'Invalid or expired pairing code.'**
  String get invalidCode;

  /// No description provided for @unreachableServer.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the server. Check the URL and Wi-Fi.'**
  String get unreachableServer;

  /// No description provided for @pairingErrorTls.
  ///
  /// In en, this message translates to:
  /// **'Secure connection failed (certificate not trusted). Use a server address with a trusted certificate, or install the server\'s certificate on this device.'**
  String get pairingErrorTls;

  /// No description provided for @pairingErrorServerUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the server at that address. Check the URL, Wi-Fi, and that the server is running.'**
  String get pairingErrorServerUnreachable;

  /// No description provided for @typeNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get typeNote;

  /// No description provided for @typeIdea.
  ///
  /// In en, this message translates to:
  /// **'Idea'**
  String get typeIdea;

  /// No description provided for @typeTask.
  ///
  /// In en, this message translates to:
  /// **'Task'**
  String get typeTask;

  /// No description provided for @typePhoto.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get typePhoto;

  /// No description provided for @typeCritique.
  ///
  /// In en, this message translates to:
  /// **'Critique'**
  String get typeCritique;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @view.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get view;

  /// No description provided for @dueForReview.
  ///
  /// In en, this message translates to:
  /// **'Due for review'**
  String get dueForReview;

  /// No description provided for @searchNotesHint.
  ///
  /// In en, this message translates to:
  /// **'Search notes…'**
  String get searchNotesHint;

  /// No description provided for @offlineChangesQueued.
  ///
  /// In en, this message translates to:
  /// **'Offline - changes queued for next sync.'**
  String get offlineChangesQueued;

  /// No description provided for @syncedChanges.
  ///
  /// In en, this message translates to:
  /// **'Synced ({count, plural, =1{1 change} other{{count} changes}} pushed).'**
  String syncedChanges(int count);

  /// No description provided for @notesBusySyncing.
  ///
  /// In en, this message translates to:
  /// **'Notes are busy syncing. Try again in a moment.'**
  String get notesBusySyncing;

  /// No description provided for @couldNotLoadNotes.
  ///
  /// In en, this message translates to:
  /// **'Could not load notes.'**
  String get couldNotLoadNotes;

  /// No description provided for @noNotesMatchQuery.
  ///
  /// In en, this message translates to:
  /// **'No notes match \"{query}\".'**
  String noNotesMatchQuery(String query);

  /// No description provided for @noNotesMatchTypes.
  ///
  /// In en, this message translates to:
  /// **'No notes match the selected types.'**
  String get noNotesMatchTypes;

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get justNow;

  /// No description provided for @minutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m ago'**
  String minutesAgo(int minutes);

  /// No description provided for @hoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{hours}h ago'**
  String hoursAgo(int hours);

  /// No description provided for @daysAgo.
  ///
  /// In en, this message translates to:
  /// **'{days}d ago'**
  String daysAgo(int days);

  /// No description provided for @noteScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get noteScreenTitle;

  /// No description provided for @aiGenerated.
  ///
  /// In en, this message translates to:
  /// **'AI-generated'**
  String get aiGenerated;

  /// No description provided for @critiqueByMarena.
  ///
  /// In en, this message translates to:
  /// **'Critique by Marena'**
  String get critiqueByMarena;

  /// No description provided for @critiquedNote.
  ///
  /// In en, this message translates to:
  /// **'Critiqued note'**
  String get critiquedNote;

  /// No description provided for @critiques.
  ///
  /// In en, this message translates to:
  /// **'Critiques'**
  String get critiques;

  /// No description provided for @markDone.
  ///
  /// In en, this message translates to:
  /// **'Mark done'**
  String get markDone;

  /// No description provided for @reopen.
  ///
  /// In en, this message translates to:
  /// **'Reopen'**
  String get reopen;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @showDone.
  ///
  /// In en, this message translates to:
  /// **'Show done'**
  String get showDone;

  /// No description provided for @markedDone.
  ///
  /// In en, this message translates to:
  /// **'Marked as done'**
  String get markedDone;

  /// No description provided for @noteReopened.
  ///
  /// In en, this message translates to:
  /// **'Reopened'**
  String get noteReopened;

  /// No description provided for @filterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filterAll;

  /// No description provided for @stopDictation.
  ///
  /// In en, this message translates to:
  /// **'Stop dictation'**
  String get stopDictation;

  /// No description provided for @formatting.
  ///
  /// In en, this message translates to:
  /// **'Formatting'**
  String get formatting;

  /// No description provided for @noteTypeSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Note type'**
  String get noteTypeSheetTitle;

  /// No description provided for @clearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get clearFilters;

  /// No description provided for @untitled.
  ///
  /// In en, this message translates to:
  /// **'(untitled)'**
  String get untitled;

  /// No description provided for @titleLabel.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get titleLabel;

  /// No description provided for @typeLabel.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get typeLabel;

  /// No description provided for @tagsLabel.
  ///
  /// In en, this message translates to:
  /// **'Tags (comma-separated)'**
  String get tagsLabel;

  /// No description provided for @bodyHint.
  ///
  /// In en, this message translates to:
  /// **'Body'**
  String get bodyHint;

  /// No description provided for @attachments.
  ///
  /// In en, this message translates to:
  /// **'Attachments'**
  String get attachments;

  /// No description provided for @generatedMemoryAid.
  ///
  /// In en, this message translates to:
  /// **'Generated memory aid'**
  String get generatedMemoryAid;

  /// No description provided for @enrichWithAi.
  ///
  /// In en, this message translates to:
  /// **'Enrich with AI'**
  String get enrichWithAi;

  /// No description provided for @noteNotFound.
  ///
  /// In en, this message translates to:
  /// **'Note not found.'**
  String get noteNotFound;

  /// No description provided for @savedLocallyWillSync.
  ///
  /// In en, this message translates to:
  /// **'Saved locally — will sync when your VesnAI server is back.'**
  String get savedLocallyWillSync;

  /// No description provided for @enrichRequested.
  ///
  /// In en, this message translates to:
  /// **'Enrichment requested - the generated note will sync in.'**
  String get enrichRequested;

  /// No description provided for @enrichFailed.
  ///
  /// In en, this message translates to:
  /// **'Enrichment failed.'**
  String get enrichFailed;

  /// No description provided for @errorWithDetail.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String errorWithDetail(String error);

  /// No description provided for @talkToVesnai.
  ///
  /// In en, this message translates to:
  /// **'Talk to VesnAI'**
  String get talkToVesnai;

  /// No description provided for @newChat.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get newChat;

  /// No description provided for @noConversationsYet.
  ///
  /// In en, this message translates to:
  /// **'No conversations yet.'**
  String get noConversationsYet;

  /// No description provided for @chatInputHint.
  ///
  /// In en, this message translates to:
  /// **'Ask, recall, or create...'**
  String get chatInputHint;

  /// No description provided for @listening.
  ///
  /// In en, this message translates to:
  /// **'Listening…'**
  String get listening;

  /// No description provided for @startingNewChat.
  ///
  /// In en, this message translates to:
  /// **'Starting new chat…'**
  String get startingNewChat;

  /// No description provided for @sendingStatus.
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get sendingStatus;

  /// No description provided for @vesnaiThinking.
  ///
  /// In en, this message translates to:
  /// **'VesnAI is thinking…'**
  String get vesnaiThinking;

  /// No description provided for @thinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking…'**
  String get thinking;

  /// No description provided for @generatingImage.
  ///
  /// In en, this message translates to:
  /// **'Generating image…'**
  String get generatingImage;

  /// No description provided for @imageGenerationFailed.
  ///
  /// In en, this message translates to:
  /// **'Image generation failed'**
  String get imageGenerationFailed;

  /// No description provided for @retryImage.
  ///
  /// In en, this message translates to:
  /// **'Retry image'**
  String get retryImage;

  /// No description provided for @notSent.
  ///
  /// In en, this message translates to:
  /// **'Not sent'**
  String get notSent;

  /// No description provided for @attach.
  ///
  /// In en, this message translates to:
  /// **'Attach'**
  String get attach;

  /// No description provided for @speak.
  ///
  /// In en, this message translates to:
  /// **'Speak'**
  String get speak;

  /// No description provided for @stopAndSend.
  ///
  /// In en, this message translates to:
  /// **'Stop & send'**
  String get stopAndSend;

  /// No description provided for @replay.
  ///
  /// In en, this message translates to:
  /// **'Replay'**
  String get replay;

  /// No description provided for @camera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get camera;

  /// No description provided for @gallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get gallery;

  /// No description provided for @file.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get file;

  /// No description provided for @voiceNote.
  ///
  /// In en, this message translates to:
  /// **'Voice note'**
  String get voiceNote;

  /// No description provided for @noteSaved.
  ///
  /// In en, this message translates to:
  /// **'Note saved'**
  String get noteSaved;

  /// No description provided for @couldNotSendMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not send message: {error}'**
  String couldNotSendMessage(String error);

  /// No description provided for @speechUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Speech recognition is unavailable on this device.'**
  String get speechUnavailable;

  /// No description provided for @addTag.
  ///
  /// In en, this message translates to:
  /// **'Add tag'**
  String get addTag;

  /// No description provided for @suggestTags.
  ///
  /// In en, this message translates to:
  /// **'Suggest tags'**
  String get suggestTags;

  /// No description provided for @photo.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get photo;

  /// No description provided for @attachFile.
  ///
  /// In en, this message translates to:
  /// **'Attach file'**
  String get attachFile;

  /// No description provided for @draw.
  ///
  /// In en, this message translates to:
  /// **'Draw'**
  String get draw;

  /// No description provided for @uploadingPhoto.
  ///
  /// In en, this message translates to:
  /// **'Uploading photo {current} of {total}…'**
  String uploadingPhoto(int current, int total);

  /// No description provided for @attachmentsNeedServer.
  ///
  /// In en, this message translates to:
  /// **'Attachments need a paired server; saved text only.'**
  String get attachmentsNeedServer;

  /// No description provided for @savedLocallyShort.
  ///
  /// In en, this message translates to:
  /// **'Saved locally — will sync when your server is back.'**
  String get savedLocallyShort;

  /// No description provided for @couldNotSaveNote.
  ///
  /// In en, this message translates to:
  /// **'Could not save note: {error}'**
  String couldNotSaveNote(String error);

  /// No description provided for @tagSuggestionsNeedServer.
  ///
  /// In en, this message translates to:
  /// **'Tag suggestions need a paired server.'**
  String get tagSuggestionsNeedServer;

  /// No description provided for @couldNotSuggestTags.
  ///
  /// In en, this message translates to:
  /// **'Could not suggest tags: {error}'**
  String couldNotSuggestTags(String error);

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @sectionServer.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get sectionServer;

  /// No description provided for @sectionModelsPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Models & privacy'**
  String get sectionModelsPrivacy;

  /// No description provided for @sectionAssistant.
  ///
  /// In en, this message translates to:
  /// **'Assistant'**
  String get sectionAssistant;

  /// No description provided for @sectionApp.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get sectionApp;

  /// No description provided for @sectionModels.
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get sectionModels;

  /// No description provided for @sectionSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get sectionSearch;

  /// No description provided for @sectionData.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get sectionData;

  /// No description provided for @notPairedShort.
  ///
  /// In en, this message translates to:
  /// **'Not paired'**
  String get notPairedShort;

  /// No description provided for @localOnlyMode.
  ///
  /// In en, this message translates to:
  /// **'Local-only mode'**
  String get localOnlyMode;

  /// No description provided for @loadingServerSettings.
  ///
  /// In en, this message translates to:
  /// **'Loading server settings...'**
  String get loadingServerSettings;

  /// No description provided for @pairToViewPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Pair with a server to view privacy settings.'**
  String get pairToViewPrivacy;

  /// No description provided for @localOnlySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Never call external APIs (configured on the server).'**
  String get localOnlySubtitle;

  /// No description provided for @assistantLanguage.
  ///
  /// In en, this message translates to:
  /// **'Assistant language'**
  String get assistantLanguage;

  /// No description provided for @assistantLanguageAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto (from chat)'**
  String get assistantLanguageAuto;

  /// No description provided for @appLanguage.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get appLanguage;

  /// No description provided for @appLanguageSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get appLanguageSystem;

  /// No description provided for @readRepliesAloud.
  ///
  /// In en, this message translates to:
  /// **'Read replies aloud'**
  String get readRepliesAloud;

  /// No description provided for @readRepliesAloudSubtitle.
  ///
  /// In en, this message translates to:
  /// **'When Chat is open and volume is up'**
  String get readRepliesAloudSubtitle;

  /// No description provided for @shareLocationWithChat.
  ///
  /// In en, this message translates to:
  /// **'Share location with chat'**
  String get shareLocationWithChat;

  /// No description provided for @shareLocationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Approximate GPS for local queries (weather, nearby). Sent per message only when enabled.'**
  String get shareLocationSubtitle;

  /// No description provided for @voiceService.
  ///
  /// In en, this message translates to:
  /// **'Voice service'**
  String get voiceService;

  /// No description provided for @voiceServicePairFirst.
  ///
  /// In en, this message translates to:
  /// **'Pair a server to register voice.'**
  String get voiceServicePairFirst;

  /// No description provided for @voiceServiceRegistered.
  ///
  /// In en, this message translates to:
  /// **'Registered ({provider}) — Speak enabled'**
  String voiceServiceRegistered(String provider);

  /// No description provided for @voiceServiceNotRegistered.
  ///
  /// In en, this message translates to:
  /// **'Register OpenAI or a TTS sidecar to enable Speak'**
  String get voiceServiceNotRegistered;

  /// No description provided for @externalApiKeys.
  ///
  /// In en, this message translates to:
  /// **'External API keys'**
  String get externalApiKeys;

  /// No description provided for @externalApiKeysSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Stored encrypted on the server; never in backups.'**
  String get externalApiKeysSubtitle;

  /// No description provided for @externalApiKeysPairFirst.
  ///
  /// In en, this message translates to:
  /// **'Pair a server to manage keys.'**
  String get externalApiKeysPairFirst;

  /// No description provided for @chatModel.
  ///
  /// In en, this message translates to:
  /// **'Chat model'**
  String get chatModel;

  /// No description provided for @languages.
  ///
  /// In en, this message translates to:
  /// **'Languages'**
  String get languages;

  /// No description provided for @backUpKnowledge.
  ///
  /// In en, this message translates to:
  /// **'Back up knowledge'**
  String get backUpKnowledge;

  /// No description provided for @backUpSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Download an encrypted copy of your notes.'**
  String get backUpSubtitle;

  /// No description provided for @restoreFromBackup.
  ///
  /// In en, this message translates to:
  /// **'Restore from backup'**
  String get restoreFromBackup;

  /// No description provided for @backupFailed.
  ///
  /// In en, this message translates to:
  /// **'Backup failed: {error}'**
  String backupFailed(String error);

  /// No description provided for @restoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Restore failed: {error}'**
  String restoreFailed(String error);

  /// No description provided for @restoredFromBackup.
  ///
  /// In en, this message translates to:
  /// **'Restored from backup.'**
  String get restoredFromBackup;

  /// No description provided for @backupPassphraseOptional.
  ///
  /// In en, this message translates to:
  /// **'Backup passphrase (optional)'**
  String get backupPassphraseOptional;

  /// No description provided for @backupPassphraseRequired.
  ///
  /// In en, this message translates to:
  /// **'Backup passphrase (required)'**
  String get backupPassphraseRequired;

  /// No description provided for @passphrase.
  ///
  /// In en, this message translates to:
  /// **'Passphrase'**
  String get passphrase;

  /// No description provided for @unpairQuestion.
  ///
  /// In en, this message translates to:
  /// **'Unpair device?'**
  String get unpairQuestion;

  /// No description provided for @unpairExplanation.
  ///
  /// In en, this message translates to:
  /// **'This removes the saved connection and revokes this device on the server. Your local notes stay on this device.'**
  String get unpairExplanation;

  /// No description provided for @unpair.
  ///
  /// In en, this message translates to:
  /// **'Unpair'**
  String get unpair;

  /// No description provided for @pairDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Pair with VesnAI server'**
  String get pairDialogTitle;

  /// No description provided for @pairedWithServer.
  ///
  /// In en, this message translates to:
  /// **'Paired with server.'**
  String get pairedWithServer;

  /// No description provided for @enterValidServerUrl.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid server URL.'**
  String get enterValidServerUrl;

  /// No description provided for @newSticky.
  ///
  /// In en, this message translates to:
  /// **'New sticky'**
  String get newSticky;

  /// No description provided for @newNote.
  ///
  /// In en, this message translates to:
  /// **'New note'**
  String get newNote;

  /// No description provided for @noNotesYet.
  ///
  /// In en, this message translates to:
  /// **'No notes yet.'**
  String get noNotesYet;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @unpairedBannerText.
  ///
  /// In en, this message translates to:
  /// **'Not paired — pair with your VesnAI server to sync, chat and search.'**
  String get unpairedBannerText;

  /// No description provided for @knowledgeGraph.
  ///
  /// In en, this message translates to:
  /// **'Knowledge graph'**
  String get knowledgeGraph;

  /// No description provided for @graphOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline — showing local notes only.'**
  String get graphOffline;

  /// No description provided for @graphRefreshed.
  ///
  /// In en, this message translates to:
  /// **'Graph refreshed ({count, plural, =1{1 change} other{{count} changes}} pushed).'**
  String graphRefreshed(int count);

  /// No description provided for @graphNoNotesMatchFilters.
  ///
  /// In en, this message translates to:
  /// **'No notes match the current filters.'**
  String get graphNoNotesMatchFilters;

  /// No description provided for @graphNoNotes.
  ///
  /// In en, this message translates to:
  /// **'No notes to graph yet.'**
  String get graphNoNotes;

  /// No description provided for @graphSemantics.
  ///
  /// In en, this message translates to:
  /// **'Interactive knowledge graph. Drag to move, pinch to zoom, tap a node to open the note.'**
  String get graphSemantics;

  /// No description provided for @tagsFilterLabel.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tagsFilterLabel;

  /// No description provided for @tagsFilterLabelCount.
  ///
  /// In en, this message translates to:
  /// **'Tags ({count})'**
  String tagsFilterLabelCount(int count);

  /// No description provided for @filterMine.
  ///
  /// In en, this message translates to:
  /// **'Mine'**
  String get filterMine;

  /// No description provided for @showAll.
  ///
  /// In en, this message translates to:
  /// **'Show all'**
  String get showAll;

  /// No description provided for @filterByTag.
  ///
  /// In en, this message translates to:
  /// **'Filter by tag'**
  String get filterByTag;

  /// No description provided for @selectedLabel.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get selectedLabel;

  /// No description provided for @noTagsYet.
  ///
  /// In en, this message translates to:
  /// **'No tags yet'**
  String get noTagsYet;

  /// No description provided for @allTagsSelected.
  ///
  /// In en, this message translates to:
  /// **'All tags selected'**
  String get allTagsSelected;

  /// No description provided for @clearTags.
  ///
  /// In en, this message translates to:
  /// **'Clear tags'**
  String get clearTags;

  /// No description provided for @searchFailed.
  ///
  /// In en, this message translates to:
  /// **'Search failed.'**
  String get searchFailed;

  /// No description provided for @searchFailedWithError.
  ///
  /// In en, this message translates to:
  /// **'Search failed: {error}'**
  String searchFailedWithError(String error);

  /// No description provided for @researchReady.
  ///
  /// In en, this message translates to:
  /// **'Research ready'**
  String get researchReady;

  /// No description provided for @researchReadyBody.
  ///
  /// In en, this message translates to:
  /// **'Your search results are saved as a note.'**
  String get researchReadyBody;

  /// No description provided for @pairForWebSearch.
  ///
  /// In en, this message translates to:
  /// **'Pair with your server to run web searches.'**
  String get pairForWebSearch;

  /// No description provided for @researchPrompt.
  ///
  /// In en, this message translates to:
  /// **'What do you want to research?'**
  String get researchPrompt;

  /// No description provided for @timeBudget.
  ///
  /// In en, this message translates to:
  /// **'Time budget: {seconds}s'**
  String timeBudget(int seconds);

  /// No description provided for @researching.
  ///
  /// In en, this message translates to:
  /// **'Researching...'**
  String get researching;

  /// No description provided for @searchAction.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchAction;

  /// No description provided for @scanPairingQr.
  ///
  /// In en, this message translates to:
  /// **'Scan pairing QR'**
  String get scanPairingQr;

  /// No description provided for @cameraPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Camera permission was denied. Allow camera access in Settings, then tap Retry.'**
  String get cameraPermissionDenied;

  /// No description provided for @cameraUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Camera unavailable'**
  String get cameraUnavailable;

  /// No description provided for @noApiKeysStored.
  ///
  /// In en, this message translates to:
  /// **'No API keys stored.'**
  String get noApiKeysStored;

  /// No description provided for @addApiKey.
  ///
  /// In en, this message translates to:
  /// **'Add API key'**
  String get addApiKey;

  /// No description provided for @apiKeyNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name (e.g. openai)'**
  String get apiKeyNameLabel;

  /// No description provided for @apiKeyValueLabel.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get apiKeyValueLabel;

  /// No description provided for @providerTtsSidecar.
  ///
  /// In en, this message translates to:
  /// **'TTS sidecar (self-hosted)'**
  String get providerTtsSidecar;

  /// No description provided for @apiKeyRequired.
  ///
  /// In en, this message translates to:
  /// **'API key is required.'**
  String get apiKeyRequired;

  /// No description provided for @sidecarUrlRequired.
  ///
  /// In en, this message translates to:
  /// **'Sidecar URL is required.'**
  String get sidecarUrlRequired;

  /// No description provided for @voiceIdsRequired.
  ///
  /// In en, this message translates to:
  /// **'Voice IDs are required (they depend on your TTS engine).'**
  String get voiceIdsRequired;

  /// No description provided for @voiceServiceRegisteredSnack.
  ///
  /// In en, this message translates to:
  /// **'Voice service registered.'**
  String get voiceServiceRegisteredSnack;

  /// No description provided for @registrationFailed.
  ///
  /// In en, this message translates to:
  /// **'Registration failed: {error}'**
  String registrationFailed(String error);

  /// No description provided for @voiceServiceRemoved.
  ///
  /// In en, this message translates to:
  /// **'Voice service removed.'**
  String get voiceServiceRemoved;

  /// No description provided for @removeFailed.
  ///
  /// In en, this message translates to:
  /// **'Remove failed: {error}'**
  String removeFailed(String error);

  /// No description provided for @voiceServiceIntroConfigured.
  ///
  /// In en, this message translates to:
  /// **'Speech (Speak) uses the registered provider below. Switch provider anytime — no server reinstall needed.'**
  String get voiceServiceIntroConfigured;

  /// No description provided for @voiceServiceIntroUnconfigured.
  ///
  /// In en, this message translates to:
  /// **'Register OpenAI or a self-hosted TTS sidecar to enable Speak in chat.'**
  String get voiceServiceIntroUnconfigured;

  /// No description provided for @providerLabel.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get providerLabel;

  /// No description provided for @sidecarUrl.
  ///
  /// In en, this message translates to:
  /// **'Sidecar URL'**
  String get sidecarUrl;

  /// No description provided for @sidecarContractHelp.
  ///
  /// In en, this message translates to:
  /// **'Any HTTP service implementing the VesnAI TTS contract works (see docs/TTS_SIDECAR.md in the project).'**
  String get sidecarContractHelp;

  /// No description provided for @openaiApiKey.
  ///
  /// In en, this message translates to:
  /// **'OpenAI API key'**
  String get openaiApiKey;

  /// No description provided for @openaiApiKeyUpdate.
  ///
  /// In en, this message translates to:
  /// **'OpenAI API key (re-enter to update)'**
  String get openaiApiKeyUpdate;

  /// No description provided for @sidecarApiKey.
  ///
  /// In en, this message translates to:
  /// **'Sidecar API key'**
  String get sidecarApiKey;

  /// No description provided for @sidecarApiKeyUpdate.
  ///
  /// In en, this message translates to:
  /// **'API key (re-enter to update)'**
  String get sidecarApiKeyUpdate;

  /// No description provided for @openaiModel.
  ///
  /// In en, this message translates to:
  /// **'OpenAI model'**
  String get openaiModel;

  /// No description provided for @polishVoiceOpenai.
  ///
  /// In en, this message translates to:
  /// **'Polish voice (OpenAI id)'**
  String get polishVoiceOpenai;

  /// No description provided for @polishVoiceId.
  ///
  /// In en, this message translates to:
  /// **'Polish voice id'**
  String get polishVoiceId;

  /// No description provided for @englishVoiceOpenai.
  ///
  /// In en, this message translates to:
  /// **'English voice (OpenAI id)'**
  String get englishVoiceOpenai;

  /// No description provided for @englishVoiceId.
  ///
  /// In en, this message translates to:
  /// **'English voice id'**
  String get englishVoiceId;

  /// No description provided for @voiceIdHint.
  ///
  /// In en, this message translates to:
  /// **'voice ID from your TTS engine'**
  String get voiceIdHint;

  /// No description provided for @updateRegistration.
  ///
  /// In en, this message translates to:
  /// **'Update registration'**
  String get updateRegistration;

  /// No description provided for @register.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get register;

  /// No description provided for @removeVoiceService.
  ///
  /// In en, this message translates to:
  /// **'Remove voice service'**
  String get removeVoiceService;

  /// No description provided for @deleteNoteQuestion.
  ///
  /// In en, this message translates to:
  /// **'Delete note?'**
  String get deleteNoteQuestion;

  /// No description provided for @deleteNoteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{title}\"? This cannot be undone.'**
  String deleteNoteConfirm(String title);

  /// No description provided for @deleteNoteSyncNote.
  ///
  /// In en, this message translates to:
  /// **'This note will be removed from this device and synced to the server when online.'**
  String get deleteNoteSyncNote;

  /// No description provided for @replyDidNotFinish.
  ///
  /// In en, this message translates to:
  /// **'This reply did not finish. Send your message again.'**
  String get replyDidNotFinish;

  /// No description provided for @couldNotSendTapRetryStatus.
  ///
  /// In en, this message translates to:
  /// **'Could not send message ({status}). Tap Retry on the message.'**
  String couldNotSendTapRetryStatus(int status);

  /// No description provided for @couldNotSendTapRetry.
  ///
  /// In en, this message translates to:
  /// **'Could not send message. Tap Retry on the message.'**
  String get couldNotSendTapRetry;

  /// No description provided for @connectToSendAttachments.
  ///
  /// In en, this message translates to:
  /// **'Connect to your VesnAI server to send attachments.'**
  String get connectToSendAttachments;

  /// No description provided for @connectToChat.
  ///
  /// In en, this message translates to:
  /// **'Connect to your VesnAI server to chat.'**
  String get connectToChat;

  /// No description provided for @ttsNeedsServer.
  ///
  /// In en, this message translates to:
  /// **'Speech synthesis needs a paired server.'**
  String get ttsNeedsServer;

  /// No description provided for @ttsRegisterFirst.
  ///
  /// In en, this message translates to:
  /// **'Register a voice service in Settings to use Speak.'**
  String get ttsRegisterFirst;

  /// No description provided for @ttsFailed.
  ///
  /// In en, this message translates to:
  /// **'Speech synthesis failed.'**
  String get ttsFailed;

  /// No description provided for @ttsApiKeyRejected.
  ///
  /// In en, this message translates to:
  /// **'Voice service rejected the API key. Update it in Settings → Voice service.'**
  String get ttsApiKeyRejected;

  /// No description provided for @ttsVoiceServiceError.
  ///
  /// In en, this message translates to:
  /// **'Speech synthesis failed: {detail}'**
  String ttsVoiceServiceError(String detail);

  /// No description provided for @uploadSessionNotFound.
  ///
  /// In en, this message translates to:
  /// **'Chat session not found on the server. Start a new chat and try again.'**
  String get uploadSessionNotFound;

  /// No description provided for @uploadTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Photo is too large for the server. Try a smaller image.'**
  String get uploadTooLarge;

  /// No description provided for @uploadConnectionDropped.
  ///
  /// In en, this message translates to:
  /// **'Connection dropped while uploading {filename}. Check Wi-Fi and try again.'**
  String uploadConnectionDropped(String filename);

  /// No description provided for @uploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not upload {filename}: {error}'**
  String uploadFailed(String filename, String error);

  /// No description provided for @notifMarenaCritique.
  ///
  /// In en, this message translates to:
  /// **'Marena left a critique'**
  String get notifMarenaCritique;

  /// No description provided for @notifMarenaCritiqueBody.
  ///
  /// In en, this message translates to:
  /// **'A critical review of one of your notes is ready.'**
  String get notifMarenaCritiqueBody;

  /// No description provided for @notifVesnaiReplied.
  ///
  /// In en, this message translates to:
  /// **'VesnAI replied'**
  String get notifVesnaiReplied;

  /// No description provided for @notifVesnaiRepliedBody.
  ///
  /// In en, this message translates to:
  /// **'A new message is ready in your chat.'**
  String get notifVesnaiRepliedBody;

  /// No description provided for @notifChatImageReady.
  ///
  /// In en, this message translates to:
  /// **'Chat image ready'**
  String get notifChatImageReady;

  /// No description provided for @notifChatImageReadyBody.
  ///
  /// In en, this message translates to:
  /// **'A generated image was added to your conversation.'**
  String get notifChatImageReadyBody;

  /// No description provided for @notifImageGenFailedBody.
  ///
  /// In en, this message translates to:
  /// **'Could not generate the chat image.'**
  String get notifImageGenFailedBody;

  /// No description provided for @notifChatReplyFailed.
  ///
  /// In en, this message translates to:
  /// **'Chat reply failed'**
  String get notifChatReplyFailed;

  /// No description provided for @notifChatReplyFailedBody.
  ///
  /// In en, this message translates to:
  /// **'VesnAI could not complete a reply.'**
  String get notifChatReplyFailedBody;

  /// No description provided for @notifImageReady.
  ///
  /// In en, this message translates to:
  /// **'Image ready'**
  String get notifImageReady;

  /// No description provided for @notifImageReadyBody.
  ///
  /// In en, this message translates to:
  /// **'A generated image was added to your note.'**
  String get notifImageReadyBody;

  /// No description provided for @notifEnrichmentReady.
  ///
  /// In en, this message translates to:
  /// **'Enrichment ready'**
  String get notifEnrichmentReady;

  /// No description provided for @notifEnrichmentReadyBody.
  ///
  /// In en, this message translates to:
  /// **'A generated note was added to your graph.'**
  String get notifEnrichmentReadyBody;

  /// No description provided for @dueReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Notes due for review'**
  String get dueReviewTitle;

  /// No description provided for @dueReviewSingle.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" is due for review.'**
  String dueReviewSingle(String title);

  /// No description provided for @dueReviewMultiple.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 note is} other{{count} notes are}} due for review.'**
  String dueReviewMultiple(int count);

  /// No description provided for @channelBgJobs.
  ///
  /// In en, this message translates to:
  /// **'Background jobs'**
  String get channelBgJobs;

  /// No description provided for @channelBgJobsDesc.
  ///
  /// In en, this message translates to:
  /// **'Notifies when searches and enrichment finish.'**
  String get channelBgJobsDesc;

  /// No description provided for @channelReminders.
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get channelReminders;

  /// No description provided for @channelRemindersDesc.
  ///
  /// In en, this message translates to:
  /// **'Scheduled reminders (notes due for review).'**
  String get channelRemindersDesc;

  /// No description provided for @openShare.
  ///
  /// In en, this message translates to:
  /// **'Open / Share'**
  String get openShare;

  /// No description provided for @shareSave.
  ///
  /// In en, this message translates to:
  /// **'Share / Save'**
  String get shareSave;

  /// No description provided for @addToNotes.
  ///
  /// In en, this message translates to:
  /// **'Add to notes'**
  String get addToNotes;

  /// No description provided for @connectToSaveToNotes.
  ///
  /// In en, this message translates to:
  /// **'Connect to VesnAI to save to notes.'**
  String get connectToSaveToNotes;

  /// No description provided for @fullscreen.
  ///
  /// In en, this message translates to:
  /// **'Fullscreen'**
  String get fullscreen;

  /// No description provided for @savedToNotes.
  ///
  /// In en, this message translates to:
  /// **'Saved to notes'**
  String get savedToNotes;

  /// No description provided for @couldNotSaveImageToNotes.
  ///
  /// In en, this message translates to:
  /// **'Could not save image to notes.'**
  String get couldNotSaveImageToNotes;

  /// No description provided for @couldNotOpenLink.
  ///
  /// In en, this message translates to:
  /// **'Could not open link: {href}'**
  String couldNotOpenLink(String href);

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @removeAttachment.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}'**
  String removeAttachment(String name);

  /// No description provided for @imageLabel.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get imageLabel;

  /// No description provided for @bodyEditorHint.
  ///
  /// In en, this message translates to:
  /// **'What do you want to remember?'**
  String get bodyEditorHint;

  /// No description provided for @yourNote.
  ///
  /// In en, this message translates to:
  /// **'Your note'**
  String get yourNote;

  /// No description provided for @pendingSyncLabel.
  ///
  /// In en, this message translates to:
  /// **'pending sync'**
  String get pendingSyncLabel;

  /// No description provided for @doneLabel.
  ///
  /// In en, this message translates to:
  /// **'done'**
  String get doneLabel;

  /// No description provided for @untitledPlain.
  ///
  /// In en, this message translates to:
  /// **'untitled'**
  String get untitledPlain;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'pl'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'pl':
      return AppLocalizationsPl();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
