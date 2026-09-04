import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../models/models.dart';
import '../services/ad_service.dart';
import '../services/analytics_service.dart';
import '../services/api_service.dart';
import '../services/gamification_service.dart';
import '../services/plan_status.dart';
import '../services/rate_prompt.dart';
import '../services/speech_service.dart';
import '../services/user_session.dart';
import '../theme/app_theme.dart';
import '../widgets/dictionary_sheet.dart';
import '../widgets/say_it_sheet.dart';
import 'premium_screen.dart';
import 'session_report_screen.dart';

const _cefrLevels = ['A0', 'A1', 'A2', 'B1', 'B2', 'C1'];
String _nextLevel(String l) {
  final i = _cefrLevels.indexOf(l);
  return (i >= 0 && i < _cefrLevels.length - 1) ? _cefrLevels[i + 1] : l;
}

String _prevLevel(String l) {
  final i = _cefrLevels.indexOf(l);
  return i > 0 ? _cefrLevels[i - 1] : l;
}

/// The core experience: a real-life conversation with the AI tutor.
/// Premium chat UI — accent-colored per scenario, tap-any-word dictionary,
/// gentle correction cards, quick-reply chips, animated typing.
class ChatScreen extends StatefulWidget {
  final Scenario scenario;
  const ChatScreen({super.key, required this.scenario});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messages = <ChatMessage>[];
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  List<String> _suggestions = [];
  bool _sending = false;
  bool _finishing = false;

  /// Set when the server refuses a turn on plan grounds. Holds the server's own
  /// reason, because a free learner at their daily cap and a paying subscriber
  /// at the fair-use ceiling need opposite things said to them.
  DailyLimitException? _limit;

  /// Voice-first: the tutor speaks its replies aloud (TTS) so the whole session
  /// is a real spoken conversation. Toggleable (public/quiet places) + persisted.
  static const _kVoicePref = 'sf_chat_voice';
  static const _kFirstReply = 'sf_first_reply_done';
  bool _autoSpeak = true;

  Color get _accent => AppColors.forScenario(widget.scenario.theme);

  bool get _hasSpoken => _messages.any((m) => m.isUser);

  /// Beginners (A0–A2) get tappable reply choices — the "choose your reply"
  /// mode from the BRD, so they're never stuck facing an empty text box.
  bool get _isBeginner => const ['A0', 'A1', 'A2'].contains(UserSession.instance.level);

  /// Simple, universal opening replies to seed the very first turn for beginners
  /// (the scenario's starter line has no server suggestions yet).
  static const _starterOptions = ['Hello!', 'Can you help me?', "Sorry, I don't understand."];

  /// End the session: fetch a feedback report, award completion XP, show the report.
  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    Map<String, dynamic> feedback;
    try {
      feedback = await ApiService.instance.sendFeedback(scenarioId: widget.scenario.id, messages: _messages);
    } catch (_) {
      feedback = {};
    }
    await GamificationService.instance.completeScenario();
    AnalyticsService.log('scenario_completed', {'scenario': widget.scenario.id});
    RatePrompt.onSessionComplete(); // ask happy users to rate (after a few sessions)

    // Adaptive difficulty: suggest a level change based on this session's
    // correction density (few mistakes → level up; many → level down).
    (String, bool, String)? suggestion;
    final userMsgs = _messages.where((m) => m.isUser).toList();
    if (userMsgs.length >= 4) {
      final corrections = userMsgs.fold<int>(0, (s, m) => s + m.corrections.length);
      final ratio = corrections / userMsgs.length;
      final cur = UserSession.instance.level;
      if (ratio < 0.3 && _nextLevel(cur) != cur) {
        suggestion = (_nextLevel(cur), true, 'You made very few mistakes — ready to level up?');
      } else if (ratio > 1.3 && _prevLevel(cur) != cur) {
        suggestion = (_prevLevel(cur), false, 'This felt challenging — an easier level might help.');
      }
    }

