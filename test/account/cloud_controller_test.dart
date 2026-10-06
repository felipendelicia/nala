import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:apuntes/account/auth_service.dart';
import 'package:apuntes/account/cloud_controller.dart';
import 'package:apuntes/document/notebook.dart';
import 'package:apuntes/bootstrap.dart';
import 'package:apuntes/account/linux_auth_service.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:oauth2/oauth2.dart' as oauth2;
import '../support/fake_auth_service.dart';
import '../support/fake_remote_store.dart';

class ChoosingAuth extends FakeAuthService {
  ChoosingAuth() : super(current: null);
  GoogleAccount next = const GoogleAccount('A', 'a@example.invalid');
  Completer<void>? gate;
  @override
  Future<GoogleAccount> signIn() async {
    await gate?.future;
    return current = next;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'una adopción interrumpida vuelve a copiar el estado local más reciente',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'nala-adoption-cancel-',
      );
      final auth = ChoosingAuth(), remote = FakeRemoteStore();
      final cloud = await CloudController.open(
        dir.path,
        auth: auth,
        autoStart: false,
        remoteFactory: (_, _) => remote,
      );
      try {
        final entry = await cloud.services.library.createNotebook(
          title: 'Antes',
          subject: '',
          pattern: PaperPattern.blank,
        );
        final partition =
            '${dir.path}/accounts/${sha256.convert(utf8.encode('A'))}';
        final partial = await AppServices.open(partition);
        for (final revision in await cloud.services.repository.history(
          entry.notebook.id,
        )) {
          await partial.repository.acceptRemote(revision);
        }
        await partial.close();
        // Durable state after cancellation/crash before selecting the partition.
        await File(
          '${dir.path}/local-adoption.json',
        ).writeAsString('{"accountId":"A","completed":true}');
        await cloud.services.library.updateNotebook(
          entry,
          entry.notebook.copyWith(title: 'Después'),
        );
        await cloud.services.library.createNotebook(
          title: 'Creado después de cancelar',
          subject: '',
          pattern: PaperPattern.blank,
        );
        await cloud.connect();
        expect(
          (await cloud.services.repository.list())
              .map((e) => e.notebook.title)
              .toSet(),
          {'Después', 'Creado después de cancelar'},
        );
        expect(await cloud.services.repository.pending(), hasLength(2));
      } finally {
        await cloud.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'desconexión persiste aunque el llavero no pueda borrar su token',
    () async {
      final dir = await Directory.systemTemp.createTemp('nala-logout-keyring-');
      final store = FakeTokenStore()
        ..value = jsonEncode({
          'clientId': 'fixture-client',
          'account': {'id': 'A', 'email': 'a@example.invalid'},
          'credentials': oauth2.Credentials('retained-token').toJson(),
        });
      await File(
        '${dir.path}/active-account.json',
      ).writeAsString('{"id":"A","email":"a@example.invalid"}');
      var remotes = 0;
      final auth = LinuxAuthService(
        clientId: 'fixture-client',
        tokenStore: store,
      );
      final cloud = await CloudController.open(
        dir.path,
        auth: auth,
        autoStart: false,
        remoteFactory: (_, _) {
          remotes++;
          return FakeRemoteStore();
        },
      );
      expect(cloud.connected, isTrue);
      store.unavailable = true;
      await cloud.disconnect();
      expect(auth.secureStorageAvailable, isFalse);
      expect(cloud.message, isNotNull);
      await cloud.close();
      store.unavailable = false;
      final restarted = await CloudController.open(
        dir.path,
        auth: LinuxAuthService(clientId: 'fixture-client', tokenStore: store),
        autoStart: false,
        remoteFactory: (_, _) {
          remotes++;
          return FakeRemoteStore();
        },
      );
      expect(restarted.connected, isFalse);
      expect(remotes, 1);
      await restarted.close();
      await dir.delete(recursive: true);
    },
  );
  test(
    'desconectar bloquea otra conexión mientras termina la cuenta anterior',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'nala-account-disconnect-',
      );
      final auth = ChoosingAuth(), remote = FakeRemoteStore();
      final cloud = await CloudController.open(
        dir.path,
        auth: auth,
        autoStart: false,
        remoteFactory: (_, _) => remote,
      );
      try {
        await cloud.connect();
        remote.listingGate = Completer<void>();
        final syncing = cloud.synchronize();
        while (remote.listingCalls == 0) {
          await Future<void>.delayed(Duration.zero);
        }
        final disconnecting = cloud.disconnect();
        expect(cloud.busy, isTrue);
        auth.next = const GoogleAccount('B', 'b@example.invalid');
        final connecting = cloud.connect();
        remote.listingGate!.complete();
        await syncing;
        await disconnecting;
        await connecting;
        expect(cloud.account!.id, 'A');
        expect(cloud.connected, isFalse);
        expect(auth.current, isNull);
      } finally {
        remote.listingGate?.completeIfPending();
        await cloud.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'adopta apuntes una vez y separa cuentas, recursos y colas al reiniciar',
    () async {
      final dir = await Directory.systemTemp.createTemp('nala-accounts-');
      final auth = ChoosingAuth();
      final remotes = <String, FakeRemoteStore>{};
      final cloud = await CloudController.open(
        dir.path,
        auth: auth,
        autoStart: false,
        remoteFactory: (account, _) =>
            remotes.putIfAbsent(account.id, FakeRemoteStore.new),
      );
      try {
        await cloud.services.library.createFolder('Universidad');
        final note = await cloud.services.library.createNotebook(
          title: 'Álgebra',
          subject: '',
          pattern: PaperPattern.ruled,
        );
        final bytes = Uint8List.fromList([1, 2, 3, 4]);
        final hash = await cloud.services.assets.put(bytes);
        await cloud.connect();
        expect(cloud.account!.id, 'A');
        expect(
          (await cloud.services.repository.list()).single.notebook.id,
          note.notebook.id,
        );
        expect(await cloud.services.assets.contains(hash), isTrue);
        expect((await cloud.services.repository.pending()).length, 1);
        await cloud.synchronize();
        expect(remotes['A']!.revisions.length, 1);
        await cloud.disconnect();
        // Offline additions remain attached to A, even after disconnecting.
        await cloud.services.library.createNotebook(
          title: 'Sólo A',
          subject: '',
          pattern: PaperPattern.blank,
        );
        auth.next = const GoogleAccount('B', 'b@example.invalid');
        await cloud.connect();
        expect(await cloud.services.repository.list(), isEmpty);
        expect(await cloud.services.assets.contains(hash), isFalse);
        await cloud.services.library.createNotebook(
          title: 'Sólo B',
          subject: '',
          pattern: PaperPattern.blank,
        );
        await cloud.synchronize();
        expect(remotes['B']!.revisions.values.single.notebook.title, 'Sólo B');
        await cloud.disconnect();
        await cloud.close();
        final offline = await CloudController.open(dir.path, autoStart: false);
        expect(offline.account!.id, 'B');
        expect(
          (await offline.services.repository.list()).single.notebook.title,
          'Sólo B',
        );
        await offline.close();
        auth.next = const GoogleAccount('A', 'a@example.invalid');
        final again = await CloudController.open(
          dir.path,
          auth: auth,
          autoStart: false,
          remoteFactory: (account, _) => remotes[account.id]!,
        );
        await again.connect();
        expect(
          (await again.services.repository.list())
              .map((e) => e.notebook.title)
              .toSet(),
          {'Álgebra', 'Sólo A'},
        );
        expect(await again.services.repository.pending(), hasLength(1));
        await again.close();
      } finally {
        await cloud.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'cambiar de cuenta espera el ciclo viejo y no sube su cola a la nueva',
    () async {
      final dir = await Directory.systemTemp.createTemp('nala-account-flight-');
      final auth = ChoosingAuth();
      final old = FakeRemoteStore(), next = FakeRemoteStore();
      final cloud = await CloudController.open(
        dir.path,
        auth: auth,
        autoStart: false,
        remoteFactory: (account, _) => account.id == 'A' ? old : next,
      );
      try {
        await cloud.connect();
        await cloud.services.library.createNotebook(
          title: 'Pendiente A',
          subject: '',
          pattern: PaperPattern.blank,
        );
        old.listingGate = Completer<void>();
        final syncing = cloud.synchronize();
        while (old.listingCalls == 0) {
          await Future<void>.delayed(Duration.zero);
        }
        auth.next = const GoogleAccount('B', 'b@example.invalid');
        var switched = false;
        final changing = cloud.connect().then((_) => switched = true);
        await Future<void>.delayed(Duration.zero);
        expect(switched, isFalse);
        old.listingGate!.complete();
        await syncing;
        await changing;
        await cloud.synchronize();
        expect(old.revisions, isEmpty);
        expect(next.revisions, isEmpty);
      } finally {
        await cloud.close();
        await dir.delete(recursive: true);
      }
    },
  );
}

extension on Completer<void> {
  void completeIfPending() {
    if (!isCompleted) complete();
  }
}
