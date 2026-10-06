"""Exercise parent death with a synthetic recorder; never open a microphone."""
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

recorder = '''
import os, signal, sys, time
from pathlib import Path
def stop(*_):
    Path(sys.argv[2]).write_text('stopped')
    sys.exit(0)
signal.signal(signal.SIGINT, stop)
Path(sys.argv[1]).write_text(str(os.getpid()))
while True: time.sleep(0.05)
'''

if sys.argv[1] == '--parent':
    binary, directory = sys.argv[2:]
    subprocess.Popen([binary, '--nala-audio-helper', sys.executable, '-c',
                      recorder, directory + '/ready', directory + '/stopped'],
                     env={**os.environ, 'DISPLAY': '', 'WAYLAND_DISPLAY': ''})
    time.sleep(60)
else:
    with tempfile.TemporaryDirectory(prefix='nala-parent-') as directory:
        parent = subprocess.Popen([sys.executable, __file__, '--parent',
                                   sys.argv[1], directory])
        ready, stopped = Path(directory) / 'ready', Path(directory) / 'stopped'
        child_pid = None
        try:
            deadline = time.monotonic() + 4
            while not ready.exists() and time.monotonic() < deadline:
                time.sleep(0.025)
            assert ready.exists(), 'El helper de audio no inició el grabador sintético.'
            child_pid = int(ready.read_text())
            parent.kill()
            parent.wait()
            deadline = time.monotonic() + 4
            while not stopped.exists() and time.monotonic() < deadline:
                time.sleep(0.025)
            assert stopped.exists(), 'El proceso de audio sobrevivió al cierre de Nala.'
        finally:
            if parent.poll() is None:
                parent.kill()
                parent.wait()
            if child_pid and not stopped.exists():
                try:
                    os.kill(child_pid, signal.SIGINT)
                except ProcessLookupError:
                    pass
