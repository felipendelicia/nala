#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
state="$root/.nala-updates"

release_binary() {
  local marker="$1" slot release
  [[ -f "$marker" && ! -L "$marker" && ! -L "$state/releases" ]] || return 1
  IFS= read -r -n 64 slot < "$marker" || return 1
  [[ "$slot" =~ ^(0|[1-9][0-9]{0,8})(\.(0|[1-9][0-9]{0,8})){2}-[0-9A-Za-z]{1,32}$ ]] || return 1
  release="$state/releases/$slot/Nala-Linux"
  [[ ! -L "$state/releases/$slot" && ! -L "$release" ]] || return 1
  [[ -f "$release/apuntes" && ! -L "$release/apuntes" && -x "$release/apuntes" ]] || return 1
  [[ -s "$release/data/flutter_assets/version.json" && -s "$release/data/icudtl.dat" ]] || return 1
  [[ -s "$release/lib/libapp.so" && -s "$release/lib/libflutter_linux_gtk.so" ]] || return 1
  printf '%s\n' "$release/apuntes"
}

run_installed() {
  local binary
  if [[ ! -L "$state" ]] &&
     { binary="$(release_binary "$state/current")" || binary="$(release_binary "$state/previous")"; }; then
    exec "$binary" "$@"
  fi
  exec "$root/Nala-Linux/apuntes" "$@"
}

activate_pending() {
  local previous
  release_binary "$state/pending" > /dev/null || return 0

  if release_binary "$state/current" > /dev/null; then
    previous="$(mktemp -- "$state/.previous-XXXXXX")" || return 1
    if ! { cat -- "$state/current" > "$previous" && mv -fT -- "$previous" "$state/previous"; }; then
      rm -f -- "$previous"
      return 1
    fi
  fi
  mv -fT -- "$state/pending" "$state/current"
}

if [[ "${1:-}" != --nala-launch-locked ]]; then
  unset NALA_PORTABLE_ROOT
  if ! command -v flock > /dev/null || [[ -L "$state" || -L "$state/run.lock" ]] ||
     ! (umask 077 && mkdir -p -- "$state") || [[ ! -w "$state" ]]; then
    run_installed "$@"
  fi

  # flock owns the lock until the GUI process exits. Its descriptor stays out of
  # Nala and its child processes, including the audio helpers.
  status=0
  flock --exclusive --nonblock --conflict-exit-code 75 --close -- \
    "$state/run.lock" bash "$root/Abrir-Nala.sh" --nala-launch-locked "$@" || status=$?
  if [[ "$status" == 75 ]]; then
    if command -v gdbus > /dev/null; then
      gdbus call --session --timeout 1 --dest com.felipe.apuntes \
        --object-path /com/felipe/apuntes --method org.freedesktop.Application.Activate \
        '{}' > /dev/null 2>&1 || true
    fi
    exit 0
  fi
  exit "$status"
fi

shift
activate_pending || printf '%s\n' 'No se pudo aplicar la actualización de Nala.' >&2
export NALA_PORTABLE_ROOT="$root"
run_installed "$@"
