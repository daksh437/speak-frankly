import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Wraps on-device speech recognition (speech_to_text) + text-to-speech
/// (flutter_tts). ChangeNotifier so mic UI can react to listening state.
/// All calls are defensive — if speech isn't available on the device, methods
/// fail gracefully instead of throwing.
class SpeechService extends ChangeNotifier {
  static final SpeechService instance = SpeechService._();
  SpeechService._();

  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _sttReady = false;
  bool _ttsReady = false;
  bool isListening = false;
  String lastWords = '';

  /// Live mic loudness for the shadowing waveform: a rolling list of recent
  /// normalized amplitudes (0..1), newest last. Updated while listening.
  static const int _waveMax = 48;
  final List<double> waveform = <double>[];

  bool get available => _sttReady;

  void _pushLevel(double raw) {
    // speech_to_text sound levels are platform-specific; on Android roughly
    // 0..~12. Normalize to a lively 0..1 for the bars.
    final v = (raw.abs() / 10.0).clamp(0.0, 1.0);
    waveform.add(v);
    if (waveform.length > _waveMax) waveform.removeAt(0);
    notifyListeners();
  }

  void _resetWaveform() {
    if (waveform.isEmpty) return;
    waveform.clear();
    notifyListeners();
  }

  Future<bool> _ensureStt() async {
    if (_sttReady) return true;
    try {
      _sttReady = await _stt.initialize(
        onStatus: (status) {
          final listening = status == 'listening';
          if (listening != isListening) {
            isListening = listening;
            notifyListeners();
          }
        },
        onError: (_) {
          if (isListening) {
            isListening = false;
            notifyListeners();
          }
        },
      );
    } catch (_) {
      _sttReady = false;
    }
    return _sttReady;
  }

  Future<void> _ensureTts() async {
    if (_ttsReady) return;
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.45);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);
      _ttsReady = true;
    } catch (_) {/* tts optional */}
  }

  /// Speak [text] aloud (for listen-and-imitate).
  Future<void> speak(String text) async {
    await _ensureTts();
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  /// Start listening. Returns false if speech recognition is unavailable.
  /// [onResult] fires with partial then final transcripts.
  Future<bool> startListening({required void Function(String text, bool isFinal) onResult}) async {
    if (!await _ensureStt()) return false;
    lastWords = '';
    isListening = true;
    _resetWaveform();
    notifyListeners();
    try {
      await _stt.listen(
        onResult: (r) {
          lastWords = r.recognizedWords;
          onResult(r.recognizedWords, r.finalResult);
          notifyListeners();
        },
        onSoundLevelChange: _pushLevel, // feeds the shadowing waveform
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          localeId: 'en_US',
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 3),
        ),
      );
      return true;
    } catch (_) {
      isListening = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> stopListening() async {
    try {
      await _stt.stop();
    } catch (_) {}
    isListening = false;
    notifyListeners();
  }
}

/// Word-overlap pronunciation score (0–100): how many target words the
/// recognizer heard. A good recognizer transcript = clearly spoken words.
int pronunciationScore(String target, String said) {
  List<String> tokens(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  final t = tokens(target);
  if (t.isEmpty) return 0;
  final saidSet = tokens(said).toSet();
  final matched = t.where(saidSet.contains).length;
  return ((matched / t.length) * 100).round();
}
