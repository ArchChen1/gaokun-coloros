#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#define ESP_MNT "/gk3esp"
#define LOG_DIR ESP_MNT "/gk3-debug"
#define KMSG_LOG LOG_DIR "/kmsg.log"
#define KMSG_PREV LOG_DIR "/kmsg.previous.log"
#define LOGCAT_LOG LOG_DIR "/logcat.txt"
#define LOGCAT_PREV LOG_DIR "/logcat.previous.txt"
#define LOG_CAP (64ull * 1024ull * 1024ull)

static int copy_file(const char *src, int out) {
    int in = open(src, O_RDONLY | O_CLOEXEC);
    if (in < 0) return -1;
    char buf[4096];
    ssize_t n;
    while ((n = read(in, buf, sizeof(buf))) > 0) {
        if (write(out, buf, (size_t)n) != n) { close(in); return -1; }
    }
    close(in);
    return n < 0 ? -1 : 0;
}

static int read_dev_numbers(const char *path, unsigned int *maj, unsigned int *min) {
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return -1;
    char buf[64];
    ssize_t n = read(fd, buf, sizeof(buf) - 1);
    close(fd);
    if (n <= 0) return -1;
    buf[n] = 0;
    return sscanf(buf, "%u:%u", maj, min) == 2 ? 0 : -1;
}

static int create_partition_node(const char *name) {
    char syspath[256];
    char devpath[256];
    snprintf(syspath, sizeof(syspath), "/sys/class/block/%s/dev", name);
    snprintf(devpath, sizeof(devpath), "/dev/%s", name);
    struct stat st;
    if (stat(devpath, &st) == 0) return S_ISBLK(st.st_mode) ? 0 : -1;
    unsigned int maj = 0, min = 0;
    if (read_dev_numbers(syspath, &maj, &min) != 0) return -1;
    if (mknod(devpath, S_IFBLK | 0600, makedev(maj, min)) != 0 && errno != EEXIST)
        return -1;
    return 0;
}

static int mount_esp(void) {
    mkdir(ESP_MNT, 0755);
    for (int i = 0; i < 60; i++) {
        if (create_partition_node("nvme0n1p1") == 0 &&
            mount("/dev/nvme0n1p1", ESP_MNT, "vfat", MS_SYNCHRONOUS, "rw,umask=000") == 0) {
            if (access(ESP_MNT "/loader", F_OK) == 0 || access(ESP_MNT "/EFI", F_OK) == 0)
                return 0;
            umount2(ESP_MNT, MNT_DETACH);
        }
        usleep(250000);
    }
    return -1;
}

static int prepare_kmsg(void) {
    if (mkdir(LOG_DIR, 0755) != 0 && errno != EEXIST) return -1;
    unlink(KMSG_PREV);
    rename(KMSG_LOG, KMSG_PREV);
    int out = open(KMSG_LOG, O_WRONLY | O_CREAT | O_TRUNC | O_SYNC | O_CLOEXEC, 0644);
    if (out < 0) return -1;
    dprintf(out, "gaokun3 delayed logger: kmsg + logcat\n\ncmdline:\n");
    copy_file("/proc/cmdline", out);
    dprintf(out, "\n\n===== kmsg =====\n");
    fsync(out);
    return out;
}

static void kmsg_loop(int out) {
    int in = open("/dev/kmsg", O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (in < 0) return;
    unsigned long long total = 0;
    char buf[16384];
    for (;;) {
        ssize_t n = read(in, buf, sizeof(buf));
        if (n > 0) {
            if (total + (unsigned long long)n > LOG_CAP) {
                if (ftruncate(out, 0) == 0) {
                    lseek(out, 0, SEEK_SET);
                    dprintf(out, "===== log truncated =====\n");
                    total = 0;
                }
            }
            if (write(out, buf, (size_t)n) == n) {
                total += (unsigned long long)n;
                fsync(out);
            }
        } else {
            usleep(20000);
        }
    }
}

static void run_logcat(void) {
    unlink(LOGCAT_PREV);
    rename(LOGCAT_LOG, LOGCAT_PREV);
    for (int i = 0; i < 240; i++) {
        if (access("/system/bin/logcat", X_OK) == 0) break;
        usleep(250000);
    }
    if (access("/system/bin/logcat", X_OK) != 0) return;
    execl("/system/bin/logcat", "logcat", "-b", "all", "-v", "threadtime", "-f", LOGCAT_LOG, (char *)NULL);
    _exit(1);
}

static void delayed_main(void) {
    setsid();
    sleep(8);
    if (mount_esp() != 0) _exit(10);
    int out = prepare_kmsg();
    if (out < 0) _exit(11);
    pid_t cat = fork();
    if (cat == 0) run_logcat();
    kmsg_loop(out);
    _exit(0);
}

int main(int argc, char **argv) {
    (void)argc;
    pid_t child = fork();
    if (child == 0) {
        pid_t grandchild = fork();
        if (grandchild > 0) _exit(0);
        if (grandchild == 0) delayed_main();
        _exit(1);
    }
    if (child > 0) waitpid(child, NULL, 0);
    execv("/init.real", argv);
    return 127;
}