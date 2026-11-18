#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#define ESP_MNT "/mnt"
#define LOG_DIR ESP_MNT "/gk3-debug"
#define LOG_CUR LOG_DIR "/debug.log"
#define LOG_CAP (64u * 1024u * 1024u)

static int copy_file(const char *src, int out) {
    int in = open(src, O_RDONLY | O_CLOEXEC);
    if (in < 0) return -1;
    char b[4096];
    ssize_t n;
    while ((n = read(in, b, sizeof b)) > 0) {
        if (write(out, b, (size_t)n) != n) { close(in); return -1; }
    }
    close(in);
    return n < 0 ? -1 : 0;
}

static int setup_environment(void) {
    mkdir("/proc", 0555);
    mkdir("/sys", 0555);
    mkdir("/dev", 0755);
    mkdir(ESP_MNT, 0755);
    mount("proc", "/proc", "proc", 0, NULL);
    mount("sysfs", "/sys", "sysfs", 0, NULL);
    mount("devtmpfs", "/dev", "devtmpfs", 0, NULL);
    if (mount("/dev/block/by-name/esp", ESP_MNT, "vfat", MS_SYNCHRONOUS, "rw,umask=000") != 0)
        return -1;
    return 0;
}

static int open_log(void) {
    mkdir(LOG_DIR, 0755);
    unlink(LOG_DIR "/debug.previous.log");
    rename(LOG_CUR, LOG_DIR "/debug.previous.log");
    int fd = open(LOG_CUR, O_WRONLY | O_CREAT | O_TRUNC | O_SYNC | O_CLOEXEC, 0644);
    if (fd < 0) return -1;
    dprintf(fd, "gaokun3 emergency debug boot\n\ncmdline:\n");
    copy_file("/proc/cmdline", fd);
    dprintf(fd, "\n\n===== /dev/kmsg =====\n");
    fsync(fd);
    return fd;
}

static void logger_loop(int out) {
    int in = open("/dev/kmsg", O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (in < 0) {
        dprintf(out, "open /dev/kmsg: %s\n", strerror(errno));
        fsync(out);
        return;
    }
    unsigned long long total = 0;
    char b[16384];
    for (;;) {
        ssize_t n = read(in, b, sizeof b);
        if (n > 0) {
            if (total + (unsigned long long)n > LOG_CAP) {
                if (ftruncate(out, 0) == 0) {
                    lseek(out, 0, SEEK_SET);
                    dprintf(out, "===== truncated =====\n");
                    total = 0;
                }
            }
            if (write(out, b, (size_t)n) == n) {
                total += (unsigned long long)n;
                fsync(out);
            }
        } else if (n < 0 && errno != EAGAIN && errno != EINTR) {
            usleep(200000);
        } else {
            usleep(20000);
        }
    }
}

int main(void) {
    if (setup_environment() != 0) {
        sync();
        reboot(0x4321fedc);
        for (;;) pause();
    }
    int out = open_log();
    if (out < 0) {
        umount(ESP_MNT);
        sync();
        reboot(0x4321fedc);
        for (;;) pause();
    }
    pid_t child = fork();
    if (child == 0) {
        sleep(20);
        write(out, "\n===== returning to Android boot after 20s =====\n", 54);
        fsync(out);
        umount(ESP_MNT);
        sync();
        reboot(0x4321fedc);
        _exit(0);
    }
    logger_loop(out);
    return 0;
}
