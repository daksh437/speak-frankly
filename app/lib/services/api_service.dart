import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import 'offline_scenarios.dart';
import 'user_session.dart';

/// All backend calls funnel through here (mirrors InstaFlow's ApiService).
///
/// Auth is the learner's Firebase **ID token** (`Authorization: Bearer …`),
/// which the backend verifies with the Admin SDK. The old `x-user-uid` header
/// is still sent so app versions and server versions can roll out
/// independently, but it is only a hint — the server prefers the token, and
/// once REQUIRE_AUTH_TOKEN is on there it stops accepting the header at all.
class ApiService {
  static final ApiService instance = ApiService._();
  ApiService._();

  final _client = http.Client();
  static const _timeout = Duration(seconds: 30);

  /// How many recent turns travel with a chat request. The tutor only needs
  /// recent context, and a turn is billed as one message however long the
  /// transcript is — so re-sending the whole session every turn makes the token
  /// cost climb with every reply. The server clamps this too; this just avoids
  /// uploading history it will throw away.
  static const _maxChatHistory = 16;

  /// The end-of-session report reads the whole session, so it keeps more.
  static const _maxFeedbackHistory = 40;

  List<ChatMessage> _recent(List<ChatMessage> messages, int keep) =>
      messages.length <= keep ? messages : messages.sublist(messages.length - keep);

