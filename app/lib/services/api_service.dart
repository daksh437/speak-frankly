import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import 'offline_scenarios.dart';
import 'user_session.dart';

/// All backend calls funnel through here (mirrors InstaFlow's ApiService).
/// Auth is the Firebase-style UID sent as `x-user-uid` / `x-user-id`.
class ApiService {
  static final ApiService instance = ApiService._();
  ApiService._();

  final _client = http.Client();
  static const _timeout = Duration(seconds: 30);

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'x-user-uid': UserSession.instance.uid,
        'x-user-id': UserSession.instance.uid,
      };

  Uri _u(String path, [Map<String, dynamic>? query]) =>
      Uri.parse('${AppConfig.baseUrl}$path').replace(
        queryParameters: query?.map((k, v) => MapEntry(k, v.toString())),
      );

  /// Wake a sleeping (Render free-tier) backend early so it's warm by the time
  /// the user finishes signing in. Fire-and-forget; errors ignored.
  void warmup() {
    _client.get(_u('/health')).timeout(const Duration(seconds: 20)).ignore();
  }

  /// Scenario library. When offline, serves the downloaded pack (if any), then
  /// a small bundled copy.
  Future<List<Scenario>> fetchScenarios() async {
    try {
      final res = await _client.get(_u('/scenarios'), headers: _headers).timeout(_timeout);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final data = (body['data'] as List?) ?? [];
      final list = data.whereType<Map<String, dynamic>>().map(Scenario.fromJson).toList();
      return list.isNotEmpty ? list : await _fallbackScenarios();
    } catch (_) {
      return _fallbackScenarios();
    }
  }

  /// Downloaded offline pack first (OfflineService.kScenariosKey), else bundled.
  Future<List<Scenario>> _fallbackScenarios() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('sf_offline_scenarios');
      if (raw != null) {
        final list = (jsonDecode(raw) as List).whereType<Map<String, dynamic>>().map(Scenario.fromJson).toList();
        if (list.isNotEmpty) return list;
      }
    } catch (_) {/* ignore */}
    return offlineScenarios();
  }

  /// Build a chat-ready scenario from a free-text topic (Context Generator).
  Future<Scenario> fetchCustomScenario(String topic) async {
    final res = await _client
        .post(
          _u('/custom/scenario'),
          headers: _headers,
          body: jsonEncode({'topic': topic, 'level': UserSession.instance.level}),
        )
        .timeout(const Duration(seconds: 45));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final data = (body['data'] as Map<String, dynamic>?) ?? {};
    final scenario = (data['scenario'] as Map<String, dynamic>?) ?? {};
    return Scenario.fromJson(scenario);
  }

  /// One conversation turn. `messages` is the full history (oldest → newest).
  /// [context] carries a custom scenario's tutor-role setup (library scenarios
  /// pass only [scenarioId]).
  Future<TutorReply> sendChat({
    String? scenarioId,
    String? context,
    required List<ChatMessage> messages,
  }) async {
    final res = await _client
        .post(
          _u('/tutor/chat'),
          headers: _headers,
          body: jsonEncode({
            'scenarioId': scenarioId,
            'context': context,
            'level': UserSession.instance.level,
            'nativeLanguage': UserSession.instance.nativeLanguage,
            'messages': messages.map((m) => m.toApi()).toList(),
          }),
        )
        .timeout(_timeout);

    if (res.statusCode == 403) {
      throw DailyLimitException();
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final data = (body['data'] as Map<String, dynamic>?) ?? {};
    return TutorReply.fromJson(data);
  }

  /// End-of-session feedback report.
  Future<Map<String, dynamic>> sendFeedback({
    String? scenarioId,
    required List<ChatMessage> messages,
  }) async {
    final res = await _client
        .post(
          _u('/tutor/feedback'),
          headers: _headers,
          body: jsonEncode({
            'scenarioId': scenarioId,
            'level': UserSession.instance.level,
            'messages': messages.map((m) => m.toApi()).toList(),
          }),
        )
        .timeout(_timeout);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['data'] as Map<String, dynamic>?) ?? {};
  }

  /// Fresh listen-and-imitate phrases for the learner's level + goal.
  Future<List<String>> fetchSpeakingPhrases({required String level, required String goal, int count = 12}) async {
    final res = await _client
        .post(
          _u('/speaking/phrases'),
          headers: _headers,
          body: jsonEncode({'level': level, 'goal': goal, 'count': count}),
        )
        .timeout(const Duration(seconds: 45));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final data = (body['data'] as Map<String, dynamic>?) ?? {};
    return ((data['phrases'] as List?) ?? []).map((e) => e.toString()).where((s) => s.trim().isNotEmpty).toList();
  }

  /// Fresh, level-aware picture-match items (emoji scene + sentences).
  Future<List<Map<String, dynamic>>> fetchPictureMatch({required String level, int count = 10}) async {
    final res = await _client
        .post(_u('/games/picture-match'), headers: _headers, body: jsonEncode({'level': level, 'count': count}))
        .timeout(const Duration(seconds: 45));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final data = (body['data'] as Map<String, dynamic>?) ?? {};
    return ((data['items'] as List?) ?? []).whereType<Map<String, dynamic>>().toList();
  }

  /// Extract useful vocabulary (word + meaning) from pasted text.
  Future<List<Map<String, dynamic>>> extractVocab(String text) async {
    final res = await _client
        .post(_u('/vocab/extract'), headers: _headers, body: jsonEncode({'text': text, 'level': UserSession.instance.level}))
        .timeout(const Duration(seconds: 45));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final data = (body['data'] as Map<String, dynamic>?) ?? {};
    return ((data['words'] as List?) ?? []).whereType<Map<String, dynamic>>().toList();
  }

  /// Cloud-synced progress (gamification + saved words).
  Future<Map<String, dynamic>> fetchProgress() async {
    final res = await _client.get(_u('/progress'), headers: _headers).timeout(_timeout);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['data'] as Map<String, dynamic>?) ?? {};
  }

  Future<void> saveProgress(Map<String, dynamic> data) async {
    await _client.post(_u('/progress'), headers: _headers, body: jsonEncode(data)).timeout(_timeout);
  }

  /// Grant premium after a confirmed Google Play subscription purchase.
  Future<void> activatePremium({String? purchaseToken}) async {
    await _client
        .post(_u('/premium/activate'), headers: _headers, body: jsonEncode({'purchaseToken': purchaseToken}))
        .timeout(_timeout);
  }

  /// The learner's plan + remaining daily messages (server is authoritative).
  Future<Map<String, dynamic>> fetchAccess() async {
    final res = await _client.get(_u('/access'), headers: _headers).timeout(_timeout);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['data'] as Map<String, dynamic>?) ?? {};
  }

  /// Translate an English tutor line into [target] language (a name, e.g.
  /// "Hindi"). Returns '' on failure so the UI can fall back gracefully.
  Future<String> translate({required String text, required String target}) async {
    try {
      final res = await _client
          .post(_u('/translate'), headers: _headers, body: jsonEncode({'text': text, 'target': target}))
          .timeout(_timeout);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final data = (body['data'] as Map<String, dynamic>?) ?? {};
      return (data['translation'] ?? '').toString();
    } catch (_) {
      return '';
    }
  }

  /// Dictionary card for a word, optionally translated into [target] language.
  Future<DictionaryCard?> lookupWord(String word, {String? target}) async {
    final res = await _client
        .get(_u('/dictionary/$word', target != null ? {'target': target} : null), headers: _headers)
        .timeout(_timeout);
    if (res.statusCode == 404) return null;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final data = body['data'] as Map<String, dynamic>?;
    if (data == null) return null;
    return DictionaryCard.fromJson(data);
  }
}

class DailyLimitException implements Exception {
  @override
  String toString() => 'Daily free limit reached';
}
