import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel/core/errors/user_error.dart';
import 'package:pixel/core/network/network_monitor.dart';

void main() {
  tearDown(() {
    NetworkMonitor.instance.resetForTesting();
  });

  group('UserError.from', () {
    test('classifies SocketException / connectionError as offline ONLY when device is confirmed offline', () {
      // Device genuinely offline -> "You're offline"
      final offlineErr1 = UserError.from(
        const SocketException('Failed host lookup: api.themoviedb.org'),
        isDeviceOffline: true,
      );
      expect(offlineErr1.type, UserErrorType.offline);
      expect(offlineErr1.title, "You're offline");
      expect(offlineErr1.message.toLowerCase(), isNot(contains('socket')));
      expect(offlineErr1.message.toLowerCase(), isNot(contains('themoviedb')));
      expect(offlineErr1.action, UserErrorAction.retry);

      final offlineErr2 = UserError.from(
        DioException(
          requestOptions: RequestOptions(path: 'https://api.example.com/v3'),
          type: DioExceptionType.connectionError,
        ),
        isDeviceOffline: true,
      );
      expect(offlineErr2.type, UserErrorType.offline);
      expect(offlineErr2.title, "You're offline");

      // Device is ONLINE -> NEVER falsely claim "You're offline"!
      final onlineErr = UserError.from(
        DioException(
          requestOptions: RequestOptions(path: 'https://api.themoviedb.org/3/movie/popular'),
          type: DioExceptionType.connectionError,
        ),
        isDeviceOffline: false,
      );
      expect(onlineErr.type, isNot(UserErrorType.offline));
      expect(onlineErr.title, "Couldn't load catalog");
    });

    test('never classifies TLS HandshakeException, badCertificate, or cancel as offline', () {
      final tlsErr = UserError.from(
        const HandshakeException('TLS handshake failed'),
        isDeviceOffline: false,
      );
      expect(tlsErr.type, isNot(UserErrorType.offline));
      expect(tlsErr.title, 'Connection failed');

      final cancelErr = UserError.from(
        DioException(
          requestOptions: RequestOptions(path: '/movie/popular'),
          type: DioExceptionType.cancel,
        ),
        isDeviceOffline: false,
      );
      expect(cancelErr.type, isNot(UserErrorType.offline));
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
