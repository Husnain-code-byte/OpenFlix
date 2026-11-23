import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Lightweight connectivity monitor backed by Android's native
/// `ConnectivityManager` (via the existing `openflix/launcher` channel).
///
/// Defaults optimistically to **online** (`isOffline == false`) until Android
/// explicitly reports no active network interface, preventing cold-start boot
/// races from ever falsely flagging an online device as offline.
class NetworkMonitor {
  NetworkMonitor._();

  static final NetworkMonitor instance = NetworkMonitor._();
  static const _channel = MethodChannel('openflix/launcher');

  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  bool _initialized = false;
  bool _isOnline = true;
  bool _hasConfirmedNativeStatus = false;

  /// True only when the OS has confirmed there is no active network interface.
  bool get isOffline => _hasConfirmedNativeStatus && !_isOnline;

  /// Most recent known online state (defaults to `true`).
  bool get isOnline => _isOnline;

  /// Emits `true` when connectivity becomes available and `false` when lost.
  Stream<bool> get onConnectivityChanged => _controller.stream;

  /// Registers the native callback listener and performs an initial non-blocking
  /// connectivity query. Safe to call multiple times.
  void initialize() {
    if (_initialized) return;
    _initialized = true;
    if (kIsWeb || !Platform.isAndroid) return;

    try {
      // Listen for native `onConnectivityChanged` broadcasts sent by MainActivity.
      // Preserves any existing handler (e.g. deep links in AddonsController) by
      // only subscribing via dedicated `openflix/connectivity` channel.
      _connectivityChannel.setMethodCallHandler((call) async {
        if (call.method == 'onConnectivityChanged' && call.arguments is bool) {
          _updateOnlineState(call.arguments as bool);
        }
      });
    } catch (_) {}

    unawaited(checkIsOnline());
  }

  static const _connectivityChannel = MethodChannel('openflix/connectivity');

  /// Actively queries Android's `ConnectivityManager` for an active network
  /// interface (`NET_CAPABILITY_INTERNET`).
  ///
  /// Returns `true` on non-Android platforms or if the query itself fails so
  /// callers never falsely assume offline on platform errors.
  Future<bool> checkIsOnline() async {
    if (kIsWeb || !Platform.isAndroid) {
      return _isOnline;
    }
    try {
      final online = await _channel
          .invokeMethod<bool>('hasNetworkConnection')
          .timeout(const Duration(seconds: 2));
      if (online != null) {
        _updateOnlineState(online);
        return online;
      }
    } catch (_) {
      // Keep optimistic online state if channel is unavailable (e.g. unit tests).
    }
    return _isOnline;
  }

  void _updateOnlineState(bool online) {
    final prev = _isOnline;
    final wasConfirmed = _hasConfirmedNativeStatus;
    _isOnline = online;
    _hasConfirmedNativeStatus = true;
    if (!wasConfirmed || prev != online) {
      if (!_controller.isClosed) {
        _controller.add(online);
      }
    }
  }

  @visibleForTesting
  void setTestOfflineState(bool offline) {
    _hasConfirmedNativeStatus = true;
    _isOnline = !offline;
  }

  @visibleForTesting
  void resetForTesting() {
    _hasConfirmedNativeStatus = false;
    _isOnline = true;
  }
}