    if (!mounted) return;
    setState(() => _finishing = false);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SessionReportScreen(feedback: feedback, xpEarned: 20, levelSuggestion: suggestion),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _messages.add(ChatMessage(role: 'model', text: widget.scenario.starter));
    // Beginners see tap-to-reply choices from the very first turn.
    if (_isBeginner) _suggestions = _starterOptions;
    AnalyticsService.log('scenario_started', {'scenario': widget.scenario.id});
    _initVoice();
  }

  /// Load the persisted voice preference and, if on, greet the learner out loud.
  Future<void> _initVoice() async {
    final p = await SharedPreferences.getInstance();
    final on = p.getBool(_kVoicePref) ?? true;
    if (!mounted) return;
    setState(() => _autoSpeak = on);
    if (on) SpeechService.instance.speak(widget.scenario.starter);
  }

  /// First-reply celebration — shown once, ever (persisted).
  Future<void> _maybeCelebrateFirstReply() async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool(_kFirstReply) ?? false) return;
    await p.setBool(_kFirstReply, true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.firstReplyWin),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _toggleVoice() async {
    final on = !_autoSpeak;
    setState(() => _autoSpeak = on);
    if (!on) SpeechService.instance.stopSpeaking();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kVoicePref, on);
  }

  @override
  void dispose() {
    SpeechService.instance.stopListening();
    SpeechService.instance.stopSpeaking();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _sending) return;
    setState(() {
      _messages.add(ChatMessage(role: 'user', text: trimmed));
      _controller.clear();
      _suggestions = [];
      _sending = true;
    });
    _scrollDown();

    try {
      final reply = await ApiService.instance.sendChat(
        scenarioId: widget.scenario.id,
        context: widget.scenario.isCustom ? widget.scenario.setup : null,
        messages: _messages,
      );
      setState(() {
        if (reply.corrections.isNotEmpty && _messages.isNotEmpty) {
          final last = _messages.lastWhere((m) => m.isUser, orElse: () => _messages.last);
          final idx = _messages.indexOf(last);
          if (idx != -1) {
            _messages[idx] = ChatMessage(role: 'user', text: last.text, corrections: reply.corrections);
          }
        }
        _messages.add(ChatMessage(role: 'model', text: reply.reply));
        _suggestions = reply.suggestions;
      });
      // Voice-first: speak the tutor's reply so it's a real spoken conversation.
      if (_autoSpeak) SpeechService.instance.speak(reply.reply);
      // Reward practice: advances daily streak + adds XP.
      GamificationService.instance.recordActivity();
      // Activation: celebrate the learner's very first reply ever — the moment
      // they realise "I can actually do this".
      _maybeCelebrateFirstReply();
    } on DailyLimitException catch (e) {
      setState(() => _limit = e);
    } catch (_) {
      setState(
        () => _messages.add(ChatMessage(role: 'model', text: "Hmm, I didn't catch that. Could you say it again? 🙂")),
      );
    } finally {
      setState(() => _sending = false);
      _scrollDown();
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 160,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(child: Text(widget.scenario.emoji, style: const TextStyle(fontSize: 20))),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.scenario.title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'AI tutor · ${widget.scenario.level}',
                    style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _toggleVoice,
            tooltip: _autoSpeak ? 'Mute tutor voice' : 'Hear tutor voice',
            icon: Icon(_autoSpeak ? Icons.volume_up_rounded : Icons.volume_off_rounded),
          ),
          if (_hasSpoken)
            _finishing
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 18),
                    child: Center(
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: TextButton(onPressed: _finish, child: const Text('Finish')),
                  ),
        ],
      ),
      body: Column(
        children: [
          if (widget.scenario.keywords.isNotEmpty) _KeywordsStrip(keywords: widget.scenario.keywords, accent: _accent),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              itemCount: _messages.length + (_sending ? 1 : 0),
              itemBuilder: (context, i) {
                if (i >= _messages.length) return _TypingBubble(accent: _accent);
                return _MessageBubble(message: _messages[i], accent: _accent, scenarioId: widget.scenario.id);
              },
            ),
          ),
          if (_suggestions.isNotEmpty && _limit == null)
            _SuggestionBar(suggestions: _suggestions, accent: _accent, onTap: _send, beginner: _isBeginner),
          if (_limit != null)
            _LimitBanner(limit: _limit!, onRewarded: () => setState(() => _limit = null))
          else
            _InputBar(controller: _controller, accent: _accent, onSend: _send, enabled: !_sending),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final Color accent;
  final String scenarioId;
  const _MessageBubble({required this.message, required this.accent, required this.scenarioId});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.isUser;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final botColor = isLight ? Colors.white : const Color(0xFF23202B);

    return Column(
      crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          decoration: BoxDecoration(
            gradient: isUser ? AppColors.gradient(accent) : null,
            color: isUser ? null : botColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isUser ? 18 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 18),
            ),
            boxShadow: isLight
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))]
                : null,
          ),
          child: isUser
              ? Text(message.text, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.35))
              : _TappableWords(text: message.text, color: scheme.onSurface),
        ),
        if (!isUser) _TutorActions(text: message.text, accent: accent, scenarioId: scenarioId),
        ...message.corrections.map((c) => _CorrectionCard(correction: c, accent: accent)),
        const SizedBox(height: 10),
      ],
    );
  }
}

