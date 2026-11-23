import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../network/network_monitor.dart';

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

  factory UserError.catalogUnavailable({String? title, String? message}) =>
      UserError(
        type: UserErrorType.unknown,
        title: title ?? "Couldn't load catalog",
        message: message ?? "The server didn't respond. Tap Retry to try again.",
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
        message:
            message ?? "This link couldn't play. Try again or pick another source.",
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
  ///
  /// Only classifies an error as [UserErrorType.offline] ("You're offline")
  /// when the device is genuinely offline (`isDeviceOffline == true`, or
  /// confirmed via [NetworkMonitor.instance.isOffline]) AND a socket/DNS or
  /// connection failure occurred. When the device has internet access, server
  /// failures, TLS delays, and timeouts are never mislabeled as offline.
  static UserError from(
    Object? error, {
    UserErrorType? fallbackType,
    bool? isDeviceOffline,
    String? logTag,
  }) {
    if (error is UserError) return error;

    if (error != null) {
      debugPrint('[UserError${logTag != null ? ':$logTag' : ''}] $error');
    }

    final confirmedOffline = isDeviceOffline ?? NetworkMonitor.instance.isOffline;

    // Unwrap wrapped repository exceptions (e.g. TmdbException carrying statusCode / cause)
    final unwrapped = _tryUnwrapKnownException(error, confirmedOffline: confirmedOffline, fallbackType: fallbackType);
    if (unwrapped != null) return unwrapped;

    if (error is TimeoutException) {
      return UserError.timeout();
    }

    if (error is HandshakeException) {
      return UserError.catalogUnavailable(
        title: 'Connection failed',
        message: "Couldn't establish a secure connection. Please try again.",
      );
    }

    if (error is SocketException) {
      return confirmedOffline
          ? UserError.offline()
          : UserError.catalogUnavailable();
    }

    if (error is DioException) {
      return _fromDio(
        error,
        fallbackType: fallbackType,
        confirmedOffline: confirmedOffline,
      );
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
    if (_looksNetworkDrop(raw)) {
      return confirmedOffline
          ? UserError.offline()
          : UserError.catalogUnavailable();
    }

    return switch (fallbackType) {
      UserErrorType.offline => confirmedOffline
          ? UserError.offline()
          : UserError.catalogUnavailable(),
      UserErrorType.timeout => UserError.timeout(),
      UserErrorType.noAddons => UserError.noAddons(),
      UserErrorType.noStreams => UserError.noStreams(),
      UserErrorType.playbackFailed => UserError.playbackFailed(),
      UserErrorType.authRequired => UserError.authRequired(),
      _ => UserError.catalogUnavailable(),
    };
  }

  /// Returns true if [error] represents a confirmed offline failure.
  static bool isOffline(Object? error, {bool? isDeviceOffline}) =>
      from(error, isDeviceOffline: isDeviceOffline).type ==
      UserErrorType.offline;

  static UserError? _tryUnwrapKnownException(
    Object? error, {
    required bool confirmedOffline,
    UserErrorType? fallbackType,
  }) {
    if (error == null) return null;
    // Duck-typed unwrap for TmdbException without introducing a circular import
    // between core/errors and features/details.
    if (error.runtimeType.toString() == 'TmdbException') {
      try {
        final dynamic dyn = error;
        final int? status = dyn.statusCode as int?;
        final Object? cause = dyn.cause;
        final String msg = (dyn.message?.toString() ?? '').toLowerCase();

        if (status == 401) {
          if (msg.contains('session')) {
            return UserError.authRequired();
          }
          return UserError.catalogUnavailable(
            title: "Couldn't load catalog",
            message: 'Catalog service authentication failed. Please retry.',
          );
        }
        if (status == 429) {
          return UserError.unknown(
            title: 'Too many requests',
            message: 'Please wait a moment and try again.',
          );
        }
        if (status != null && status >= 500) {
          return UserError.catalogUnavailable(
            title: 'Service unavailable',
            message: 'The server is having trouble right now. Please retry.',
          );
        }
        if (cause is DioException) {
          return _fromDio(
            cause,
            fallbackType: fallbackType,
            confirmedOffline: confirmedOffline,
          );
        }
      } catch (_) {}
    }
    return null;
  }

  static UserError _fromDio(
    DioException e, {
    UserErrorType? fallbackType,
    required bool confirmedOffline,
  }) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return UserError.timeout();
      case DioExceptionType.badCertificate:
        return UserError.catalogUnavailable(
          title: 'Connection failed',
          message: "Couldn't establish a secure connection. Please try again.",
        );
      case DioExceptionType.connectionError:
        return confirmedOffline
            ? UserError.offline()
            : UserError.catalogUnavailable();
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
          return UserError.catalogUnavailable(
            title: 'Service unavailable',
            message: 'The server is having trouble right now. Please retry.',
          );
        }
        break;
      case DioExceptionType.cancel:
        return UserError.catalogUnavailable();
      case DioExceptionType.unknown:
        if (e.error is HandshakeException) {
          return UserError.catalogUnavailable(
            title: 'Connection failed',
            message: "Couldn't establish a secure connection. Please try again.",
          );
        }
        if (e.error is SocketException) {
          return confirmedOffline
              ? UserError.offline()
              : UserError.catalogUnavailable();
        }
        final msg = '${e.message ?? ''} ${e.error ?? ''}'.toLowerCase();
        if (_looksTimeout(msg)) return UserError.timeout();
        if (_looksNetworkDrop(msg)) {
          return confirmedOffline
              ? UserError.offline()
              : UserError.catalogUnavailable();
        }
        break;
      default:
        return UserError.timeout();
    }

    return switch (fallbackType) {
      UserErrorType.playbackFailed => UserError.playbackFailed(),
      UserErrorType.noStreams => UserError.noStreams(),
      UserErrorType.authRequired => UserError.authRequired(),
      _ => UserError.catalogUnavailable(),
    };
  }

  static bool _looksNetworkDrop(String s) =>
      s.contains('socketexception') ||
      s.contains('failed host lookup') ||
      s.contains('no address associated') ||
      s.contains('network is unreachable') ||
      s.contains('connection refused') ||
      s.contains('connection reset') ||
      s.contains('connection closed') ||
      s.contains('connection error') ||
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
