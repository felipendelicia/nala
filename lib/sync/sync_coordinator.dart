import 'dart:async';
import 'package:flutter/widgets.dart';
import 'sync_engine.dart';
import 'sync_state.dart';

class SyncCoordinator with WidgetsBindingObserver {
  SyncCoordinator(this.engine, {DateTime Function()? now})
    : now = now ?? DateTime.now {
    engine.addListener(_stateChanged);
    WidgetsBinding.instance.addObserver(this);
  }
  final SyncEngine engine;
  final DateTime Function() now;
  Timer? _debounce, _poll, _retry;
  DateTime? _retryAt;
  bool _active = false, _closed = false;
  bool _waitingForSync = false;

  void start() {
    if (_closed || _active) return;
    _active = true;
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _trigger());
    _trigger();
  }

  void stop() {
    _active = false;
    _debounce?.cancel();
    _poll?.cancel();
    _retry?.cancel();
  }

  void notifyLocalChange() {
    if (_closed) return;
    engine.notifyPending();
    if (!_active) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), _syncLocalChanges);
  }

  void _syncLocalChanges() {
    if (engine.status.phase != SyncPhase.syncing) {
      _trigger();
      return;
    }
    if (_waitingForSync) return;
    _waitingForSync = true;
    unawaited(
      engine.idle.then((_) {
        _waitingForSync = false;
        if (engine.status.phase == SyncPhase.pending) _trigger();
      }),
    );
  }

  void _stateChanged() {
    if (_closed) return;
    if (engine.status.phase == SyncPhase.error) {
      _retryAt = now().add(
        engine.status.retryAfter ?? const Duration(seconds: 30),
      );
      _scheduleRetry();
    } else if (engine.status.phase == SyncPhase.synced) {
      _retryAt = null;
      _retry?.cancel();
    }
  }

  void _scheduleRetry() {
    _retry?.cancel();
    if (!_active || _retryAt == null) return;
    final wait = _retryAt!.difference(now());
    _retry = Timer(wait.isNegative ? Duration.zero : wait, _trigger);
  }

  void _trigger() {
    if (!_active || _closed || engine.status.phase == SyncPhase.needsSignIn) {
      return;
    }
    if (_retryAt != null && now().isBefore(_retryAt!)) {
      _scheduleRetry();
      return;
    }
    unawaited(engine.synchronize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_active) {
          _trigger();
        } else {
          start();
        }
      case AppLifecycleState.inactive:
        start();
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        stop();
    }
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    stop();
    engine.removeListener(_stateChanged);
    WidgetsBinding.instance.removeObserver(this);
  }
}
