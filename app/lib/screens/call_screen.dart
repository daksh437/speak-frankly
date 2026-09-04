import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/analytics_service.dart';
import '../services/api_service.dart';
import '../services/gamification_service.dart';
import '../services/progress_history.dart';
import '../services/rate_prompt.dart';
import '../services/speech_service.dart';
import '../theme/app_theme.dart';
import 'session_report_screen.dart';

/// A three-minute spoken conversation, shaped like a phone call.
///
/// WHY THIS EXISTS ALONGSIDE THE CHAT SCREEN
/// The chat screen has a keyboard, and a keyboard is an escape hatch. Onboarding
/// asks what the learner's problem is and most answer some version of "I freeze
/// when I have to speak" — and then the app hands them a text box, which is the
/// one way to practise that never makes them do the thing they are afraid of.
/// A call has no text box. You speak or nothing happens.
///
/// It is deliberately short. Three minutes is small enough to say yes to on a
/// bad day, which is the only length that survives contact with a real week.
///
/// WHAT THIS IS NOT
/// It is not a real call. The screen has to stay on and in front, because the
/// speech plugins only run with the app foregrounded, and the tutor cannot be
/// interrupted mid-sentence — while it speaks the microphone is closed, or it
/// would transcribe its own voice. Both are stated here rather than discovered.
class CallScreen extends StatefulWidget {
  final Scenario scenario;
  const CallScreen({super.key, required this.scenario});
  @override
  State<CallScreen> createState() => _CallScreenState();
}

enum _Phase { connecting, tutorSpeaking, listening, thinking, ended }

class _CallScreenState extends State<CallScreen> {
  /// How long a call runs before the tutor winds it up.
  static const _target = Duration(minutes: 3);

  /// Silence that ends the learner's turn. Shorter than the chat screen's: in a
  /// conversation, three seconds of nothing after every sentence reads as the
  /// app having crashed.
  static const _turnPause = Duration(milliseconds: 1600);

  final _messages = <ChatMessage>[];
  _Phase _phase = _Phase.connecting;
  String _heard = '';
  String _lastTutorLine = '';
  Duration _elapsed = Duration.zero;
  Timer? _ticker;
  bool _finishing = false;

  /// Set once the clock runs out, so the call ends after the turn in progress
  /// rather than cutting the tutor off mid-sentence.
  bool _timeUp = false;

  Color get _accent => AppColors.forScenario(widget.scenario.theme);

