import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/models.dart';
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

  /// Scenario library.
  Future<List<Scenario>> fetchScenarios() async {
    final res = await _client.get(_u('/scenarios'), headers: _headers).timeout(_timeout);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final data = (body['data'] as List?) ?? [];
    return data.whereType<Map<String, dynamic>>().map(Scenario.fromJson).toList();
  }

  /// One conversation turn. `messages` is the full history (oldest → newest).
  Future<TutorReply> sendChat({
    String? scenarioId,
    required List<ChatMessage> messages,
  }) async {
    final res = await _client
        .post(
          _u('/tutor/chat'),
          headers: _headers,
          body: jsonEncode({
            'scenarioId': scenarioId,
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

  /// The learner's plan + remaining daily messages (server is authoritative).
  Future<Map<String, dynamic>> fetchAccess() async {
    final res = await _client.get(_u('/access'), headers: _headers).timeout(_timeout);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['data'] as Map<String, dynamic>?) ?? {};
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
