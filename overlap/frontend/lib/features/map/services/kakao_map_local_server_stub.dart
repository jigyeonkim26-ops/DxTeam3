class KakaoMapLocalServer {
  Future<void> start({required String javascriptKey}) {
    throw UnsupportedError('Kakao Map WebView is available on Android only.');
  }

  Future<void> close() async {}

  String debugMapPage(String javascriptKey) {
    throw UnsupportedError('Kakao Map WebView is available on Android only.');
  }
}
