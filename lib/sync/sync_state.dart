enum SyncPhase { localOnly, pending, syncing, synced, error, needsSignIn }

class SyncStatus {
  const SyncStatus(
    this.phase, {
    this.pendingCount = 0,
    this.message,
    this.retryAfter,
  });
  final SyncPhase phase;
  final int pendingCount;
  final String? message;
  final Duration? retryAfter;
  String get label => switch (phase) {
    SyncPhase.localOnly => 'Guardado en este dispositivo',
    SyncPhase.pending => 'Cambios pendientes de sincronizar',
    SyncPhase.syncing => 'Sincronizando con el servidor…',
    SyncPhase.synced => 'Sincronizado con el servidor',
    SyncPhase.error => 'Guardado local · Sincronización pendiente',
    SyncPhase.needsSignIn => 'Guardado local · Reconectar servidor',
  };
}
