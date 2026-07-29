import 'package:flutter/foundation.dart';

import 'api_service.dart';

/// Caches whether the signed-in user is an admin (decided SERVER-SIDE from their
/// Firebase email — see backend /admin/me). The Home screen shows the Admin
/// entry only when [isAdmin] is true.
class AdminService extends ChangeNotifier {
  static final AdminService instance = AdminService._();
  AdminService._();

  bool isAdmin = false;
  bool isOwner = false;
  bool checked = false;

  Future<void> check() async {
    try {
      final data = await ApiService.instance.adminMe();
      isAdmin = data['isAdmin'] == true;
      isOwner = data['isOwner'] == true;
    } catch (_) {
      isAdmin = false;
      isOwner = false;
    }
    checked = true;
    notifyListeners();
  }
}
