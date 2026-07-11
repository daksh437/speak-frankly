import 'package:flutter/material.dart';

import '../services/offline_service.dart';
import '../services/user_session.dart';
import '../theme/app_theme.dart';

/// Offline downloads (BRD §7.2). One tap caches the scenario library, speaking
/// phrases, and picture-match items for the learner's level so they can keep
/// practising with no connection.
class OfflineDownloadsScreen extends StatefulWidget {
  const OfflineDownloadsScreen({super.key});
  @override
  State<OfflineDownloadsScreen> createState() => _OfflineDownloadsScreenState();
}

class _OfflineDownloadsScreenState extends State<OfflineDownloadsScreen> {
  @override
  void initState() {
    super.initState();
    OfflineService.instance.load();
  }

  Future<void> _download() async {
    final ok = await OfflineService.instance.download();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Downloaded for offline use ✅' : 'Download failed — check your connection.')),
    );
  }

  Future<void> _clear() async {
    await OfflineService.instance.clearPack();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offline pack removed.')));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Offline downloads')),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: OfflineService.instance,
          builder: (context, _) {
            final svc = OfflineService.instance;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              children: [
                Center(
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(gradient: AppColors.gradient(AppTheme.seed), shape: BoxShape.circle),
                    child: const Center(child: Text('📥', style: TextStyle(fontSize: 40))),
                  ),
                ),
                const SizedBox(height: 16),
                const Center(child: Text('Practise offline', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
                const SizedBox(height: 8),
                Center(
                  child: Text('Download scenarios, speaking phrases and games for your level — then keep learning with no internet.',
                      textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14, height: 1.35)),
                ),
                const SizedBox(height: 24),
                _row(context, '💬', 'Scenarios', svc.isDownloaded ? '${svc.scenarioCount} conversations' : 'Role-play conversations'),
                _row(context, '🎙️', 'Speaking phrases', svc.isDownloaded ? '${svc.phraseCount} phrases' : 'Shadowing practice set'),
                _row(context, '🖼️', 'Picture match', svc.isDownloaded ? '${svc.pictureCount} items' : 'Vocabulary game'),
                const SizedBox(height: 18),
                if (svc.isDownloaded)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.success.withValues(alpha: 0.3))),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text('Ready offline · level ${svc.level ?? UserSession.instance.level}'
                              '${svc.downloadedAt != null ? ' · ${_ago(svc.downloadedAt!)}' : ''}',
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: svc.downloading ? null : _download,
                    icon: svc.downloading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.download_rounded),
                    label: Text(svc.downloading ? 'Downloading…' : (svc.isDownloaded ? 'Update pack' : 'Download for offline')),
                  ),
                ),
                if (svc.isDownloaded && !svc.downloading) ...[
                  const SizedBox(height: 8),
                  TextButton(onPressed: _clear, child: const Text('Remove offline pack')),
                ],
                const SizedBox(height: 12),
                Text('Tip: the AI conversation itself needs internet, but downloaded scenarios, phrases and games work fully offline.',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, height: 1.35)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String emoji, String title, String sub) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                Text(sub, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inDays < 1) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}
