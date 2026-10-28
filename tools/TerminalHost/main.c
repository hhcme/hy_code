/* A fresh process, never an application host. Acquire a controlling tty before
 * exec so interactive shells receive job control, signals and resize events. */
#include <errno.h>
#include <stdio.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc < 2 || argv[1][0] != '/' || !isatty(STDIN_FILENO)) return 126;
    if (setsid() < 0 || ioctl(STDIN_FILENO, TIOCSCTTY, 0) < 0 ||
        tcsetpgrp(STDIN_FILENO, getpgrp()) < 0) {
        fprintf(stderr, "HyCode: 无法建立终端会话（%d）\r\n", errno);
        return 126;
    }
    execv(argv[1], argv + 1);
    fprintf(stderr, "HyCode: 无法启动 Shell（%d）\r\n", errno);
    return 127;
}
