import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/gamification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/dictionary_sheet.dart';

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
  bool _limitReached = false;

  Color get _accent => AppColors.forScenario(widget.scenario.theme);

  @override
  void initState() {
    super.initState();
    _messages.add(ChatMessage(role: 'model', text: widget.scenario.starter));
  }

  @override
  void dispose() {
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
      // Reward practice: advances daily streak + adds XP.
      GamificationService.instance.recordActivity();
    } on DailyLimitException {
      setState(() => _limitReached = true);
    } catch (_) {
      setState(() => _messages.add(ChatMessage(
          role: 'model', text: "Hmm, I didn't catch that. Could you say it again? 🙂")));
    } finally {
      setState(() => _sending = false);
      _scrollDown();
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent + 160,
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
              child: Center(child: Text(widget.scenario.emoji, style: const TextStyle(fontSize: 20))),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.scenario.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                  Text('AI tutor · ${widget.scenario.level}',
                      style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              itemCount: _messages.length + (_sending ? 1 : 0),
              itemBuilder: (context, i) {
                if (i >= _messages.length) return _TypingBubble(accent: _accent);
                return _MessageBubble(message: _messages[i], accent: _accent);
              },
            ),
          ),
          if (_suggestions.isNotEmpty && !_limitReached) _SuggestionBar(suggestions: _suggestions, accent: _accent, onTap: _send),
          if (_limitReached) const _LimitBanner() else _InputBar(controller: _controller, accent: _accent, onSend: _send, enabled: !_sending),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final Color accent;
  const _MessageBubble({required this.message, required this.accent});

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
        ...message.corrections.map((c) => _CorrectionCard(correction: c)),
        const SizedBox(height: 10),
      ],
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

class _CorrectionCard extends StatelessWidget {
  final Correction correction;
  const _CorrectionCard({required this.correction});

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
                child: Text(correction.better,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: Color(0xFFB45309))),
              ),
            ],
          ),
          if (correction.reason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3, left: 21),
              child: Text(correction.reason,
                  style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }
}

class _SuggestionBar extends StatelessWidget {
  final List<String> suggestions;
  final Color accent;
  final void Function(String) onTap;
  const _SuggestionBar({required this.suggestions, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
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
                        Text(s, style: TextStyle(color: accent, fontWeight: FontWeight.w600, fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final Color accent;
  final void Function(String) onSend;
  final bool enabled;
  const _InputBar({required this.controller, required this.accent, required this.onSend, required this.enabled});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                textInputAction: TextInputAction.send,
                onSubmitted: onSend,
                decoration: const InputDecoration(hintText: 'Type your reply…'),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: enabled ? () => onSend(controller.text) : null,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: AppColors.gradient(accent),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
              ),
            ),
          ],
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
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat();

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
            topLeft: Radius.circular(18), topRight: Radius.circular(18), bottomRight: Radius.circular(18), bottomLeft: Radius.circular(4)),
          boxShadow: isLight ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))] : null,
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
                    child: Container(width: 8, height: 8, decoration: BoxDecoration(color: widget.accent, shape: BoxShape.circle)),
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

class _LimitBanner extends StatelessWidget {
  const _LimitBanner();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(18)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("You've reached today's free limit 🎯",
                style: TextStyle(fontWeight: FontWeight.bold, color: scheme.onErrorContainer)),
            const SizedBox(height: 4),
            Text('Come back tomorrow, or upgrade to Premium for unlimited practice.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onErrorContainer, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
