import 'dart:async';

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// A single transcription update from on-device speech recognition.
///
/// The recognizer emits a stream of partials with [isFinal] == false as the
/// user speaks, followed by one [isFinal] == true result when it settles.
class SpeechResult {
  final String text;
  final bool isFinal;
  const SpeechResult(this.text, {this.isFinal = false});
}

/// On-device speech-to-text, behind an interface so the chat UI can be driven
/// by a fake in widget tests.
///
/// Transcription happens entirely on the phone (iOS Speech / Android
/// SpeechRecognizer); nothing is sent to the server for STT. Only the final
/// text is later posted to `/v1/chat` for the LLM reply.
abstract class SpeechInputService {
  /// Prepare the recognizer and request permissions. Returns false when speech
  /// recognition is unavailable (no engine, denied permission, etc.).
  Future<bool> initialize();

  /// Begin listening. Emits partial results immediately, then a single final
  /// result, after which the stream closes. [localeId] is a BCP-47-ish id such
  /// as `pl_PL` or `en_US`.
  ///
  /// [pauseFor] is how long a silence is tolerated before the dictation is
  /// considered complete (so brief mid-sentence pauses do not cut you off);
  /// [listenFor] is the hard cap on a single dictation.
  Stream<SpeechResult> listen({
    String? localeId,
    Duration pauseFor,
    Duration listenFor,
  });

  /// Stop listening and finalize: emits the accumulated transcript as the final
  /// result, then closes the stream.
  Future<void> stop();

  bool get isListening;
}

/// Default implementation backed by the `speech_to_text` plugin.
///
/// The platform recognizer ends a session after its own short silence window
/// (on Android this cannot be extended via `pauseFor`), which would truncate a
/// longer sentence. To support continuous dictation we **accumulate** text
/// across recognizer sessions and only emit a final result when the user stops
/// or a real pause ([_pauseFor] of sustained silence) elapses; until then each
/// ended session is restarted so continued speech keeps being captured.
class NativeSpeechInputService implements SpeechInputService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _available = false;

  StreamController<SpeechResult>? _controller;
  String _accumulated = '';
  String _current = '';
  bool _manualStop = false;
  bool _finalized = false;
  bool _restartPending = false;
  Timer? _silenceTimer;
  Duration _pauseFor = const Duration(seconds: 3);
  Duration _listenFor = const Duration(minutes: 2);
  DateTime _startedAt = DateTime.now();
  String? _localeId;

  @override
  bool get isListening => _speech.isListening;

  @override
  Future<bool> initialize() async {
    if (_available) return true;
    _available = await _speech.initialize(onError: _onError);
    return _available;
  }

  String get _combined => '$_accumulated $_current'.trim();

  @override
  Stream<SpeechResult> listen({
    String? localeId,
    Duration pauseFor = const Duration(seconds: 3),
    Duration listenFor = const Duration(minutes: 2),
  }) {
    final controller = StreamController<SpeechResult>();
    _controller = controller;
    _accumulated = '';
    _current = '';
    _manualStop = false;
    _finalized = false;
    _restartPending = false;
    _pauseFor = pauseFor;
    _listenFor = listenFor;
    _localeId = localeId;
    _startedAt = DateTime.now();

    Future<void> begin() async {
      if (!await initialize()) {
        controller.addError('Speech recognition unavailable on this device.');
        await controller.close();
        return;
      }
      await _startSession();
    }

    controller.onCancel = () async {
      _manualStop = true;
      _silenceTimer?.cancel();
      await _speech.stop();
    };
    begin();
    return controller.stream;
  }

  Future<void> _startSession() async {
    _restartPending = false;
    if (_finalized || _manualStop) return;
    if (DateTime.now().difference(_startedAt) >= _listenFor) {
      _finalize();
      return;
    }
    try {
      await _speech.listen(
        onResult: (r) {
          if (_finalized) return;
          _current = r.recognizedWords;
          // Any recognized speech means the user isn't done: cancel the pending
          // end-of-dictation finalize.
          if (_current.isNotEmpty) _silenceTimer?.cancel();
          _controller?.add(SpeechResult(_combined, isFinal: false));
          if (r.finalResult) _onSessionEnded();
        },
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          localeId: _localeId,
          // Dictation mode (iOS) keeps the recognizer open for longer speech.
          listenMode: stt.ListenMode.dictation,
          pauseFor: _pauseFor,
          listenFor: _listenFor,
        ),
      );
    } catch (_) {
      // Recognizer busy/failed to start; treat as a session end so the silence
      // timer (or a retry) takes over rather than dropping the dictation.
      _onSessionEnded();
    }
  }

  /// A recognizer session ended (final result, timeout, or transient error).
  /// Fold its words into the running transcript, then either finalize (manual
  /// stop / sustained silence) or restart to keep capturing.
  void _onSessionEnded() {
    if (_finalized) return;
    if (_current.isNotEmpty) {
      _accumulated = _combined;
      _current = '';
    }
    if (_manualStop) {
      _finalize();
      return;
    }
    // Finalize if no further speech arrives within pauseFor; otherwise keep a
    // session running so continued speech is captured.
    _silenceTimer?.cancel();
    _silenceTimer = Timer(_pauseFor, _finalize);
    _scheduleRestart();
  }

  void _scheduleRestart() {
    if (_restartPending || _finalized || _manualStop) return;
    _restartPending = true;
    // A small delay avoids "recognizer busy" right after a session ends.
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_finalized || _manualStop) {
        _restartPending = false;
        return;
      }
      if (_speech.isListening) {
        _restartPending = false;
        return;
      }
      _startSession();
    });
  }

  void _onError(SpeechRecognitionError e) {
    if (_finalized) return;
    // A permanent error with nothing captured is a real failure; surface it.
    if (e.permanent && _combined.isEmpty && _accumulated.isEmpty) {
      _controller?.addError(e.errorMsg);
      _finalize();
      return;
    }
    // Transient errors (no-match / speech-timeout) just mean a quiet session.
    _onSessionEnded();
  }

  void _finalize() {
    if (_finalized) return;
    _finalized = true;
    _silenceTimer?.cancel();
    _speech.stop();
    final controller = _controller;
    if (controller != null && !controller.isClosed) {
      controller.add(SpeechResult(_combined, isFinal: true));
      controller.close();
    }
  }

  @override
  Future<void> stop() async {
    _manualStop = true;
    _silenceTimer?.cancel();
    await _speech.stop();
    _finalize();
  }
}
