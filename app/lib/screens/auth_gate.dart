import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/account_service.dart';
import '../services/plan_status.dart';
import '../services/premium_service.dart';
import '../services/user_session.dart';
import 'login_screen.dart';
import 'main_shell.dart';
import 'onboarding_screen.dart';
import 'trial_paywall_screen.dart';

/// Routes by auth state: signed out → LoginScreen; signed in → prepare that
/// account's session (reset+load if a different account) → onboarding → paywall
/// → app.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _authStream = FirebaseAuth.instance.authStateChanges();
  String? _readyUid; // uid whose session has been prepared
  bool _preparing = false;

  Future<void> _prepare(String uid) async {
    if (_preparing || _readyUid == uid) return;
    _preparing = true;
    await AccountService.switchTo(uid);
    if (!mounted) return;
    setState(() {
      _readyUid = uid;
      _preparing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _Loader();
        }
        final user = snap.data;
        if (user == null) {
          _readyUid = null; // so the next sign-in re-prepares
          return const LoginScreen();
        }
        if (_readyUid != user.uid) {
          _prepare(user.uid); // async; shows loader until ready
          return const _Loader();
        }
        // Flow after sign-in: new users onboard first, then hit the paywall.
        return UserSession.instance.onboarded
            ? const PaywallGate()
            : const OnboardingScreen();
      },
    );
  }
}

/// Hard paywall: nobody reaches the app without an entitlement.
///
/// The SERVER decides — `/access` reports the plan and whether this account is
/// behind the paywall at all. This widget only mirrors that answer, so a
/// rebuilt or patched client cannot let itself in; the backend would refuse
/// every AI call anyway.
///
/// The paywall is for NEW accounts. Anyone who was using the app before it
/// existed keeps their free tier — the server decides who that is from the
/// account's creation date, and says so in `paywalled`.
///
/// Two deliberate softenings:
///  - While the first /access call is in flight we show a loader, not the
///    paywall, so a paying learner never sees a sales page on launch.
///  - If that call FAILS (offline, server down) we let them through. The
///    server still refuses the actual work, so nothing is given away — but a
///    subscriber on a flaky train connection is not accused of not paying.
class PaywallGate extends StatefulWidget {
  const PaywallGate({super.key});
  @override
  State<PaywallGate> createState() => _PaywallGateState();
}

class _PaywallGateState extends State<PaywallGate> {
  @override
  void initState() {
    super.initState();
    // Play first: restorePurchases() inside init() re-grants an existing
    // subscription after a reinstall or a renewal, which the refresh below
    // then sees.
    PremiumService.instance.addListener(_onPlayResult);
    PremiumService.instance.init();
    PlanStatus.instance.refresh();
  }

  @override
  void dispose() {
    PremiumService.instance.removeListener(_onPlayResult);
    super.dispose();
  }

  bool _rechecked = false;

  /// A restored purchase has been sent to the server — ask again what this
  /// account is entitled to now. Once is enough: Play notifies for several
  /// unrelated reasons and this must not turn into a refresh loop.
  void _onPlayResult() {
    if (_rechecked || !PremiumService.instance.justActivated) return;
    if (PlanStatus.instance.isPremium) return;
    _rechecked = true;
    PlanStatus.instance.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([PlanStatus.instance, PremiumService.instance]),
      builder: (context, _) {
        final plan = PlanStatus.instance;
        // Wait for BOTH answers: the server's, and Play's restore — otherwise a
        // subscriber whose renewal we have not recorded yet sees the paywall
        // blink past on launch.
        if (!plan.attempted || !PremiumService.instance.ready) return const _Loader();
        if (!plan.loaded) return const MainShell(); // couldn't ask; server still enforces
        if (plan.hasPremiumAccess) return const MainShell();
        // Free, but not paywalled: a learner who was already here before the
        // paywall existed. They keep the free tier they signed up for.
        if (!plan.paywalled) return const MainShell();
        return TrialPaywallScreen(
          onSubscribed: () => PlanStatus.instance.refresh(),
        );
      },
    );
  }
}

class _Loader extends StatelessWidget {
  const _Loader();
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}
