#ifndef HYCODE_TERMINAL_H
#define HYCODE_TERMINAL_H
#include <sys/types.h>
#include <stddef.h>

/* Caller supplies immutable, NUL-terminated argv/envp for the duration of spawn.
 * On success caller owns master_fd and must reap pid exactly once. On failure
 * no descriptors or child are transferred. Returns errno, or zero on success.
 * Does not fork into the Swift runtime: a fresh helper acquires the control tty.
 * All calls are serialized by the Swift session's private dispatch queue. */
int hycode_terminal_spawn(const char *helper, char *const argv[], char *const envp[],
                          const char *directory, int columns, int rows,
                          pid_t *pid, int *master_fd);
int hycode_terminal_resize(int fd, int columns, int rows);
/* Background-only account lookup, bounded storage; no credential access. */
int hycode_terminal_user_shell(char *buffer, size_t capacity);
/* Signal the owned, unreaped leader and verified members of its session.
 * Jobs deliberately detached into another session are outside this contract. */
void hycode_terminal_signal(pid_t leader, int fd, int signal_number);
#endif
