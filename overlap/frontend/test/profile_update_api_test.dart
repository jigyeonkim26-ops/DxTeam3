import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:overlap_app/core/network/api_transport.dart';
import 'package:overlap_app/features/auth/services/auth_api_service.dart';

void main() {
  tearDown(ApiTransport.clearAccessToken);

  test(
    'updates only supplied profile fields through the authenticated API',
    () async {
      ApiTransport.setAccessToken('profile-test-token');
      final client = _Client((request) {
        expect(request.method, 'PATCH');
        expect(request.uri.path, '/auth/me');
        expect(
          request.headers.values['authorization'],
          'Bearer profile-test-token',
        );
        expect(jsonDecode(request.body.toString()), {
          'nickname': 'updated-user',
        });
        return {
          'id': 1,
          'email': 'member@example.com',
          'nickname': 'updated-user',
          'birth_date': '1990-01-01',
          'gender': 'female',
        };
      });

      final profile = await HttpOverrides.runZoned(
        () => AuthApiService.updateCurrentUser(nickname: ' updated-user '),
        createHttpClient: (_) => client,
      );

      expect(client.requests, hasLength(1));
      expect(profile.nickname, 'updated-user');
      expect(profile.birthDateText, '1990-01-01');
      expect(profile.gender, 'female');
    },
  );

  test('does not send an empty profile update request', () async {
    await expectLater(
      AuthApiService.updateCurrentUser(),
      throwsA(isA<ApiException>()),
    );
  });

  test('uploads a selected profile photo with the authenticated API', () async {
    ApiTransport.setAccessToken('profile-photo-token');
    final client = _Client((request) {
      expect(request.method, 'POST');
      expect(request.uri.path, '/auth/me/photo');
      expect(
        request.headers.values['authorization'],
        'Bearer profile-photo-token',
      );
      expect(request.uploadedBytes.takeBytes(), isNotEmpty);
      return null;
    });

    await HttpOverrides.runZoned(
      () => AuthApiService.uploadProfilePhoto(
        XFile.fromData(
          Uint8List.fromList(<int>[137, 80, 78, 71]),
          name: 'profile.png',
        ),
      ),
      createHttpClient: (_) => client,
    );

    expect(client.requests, hasLength(1));
  });
}

class _Client implements HttpClient {
  _Client(this.respond);

  final Object? Function(_Request request) respond;
  final requests = <_Request>[];

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final request = _Request(method, url, this);
    requests.add(request);
    return request;
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

class _Request implements HttpClientRequest {
  _Request(this.method, this.uri, this.client);

  @override
  final String method;
  @override
  final Uri uri;
  final _Client client;
  @override
  int contentLength = -1;
  @override
  bool followRedirects = true;
  @override
  int maxRedirects = 5;
  @override
  bool persistentConnection = true;
  final body = StringBuffer();
  final uploadedBytes = BytesBuilder(copy: false);
  @override
  final _Headers headers = _Headers();

  @override
  void write(Object? object) => body.write(object);

  @override
  void add(List<int> data) => uploadedBytes.add(data);

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final data in stream) {
      uploadedBytes.add(data);
    }
  }

  @override
  Future<HttpClientResponse> close() async => _Response(client.respond(this));

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

class _Headers implements HttpHeaders {
  final values = <String, Object>{};

  @override
  ContentType? contentType;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = value;
  }

  @override
  void forEach(void Function(String name, List<String> values) action) {
    values.forEach((name, value) => action(name, [value.toString()]));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(Object? data)
    : _stream = Stream.value(data == null ? [] : utf8.encode(jsonEncode(data)));

  final Stream<List<int>> _stream;
  @override
  final HttpHeaders headers = _Headers();

  @override
  int get statusCode => 200;
  @override
  int get contentLength => -1;
  @override
  bool get isRedirect => false;
  @override
  bool get persistentConnection => true;
  @override
  String get reasonPhrase => 'OK';
  @override
  List<RedirectInfo> get redirects => const [];

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}
