class ApiConfig {
  // Android Emulator reaches the host machine through 10.0.2.2.
  // Override for a physical device with --dart-define=API_BASE_URL=http://<host-ip>:8002.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8002',
  );
}