/// Under each tutor line: hear it aloud (🔊), translate it (🌐) into the
/// learner's native language, and report it (⚑) if the AI said something
/// offensive or unsafe — the in-app reporting path Play's generative-AI policy
/// requires. Reports land in Firestore and are reviewed from the admin panel.
class _TutorActions extends StatefulWidget {
  final String text;
  final Color accent;
  final String scenarioId;
  const _TutorActions({required this.text, required this.accent, required this.scenarioId});
  @override
  State<_TutorActions> createState() => _TutorActionsState();
}

class _TutorActionsState extends State<_TutorActions> {
  String? _translation;
  bool _loading = false;
  bool _show = false;
  bool _reported = false;
  bool _reporting = false;

  String get _target {
    final n = UserSession.instance.nativeLanguage.trim();
    return (n.isEmpty || n.toLowerCase() == 'other') ? 'Hindi' : n;
  }

  Future<void> _translate() async {
    if (_translation != null) {
      setState(() => _show = !_show); // toggle
      return;
    }
    setState(() => _loading = true);
    final t = await ApiService.instance.translate(text: widget.text, target: _target);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _translation = t;
      _show = true;
    });
    if (t.isEmpty && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.translationUnavailable)));
    }
  }

  /// Ask which kind of problem it is, then send the report. One tap per reason
  /// (no extra confirm step) so reporting something offensive is never a chore.
  Future<void> _report() async {
    if (_reporting || _reported) return;
    final l = AppLocalizations.of(context)!;
    final reason = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(l.reportTitle, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                l.reportSubtitle,
                style: TextStyle(fontSize: 13, color: Theme.of(sheetContext).colorScheme.onSurfaceVariant),
              ),
            ),
            _ReportReasonTile(icon: Icons.report_gmailerrorred_rounded, label: l.reasonOffensive, value: 'offensive'),
            _ReportReasonTile(icon: Icons.dangerous_outlined, label: l.reasonUnsafe, value: 'unsafe'),
            _ReportReasonTile(icon: Icons.error_outline_rounded, label: l.reasonWrong, value: 'wrong'),
            _ReportReasonTile(icon: Icons.more_horiz_rounded, label: l.reasonOther, value: 'other'),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: TextButton(onPressed: () => Navigator.of(sheetContext).pop(), child: Text(l.cancelLabel)),
              ),
            ),
          ],
        ),
      ),
    );
    if (reason == null || !mounted) return;

    setState(() => _reporting = true);
    final ok = await ApiService.instance.reportAiContent(
      text: widget.text,
      reason: reason,
      scenarioId: widget.scenarioId,
    );
    AnalyticsService.log('ai_content_reported', {'reason': reason});
    if (!mounted) return;
    setState(() {
      _reporting = false;
      _reported = ok;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? l.reportThanks : l.reportFailed)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;
    // English-immersion learners don't need an English→English translation.
    final showTranslate = _target.toLowerCase() != 'english';
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ActionChip(
                icon: Icons.volume_up_rounded,
                label: l.listenLabel,
                color: widget.accent,
                onTap: () => SpeechService.instance.speak(widget.text),
              ),
              const SizedBox(width: 6),
              // Shadowing the tutor's own line. The target is known, so this is
              // a real assessment rather than a transcript graded against itself.
              _ActionChip(
                icon: Icons.mic_rounded,
                label: 'Repeat',
                color: widget.accent,
                onTap: () => showSayItSheet(
                  context,
                  phrase: widget.text,
                  accent: widget.accent,
                  source: 'tutor_line',
                ),
              ),
              if (showTranslate) const SizedBox(width: 6),
              if (showTranslate)
                _ActionChip(
                  icon: Icons.translate_rounded,
                  label: _target,
                  color: widget.accent,
                  loading: _loading,
                  active: _show && (_translation?.isNotEmpty ?? false),
                  onTap: _translate,
                ),
              const SizedBox(width: 6),
              // Muted on purpose: always available, never competing with the
              // learning actions above.
              _ActionChip(
                icon: _reported ? Icons.check_rounded : Icons.flag_outlined,
                label: l.reportLabel,
                color: scheme.onSurfaceVariant,
                loading: _reporting,
                onTap: _report,
              ),
            ],
          ),
          if (_show && (_translation?.isNotEmpty ?? false))
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
              decoration: BoxDecoration(
                color: widget.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: widget.accent.withValues(alpha: 0.25)),
              ),
              child: Text(_translation!, style: TextStyle(fontSize: 14, color: scheme.onSurface, height: 1.35)),
            ),
        ],
      ),
    );
  }
}

