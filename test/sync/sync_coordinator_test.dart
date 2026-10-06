import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/document/asset_store.dart';
import 'package:apuntes/sync/sync_engine.dart';
import 'package:apuntes/sync/sync_coordinator.dart';
import '../support/fake_remote_store.dart';
import '../support/memory_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('guardar agrupa sincronizaciones y pausar suspende el sondeo', () {
    fakeAsync((async) {
      final remote = FakeRemoteStore();
      final engine = SyncEngine(
        repository: MemoryRepository(),
        assets: FileAssetStore('/unused'),
        remote: remote,
      );
      final coordinator = SyncCoordinator(
        engine,
        now: async.getClock(DateTime.utc(2026)).now,
      );
      coordinator.start();
      async.flushMicrotasks();
      expect(remote.listingCalls, 2);
      coordinator.notifyLocalChange();
      async.elapse(const Duration(seconds: 1));
      coordinator.notifyLocalChange();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(remote.listingCalls, 2);
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(remote.listingCalls, 4);
      coordinator.didChangeAppLifecycleState(AppLifecycleState.paused);
      async.elapse(const Duration(minutes: 2));
      async.flushMicrotasks();
      expect(remote.listingCalls, 4);
      coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
      async.flushMicrotasks();
      expect(remote.listingCalls, 6);
      coordinator.dispose();
      engine.dispose();
      async.flushMicrotasks();
    });
  });
  test('un cambio nuevo respeta la espera tras un fallo y recupera la red', () {
    fakeAsync((async) {
      final remote = FakeRemoteStore()..offline = true;
      final engine = SyncEngine(
        repository: MemoryRepository(),
        assets: FileAssetStore('/unused'),
        remote: remote,
      );
      final coordinator = SyncCoordinator(
        engine,
        now: async.getClock(DateTime.utc(2026)).now,
      );
      coordinator.start();
      async.flushMicrotasks();
      expect(remote.listingCalls, 1);
      coordinator.notifyLocalChange();
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(remote.listingCalls, 2);
      // Second failure waits four seconds; editing must not shorten that wait.
      coordinator.notifyLocalChange();
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(remote.listingCalls, 2);
      remote.offline = false;
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(remote.listingCalls, 4);
      coordinator.dispose();
      engine.dispose();
      async.flushMicrotasks();
    });
  });
}
