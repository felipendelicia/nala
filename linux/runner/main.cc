#include "my_application.h"
#include <cstring>
#include <cstdio>
#include <csignal>
#include <sys/prctl.h>
#include <unistd.h>

int main(int argc, char** argv) {
  // The recording process must not survive closing or terminating Nala.
  // This mode execs the audio tool before GTK or the Flutter engine starts.
  if (argc >= 3 && std::strcmp(argv[1], "--nala-audio-helper") == 0) {
    const pid_t parent = getppid();
    if (prctl(PR_SET_PDEATHSIG, SIGINT) != 0) return 126;
    if (getppid() != parent) raise(SIGINT);
    execvp(argv[2], &argv[2]);
    std::perror("Nala audio");
    return 127;
  }
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
