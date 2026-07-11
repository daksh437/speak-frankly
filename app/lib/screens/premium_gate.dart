import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/premium_service.dart';
import 'premium_screen.dart';

/// Hard paywall. After sign-in, the whole app sits behind this gate: it asks the
/// server (`/access`) whether the learner may use the AI. Only premium (or a
/// degraded/allow-through backend) reaches [child]; everyone else sees the
/// blocking [PremiumScreen] until they subscribe. Server is authoritative — the
/// tutor endpoints reject non-premium requests regardless of the UI.
class PremiumGate extends StatefulWidget {
  const PremiumGate({super.key, required this.child});
  final Widget child;
  @override
  State<PremiumGate> createState() => _PremiumGateState();
}

class _PremiumGateState extends State<PremiumGate> {
  bool _loading = true;
  bool _allowed = false;

  @override
  void initState() {
    super.initState();
    PremiumService.instance.addListener(_onPremiumChanged);
    _check();
  }

  @override
  void dispose() {
    PremiumService.instance.removeListener(_onPremiumChanged);
    super.dispose();
  }

  void _onPremiumChanged() {
    // A purchase/restore just completed → re-ask the server.
    if (PremiumService.instance.justActivated && !_allowed) _check();
  }

  Future<void> _check() async {
    if (mounted) setState(() => _loading = true);
    bool allowed = false;
    try {
      final access = await ApiService.instance.fetchAccess();
      // Pass when the server says premium, or when it can't decide (degraded
      // mode returns allowed:true) — never lock a user out on a backend hiccup.
      allowed = access['planType'] == 'premium' || access['allowed'] == true;
    } catch (_) {
      // Network error → don't hard-lock; let them in and rely on server-side
      // enforcement (tutor calls will still 403 without premium).
      allowed = true;
    }
    if (!mounted) return;
    setState(() {
      _allowed = allowed;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_allowed) return widget.child;
    return PremiumScreen(blocking: true, onSubscribed: _check);
  }
}
