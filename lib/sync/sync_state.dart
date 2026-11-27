enum SyncPhase { localOnly, pending, syncing, synced, error, needsSignIn }

enum SyncStage { receiving, sending }

class SyncStatus {
  const SyncStatus(
    this.phase, {
    this.pendingCount = 0,
    this.message,
    this.retryAfter,
    this.stage,
  });
  final SyncPhase phase;
  final int pendingCount;
  final String? message;
  final Duration? retryAfter;
  final SyncStage? stage;
  String get label => switch (phase) {
    SyncPhase.localOnly => 'Guardado en este dispositivo',
    SyncPhase.pending => 'Cambios pendientes de sincronizar',
    SyncPhase.syncing => switch (stage) {
      SyncStage.receiving => 'Recibiendo cambios del servidor…',
      SyncStage.sending => 'Enviando cambios al servidor…',
      null => 'Sincronizando con el servidor…',
    },
    SyncPhase.synced => 'Sincronizado con el servidor',
    SyncPhase.error => 'Guardado local · Sincronización pendiente',
    SyncPhase.needsSignIn => 'Guardado local · Reconectar servidor',
  };
}
