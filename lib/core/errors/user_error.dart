import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Semantic categories for user-facing errors across OpenFlix.
enum UserErrorType {
  offline,
  timeout,
  noAddons,
  noStreams,
  playbackFailed,
  authRequired,
  unknown,
}

/// Primary 1-tap recovery intent paired with a [UserError].
enum UserErrorAction {
  retry,
  installAddons,
  switchLink,
  signIn,
}

/// Plain-English, user-facing error representation.
///
/// Raw exception names, URLs, HTTP status codes, and stack traces must never
/// appear in [title] or [message] — log technical details with [debugPrint].
class UserError extends Equatable {
  const UserError({
    required this.type,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.action,
  });

  final UserErrorType type;
  final String title;
  final String message;
  final String actionLabel;
  final UserErrorAction action;

  factory UserError.offline({String? message}) => UserError(
        type: UserErrorType.offline,
        title: "You're offline",
        message: message ?? 'Check your internet connection and try again.',
        actionLabel: 'Retry',
        action: UserErrorAction.retry,
      );

  factory UserError.timeout({String? message}) => UserError(
        type: UserErrorType.timeout,
        title: 'Connection timed out',
        message: message ?? 'The server took too long to respond.',
        actionLabel: 'Retry',
        action: UserErrorAction.retry,
      );

  factory UserError.noAddons() => const UserError(
        type: UserErrorType.noAddons,
        title: 'No addons installed',
        message: 'Add a streaming addon to find playable links.',
        actionLabel: 'Install Addons',
        action: UserErrorAction.installAddons,
      );

  factory UserError.noStreams({String? message}) => UserError(
        type: UserErrorType.noStreams,
        title: "Couldn't find streams",
        message: message ?? 'No playable links were found for this title.',
        actionLabel: 'Retry',
        action: UserErrorAction.retry,
      );

  factory UserError.playbackFailed({
    String? message,
    bool preferSwitchLink = false,
  }) =>
      UserError(
        type: UserErrorType.playbackFailed,
        title: 'Playback interrupted',
        message: message ?? "This link couldn't play. Try again or pick another source.",
        actionLabel: preferSwitchLink ? 'Switch Link' : 'Retry',
        action: preferSwitchLink
            ? UserErrorAction.switchLink
            : UserErrorAction.retry,
      );

  factory UserError.authRequired({String? message}) => UserError(
        type: UserErrorType.authRequired,
        title: 'Sign in required',
        message: message ?? 'Reconnect your TMDB account to continue syncing.',
        actionLabel: 'Sign In',
        action: UserErrorAction.signIn,
      );

  factory UserError.unknown({String? title, String? message}) => UserError(
        type: UserErrorType.unknown,
        title: title ?? 'Something went wrong',
        message: message ?? 'Please try again in a moment.',
        actionLabel: 'Retry',
        action: UserErrorAction.retry,
      );

  /// Maps any raw exception, [DioException], HTTP error, or technical string
  /// into a clean, human-readable [UserError].
  static UserError from(
    Object? error, {
    UserErrorType? fallbackType,
    String? logTag,
  }) {
    if (error is UserError) return error;

    if (error != null) {
      debugPrint('[UserError${logTag != null ? ':$logTag' : ''}] $error');
    }

    if (error is SocketException || error is HandshakeException) {
      return UserError.offline();
    }

    if (error is TimeoutException) {
      return UserError.timeout();
    }

    if (error is DioException) {
      return _fromDio(error, fallbackType: fallbackType);
    }

    if (error is FormatException) {
      if (fallbackType == UserErrorType.playbackFailed) {
        return UserError.playbackFailed();
      }
      return UserError.unknown(
        title: "Couldn't read response",
        message: 'Received unexpected data from the server. Please try again.',
      );
    }

    final raw = (error?.toString() ?? '').trim().toLowerCase();

    if (_looksOffline(raw)) {
      return UserError.offline();
    }
    if (_looksTimeout(raw)) {
      return UserError.timeout();
    }
    if (_looksNoAddons(raw)) {
      return UserError.noAddons();
    }
    if (_looksAuthError(raw)) {
      return UserError.authRequired();
    }
    if (_looksNoStreams(raw)) {
      return UserError.noStreams();
    }
    if (_looksPlaybackError(raw)) {
      return UserError.playbackFailed();
    }

    return switch (fallbackType) {
      UserErrorType.offline => UserError.offline(),
      UserErrorType.timeout => UserError.timeout(),
      UserErrorType.noAddons => UserError.noAddons(),
      UserErrorType.noStreams => UserError.noStreams(),
      UserErrorType.playbackFailed => UserError.playbackFailed(),
      UserErrorType.authRequired => UserError.authRequired(),
      _ => UserError.unknown(),
    };
  }

