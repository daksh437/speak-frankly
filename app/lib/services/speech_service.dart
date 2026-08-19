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

  /// Recognizer confidence for the most recent final result (0..1), or 0 when
  /// the device didn't provide one. Blended into the pronunciation score so a
  /// clearly-heard phrase scores higher than a barely-parsed one.
  double lastConfidence = 0.0;

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

  /// Stop any in-progress text-to-speech (e.g. when muting the tutor voice).
  Future<void> stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  /// Start listening. Returns false if speech recognition is unavailable.
  /// [onResult] fires with partial then final transcripts.
  Future<bool> startListening({required void Function(String text, bool isFinal) onResult}) async {
    if (!await _ensureStt()) return false;
    lastWords = '';
    lastConfidence = 0.0;
    isListening = true;
    _resetWaveform();
    notifyListeners();
    try {
      await _stt.listen(
        onResult: (r) {
          lastWords = r.recognizedWords;
          // Only final results carry a meaningful confidence rating.
          if (r.finalResult && r.hasConfidenceRating && r.confidence > 0) {
            lastConfidence = r.confidence.clamp(0.0, 1.0);
          }
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

/// How a single target word came out, so the UI can colour it.
enum WordVerdict { good, close, missed }

class WordScore {
  final String word;
  final double similarity; // 0..1 (1 = exact match to what was heard, in order)
  const WordScore(this.word, this.similarity);

  WordVerdict get verdict => similarity >= 0.8
      ? WordVerdict.good
      : (similarity >= 0.45 ? WordVerdict.close : WordVerdict.missed);
}

/// A full pronunciation assessment: an overall 0–100 score plus a per-word
/// breakdown, so the learner sees *which* words landed and which slipped.
class PronunciationResult {
  final int score;
  final List<WordScore> words;
  final double confidence; // recognizer confidence, 0 if the device gave none
  const PronunciationResult({required this.score, required this.words, required this.confidence});

  int get goodCount => words.where((w) => w.verdict == WordVerdict.good).length;
  int get missedCount => words.where((w) => w.verdict == WordVerdict.missed).length;
}

List<String> _pronTokens(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .toList();

/// Levenshtein edit distance between two short strings.
int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  final prev = List<int>.generate(b.length + 1, (i) => i);
  final curr = List<int>.filled(b.length + 1, 0);
  for (var i = 0; i < a.length; i++) {
    curr[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
      curr[j + 1] = [curr[j] + 1, prev[j + 1] + 1, prev[j] + cost]
          .reduce((x, y) => x < y ? x : y);
    }
    for (var j = 0; j <= b.length; j++) {
      prev[j] = curr[j];
    }
  }
  return prev[b.length];
}

/// Word similarity 0..1 — a near-miss ("wan" for "want") earns partial credit
/// instead of a flat zero, so a small slip isn't graded like a skipped word.
double _wordSim(String a, String b) {
  if (a == b) return 1.0;
  final maxLen = a.length > b.length ? a.length : b.length;
  if (maxLen == 0) return 0.0;
  final sim = 1.0 - _levenshtein(a, b) / maxLen;
  return sim < 0 ? 0.0 : sim;
}

/// Full on-device pronunciation assessment.
///
/// This measures how much of the target phrase the recognizer heard, IN ORDER,
/// with partial credit for near-misses and a nudge from the recognizer's own
/// confidence. It still cannot judge accent, stress or intonation (that needs a
/// speech-assessment API) — but it is a real, honest step up from "did the word
/// appear anywhere at all". Words are aligned with Needleman–Wunsch so inserted
/// or dropped words don't throw the rest of the sentence off.
PronunciationResult assessPronunciation(String target, String said, {double confidence = 0.0}) {
  final t = _pronTokens(target);
  if (t.isEmpty) {
    return PronunciationResult(score: 0, words: const [], confidence: confidence);
  }
  final s = _pronTokens(said);

  // DP alignment: dp[i][j] = best total similarity aligning t[0..i) with s[0..j).
  final n = t.length, m = s.length;
  final dp = List.generate(n + 1, (_) => List<double>.filled(m + 1, 0));
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      final match = dp[i - 1][j - 1] + _wordSim(t[i - 1], s[j - 1]);
      final skipT = dp[i - 1][j]; // target word with no spoken counterpart
      final skipS = dp[i][j - 1]; // extra spoken word
      dp[i][j] = [match, skipT, skipS].reduce((a, b) => a > b ? a : b);
    }
  }

  // Trace back to give each target word the similarity it was aligned with.
  final perWord = List<double>.filled(n, 0);
  var i = n, j = m;
  while (i > 0 && j > 0) {
    final match = dp[i - 1][j - 1] + _wordSim(t[i - 1], s[j - 1]);
    if (dp[i][j] == match) {
      perWord[i - 1] = _wordSim(t[i - 1], s[j - 1]);
      i--; j--;
    } else if (dp[i][j] == dp[i - 1][j]) {
      i--; // target word skipped → stays 0
    } else {
      j--; // extra spoken word ignored
    }
  }

  final words = [for (var k = 0; k < n; k++) WordScore(t[k], perWord[k])];
  final wordScore = perWord.reduce((a, b) => a + b) / n; // 0..1

  // Blend in recognizer confidence when the device actually reported one, so a
  // crisp reading edges out a mumbled one that happened to parse. Weight it
  // lightly — Android confidence is noisy.
  final blended = confidence > 0 ? (wordScore * 0.85 + confidence * 0.15) : wordScore;
  return PronunciationResult(
    score: (blended.clamp(0.0, 1.0) * 100).round(),
    words: words,
    confidence: confidence,
  );
}

/// Backwards-compatible 0–100 score (used by the placement test).
int pronunciationScore(String target, String said) =>
    assessPronunciation(target, said).score;