  @override
  void initState() {
    super.initState();
    AnalyticsService.log('call_started', {'scenario': widget.scenario.id});
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(seconds: 1));
      if (_elapsed >= _target) _timeUp = true;
    });
    _run();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    SpeechService.instance.stopListening();
    SpeechService.instance.stopSpeaking();
    super.dispose();
  }

  bool get _live => mounted && _phase != _Phase.ended;

  /// Open the call with the scenario's own first line.
  Future<void> _run() async {
    final opener = widget.scenario.starter.trim().isEmpty
        ? 'Hi! Good to hear from you. How are you doing today?'
        : widget.scenario.starter;
    _messages.add(ChatMessage(role: 'model', text: opener));
    await _say(opener);
    if (_live) _listen();
  }

  /// Speak a line and wait for it to finish. The microphone stays shut while
  /// this runs — an open mic would record the tutor and answer itself.
  Future<void> _say(String text) async {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.tutorSpeaking;
      _lastTutorLine = text;
      _heard = '';
    });
    await SpeechService.instance.speak(text);
  }

  Future<void> _listen() async {
    if (!_live) return;
    setState(() {
      _phase = _Phase.listening;
      _heard = '';
    });
    var handled = false;
    final ok = await SpeechService.instance.startListening(
      pauseFor: _turnPause,
      onResult: (text, isFinal) {
        if (!_live) return;
        setState(() => _heard = text);
        if (isFinal && !handled) {
          handled = true;
          _send(text);
        }
      },
    );
    if (!ok && mounted) {
      setState(() => _phase = _Phase.ended);
      _showUnavailable();
    }
  }

  Future<void> _send(String said) async {
    final text = said.trim();
    // Silence, or noise the recogniser could not read. Nudging is friendlier
    // than sending an empty turn, and costs no AI call.
    if (text.isEmpty) {
      if (!_live) return;
      await _say("Sorry, I didn't catch that. Could you say it again?");
      if (_live) _listen();
      return;
    }

    if (!mounted) return;
    setState(() {
      _messages.add(ChatMessage(role: 'user', text: text));
      _phase = _Phase.thinking;
    });

    TutorReply reply;
    try {
      reply = await ApiService.instance.sendChat(
        scenarioId: widget.scenario.id,
        context: widget.scenario.isCustom ? widget.scenario.setup : null,
        messages: _messages,
      );
    } on DailyLimitException catch (e) {
      if (!mounted) return;
      // The call is over either way; the report screen and the paywall are both
      // better places to explain why than a voice line nobody can act on.
      await _say(e.isFairUse
          ? "That's a lot of practice today. Let's pick this up tomorrow."
          : "That's all the practice I can give you right now. Let's finish here.");
      await _finish();
      return;
    } catch (_) {
      if (!_live) return;
      await _say("Sorry, I lost you for a second. Could you say that again?");
      if (_live) _listen();
      return;
    }

    if (!mounted) return;
    // Corrections are collected but not spoken. Reading someone's grammar back
    // to them mid-call is exactly the interruption this format exists to avoid;
    // they belong in the report at the end, where they can be looked at.
    setState(() {
      if (reply.corrections.isNotEmpty) {
        final i = _messages.lastIndexWhere((m) => m.isUser);
        if (i != -1) {
          _messages[i] = ChatMessage(
            role: 'user',
            text: _messages[i].text,
            corrections: reply.corrections,
          );
        }
      }
      _messages.add(ChatMessage(role: 'model', text: reply.reply));
    });
    GamificationService.instance.recordActivity();

    await _say(reply.reply);
    if (!_live) return;
    if (_timeUp) {
      await _say("That's our time. You did really well — same time tomorrow?");
      await _finish();
    } else {
      _listen();
    }
  }

  void _showUnavailable() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Speech recognition is not available on this device.')),
    );
    Navigator.of(context).pop();
  }

  /// End the call and go to the same report a chat session produces.
  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    _ticker?.cancel();
    if (mounted) setState(() => _phase = _Phase.ended);
    await SpeechService.instance.stopListening();
    await SpeechService.instance.stopSpeaking();

    final userTurns = _messages.where((m) => m.isUser).toList();

    // A call the learner never spoke in is not a session. Recording it would
    // put a zero-turn day into the progress history and drag the trend down for
    // something that never happened.
    if (userTurns.isEmpty) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    ProgressHistory.instance.recordSession(
      turns: userTurns.length,
      corrections: userTurns.fold<int>(0, (s, m) => s + m.corrections.length),
    );
    await GamificationService.instance.completeScenario();
    AnalyticsService.log('call_completed', {
      'scenario': widget.scenario.id,
      'turns': userTurns.length,
      'seconds': _elapsed.inSeconds,
    });
    RatePrompt.onSessionComplete();

    Map<String, dynamic> feedback;
    try {
      feedback = await ApiService.instance.sendFeedback(
        scenarioId: widget.scenario.id,
        messages: _messages,
      );
    } catch (_) {
      feedback = {};
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => SessionReportScreen(feedback: feedback, xpEarned: 20),
      ),
    );
  }

  // ---- UI -----------------------------------------------------------------

  String get _status => switch (_phase) {
        _Phase.connecting => 'Connecting…',
        _Phase.tutorSpeaking => 'Speaking…',
        _Phase.listening => 'Listening — go ahead',
        _Phase.thinking => 'Thinking…',
        _Phase.ended => 'Call ended',
      };

  String get _clock {
    final m = _elapsed.inMinutes.toString().padLeft(2, '0');
    final s = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      // Leaving by the back button must still end the call properly, or the
      // tutor keeps talking to an empty room.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish();
      },
      child: Scaffold(
        backgroundColor: scheme.surface,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Column(
              children: [
                Text(widget.scenario.title,
                    style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text(_clock,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                      fontFeatures: const [],
                    )),
                const Spacer(),
                _Orb(accent: _accent, phase: _phase, emoji: widget.scenario.emoji),
                const SizedBox(height: 26),
                Text(_status,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                const SizedBox(height: 10),
                // What the recogniser has caught so far. The only text on the
                // screen, and it is feedback rather than something to read —
                // it is how a learner knows they are being heard at all.
                SizedBox(
                  height: 52,
                  child: Text(
                    _heard,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14.5, color: scheme.onSurfaceVariant, height: 1.35),
                  ),
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _RoundButton(
                      icon: Icons.replay_rounded,
                      label: 'Repeat',
                      color: scheme.surfaceContainerHighest,
                      iconColor: scheme.onSurface,
                      // Hearing it again is the single most useful thing a
                      // learner can ask for, and it costs no AI call.
                      onTap: _phase == _Phase.listening && _lastTutorLine.isNotEmpty
                          ? () async {
                              await SpeechService.instance.stopListening();
                              await _say(_lastTutorLine);
                              if (_live) _listen();
                            }
                          : null,
                    ),
                    _RoundButton(
                      icon: Icons.call_end_rounded,
                      label: 'End',
                      color: const Color(0xFFEF4444),
                      iconColor: Colors.white,
                      big: true,
                      onTap: _phase == _Phase.ended ? null : _finish,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The thing on screen that is alive: a ring that pulses while the tutor talks
/// and rides the microphone level while the learner does.
class _Orb extends StatelessWidget {
  final Color accent;
  final _Phase phase;
  final String emoji;
  const _Orb({required this.accent, required this.phase, required this.emoji});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SpeechService.instance,
      builder: (context, _) {
        final levels = SpeechService.instance.waveform;
        final level = (phase == _Phase.listening && levels.isNotEmpty) ? levels.last : 0.0;
        final ringed = phase == _Phase.tutorSpeaking || phase == _Phase.listening;
        final size = 168.0 + (phase == _Phase.listening ? level * 26 : 0);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.gradient(accent),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: ringed ? 0.45 : 0.2),
                blurRadius: phase == _Phase.listening ? 40 + level * 30 : 26,
                spreadRadius: phase == _Phase.listening ? level * 8 : 0,
              ),
            ],
          ),
          child: Center(
            child: phase == _Phase.thinking
                ? const SizedBox(
                    width: 34, height: 34,
                    child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                  )
                : Text(emoji, style: const TextStyle(fontSize: 62)),
          ),
        );
      },
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color iconColor;
  final VoidCallback? onTap;
  final bool big;
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.iconColor,
    required this.onTap,
    this.big = false,
  });

  @override
  Widget build(BuildContext context) {
    final side = big ? 68.0 : 56.0;
    final enabled = onTap != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: enabled ? 1 : 0.35,
          child: Material(
            color: color,
            shape: const CircleBorder(),
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: side,
                height: side,
                child: Icon(icon, color: iconColor, size: big ? 30 : 24),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            )),
      ],
    );
  }
}
