import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';

/// In-app admin panel (visible only to admins — see AdminService / backend
/// /admin). Lets an admin see basic stats, grant admin access to a teammate by
/// Gmail, and grant premium to a user by email. All actions are re-checked
/// server-side; the client is only a convenience UI.
class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});
  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  Map<String, dynamic> _stats = {};
  List<Map<String, dynamic>> _admins = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService.instance.adminStats(),
        ApiService.instance.adminListAdmins(),
      ]);
      _stats = results[0] as Map<String, dynamic>;
      _admins = results[1] as List<Map<String, dynamic>>;
    } catch (_) {/* keep old */}
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

  Future<void> _grantPremium() async {
    final email = await _promptEmail('Grant premium', 'User\'s account email', 'user@gmail.com');
    if (email == null || email.isEmpty) return;
    final res = await ApiService.instance.adminGrantPremium(email, days: 31);
    _snack(res['ok'] == true ? 'Premium granted to $email (31 days)' : 'Failed: ${res['error'] ?? 'error'}');
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                  // Stats
                  const _SectionTitle('Overview'),
                  Row(
                    children: [
                      _stat('Users', _stats['total'], const Color(0xFF6366F1)),
                      const SizedBox(width: 10),
                      _stat('Premium', _stats['premium'], const Color(0xFFF59E0B)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _stat('On trial', _stats['trial'], const Color(0xFF00C2A8)),
                      const SizedBox(width: 10),
                      _stat('Free', _stats['free'], scheme.onSurfaceVariant),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Admin management
                  const _SectionTitle('Admins'),
                  Text('People who can open this panel. Add a teammate by their Gmail.',
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
                  const SizedBox(height: 10),
                  ..._admins.map((a) => _adminTile(a)),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _addAdmin,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('Add admin by Gmail'),
                  ),
                  const SizedBox(height: 24),

                  // Support tools
                  const _SectionTitle('Support tools'),
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: Icon(Icons.workspace_premium_rounded, color: AppTheme.seed),
                      title: const Text('Grant premium to a user'),
                      subtitle: const Text('By account email · 31 days'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _grantPremium,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _stat(String label, Object? value, Color color) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
        decoration: BoxDecoration(
          color: isLight ? Colors.white : const Color(0xFF1E1B26),
          borderRadius: BorderRadius.circular(16),
          boxShadow: isLight ? [BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, 5))] : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${value ?? '—'}', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
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
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      );
}
