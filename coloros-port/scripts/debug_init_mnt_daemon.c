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

#define ESP_MNT "/mnt/gk3esp"
#define LOG_DIR ESP_MNT "/gk3-debug"
#define LOG_CUR LOG_DIR "/kmsg.log"
#define LOG_PREV LOG_DIR "/kmsg.previous.log"
#define LOG_CAP (64ull * 1024ull * 1024ull)

static int copy_file(const char *src, int out) {
    int in = open(src, O_RDONLY | O_CLOEXEC);
    if (in < 0) return -1;
    char b[4096];
    ssize_t n;
    while ((n = read(in, b, sizeof(b))) > 0) {
        if (write(out, b, (size_t)n) != n) { close(in); return -1; }
    }
    close(in);
    return n < 0 ? -1 : 0;
}

static int esp_marker(void) {
    if (access(ESP_MNT "/loader/loader.conf", R_OK) == 0) return 1;
    DIR *d = opendir(ESP_MNT "/loader/entries");
    if (!d) return 0;
    int found = 0;
    struct dirent *e;
    while ((e = readdir(d))) {
        size_t n = strlen(e->d_name);
        if (n < 5 || strcmp(e->d_name + n - 5, ".conf")) continue;
        char p[512];
        snprintf(p, sizeof(p), ESP_MNT "/loader/entries/%s", e->d_name);
        int fd = open(p, O_RDONLY | O_CLOEXEC);
        if (fd < 0) continue;
        char b[8192];
        ssize_t r = read(fd, b, sizeof(b) - 1);
        close(fd);
        if (r > 0) {
            b[r] = 0;
            if (strstr(b, "android") || strstr(b, "Android")) { found = 1; break; }
        }
    }
    closedir(d);
    return found;
}

static int try_mount(const char *dev) {
    if (mount(dev, ESP_MNT, "vfat", MS_SYNCHRONOUS, "rw,umask=000") != 0) return 0;
    if (esp_marker()) return 1;
    umount2(ESP_MNT, MNT_DETACH);
    return 0;
}

static int ensure_block_node(const char *name) {
    char devpath[512], syspath[512];
    snprintf(devpath, sizeof(devpath), "/dev/%s", name);
    struct stat st;
    if (stat(devpath, &st) == 0) return S_ISBLK(st.st_mode) ? 0 : -1;

    snprintf(syspath, sizeof(syspath), "/sys/class/block/%s/dev", name);
    int fd = open(syspath, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return -1;
    char b[64];
    ssize_t n = read(fd, b, sizeof(b) - 1);
    close(fd);
    if (n <= 0) return -1;
    b[n] = 0;
    unsigned int maj = 0, min = 0;
    if (sscanf(b, "%u:%u", &maj, &min) != 2) return -1;
    if (mknod(devpath, S_IFBLK | 0600, makedev(maj, min)) != 0 && errno != EEXIST)
        return -1;
    return 0;
}

static int find_esp(void) {
    if (try_mount("/dev/block/by-name/esp")) return 1;
    DIR *d = opendir("/sys/class/block");
    if (!d) return 0;
    struct dirent *e;
    int found = 0;
    while ((e = readdir(d))) {
        if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, "..")) continue;
        if (!strncmp(e->d_name, "loop", 4) || !strncmp(e->d_name, "ram", 3) ||
            !strncmp(e->d_name, "zram", 4) || !strncmp(e->d_name, "dm-", 3)) continue;
        char partpath[512];
        snprintf(partpath, sizeof(partpath), "/sys/class/block/%s/partition", e->d_name);
        if (access(partpath, F_OK) != 0) continue;
        if (ensure_block_node(e->d_name) != 0) continue;
        char dev[512];
        snprintf(dev, sizeof(dev), "/dev/%s", e->d_name);
        if (try_mount(dev)) { found = 1; break; }
    }
    closedir(d);
    return found;
}

static int prepare_log(void) {
    mkdir("/mnt", 0755);
    mkdir(ESP_MNT, 0755);
    if (!find_esp()) return -1;
    mkdir(LOG_DIR, 0755);
    unlink(LOG_PREV);
    rename(LOG_CUR, LOG_PREV);
    int fd = open(LOG_CUR, O_WRONLY | O_CREAT | O_TRUNC | O_SYNC | O_CLOEXEC, 0644);
    if (fd < 0) return -1;
    dprintf(fd, "gaokun3 persistent kmsg capture\n\ncmdline:\n");
    copy_file("/proc/cmdline", fd);
    dprintf(fd, "\n\n===== kmsg =====\n");
    fsync(fd);
    return fd;
}

static void logger_loop(int out) {
    int in = -1;
    for (int i = 0; i < 600 && in < 0; i++) {
        in = open("/dev/kmsg", O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        if (in < 0) usleep(100000);
    }
    if (in < 0) {
        dprintf(out, "open /dev/kmsg failed: %s\n", strerror(errno));
        fsync(out);
        return;
    }
    unsigned long long total = 0;
    char b[16384];
    for (;;) {
        ssize_t n = read(in, b, sizeof(b));
        if (n > 0) {
            if (total + (unsigned long long)n > LOG_CAP) {
                if (ftruncate(out, 0) == 0) {
                    lseek(out, 0, SEEK_SET);
                    dprintf(out, "===== log truncated =====\n");
                    total = 0;
                }
            }
            if (write(out, b, (size_t)n) == n) {
                total += (unsigned long long)n;
                fsync(out);
            } else {
                usleep(100000);
            }
        } else if (n < 0 && errno != EAGAIN && errno != EINTR) {
            usleep(200000);
        } else {
            usleep(20000);
        }
    }
}

static void logger_main(void) {
    for (int i = 0; i < 600; i++) {
        if (access("/dev/kmsg", R_OK) == 0 && access("/proc/cmdline", R_OK) == 0 &&
            access("/sys/class/block", R_OK) == 0)
            break;
        usleep(100000);
    }
    int out = prepare_log();
    if (out < 0) return;
    logger_loop(out);
    close(out);
}

int main(void) {
    pid_t child = fork();
    if (child == 0) {
        setsid();
        pid_t grandchild = fork();
        if (grandchild > 0) _exit(0);
        if (grandchild == 0) logger_main();
        _exit(1);
    }
    if (child > 0) waitpid(child, NULL, 0);
    execl("/init.real", "/init", (char *)NULL);
    int k = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
    if (k >= 0) {
        dprintf(k, "gk3debug: exec /init.real failed: %s\n", strerror(errno));
        close(k);
    }
    return 127;
}