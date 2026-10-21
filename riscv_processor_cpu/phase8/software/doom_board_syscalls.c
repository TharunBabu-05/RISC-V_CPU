#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>

#include "ddr_wad_handoff.h"
#include "soc.h"
#include "uart.h"

extern char __heap_start;
extern char __heap_end;
static char *heap_next = &__heap_start;
static struct {
    uint32_t position;
    int open;
} wad_files[4];

static int wad_fd(int fd) {
    int slot = fd - 3;
    return slot >= 0 && slot < 4 && wad_files[slot].open ? slot : -1;
}

static const ddr_wad_handoff_t *wad_info(void) {
    const ddr_wad_handoff_t *info =
        (const ddr_wad_handoff_t *)DDR_WAD_HANDOFF_ADDR;
    if (info->magic != DDR_WAD_HANDOFF_MAGIC || info->base != DDR_WAD_BASE ||
        info->size < 12 || info->size > DDR_WAD_MAX) return 0;
    return info;
}

static int is_wad_path(const char *path) {
    const char *name = strrchr(path, '/');
    if (name) path = name + 1;
    return strcmp(path, "doom1.wad") == 0;
}

void *_sbrk(ptrdiff_t increment) {
    char *previous = heap_next;
    uintptr_t next = ((uintptr_t)heap_next + increment + 7u) & ~(uintptr_t)7u;
    if (increment < 0 || next > (uintptr_t)&__heap_end) {
        errno = ENOMEM;
        return (void *)-1;
    }
    heap_next = (char *)next;
    return previous;
}

int _open(const char *path, int flags, ...) {
    if (is_wad_path(path) && wad_info() && !(flags & (O_WRONLY | O_RDWR))) {
        for (int i = 0; i < 4; ++i) {
            if (!wad_files[i].open) {
                wad_files[i].position = 0;
                wad_files[i].open = 1;
                return i + 3;
            }
        }
        errno = EMFILE;
        return -1;
    }
    errno = ENOENT;
    return -1;
}

int _close(int fd) {
    int slot = wad_fd(fd);
    if (slot >= 0) {
        wad_files[slot].open = 0;
        return 0;
    }
    if (fd == 0 || fd == 1 || fd == 2) return 0;
    errno = EBADF;
    return -1;
}

ssize_t _read(int fd, void *buffer, size_t count) {
    int slot = wad_fd(fd);
    if (slot >= 0 && wad_info()) {
        uint32_t size = wad_info()->size;
        uint32_t position = wad_files[slot].position;
        if (position > size) return 0;
        if (count > size - position) count = size - position;
        memcpy(buffer, (const void *)(DDR_WAD_BASE + position), count);
        wad_files[slot].position += count;
        return (ssize_t)count;
    }
    if (fd == 0 && uart_kbhit()) {
        *(char *)buffer = uart_getc();
        return 1;
    }
    errno = EBADF;
    return -1;
}

ssize_t _write(int fd, const void *buffer, size_t count) {
    if (fd != 1 && fd != 2) {
        errno = EBADF;
        return -1;
    }
    const char *data = buffer;
    for (size_t i = 0; i < count; ++i) {
        if (data[i] == '\n') uart_putc('\r');
        uart_putc(data[i]);
    }
    return (ssize_t)count;
}

off_t _lseek(int fd, off_t offset, int whence) {
    int slot = wad_fd(fd);
    if (slot < 0 || !wad_info()) {
        errno = EBADF;
        return -1;
    }
    int64_t base = whence == SEEK_SET ? 0 :
                   whence == SEEK_CUR ? wad_files[slot].position :
                   whence == SEEK_END ? wad_info()->size : -1;
    int64_t position = base + offset;
    if (base < 0 || position < 0 || position > wad_info()->size) {
        errno = EINVAL;
        return -1;
    }
    wad_files[slot].position = (uint32_t)position;
    return (off_t)position;
}

int _fstat(int fd, struct stat *st) {
    memset(st, 0, sizeof(*st));
    if (wad_fd(fd) >= 0 && wad_info()) {
        st->st_mode = S_IFREG | 0444;
        st->st_size = wad_info()->size;
        return 0;
    }
    if (fd >= 0 && fd <= 2) {
        st->st_mode = S_IFCHR | 0666;
        return 0;
    }
    errno = EBADF;
    return -1;
}

int _stat(const char *path, struct stat *st) {
    if (is_wad_path(path) && wad_info()) {
        memset(st, 0, sizeof(*st));
        st->st_mode = S_IFREG | 0444;
        st->st_size = wad_info()->size;
        return 0;
    }
    errno = ENOENT;
    return -1;
}

int _isatty(int fd) { return fd >= 0 && fd <= 2; }

int _getpid(void) { return 1; }

int _kill(int pid, int signal) {
    (void)pid;
    (void)signal;
    errno = ESRCH;
    return -1;
}

int _link(const char *old_path, const char *new_path) {
    (void)old_path;
    (void)new_path;
    errno = EROFS;
    return -1;
}

int _unlink(const char *path) {
    (void)path;
    errno = EROFS;
    return -1;
}

int mkdir(const char *path, mode_t mode) {
    (void)path;
    (void)mode;
    errno = EROFS;
    return -1;
}

int _gettimeofday(struct timeval *tv, void *tz) {
    (void)tz;
    uint32_t hi, lo, check;
    do {
        hi = CLINT_MTIME_HI;
        lo = CLINT_MTIME_LO;
        check = CLINT_MTIME_HI;
    } while (hi != check);
    uint64_t micros = (((uint64_t)hi << 32) | lo) / 25u;
    tv->tv_sec = (time_t)(micros / 1000000u);
    tv->tv_usec = (suseconds_t)(micros % 1000000u);
    return 0;
}
