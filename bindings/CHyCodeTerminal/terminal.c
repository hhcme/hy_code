#include "hycode_terminal.h"
#include <errno.h>
#include <fcntl.h>
#include <libproc.h>
#include <pwd.h>
#include <signal.h>
#include <spawn.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>
#include <util.h>

static int terminal_fd(int fd) {
    if (fd >= 3) return fd;
    int copy = fcntl(fd, F_DUPFD_CLOEXEC, 3);
    int error = errno;
    close(fd);
    errno = error;
    return copy;
}

int hycode_terminal_spawn(const char *helper, char *const argv[], char *const envp[],
                          const char *directory, int columns, int rows,
                          pid_t *pid, int *master_fd) {
    if (!helper || !argv || !argv[0] || !envp || !directory || !pid || !master_fd ||
        columns < 2 || columns > 500 || rows < 2 || rows > 300) return EINVAL;
    struct winsize size = { .ws_row = (uint16_t)rows, .ws_col = (uint16_t)columns };
    int master = -1, slave = -1, result;
    if (openpty(&master, &slave, NULL, NULL, &size) < 0) return errno;
    master = terminal_fd(master);
    if (master < 0) { result = errno; close(slave); return result; }
    slave = terminal_fd(slave);
    if (slave < 0) { result = errno; close(master); return result; }
    if (fcntl(master, F_SETFD, FD_CLOEXEC) < 0 ||
        fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK) < 0) {
        result = errno; goto close_fds;
    }
    posix_spawn_file_actions_t actions;
    posix_spawnattr_t attrs;
    result = posix_spawn_file_actions_init(&actions);
    if (result) goto close_fds;
    result = posix_spawnattr_init(&attrs);
    if (result) { posix_spawn_file_actions_destroy(&actions); goto close_fds; }
    sigset_t defaults, mask;
    sigemptyset(&defaults);
    sigemptyset(&mask);
    const int signals[] = { SIGHUP, SIGINT, SIGQUIT, SIGTERM, SIGPIPE, SIGCHLD, SIGTSTP, SIGTTIN, SIGTTOU };
    for (unsigned i = 0; i < sizeof(signals) / sizeof(signals[0]); ++i) sigaddset(&defaults, signals[i]);
#define TRY(call) do { result = (call); if (result) goto destroy; } while (0)
    TRY(posix_spawnattr_setsigdefault(&attrs, &defaults));
    TRY(posix_spawnattr_setsigmask(&attrs, &mask));
    TRY(posix_spawnattr_setflags(&attrs, POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK));
    if (__builtin_available(macOS 26.0, *)) {
        TRY(posix_spawn_file_actions_addchdir(&actions, directory));
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        TRY(posix_spawn_file_actions_addchdir_np(&actions, directory));
#pragma clang diagnostic pop
    }
    for (int fd = 0; fd < 3; ++fd) TRY(posix_spawn_file_actions_adddup2(&actions, slave, fd));
    TRY(posix_spawn_file_actions_addclose(&actions, master));
    TRY(posix_spawn_file_actions_addclose(&actions, slave));
    TRY(posix_spawn(pid, helper, &actions, &attrs, argv, envp));
destroy:
    posix_spawnattr_destroy(&attrs);
    posix_spawn_file_actions_destroy(&actions);
#undef TRY
close_fds:
    close(slave);
    if (result) close(master); else *master_fd = master;
    return result;
}

int hycode_terminal_resize(int fd, int columns, int rows) {
    if (columns < 2 || columns > 500 || rows < 2 || rows > 300) return EINVAL;
    struct winsize size = { .ws_row = (uint16_t)rows, .ws_col = (uint16_t)columns };
    return ioctl(fd, TIOCSWINSZ, &size) < 0 ? errno : 0;
}

int hycode_terminal_user_shell(char *buffer, size_t capacity) {
    if (!buffer || capacity == 0) return EINVAL;
    char scratch[16384];
    struct passwd account, *result = NULL;
    int error = getpwuid_r(getuid(), &account, scratch, sizeof(scratch), &result);
    if (error) return error;
    if (!result || !account.pw_shell || account.pw_shell[0] != '/') return ENOENT;
    return strlcpy(buffer, account.pw_shell, capacity) >= capacity ? ERANGE : 0;
}

void hycode_terminal_signal(pid_t leader, int fd, int number) {
    if (leader <= 1) return;
    (void)fd;
    /* Interactive job control creates additional process groups. Enumerate the
     * session, not just its foreground group; inspect no command lines or files.
     * The unreaped leader reserves the session identity throughout cleanup. */
    int count = proc_listallpids(NULL, 0);
    if (count > 0 && count < 65536) {
        int capacity = count + 256;
        pid_t *pids = calloc((size_t)capacity, sizeof(pid_t));
        if (pids) {
            int found = proc_listallpids(pids, capacity * (int)sizeof(pid_t));
            if (found > capacity) found = capacity;
            for (int i = 0; i < found; ++i) {
                pid_t candidate = pids[i];
                if (candidate <= 1 || candidate == leader || getsid(candidate) != leader) continue;
                struct proc_bsdinfo before, current;
                int size = sizeof(before);
                if (proc_pidinfo(candidate, PROC_PIDTBSDINFO, 0, &before, size) != size) continue;
                if (getsid(candidate) != leader ||
                    proc_pidinfo(candidate, PROC_PIDTBSDINFO, 0, &current, size) != size ||
                    before.pbi_start_tvsec != current.pbi_start_tvsec ||
                    before.pbi_start_tvusec != current.pbi_start_tvusec) continue;
                kill(candidate, number);
            }
            free(pids);
        }
    }
    kill(-leader, number);
    kill(leader, number); /* also covers a helper which has not called setsid yet */
}
