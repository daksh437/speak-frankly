import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/dictionary_sheet.dart';

/// The core experience: a real-life conversation with the AI tutor.
/// - Tutor opens with the scenario starter.
/// - Learner types (mic can be added later); tutor replies in character.
/// - Tap ANY word to see its dictionary card.
/// - Gentle corrections appear under the learner's own messages.
/// - Quick-reply suggestion chips help beginners keep going.
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

  @override
  void initState() {
    super.initState();
    // Seed the conversation with the scenario's opening line.
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
        // Attach corrections to the learner's last message.
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
        _scroll.animateTo(_scroll.position.maxScrollExtent + 120,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.scenario.emoji}  ${widget.scenario.title}')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_sending ? 1 : 0),
              itemBuilder: (context, i) {
                if (i >= _messages.length) return const _TypingBubble();
                return _MessageBubble(message: _messages[i]);
              },
            ),
          ),
          if (_suggestions.isNotEmpty && !_limitReached) _SuggestionBar(suggestions: _suggestions, onTap: _send),
          if (_limitReached) const _LimitBanner() else _InputBar(controller: _controller, onSend: _send, enabled: !_sending),
        ],
      ),
    );
  }
}

/// A chat bubble. Tutor (model) messages have every word tappable for dictionary.
class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.isUser;
    return Column(
      crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          decoration: BoxDecoration(
            color: isUser ? scheme.primary : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: _TappableWords(
            text: message.text,
            color: isUser ? scheme.onPrimary : scheme.onSurface,
          ),
        ),
        ...message.corrections.map((c) => _CorrectionChip(correction: c)),
        const SizedBox(height: 10),
      ],
    );
  }
}

/// Splits text into tappable words → dictionary lookup on tap.
class _TappableWords extends StatelessWidget {
  final String text;
  final Color color;
  const _TappableWords({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    final parts = text.split(RegExp(r'(\s+)'));
    return Wrap(
      children: parts.map((w) {
        if (w.trim().isEmpty) return Text(' ', style: TextStyle(color: color));
        return GestureDetector(
          onTap: () => showDictionarySheet(context, w),
          child: Text('$w ', style: TextStyle(color: color, fontSize: 15, height: 1.3)),
        );
      }).toList(),
    );
  }
}

class _CorrectionChip extends StatelessWidget {
  final Correction correction;
  const _CorrectionChip({required this.correction});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lightbulb_outline, size: 15, color: Colors.orange),
              const SizedBox(width: 6),
              Flexible(child: Text('Better: ${correction.better}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
            ],
          ),
          if (correction.reason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 21),
              child: Text(correction.reason, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ),
        ],
      ),
    );
  }
}

class _SuggestionBar extends StatelessWidget {
  final List<String> suggestions;
  final void Function(String) onTap;
  const _SuggestionBar({required this.suggestions, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: suggestions
            .map((s) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(label: Text(s), onPressed: () => onTap(s)),
                ))
            .toList(),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final void Function(String) onSend;
  final bool enabled;
  const _InputBar({required this.controller, required this.onSend, required this.enabled});

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
                decoration: InputDecoration(
                  hintText: 'Type your reply…',
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FloatingActionButton.small(
              onPressed: enabled ? () => onSend(controller.text) : null,
              child: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const SizedBox(
          width: 34,
          child: Text('…', style: TextStyle(fontSize: 20)),
        ),
      ),
    );
  }
}

class _LimitBanner extends StatelessWidget {
  const _LimitBanner();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.errorContainer,
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("You've reached today's free limit 🎯",
              style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onErrorContainer)),
          const SizedBox(height: 4),
          Text('Come back tomorrow, or upgrade to Premium for unlimited practice.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer, fontSize: 13)),
        ],
      ),
    );
  }
}
