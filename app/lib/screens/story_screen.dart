import 'package:flutter/material.dart';

import '../models/story.dart';
import '../services/analytics_service.dart';
import '../services/gamification_service.dart';
import '../services/speech_service.dart';
import '../theme/app_theme.dart';
import '../widgets/dictionary_sheet.dart';

/// Plays a scripted branching story (BRD §4.1). Shows the tutor's line, lets the
/// learner pick a reply, gives gentle per-choice feedback, and branches to the
/// next node until an ending — then a short summary. Fully offline, no AI.
class StoryScreen extends StatefulWidget {
  final Story story;
  const StoryScreen({super.key, required this.story});
  @override
  State<StoryScreen> createState() => _StoryScreenState();
}

enum _Kind { tutor, learner, note }

class _Msg {
  final _Kind kind;
  final String text;
  final bool good;
  _Msg(this.kind, this.text, {this.good = true});
}

class _StoryScreenState extends State<StoryScreen> {
  final _messages = <_Msg>[];
  final _scroll = ScrollController();
  late StoryNode _node;
  int _turns = 0;
  bool _finished = false;
  Color get _accent => AppTheme.seed;

  @override
  void initState() {
    super.initState();
    _node = widget.story.start;
    _messages.add(_Msg(_Kind.tutor, _node.tutor));
    AnalyticsService.log('story_started', {'story': widget.story.id});
    WidgetsBinding.instance.addPostFrameCallback((_) => _speak(_node.tutor));
  }

  @override
  void dispose() {
    SpeechService.instance.stopListening();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _speak(String text) => SpeechService.instance.speak(text);

  void _choose(StoryChoice choice) {
    setState(() {
      _messages.add(_Msg(_Kind.learner, choice.text, good: choice.good));
      if (choice.note != null) _messages.add(_Msg(_Kind.note, choice.note!, good: choice.good));
      _turns++;
    });
    // Small reward for engaging with the story.
    GamificationService.instance.recordActivity(xpGain: 3);

    if (choice.isEnd) {
      _finish();
      return;
    }
    final next = widget.story.node(choice.next);
    if (next == null) {
      _finish();
      return;
    }
    setState(() {
      _node = next;
      _messages.add(_Msg(_Kind.tutor, next.tutor));
    });
    _speak(next.tutor);
    _scrollDown();
  }

  Future<void> _finish() async {
    if (_finished) return;
    _finished = true;
    await GamificationService.instance.completeScenario(xpBonus: 15);
    AnalyticsService.log('story_completed', {'story': widget.story.id});
    _scrollDown();
    if (mounted) setState(() {});
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent + 200,
            duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
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
              decoration: BoxDecoration(color: _accent.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
              child: Center(child: Text(widget.story.emoji, style: const TextStyle(fontSize: 20))),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.story.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                  Text('Story · ${widget.story.level}',
                      style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              itemCount: _messages.length + (_finished ? 1 : 0),
              itemBuilder: (context, i) {
                if (i >= _messages.length) return _EndingCard(story: widget.story, turns: _turns, accent: _accent);
                return _Bubble(msg: _messages[i], accent: _accent, onListen: _speak);
              },
            ),
          ),
          if (!_finished) _choices(),
        ],
      ),
    );
  }

  Widget _choices() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Row(
                children: [
                  Icon(Icons.touch_app_rounded, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text('Choose your reply',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            for (final c in _node.choices)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: _accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    onTap: () => _choose(c),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                      child: Row(
                        children: [
                          Expanded(child: Text(c.text, style: TextStyle(color: _accent, fontWeight: FontWeight.w600, fontSize: 14.5))),
                          Icon(Icons.arrow_forward_rounded, size: 18, color: _accent),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final _Msg msg;
  final Color accent;
  final Future<void> Function(String) onListen;
  const _Bubble({required this.msg, required this.accent, required this.onListen});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;

    if (msg.kind == _Kind.note) {
      const amber = AppColors.correction;
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: amber.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: amber.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.lightbulb_rounded, size: 16, color: amber),
            const SizedBox(width: 8),
            Expanded(child: Text(msg.text, style: TextStyle(fontSize: 13, color: scheme.onSurface, height: 1.3))),
          ],
        ),
      );
    }

    final isLearner = msg.kind == _Kind.learner;
    return Column(
      crossAxisAlignment: isLearner ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
          decoration: BoxDecoration(
            gradient: isLearner ? AppColors.gradient(accent) : null,
            color: isLearner ? null : (isLight ? Colors.white : const Color(0xFF23202B)),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isLearner ? 18 : 4),
              bottomRight: Radius.circular(isLearner ? 4 : 18),
            ),
            boxShadow: isLight && !isLearner
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))]
                : null,
          ),
          child: isLearner
              ? Text(msg.text, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.35))
              : _TappableWords(text: msg.text, color: scheme.onSurface),
        ),
        if (!isLearner)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () => onListen(msg.text),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.volume_up_rounded, size: 16, color: accent),
                    const SizedBox(width: 4),
                    Text('Listen', style: TextStyle(fontSize: 12, color: accent, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Tap any word in the tutor's line → dictionary card.
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

class _EndingCard extends StatelessWidget {
  final Story story;
  final int turns;
  final Color accent;
  const _EndingCard({required this.story, required this.turns, required this.accent});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const Text('🎉', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 8),
          Text('Story complete!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: scheme.onPrimaryContainer)),
          const SizedBox(height: 4),
          Text('+15 XP  ⭐  ·  $turns replies',
              style: TextStyle(fontSize: 13, color: scheme.onPrimaryContainer.withValues(alpha: 0.85))),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Words from this story — tap to look up',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: scheme.onPrimaryContainer)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final w in story.keywords)
                InkWell(
                  onTap: () => showDictionarySheet(context, w),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: scheme.surface.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(w, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
          ),
        ],
      ),
    );
  }
}
