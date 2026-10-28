// Consolidated libc header for translate-c. Union of the system headers that
// were previously pulled in via per-file @cImport blocks across the compositor
// (server, UI widgets, ipc) and the kidul-files TUI. _FORTIFY_SOURCE is
// disabled so translate-c emits the plain function declarations rather than
// glibc's __*_chk fortify aliases (same runtime symbols, cleaner bindings).
#define _FORTIFY_SOURCE 0

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/statvfs.h>
#include <dirent.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <time.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <signal.h>
#include <sys/wait.h>
