/// Single source of truth for the backend base URL (mirrors InstaFlow's
/// ApiService.baseUrl convention).
///
/// - Production: your deployed Render service.
/// - Local dev on an Android emulator: use http://10.0.2.2:10000
///   (10.0.2.2 is the emulator's alias for your machine's localhost).
/// - Local dev on a physical phone: use `http://<your-PC-LAN-IP>:10000`
///
/// Override at build time without editing code:
///   flutter run --dart-define=SPEAKFLOW_API=http://10.0.2.2:10000
class AppConfig {
  static const String baseUrl = String.fromEnvironment(
    'SPEAKFLOW_API',
    defaultValue: 'https://speak-frankly.onrender.com',
  );

  static const String privacyUrl = '$baseUrl/privacy';
  static const String termsUrl = '$baseUrl/terms';
}
