import 'package:flutter/material.dart';

import '../services/gamification_service.dart';
import '../services/speaking_phrases.dart';
import '../services/speech_service.dart';
import '../theme/app_theme.dart';

/// Listen-and-imitate speaking practice. Hear a phrase (TTS), say it back, and
/// get a pronunciation score from the on-device recognizer. Earns XP.
class SpeakScreen extends StatefulWidget {
  const SpeakScreen({super.key});
  @override
  State<SpeakScreen> createState() => _SpeakScreenState();
}

class _SpeakScreenState extends State<SpeakScreen> {
  List<String>? _phrases;
  bool _loadingPhrases = true;

  int _index = 0;
  String _recognized = '';
  int? _score;
  bool _scored = false;

  String get _phrase => _phrases![_index];

  @override
  void initState() {
    super.initState();
    _loadPhrases();
  }

  Future<void> _loadPhrases({bool forceRefresh = false}) async {
    setState(() => _loadingPhrases = true);
    final list = await SpeakingPhrases.getToday(forceRefresh: forceRefresh);
    if (!mounted) return;
    SpeechService.instance.stopListening();
    setState(() {
      _phrases = list;
      _loadingPhrases = false;
      _index = 0;
      _recognized = '';
      _score = null;
      _scored = false;
    });
  }

  Future<void> _listen() => SpeechService.instance.speak(_phrase);

  Future<void> _record() async {
    setState(() {
      _recognized = '';
      _score = null;
      _scored = false;
    });
    final ok = await SpeechService.instance.startListening(
      onResult: (text, isFinal) {
        if (!mounted) return;
        setState(() => _recognized = text);
        if (isFinal && !_scored) _evaluate(text);
      },
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Speech recognition is not available on this device.')),
      );
    }
  }

  void _evaluate(String said) {
    _scored = true;
    final score = pronunciationScore(_phrase, said);
    final xp = score >= 85 ? 10 : (score >= 60 ? 6 : 2);
    GamificationService.instance.recordActivity(xpGain: xp);
    setState(() => _score = score);
  }

  void _next() {
    SpeechService.instance.stopListening();
    setState(() {
      _index = (_index + 1) % _phrases!.length;
      _recognized = '';
      _score = null;
      _scored = false;
    });
  }

  @override
  void dispose() {
    SpeechService.instance.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Speaking Practice'),
        actions: [
          IconButton(
            onPressed: _loadingPhrases ? null : () => _loadPhrases(forceRefresh: true),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'New phrases',
          ),
          if (_phrases != null)
            Center(child: Text('${_index + 1}/${_phrases!.length}', style: TextStyle(color: scheme.onSurfaceVariant))),
          const SizedBox(width: 14),
        ],
      ),
      body: (_loadingPhrases || _phrases == null)
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Text('Say this out loud', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14)),
              const SizedBox(height: 16),
              // Phrase card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.light ? Colors.white : const Color(0xFF1E1B26),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: Theme.of(context).brightness == Brightness.light
                      ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, 10))]
                      : null,
                ),
                child: Column(
                  children: [
                    Text(_phrase, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.35)),
                    const SizedBox(height: 18),
                    OutlinedButton.icon(
                      onPressed: _listen,
                      icon: const Icon(Icons.volume_up_rounded),
                      label: const Text('Listen'),
                      style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (_recognized.isNotEmpty || _score != null) _ResultCard(recognized: _recognized, score: _score),
              const Spacer(),
              // Mic button
              AnimatedBuilder(
                animation: SpeechService.instance,
                builder: (context, _) {
                  final listening = SpeechService.instance.isListening;
                  return Column(
                    children: [
                      Text(listening ? 'Listening… tap to stop' : 'Tap the mic and speak',
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: listening ? SpeechService.instance.stopListening : _record,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: listening ? 88 : 76,
                          height: listening ? 88 : 76,
                          decoration: BoxDecoration(
                            gradient: AppColors.gradient(listening ? const Color(0xFFEF4444) : AppTheme.seed),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: (listening ? const Color(0xFFEF4444) : AppTheme.seed).withValues(alpha: 0.45),
                                blurRadius: listening ? 26 : 16,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Icon(listening ? Icons.stop_rounded : Icons.mic_rounded, color: Colors.white, size: 34),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(onPressed: _next, child: const Text('Next phrase')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final String recognized;
  final int? score;
  const _ResultCard({required this.recognized, required this.score});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color color;
    String label;
    if (score == null) {
      color = scheme.onSurfaceVariant;
      label = '';
    } else if (score! >= 85) {
      color = AppColors.success;
      label = 'Excellent! 🌟';
    } else if (score! >= 60) {
      color = const Color(0xFFF59E0B);
      label = 'Good, keep going 👍';
    } else {
      color = const Color(0xFFEF4444);
      label = 'Keep practicing 🔁';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('You said', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
              const Spacer(),
              if (score != null)
                Text('$score%', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: color)),
            ],
          ),
          const SizedBox(height: 4),
          Text(recognized.isEmpty ? '…' : '"$recognized"', style: const TextStyle(fontSize: 15)),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          ],
        ],
      ),
    );
  }
}
