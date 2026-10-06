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
    SyncPhase.syncing => 'Sincronizando con Drive…',
    SyncPhase.synced => 'Sincronizado con Drive',
    SyncPhase.error => 'Guardado local · Drive pendiente',
    SyncPhase.needsSignIn => 'Guardado local · Reconectar Drive',
  };
}
