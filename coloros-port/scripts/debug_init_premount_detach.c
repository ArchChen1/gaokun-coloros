#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
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
#define LOG_CUR LOG_DIR "/kmsg.log"
#define LOG_PREV LOG_DIR "/kmsg.previous.log"
#define LOG_CAP (64ull * 1024ull * 1024ull)

static int kmsg_fd = -1;
static int console_fd = -1;

static void note(const char *fmt, ...) {
    char buf[1024];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    if (n < 0) return;
    if (n > (int)sizeof(buf) - 1) n = (int)sizeof(buf) - 1;
    if (kmsg_fd >= 0) { ssize_t ignored = write(kmsg_fd, buf, (size_t)n); (void)ignored; }
    if (console_fd >= 0) { ssize_t ignored = write(console_fd, buf, (size_t)n); (void)ignored; }
}

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

static int ensure_sysfs(void) {
    if (access("/sys/class/block", F_OK) == 0) return 0;
    mkdir("/sys", 0755);
    if (mount("sysfs", "/sys", "sysfs", 0, NULL) == 0) return 1;
    if (errno == EBUSY) return 0;
    note("gk3log: mount sysfs failed: %s\n", strerror(errno));
    return -1;
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
    if (mknod(devpath, S_IFBLK | 0600, makedev(maj, min)) != 0 && errno != EEXIST) return -1;
    return 0;
}

static int mount_esp(void) {
    mkdir(ESP_MNT, 0755);
    int sys_mounted = ensure_sysfs();
    if (sys_mounted < 0) return -1;

    int ok = -1;
    if (create_partition_node("nvme0n1p1") == 0) {
        if (mount("/dev/nvme0n1p1", ESP_MNT, "vfat", MS_SYNCHRONOUS, "rw,umask=000") == 0) {
            if (access(ESP_MNT "/loader", F_OK) == 0 || access(ESP_MNT "/EFI", F_OK) == 0) {
                ok = 0;
            } else {
                note("gk3log: nvme0n1p1 mounted but ESP marker missing\n");
                umount2(ESP_MNT, MNT_DETACH);
            }
        } else {
            note("gk3log: mount nvme0n1p1 failed: %s\n", strerror(errno));
        }
    } else {
        note("gk3log: cannot create nvme0n1p1 node\n");
    }

    if (sys_mounted == 1) umount2("/sys", MNT_DETACH);
    return ok;
}

static int open_log(void) {
    if (mount_esp() != 0) return -1;
    if (mkdir(LOG_DIR, 0755) != 0 && errno != EEXIST) return -1;
    unlink(LOG_PREV);
    rename(LOG_CUR, LOG_PREV);
    int out = open(LOG_CUR, O_WRONLY | O_CREAT | O_TRUNC | O_SYNC | O_CLOEXEC, 0644);
    if (out < 0) return -1;
    dprintf(out, "gaokun3 pre-init kmsg capture (ESP detached before Android init)\n");
    dprintf(out, "kmsg_fd=%d console_fd=%d\n\ncmdline:\n", kmsg_fd, console_fd);
    copy_file("/proc/cmdline", out);
    dprintf(out, "\n\n===== kmsg =====\n");
    fsync(out);
    return out;
}

static void logger_loop(int out, int in) {
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

int main(int argc, char **argv) {
    (void)argc;
    console_fd = open("/dev/console", O_WRONLY | O_CLOEXEC);
    kmsg_fd = open("/dev/kmsg", O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (kmsg_fd >= 0) note("gk3log: wrapper entered, kmsg opened\n");

    int out = open_log();
    if (out < 0) {
        note("gk3log: ESP log unavailable, continuing Android boot\n");
    } else {
        note("gk3log: ESP log ready\n");
    }

    pid_t child = fork();
    if (child == 0) {
        setsid();
        if (out >= 0 && kmsg_fd >= 0) logger_loop(out, kmsg_fd);
        _exit(0);
    }
    if (child < 0) note("gk3log: fork failed: %s\n", strerror(errno));

    if (out >= 0) {
        note("gk3log: detaching ESP mount before Android init\n");
        fsync(out);
    }
    if (umount2(ESP_MNT, MNT_DETACH) == 0) {
        note("gk3log: ESP detached; log file descriptor retained\n");
    } else {
        note("gk3log: detach ESP failed: %s (continuing)\n", strerror(errno));
    }

    if (out >= 0) close(out);
    if (kmsg_fd >= 0) close(kmsg_fd);
    if (console_fd >= 0) close(console_fd);

    execv("/init.real", argv);
    return 127;
}