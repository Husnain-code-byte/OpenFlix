import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel/core/errors/user_error.dart';

void main() {
  group('UserError.from', () {
    test('maps SocketException and network strings to offline without leaking technical text', () {
      final err1 = UserError.from(const SocketException('Failed host lookup: api.themoviedb.org'));
      expect(err1.type, UserErrorType.offline);
      expect(err1.title, "You're offline");
      expect(err1.message.toLowerCase(), isNot(contains('socket')));
      expect(err1.message.toLowerCase(), isNot(contains('themoviedb')));
      expect(err1.action, UserErrorAction.retry);

      final err2 = UserError.from(
        DioException(
          requestOptions: RequestOptions(path: 'https://api.example.com/v3'),
          type: DioExceptionType.connectionError,
        ),
      );
      expect(err2.type, UserErrorType.offline);
      expect(err2.title, "You're offline");
    });

    test('maps TimeoutException and Dio timeouts to timeout', () {
      final err1 = UserError.from(TimeoutException('Timed out after 10s'));
      expect(err1.type, UserErrorType.timeout);
      expect(err1.title, 'Connection timed out');

      final err2 = UserError.from(
        DioException(
          requestOptions: RequestOptions(path: '/stream'),
          type: DioExceptionType.receiveTimeout,
        ),
      );
      expect(err2.type, UserErrorType.timeout);
    });

    test('maps HTTP 401/5xx responses cleanly without exposing status codes or URLs', () {
      final authErr = UserError.from(
        DioException(
          requestOptions: RequestOptions(path: 'https://api.themoviedb.org/3/account'),
          response: Response(
            requestOptions: RequestOptions(path: '/account'),
            statusCode: 401,
          ),
          type: DioExceptionType.badResponse,
        ),
      );
      expect(authErr.type, UserErrorType.authRequired);
      expect(authErr.action, UserErrorAction.signIn);
      expect(authErr.message, isNot(contains('401')));

      final serverErr = UserError.from(
        DioException(
          requestOptions: RequestOptions(path: 'https://api.themoviedb.org/3/movie'),
          response: Response(
            requestOptions: RequestOptions(path: '/movie'),
            statusCode: 503,
          ),
          type: DioExceptionType.badResponse,
        ),
      );
      expect(serverErr.type, UserErrorType.unknown);
      expect(serverErr.message, isNot(contains('503')));
      expect(serverErr.message, isNot(contains('http')));
    });

    test('maps missing addons and libmpv/MediaCodec errors cleanly', () {
      final noAddons = UserError.noAddons();
      expect(noAddons.type, UserErrorType.noAddons);
      expect(noAddons.title, 'No addons installed');
      expect(noAddons.message, 'Add a streaming addon to find playable links.');
      expect(noAddons.actionLabel, 'Install Addons');
      expect(noAddons.action, UserErrorAction.installAddons);

      final mpvErr = UserError.from(
        'Playback error: mpv c2.mtk.avc.decoder failed on https://secret.debrid.link/123',
        fallbackType: UserErrorType.playbackFailed,
      );
      expect(mpvErr.type, UserErrorType.playbackFailed);
      expect(mpvErr.message, isNot(contains('mpv')));
      expect(mpvErr.message, isNot(contains('c2.mtk')));
      expect(mpvErr.message, isNot(contains('https://')));
    });
  });
}