  /// Returns true if [error] represents a network/offline failure.
  static bool isOffline(Object? error) => from(error).type == UserErrorType.offline;

  static UserError _fromDio(
    DioException e, {
    UserErrorType? fallbackType,
  }) {
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.badCertificate:
        return UserError.offline();
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return UserError.timeout();
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode ?? 0;
        if (code == 401 || code == 403) {
          if (fallbackType == UserErrorType.playbackFailed) {
            return UserError.playbackFailed(
              message: 'This stream source is unavailable right now.',
              preferSwitchLink: true,
            );
          }
          if (code == 401) return UserError.authRequired();
          return UserError.unknown(
            title: 'Access unavailable',
            message: 'This source is temporarily restricted. Try again later.',
          );
        }
        if (code == 404) {
          if (fallbackType == UserErrorType.noStreams) {
            return UserError.noStreams();
          }
          return UserError.unknown(
            title: 'Content unavailable',
            message: "We couldn't find what you requested.",
          );
        }
        if (code == 429) {
          return UserError.unknown(
            title: 'Too many requests',
            message: 'Please wait a moment and try again.',
          );
        }
        if (code >= 500) {
          return UserError.unknown(
            title: 'Service unavailable',
            message: 'The server is having trouble right now. Please retry.',
          );
        }
        break;
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
        if (e.error is SocketException || e.error is HandshakeException) {
          return UserError.offline();
        }
        final msg = '${e.message ?? ''} ${e.error ?? ''}'.toLowerCase();
        if (_looksOffline(msg)) return UserError.offline();
        if (_looksTimeout(msg)) return UserError.timeout();
        break;
      default:
        return UserError.timeout();
    }

    return switch (fallbackType) {
      UserErrorType.playbackFailed => UserError.playbackFailed(),
      UserErrorType.noStreams => UserError.noStreams(),
      UserErrorType.authRequired => UserError.authRequired(),
      _ => UserError.unknown(),
    };
  }

  static bool _looksOffline(String s) =>
      s.contains('socketexception') ||
      s.contains('failed host lookup') ||
      s.contains('no address associated') ||
      s.contains('network is unreachable') ||
      s.contains('connection refused') ||
      s.contains('connection reset') ||
      s.contains('connection closed') ||
      s.contains('connection error') ||
      s.contains('handshakeexception') ||
      s.contains('errno = 7') ||
      s.contains('errno = 101') ||
      s.contains('offline') ||
      s.contains('no internet') ||
      s.contains('unable to reach');

  static bool _looksTimeout(String s) =>
      s.contains('timeout') ||
      s.contains('timed out') ||
      s.contains('deadline exceeded');

  static bool _looksNoAddons(String s) =>
      s.contains('no stream addons') ||
      s.contains('no addons installed') ||
      s.contains('no addons enabled');

  static bool _looksNoStreams(String s) =>
      s.contains('no direct streams') ||
      s.contains('no working streams') ||
      s.contains('no streams found') ||
      s.contains('no streams returned') ||
      s.contains('no playable');

  static bool _looksAuthError(String s) =>
      s.contains('session expired') ||
      s.contains('status code of 401') ||
      s.contains('http 401') ||
      s.contains('unauthorized') ||
      s.contains('sign in');

  static bool _looksPlaybackError(String s) =>
      s.contains('playback error') ||
      s.contains('mediacodec') ||
      s.contains('libmpv') ||
      s.contains('mpv') ||
      s.contains('invalid stream url') ||
      s.contains('stream connection') ||
      s.contains('mismatched video') ||
      s.contains('decoder');

  @override
  List<Object?> get props => [type, title, message, actionLabel, action];
}