/// One reason row in the report sheet; popping with its value sends the report.
class _ReportReasonTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _ReportReasonTile({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 21, color: Theme.of(context).colorScheme.onSurfaceVariant),
      title: Text(label, style: const TextStyle(fontSize: 14.5)),
      onTap: () => Navigator.of(context).pop(value),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool loading;
  final bool active;
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.loading = false,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? color.withValues(alpha: 0.16) : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              loading
                  ? SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, color: color))
                  : Icon(icon, size: 15, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Splits tutor text into tappable words → dictionary lookup on tap.
class _TappableWords extends StatelessWidget {
  final String text;
  final Color color;
  const _TappableWords({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    final parts = text.split(RegExp(r'(\s+)'));
    return Wrap(
      children: parts.map((w) {
        if (w.trim().isEmpty) return const SizedBox(width: 4);
        return GestureDetector(
          onTap: () => showDictionarySheet(context, w),
          child: Text('$w ', style: TextStyle(color: color, fontSize: 15, height: 1.4)),
        );
      }).toList(),
    );
  }
}

/// The tutor's fix for something the learner just said, with a mic to say the
/// fixed version back.
///
/// The mic is the point. A correction the learner only READS is a note; one
/// they say out loud is a rep — and because the app knows the sentence it just
/// asked for, the pronunciation can actually be scored against it (which free
/// conversation can never be, having no reference to score against).
class _CorrectionCard extends StatelessWidget {
  final Correction correction;
  final Color accent;
  const _CorrectionCard({required this.correction, required this.accent});

  @override
  Widget build(BuildContext context) {
    const amber = AppColors.correction;
    return Container(
      margin: const EdgeInsets.only(top: 3, bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: amber.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome_rounded, size: 15, color: amber),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  correction.better,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: Color(0xFFB45309)),
                ),
              ),
              const SizedBox(width: 6),
              _SayItButton(
                phrase: correction.better,
                accent: accent,
                source: 'correction',
                color: amber,
              ),
            ],
          ),
          if (correction.reason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3, left: 21),
              child: Text(
                correction.reason,
                style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

/// A small mic that opens the say-it sheet for a phrase the app already knows.
class _SayItButton extends StatelessWidget {
  final String phrase;
  final Color accent;
  final String source;
  final Color color;
  const _SayItButton({required this.phrase, required this.accent, required this.source, required this.color});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () => showSayItSheet(context, phrase: phrase, accent: accent, source: source),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.mic_rounded, size: 13, color: color),
              const SizedBox(width: 3),
              Text('Say it', style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionBar extends StatelessWidget {
  final List<String> suggestions;
  final Color accent;
  final void Function(String) onTap;

  /// For beginners, show a gentle "tap a reply" prompt above the choices.
  final bool beginner;
  const _SuggestionBar({required this.suggestions, required this.accent, required this.onTap, this.beginner = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (beginner)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 6, bottom: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.touch_app_rounded, size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  'Not sure what to say? Tap a reply',
                  style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        SizedBox(
          height: 50,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            children: [
              for (final s in suggestions)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Material(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      onTap: () => onTap(s),
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.north_east_rounded, size: 14, color: accent),
                            const SizedBox(width: 6),
                            Text(
                              s,
                              style: TextStyle(color: accent, fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Words to learn" — the scenario's key vocabulary as tappable chips
/// (tap → dictionary card → save). Smart-vocab surfacing (BRD §5.2).
class _KeywordsStrip extends StatelessWidget {
  final List<String> keywords;
  final Color accent;
  const _KeywordsStrip({required this.keywords, required this.accent});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 6),
            child: Row(
              children: [
                Icon(Icons.school_rounded, size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  'Words to learn — tap to look up',
                  style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final w in keywords)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Material(
                      color: accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        onTap: () => showDictionarySheet(context, w),
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: Text(
                            w,
                            style: TextStyle(color: accent, fontWeight: FontWeight.w600, fontSize: 12.5),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InputBar extends StatefulWidget {
  final TextEditingController controller;
  final Color accent;
  final void Function(String) onSend;
  final bool enabled;
  const _InputBar({required this.controller, required this.accent, required this.onSend, required this.enabled});
  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  static const _red = Color(0xFFEF4444);
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final has = widget.controller.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  /// Voice-first: start listening, stream the transcript into the field, and
  /// auto-send when the recognizer finalizes — so a reply is just "tap, speak".
  Future<void> _startMic() async {
    final s = SpeechService.instance;
    if (s.isListening) {
      await s.stopListening();
      return;
    }
    await s.stopSpeaking(); // don't record the tutor's own voice
    final ok = await s.startListening(
      onResult: (text, isFinal) {
        widget.controller.text = text;
        widget.controller.selection = TextSelection.collapsed(offset: text.length);
        if (isFinal) {
          s.stopListening();
          final t = text.trim();
          if (t.isNotEmpty) widget.onSend(t); // auto-send the spoken reply
        }
      },
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Speech recognition is not available on this device.')));
    }
  }

  void _onPrimaryTap(bool listening) {
    if (!widget.enabled) return;
    if (listening) {
      SpeechService.instance.stopListening();
    } else if (_hasText) {
      widget.onSend(widget.controller.text);
    } else {
      _startMic();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: AnimatedBuilder(
          animation: SpeechService.instance,
          builder: (context, _) {
            final listening = SpeechService.instance.isListening;
            // Primary action: mic when empty (voice-first), send when typing,
            // stop while listening.
            final IconData icon = listening
                ? Icons.stop_rounded
                : (_hasText ? Icons.arrow_upward_rounded : Icons.mic_rounded);
            final Color color = listening ? _red : widget.accent;
            return Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    enabled: widget.enabled && !listening,
                    textInputAction: TextInputAction.send,
                    onSubmitted: widget.onSend,
                    decoration: InputDecoration(
                      hintText: listening ? 'Listening… speak now' : 'Tap the mic to speak, or type…',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _onPrimaryTap(listening),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: listening ? 56 : 52,
                    height: listening ? 56 : 52,
                    decoration: BoxDecoration(
                      gradient: AppColors.gradient(color),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.45),
                          blurRadius: listening ? 18 : 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(icon, color: Colors.white, size: listening ? 30 : 26),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TypingBubble extends StatefulWidget {
  final Color accent;
  const _TypingBubble({required this.accent});
  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isLight ? Colors.white : const Color(0xFF23202B),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
          ),
          boxShadow: isLight
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))]
              : null,
        ),
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final t = (_c.value - i * 0.2) % 1.0;
                final scale = 0.6 + 0.4 * (t < 0.5 ? t * 2 : (1 - t) * 2);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: widget.accent, shape: BoxShape.circle),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}

class _LimitBanner extends StatefulWidget {
  final DailyLimitException limit;
  final VoidCallback onRewarded;
  const _LimitBanner({required this.limit, required this.onRewarded});
  @override
  State<_LimitBanner> createState() => _LimitBannerState();
}

class _LimitBannerState extends State<_LimitBanner> {
  bool _watching = false;

  /// Free learners can watch a rewarded ad for bonus messages today.
  /// Not offered when the server's refusal is one an ad cannot lift.
  bool get _canWatchAd =>
      widget.limit.canEarnMore && PlanStatus.instance.planType == 'free' && AdService.instance.isReady;

  Future<void> _watchAd() async {
    if (_watching) return;
    setState(() => _watching = true);
    await AdService.instance.showRewarded(
      onReward: () async {
        final ok = await ApiService.instance.rewardAd(); // server grants the bonus
        if (!mounted) return;
        if (ok) {
          widget.onRewarded(); // reveal the input again
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('+5 messages added — keep practising! 🎉')));
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("You've used all ad rewards for today.")));
        }
      },
    );
    if (mounted) setState(() => _watching = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context)!;
    final streak = GamificationService.instance.streak;
    // Loss-aversion: if the learner has a streak going, lead with what they'd
    // lose by stopping now — the strongest upsell moment.
    final fairUse = widget.limit.isFairUse;
    // Never upsell a subscriber who has hit the fair-use ceiling: they have
    // already bought the thing the upsell sells, so they get the server's own
    // wording and no Premium button at all.
    final String headline;
    final String sub;
    if (fairUse) {
      headline = "That's a lot of practice today! 🎉";
      sub = widget.limit.message.isNotEmpty
          ? widget.limit.message
          : "You've hit today's fair-use limit. It resets at midnight UTC.";
    } else if (streak >= 2) {
      headline = loc.streakLimitTitle(streak);
      sub = loc.streakLimitSub;
    } else {
      headline = loc.limitReachedTitle;
      sub = loc.limitReachedSub;
    }
    // Hitting a fair-use ceiling is not an error - the learner did nothing
    // wrong - so it does not get the red treatment the "buy more" states do.
    final bg = fairUse ? scheme.primaryContainer : scheme.errorContainer;
    final fg = fairUse ? scheme.onPrimaryContainer : scheme.onErrorContainer;
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(18)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              headline,
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, color: fg),
            ),
            const SizedBox(height: 4),
            Text(
              sub,
              textAlign: TextAlign.center,
              style: TextStyle(color: fg, fontSize: 13),
            ),
            if (!fairUse) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PremiumScreen())),
                icon: const Text('👑', style: TextStyle(fontSize: 14)),
                label: Text(loc.upgradeToPremium),
              ),
            ],
            if (_canWatchAd) ...[
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: _watching ? null : _watchAd,
                icon: _watching
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('🎬', style: TextStyle(fontSize: 14)),
                label: Text(
                  _watching ? 'Loading…' : 'Watch a short ad → +5 messages',
                  style: TextStyle(color: scheme.onErrorContainer, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
