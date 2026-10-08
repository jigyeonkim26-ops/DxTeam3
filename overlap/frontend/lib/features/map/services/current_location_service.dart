import 'package:geolocator/geolocator.dart';

enum CurrentLocationPermissionState {
  granted,
  denied,
  deniedForever,
  serviceDisabled,
}

abstract final class CurrentLocationService {
  static Future<CurrentLocationPermissionState> permissionState() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return CurrentLocationPermissionState.serviceDisabled;
    }

    return _fromPermission(await Geolocator.checkPermission());
  }

  static Future<CurrentLocationPermissionState>
  requestForegroundPermission() async {
    final current = await Geolocator.checkPermission();
    if (current == LocationPermission.deniedForever) {
      return CurrentLocationPermissionState.deniedForever;
    }

    final permission = current == LocationPermission.denied
        ? await Geolocator.requestPermission()
        : current;
    return _fromPermission(permission);
  }

  static Future<Position?> currentPosition() async {
    final state = await permissionState();
    if (state != CurrentLocationPermissionState.granted) return null;

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
      ),
    );
  }

  static Future<bool> openAppSettings() => Geolocator.openAppSettings();

  static CurrentLocationPermissionState _fromPermission(
    LocationPermission permission,
  ) => switch (permission) {
    LocationPermission.always ||
    LocationPermission.whileInUse => CurrentLocationPermissionState.granted,
    LocationPermission.deniedForever =>
      CurrentLocationPermissionState.deniedForever,
    LocationPermission.denied => CurrentLocationPermissionState.denied,
    LocationPermission.unableToDetermine =>
      CurrentLocationPermissionState.denied,
  };
}

/// Limits the entry prompt to one display per app process, even when the
/// AppShell rebuilds or tabs change.
abstract final class LocationPermissionPromptGate {
  static bool _shownThisSession = false;

  static bool tryShow() {
    if (_shownThisSession) return false;
    _shownThisSession = true;
    return true;
  }
}
