class ApiConfig {
  // Android Emulator reaches the host machine through 10.0.2.2.
  // Physical devices using `adb reverse tcp:8002 tcp:8002` can override this
  // with `--dart-define=API_BASE_URL=http://localhost:8002`.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8002',
  );
}
