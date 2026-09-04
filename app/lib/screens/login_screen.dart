import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/app_logo.dart';

/// First screen for signed-out users: a branded hero + "Continue with Google".
/// On success, AuthGate reacts to the auth state change and routes onward.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Wake the backend while the user reads the screen / picks an account,
    // so the post-login data load isn't stuck behind a cold start.
    ApiService.instance.warmup();
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await AuthService.signInWithGoogle();
      // AuthGate's authStateChanges stream handles navigation on success.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.signInFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Email + password, for app-store review. Not a route a learner has an
  /// account for — see AuthService.signInWithEmail for why it exists at all.
  Future<void> _signInWithEmail() async {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final creds = await showDialog<(String, String)>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign in with email'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emailCtrl,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
              onSubmitted: (_) => Navigator.pop(ctx, (emailCtrl.text, passCtrl.text)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, (emailCtrl.text, passCtrl.text)),
            child: const Text('Sign in'),
          ),
        ],
      ),
    );
    emailCtrl.dispose();
    passCtrl.dispose();
    if (creds == null || creds.$1.trim().isEmpty || creds.$2.isEmpty || !mounted) return;

    setState(() => _busy = true);
    try {
      await AuthService.signInWithEmail(creds.$1, creds.$2);
      // AuthGate's authStateChanges stream handles navigation on success.
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        // The real reason, not a generic failure: whoever is typing here is
        // following instructions, and "wrong password" versus "no such account"
        // is the difference between retyping and asking for new credentials.
        final msg = switch (e.code) {
          'invalid-email' => 'That email address is not valid.',
          'user-not-found' || 'invalid-credential' || 'wrong-password' =>
            'Email or password is incorrect.',
          'user-disabled' => 'That account has been disabled.',
          'too-many-requests' => 'Too many attempts. Wait a moment and try again.',
          'operation-not-allowed' => 'Email sign-in is not enabled for this app.',
          _ => 'Could not sign in. Please try again.',
        };
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.signInFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [scheme.primaryContainer.withValues(alpha: 0.45), scheme.surface, scheme.surface],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
            child: Column(
              children: [
                const Spacer(flex: 2),
                Container(
                  width: 132,
                  height: 132,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [scheme.primary, scheme.tertiary]),
                    boxShadow: [BoxShadow(color: scheme.primary.withValues(alpha: 0.35), blurRadius: 30, offset: const Offset(0, 12))],
                  ),
                  child: const Center(child: AppLogo(size: 76)),
                ),
                const SizedBox(height: 32),
                Text('Speak Frankly', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                Text(
                  l.welcomeSubtitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
                ),
                const Spacer(flex: 3),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    onPressed: _busy ? null : _signIn,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 1,
                    ),
                    child: _busy
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const _GoogleG(),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Text(
                                  l.continueWithGoogle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 6),
                // The reviewer's way in. Small on purpose: a learner has no
                // account to sign in with and should not be invited to look for
                // one, but an app-store reviewer following written instructions
                // finds it immediately - and Google Sign-In is exactly what
                // keeps failing on their test devices.
                TextButton(
                  onPressed: _busy ? null : _signInWithEmail,
                  child: Text('Sign in with email',
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
                ),
                const SizedBox(height: 6),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(l.agreeToPrefix, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                    GestureDetector(
                      onTap: () => _open(AppConfig.termsUrl),
                      child: Text(l.termsLabel, style: TextStyle(color: scheme.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    Text(l.andWord, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                    GestureDetector(
                      onTap: () => _open(AppConfig.privacyUrl),
                      child: Text(l.privacyLabel, style: TextStyle(color: scheme.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    // Languages that need a trailing clause (e.g. Hindi
                    // "…से सहमत होते हैं"); empty in English.
                    if (l.agreeToSuffix.isNotEmpty)
                      Text(l.agreeToSuffix, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Simple multicolor "G" mark (no asset needed).
class _GoogleG extends StatelessWidget {
  const _GoogleG();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF4285F4), Color(0xFFEA4335)]),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text('G', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
    );
  }
}