  /// Headers for an authenticated call. The uid comes from the signed-in
  /// Firebase user when there is one — never from the local prefs id, which is
  /// a placeholder generated before sign-in and would create junk user docs
  /// (and burn this device's one free trial) if it ever reached the server.
  Future<Map<String, String>> _authHeaders() async {
    String uid = UserSession.instance.uid;
    String? token;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        uid = user.uid;
        token = await user.getIdToken();
      }
    } catch (_) {/* Firebase unavailable → fall back to the session uid */}

    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      'x-user-uid': uid,
      'x-user-id': uid,
      'x-device-id': UserSession.instance.deviceId,
    };
  }

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
      final res = await _client.get(_u('/scenarios'), headers: await _authHeaders()).timeout(_timeout);
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
          headers: await _authHeaders(),
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
          headers: await _authHeaders(),
          body: jsonEncode({
            'scenarioId': scenarioId,
            'context': context,
            'level': UserSession.instance.level,
            'nativeLanguage': UserSession.instance.nativeLanguage,
            'messages': _recent(messages, _maxChatHistory).map((m) => m.toApi()).toList(),
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
          headers: await _authHeaders(),
          body: jsonEncode({
            'scenarioId': scenarioId,
            'level': UserSession.instance.level,
            'messages': _recent(messages, _maxFeedbackHistory).map((m) => m.toApi()).toList(),
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
          headers: await _authHeaders(),
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
        .post(_u('/games/picture-match'), headers: await _authHeaders(), body: jsonEncode({'level': level, 'count': count}))
        .timeout(const Duration(seconds: 45));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final data = (body['data'] as Map<String, dynamic>?) ?? {};
    return ((data['items'] as List?) ?? []).whereType<Map<String, dynamic>>().toList();
  }

  /// Extract useful vocabulary (word + meaning) from pasted text.
  Future<List<Map<String, dynamic>>> extractVocab(String text) async {
    final res = await _client
        .post(_u('/vocab/extract'), headers: await _authHeaders(), body: jsonEncode({'text': text, 'level': UserSession.instance.level}))
        .timeout(const Duration(seconds: 45));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final data = (body['data'] as Map<String, dynamic>?) ?? {};
    return ((data['words'] as List?) ?? []).whereType<Map<String, dynamic>>().toList();
  }

  /// Cloud-synced progress (gamification + saved words).
  Future<Map<String, dynamic>> fetchProgress() async {
    final res = await _client.get(_u('/progress'), headers: await _authHeaders()).timeout(_timeout);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['data'] as Map<String, dynamic>?) ?? {};
  }

  Future<void> saveProgress(Map<String, dynamic> data) async {
    await _client.post(_u('/progress'), headers: await _authHeaders(), body: jsonEncode(data)).timeout(_timeout);
  }

  /// Grant premium after a confirmed Google Play subscription purchase.
  Future<void> activatePremium({String? purchaseToken}) async {
    await _client
        .post(_u('/premium/activate'), headers: await _authHeaders(), body: jsonEncode({'purchaseToken': purchaseToken}))
        .timeout(_timeout);
  }

  /// Permanently erase this account and everything stored against it.
  ///
  /// The server takes the uid from the VERIFIED ID token, never from a header,
  /// so this can only ever delete the caller's own account. Returns false if
  /// the server refused (the caller then points the learner at the email
  /// fallback rather than pretending the data is gone).
  Future<bool> deleteAccount() async {
    try {
      final res = await _client.delete(_u('/account'), headers: await _authHeaders()).timeout(_timeout);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// The learner's plan + remaining daily messages (server is authoritative).
  Future<Map<String, dynamic>> fetchAccess() async {
    final res = await _client.get(_u('/access'), headers: await _authHeaders()).timeout(_timeout);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['data'] as Map<String, dynamic>?) ?? {};
  }

  /// Grant ad-reward bonus messages after a rewarded ad (server-authoritative).
  /// Returns true if bonus was granted (false if the daily reward cap is hit).
  Future<bool> rewardAd() async {
    try {
      final res = await _client.post(_u('/access/reward-ad'), headers: await _authHeaders()).timeout(_timeout);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Translate an English tutor line into [target] language (a name, e.g.
  /// "Hindi"). Returns '' on failure so the UI can fall back gracefully.
  Future<String> translate({required String text, required String target}) async {
    try {
      final res = await _client
          .post(_u('/translate'), headers: await _authHeaders(), body: jsonEncode({'text': text, 'target': target}))
          .timeout(_timeout);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final data = (body['data'] as Map<String, dynamic>?) ?? {};
      return (data['translation'] ?? '').toString();
    } catch (_) {
      return '';
    }
  }

  /// Report an AI reply the learner found offensive/unsafe/wrong. Required by
  /// Play's generative-AI policy; the owner reviews these in the admin panel.
  /// Returns false only if the report couldn't be sent at all.
  Future<bool> reportAiContent({
    required String text,
    required String reason,
    String? note,
    String? scenarioId,
  }) async {
    try {
      final res = await _client
          .post(
            _u('/report'),
            headers: await _authHeaders(),
            body: jsonEncode({
              'text': text,
              'reason': reason,
              'note': note ?? '',
              'scenarioId': scenarioId ?? '',
              'level': UserSession.instance.level,
            }),
          )
          .timeout(_timeout);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Dictionary card for a word, optionally translated into [target] language.
  Future<DictionaryCard?> lookupWord(String word, {String? target}) async {
    final res = await _client
        .get(_u('/dictionary/$word', target != null ? {'target': target} : null), headers: await _authHeaders())
        .timeout(_timeout);
    if (res.statusCode == 404) return null;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final data = body['data'] as Map<String, dynamic>?;
    if (data == null) return null;
    return DictionaryCard.fromJson(data);
  }

  // ---- Admin panel (server verifies admin from the Firebase email) ----

  /// Whether the current user is an admin → { isAdmin, isOwner, email }.
  Future<Map<String, dynamic>> adminMe() async {
    final res = await _client.get(_u('/admin/me'), headers: await _authHeaders()).timeout(_timeout);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['data'] as Map<String, dynamic>?) ?? {};
  }

  Future<List<Map<String, dynamic>>> adminListAdmins() async {
    final res = await _client.get(_u('/admin/admins'), headers: await _authHeaders()).timeout(_timeout);
    final body = _decodeAdmin(res);
    final data = (body['data'] as Map<String, dynamic>?) ?? {};
    return ((data['admins'] as List?) ?? []).whereType<Map<String, dynamic>>().toList();
  }

  Future<bool> adminAddAdmin(String email) async {
    final res = await _client
        .post(_u('/admin/admins'), headers: await _authHeaders(), body: jsonEncode({'email': email}))
        .timeout(_timeout);
    return res.statusCode == 200;
  }

  Future<bool> adminRemoveAdmin(String email) async {
    final res = await _client
        .delete(_u('/admin/admins/${Uri.encodeComponent(email)}'), headers: await _authHeaders())
        .timeout(_timeout);
    return res.statusCode == 200;
  }

  /// Dashboard numbers, all computed server-side from live data.
  /// Throws [AdminApiException] on a non-200 so the panel can show the real
  /// reason (not-an-admin, outdated app, server error) instead of empty cards.
  Future<Map<String, dynamic>> adminStats() async {
    final res = await _client.get(_u('/admin/stats'), headers: await _authHeaders()).timeout(_timeout);
    final body = _decodeAdmin(res);
    return (body['data'] as Map<String, dynamic>?) ?? {};
  }

  /// Recent learners with their real plan + usage.
  Future<List<Map<String, dynamic>>> adminUsers({int limit = 50}) async {
    final res = await _client
        .get(_u('/admin/users', {'limit': limit}), headers: await _authHeaders())
        .timeout(_timeout);
    final body = _decodeAdmin(res);
    final data = (body['data'] as Map<String, dynamic>?) ?? {};
    return ((data['users'] as List?) ?? []).whereType<Map<String, dynamic>>().toList();
  }

  Map<String, dynamic> _decodeAdmin(http.Response res) {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw AdminApiException(res.statusCode, 'Unexpected server response');
    }
    if (res.statusCode != 200) {
      throw AdminApiException(
        res.statusCode,
        (body['message'] ?? body['error'] ?? 'Request failed').toString(),
      );
    }
    return body;
  }

  /// Reported AI replies, newest first (admin only).
  Future<List<Map<String, dynamic>>> adminListReports() async {
    final res = await _client.get(_u('/admin/reports'), headers: await _authHeaders()).timeout(_timeout);
    final body = _decodeAdmin(res);
    final data = (body['data'] as Map<String, dynamic>?) ?? {};
    return ((data['reports'] as List?) ?? []).whereType<Map<String, dynamic>>().toList();
  }

  /// Mark a report reviewed (admin only).
  Future<bool> adminReviewReport(String id) async {
    final res = await _client
        .post(_u('/admin/reports/${Uri.encodeComponent(id)}/review'), headers: await _authHeaders())
        .timeout(_timeout);
    return res.statusCode == 200;
  }

  /// Grant premium to a user by email for [days]. Returns the server response.
  Future<Map<String, dynamic>> adminGrantPremium(String email, {int days = 31}) async {
    final res = await _client
        .post(_u('/admin/grant-premium'), headers: await _authHeaders(), body: jsonEncode({'email': email, 'days': days}))
        .timeout(_timeout);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return {'ok': res.statusCode == 200, ...body};
  }
}

/// An admin call the server refused — carries the real status + message so the
/// panel can tell "you are not an admin" apart from "the server is down".
class AdminApiException implements Exception {
  final int status;
  final String message;
  AdminApiException(this.status, this.message);

  String get friendly => switch (status) {
        401 => 'Sign in again with your admin account (this app version may be out of date).',
        403 => 'This account is not an admin.',
        503 => 'The database is unavailable right now.',
        _ => message,
      };

  @override
  String toString() => 'AdminApiException($status): $message';
}

class DailyLimitException implements Exception {
  @override
  String toString() => 'Daily free limit reached';
}
