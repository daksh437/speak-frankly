import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';

/// In-app admin panel (visible only to admins — see AdminService / backend
/// /admin). Everything on this screen is live server data: plan mix, signups,
/// activity, AI health, the auth-rollout counters and the report queue.
///
/// Nothing here is faked or defaulted — a value the server could not compute
/// renders as a dash, and a failed load shows the real reason instead of a
/// screen full of zeros.
class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});
  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _admins = [];
  List<Map<String, dynamic>> _reports = [];
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ApiService.instance.adminStats(),
        ApiService.instance.adminListAdmins(),
        ApiService.instance.adminListReports(),
        ApiService.instance.adminUsers(limit: 50),
      ]);
      _stats = results[0] as Map<String, dynamic>;
      _admins = (results[1] as List).cast<Map<String, dynamic>>();
      _reports = (results[2] as List).cast<Map<String, dynamic>>();
      _users = (results[3] as List).cast<Map<String, dynamic>>();
    } on AdminApiException catch (e) {
      _error = e.friendly;
    } catch (e) {
      _error = 'Could not reach the server. Check your connection and try again.';
    }
    if (mounted) setState(() => _loading = false);
  }

  void _snack(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _addAdmin() async {
    final email = await _promptEmail('Add admin', 'Teammate\'s Gmail', 'e.g. name@gmail.com');
    if (email == null || email.isEmpty) return;
    final ok = await ApiService.instance.adminAddAdmin(email);
    _snack(ok ? 'Added $email as admin' : 'Could not add admin');
    if (ok) _load();
  }

  Future<void> _removeAdmin(String email) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove admin?'),
        content: Text('Remove admin access for $email?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirm != true) return;
    final ok = await ApiService.instance.adminRemoveAdmin(email);
    _snack(ok ? 'Removed $email' : 'Could not remove');
    if (ok) _load();
  }

  Future<void> _grantPremium([String? prefill]) async {
    final email = prefill ?? await _promptEmail('Grant premium', 'User\'s account email', 'user@gmail.com');
    if (email == null || email.isEmpty) return;
    final res = await ApiService.instance.adminGrantPremium(email, days: 31);
    _snack(res['ok'] == true ? 'Premium granted to $email (31 days)' : 'Failed: ${res['error'] ?? 'error'}');
    if (res['ok'] == true) _load();
  }

  Future<String?> _promptEmail(String title, String label, String hint) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(labelText: label, hintText: hint),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
  }

  // ---- helpers -------------------------------------------------------------

  Map<String, dynamic> _sub(String key) => (_stats[key] as Map<String, dynamic>?) ?? const {};

  int get _newReports => _reports.where((r) => (r['status'] ?? 'new') == 'new').length;

  String _when(String? isoStr) {
    if (isoStr == null || isoStr.length < 10) return '—';
    final d = DateTime.tryParse(isoStr)?.toLocal();
    if (d == null) return isoStr.substring(0, 10);
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return isoStr.substring(0, 10);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ai = _sub('ai');
    final auth = _sub('auth');
    final config = _sub('config');
    final degraded = _stats['degraded'] == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin panel'),
        actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  if (_error != null) _errorCard(_error!),
                  if (degraded)
                    _noteCard('The server could not reach Firestore, so user numbers are unavailable.',
                        const Color(0xFFF59E0B)),
                  // The server reads a bounded number of user documents to build
                  // the breakdowns. Past that bound they describe a sample, and
                  // saying so beats letting them read as the whole picture.
                  if (_stats['partial'] == true)
                    _noteCard(
                        'Total users is exact. The breakdowns below cover the first '
                        '${_stats['scanned'] ?? 0} accounts only.',
                        const Color(0xFF0EA5E9)),

                  // ---- Plan mix ----
                  const _SectionTitle('Learners'),
                  Row(children: [
                    _stat('Total users', _stats['total'], const Color(0xFF6366F1)),
                    const SizedBox(width: 10),
                    _stat('Premium', _stats['premium'], const Color(0xFFF59E0B),
                        sub: _premiumBreakdown()),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    _stat('On trial', _stats['trial'], const Color(0xFF00C2A8)),
                    const SizedBox(width: 10),
                    _stat('Free', _stats['free'], scheme.onSurfaceVariant),
                  ]),
                  const SizedBox(height: 18),

                  // ---- Growth ----
                  const _SectionTitle('Signups'),
                  Row(children: [
                    _stat('New today', _stats['newToday'], const Color(0xFF10B981)),
                    const SizedBox(width: 10),
                    _stat('Last 7 days', _stats['new7d'], const Color(0xFF10B981)),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    _stat('Last 30 days', _stats['new30d'], const Color(0xFF10B981)),
                    const SizedBox(width: 10),
                    _stat('Devices on trial', _stats['trialDevices'], scheme.onSurfaceVariant,
                        sub: 'one trial per device'),
                  ]),
                  const SizedBox(height: 18),

                  // ---- Activity ----
                  const _SectionTitle('Activity'),
                  Row(children: [
                    _stat('Active today', _stats['activeToday'], const Color(0xFF6366F1),
                        sub: 'sent a message'),
                    const SizedBox(width: 10),
                    _stat('Active 7 days', _stats['active7d'], const Color(0xFF6366F1)),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    _stat('Messages today', _stats['messagesToday'], const Color(0xFF8B5CF6)),
                    const SizedBox(width: 10),
                    _stat('Messages all time', _stats['messagesAllTime'], const Color(0xFF8B5CF6)),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    _stat('Helper calls today', _stats['auxToday'], const Color(0xFF0EA5E9),
                        sub: 'translate, phrases, games'),
                    const SizedBox(width: 10),
                    _stat('Hit daily limit', _stats['atLimitToday'], const Color(0xFFEF4444),
                        sub: 'upgrade prompts today'),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    _stat('Ad rewards today', _stats['adRewardsToday'], const Color(0xFFF59E0B)),
                    const SizedBox(width: 10),
                    _stat('Reports', _stats['reportsTotal'], const Color(0xFFEF4444),
                        sub: '${_stats['reportsNew'] ?? 0} new'),
                  ]),
                  const SizedBox(height: 18),

                  // ---- Server health (this backend instance) ----
                  const _SectionTitle('AI + server'),
                  _kvCard([
                    _kv('Gemini', config['geminiLive'] == true ? 'live (${config['geminiModel']})' : 'MOCK mode — no API key'),
                    _kv('Fallback models', ((config['geminiModels'] as List?) ?? []).skip(1).join(', ')),
                    _kv('AI calls (since restart)', '${ai['calls'] ?? '—'} · ${ai['ok'] ?? 0} ok · ${ai['failed'] ?? 0} failed'),
                    _kv('Served by fallback', '${ai['fallbacks'] ?? 0}'),
                    if ((ai['lastError'] ?? '').toString().isNotEmpty)
                      _kv('Last AI error', ai['lastError'].toString(), warn: true),
                    _kv('Token auth', auth['requireAuthToken'] == true ? 'required' : 'soft rollout'),
                    _kv('Verified / legacy calls', '${auth['verified'] ?? 0} / ${auth['legacyHeader'] ?? 0}',
                        warn: (auth['legacyHeader'] ?? 0) is int && (auth['legacyHeader'] ?? 0) > 0),
                    _kv('Free plan', '${config['dailyMessagesFree'] ?? '—'} messages + ${config['dailyAuxFree'] ?? '—'} helper calls/day'),
                    _kv('Trial', '${config['trialDays'] ?? '—'} days'),
                    if (_stats['generatedAt'] != null) _kv('Updated', _when(_stats['generatedAt'].toString())),
                  ]),
                  const SizedBox(height: 18),

                  // ---- Reported AI replies ----
                  _SectionTitle('Reported AI replies${_newReports > 0 ? ' ($_newReports new)' : ''}'),
                  if (_reports.isEmpty)
                    Text('Nothing reported yet.', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5))
                  else
                    ..._reports.take(20).map(_reportTile),
                  const SizedBox(height: 18),

                  // ---- Real users ----
                  _SectionTitle('Users (${_users.length} shown)'),
                  if (_users.isEmpty)
                    Text('No user documents yet.', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5))
                  else
                    ..._users.map(_userTile),
                  const SizedBox(height: 18),

                  // ---- Admins ----
                  const _SectionTitle('Admins'),
                  Text('People who can open this panel. Add a teammate by their Gmail.',
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
                  const SizedBox(height: 10),
                  ..._admins.map(_adminTile),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _addAdmin,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('Add admin by Gmail'),
                  ),
                  const SizedBox(height: 18),

                  // ---- Support tools ----
                  const _SectionTitle('Support tools'),
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: Icon(Icons.workspace_premium_rounded, color: AppTheme.seed),
                      title: const Text('Grant premium to a user'),
                      subtitle: const Text('By account email · 31 days'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _grantPremium(),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  String? _premiumBreakdown() {
    final v = _stats['premiumVerified'];
    final g = _stats['premiumGranted'];
    if (v == null && g == null) return null;
    return '${v ?? 0} paid · ${g ?? 0} granted';
  }

  Widget _errorCard(String msg) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444)),
            const SizedBox(width: 10),
            Expanded(child: Text(msg, style: const TextStyle(fontSize: 13, height: 1.3))),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );

  Widget _noteCard(String msg, Color color) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Text(msg, style: const TextStyle(fontSize: 12.5, height: 1.3)),
      );

  Widget _stat(String label, Object? value, Color color, {String? sub}) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
        decoration: BoxDecoration(
          color: isLight ? Colors.white : const Color(0xFF1E1B26),
          borderRadius: BorderRadius.circular(16),
          boxShadow: isLight ? [BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, 5))] : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A null value means the server could not compute it — show a dash
            // rather than a zero that reads as real data.
            Text('${value ?? '—'}', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            if (sub != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(sub, style: TextStyle(fontSize: 10.5, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.8))),
              ),
          ],
        ),
      ),
    );
  }

  Widget _kvCard(List<Widget> rows) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Column(children: rows),
        ),
      );

  Widget _kv(String k, String v, {bool warn = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 4, child: Text(k, style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant))),
          Expanded(
            flex: 5,
            child: Text(
              v.isEmpty ? '—' : v,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: warn ? const Color(0xFFF59E0B) : scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _reviewReport(String id) async {
    final ok = await ApiService.instance.adminReviewReport(id);
    _snack(ok ? 'Marked reviewed' : 'Could not update');
    if (ok) _load();
  }

  Widget _reportTile(Map<String, dynamic> r) {
    final scheme = Theme.of(context).colorScheme;
    final reason = (r['reason'] ?? 'other').toString();
    final isNew = (r['status'] ?? 'new') == 'new';
    final color = switch (reason) {
      'offensive' || 'unsafe' => const Color(0xFFEF4444),
      'wrong' => const Color(0xFFF59E0B),
      _ => scheme.onSurfaceVariant,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(isNew ? Icons.flag_rounded : Icons.check_circle_outline_rounded,
            color: isNew ? color : scheme.onSurfaceVariant),
        title: Text((r['text'] ?? '').toString(),
            maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, height: 1.3)),
        subtitle: Text(
          [
            reason,
            _when(r['createdAt'] as String?),
            if ((r['email'] ?? '').toString().isNotEmpty) r['email'],
            if ((r['scenarioId'] ?? '').toString().isNotEmpty) r['scenarioId'],
          ].join(' · '),
          style: TextStyle(fontSize: 11.5, color: color),
        ),
        trailing: isNew
            ? IconButton(
                tooltip: 'Mark reviewed',
                onPressed: () => _reviewReport((r['id'] ?? '').toString()),
                icon: const Icon(Icons.done_rounded),
              )
            : null,
        isThreeLine: true,
      ),
    );
  }

  Widget _userTile(Map<String, dynamic> u) {
    final scheme = Theme.of(context).colorScheme;
    final plan = (u['plan'] ?? 'free').toString();
    final email = (u['email'] ?? '').toString();
    final name = (u['displayName'] ?? '').toString();
    final title = email.isNotEmpty ? email : (name.isNotEmpty ? name : (u['uid'] ?? '').toString());
    final planColor = switch (plan) {
      'premium' => const Color(0xFFF59E0B),
      'trial' => const Color(0xFF00C2A8),
      _ => scheme.onSurfaceVariant,
    };
    // A doc with no Firebase account behind it is a leftover test/curl record,
    // not a learner — label it so the list stays honest.
    final orphan = u['hasAccount'] == false;
    final facts = [
      if (orphan) 'no account (test doc)',
      if ((u['level'] ?? '').toString().isNotEmpty) u['level'],
      '${u['messagesAllTime'] ?? 0} msgs',
      '${u['streak'] ?? 0}d streak',
      '${u['savedWords'] ?? 0} words',
      'seen ${_when(u['lastSeenAt'] as String?)}',
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: (orphan ? scheme.onSurfaceVariant : planColor).withValues(alpha: 0.15),
          child: orphan
              ? Icon(Icons.bug_report_outlined, size: 18, color: scheme.onSurfaceVariant)
              : Text(title.isNotEmpty ? title[0].toUpperCase() : '?',
                  style: TextStyle(color: planColor, fontWeight: FontWeight.w700)),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
        subtitle: Text(facts, style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              plan == 'premium' && u['premiumVerified'] != true ? 'premium*' : plan,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: planColor),
            ),
            if (email.isNotEmpty)
              IconButton(
                tooltip: 'Grant premium (31 days)',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _grantPremium(email),
                icon: const Icon(Icons.workspace_premium_outlined, size: 18),
              ),
          ],
        ),
        isThreeLine: false,
      ),
    );
  }

  Widget _adminTile(Map<String, dynamic> a) {
    final email = (a['email'] ?? '').toString();
    final role = (a['role'] ?? 'admin').toString();
    final isOwner = role == 'owner';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(child: Text(email.isNotEmpty ? email[0].toUpperCase() : '?')),
      title: Text(email),
      subtitle: Text(isOwner ? 'Owner' : 'Admin'),
      trailing: isOwner
          ? const Icon(Icons.verified_rounded, color: Color(0xFFF59E0B))
          : IconButton(onPressed: () => _removeAdmin(email), icon: const Icon(Icons.remove_circle_outline_rounded)),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      );
}
