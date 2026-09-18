#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/file.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define GW_REQUEST 0xC0045808UL
#define GW_RELEASE 0xC0045809UL
#define GW_SET_DIR 0xC004580AUL
#define GW_SET_OUT 0xC004580BUL
#define GW_GET_IN  0xC004580CUL
#define STATE "/tmp/fh8626_lens.state"
#define LOCK  "/tmp/fh8626_lens.lock"

static int gpio_write(int fd, unsigned gpio, int value)
{
    uint32_t pair[2] = {gpio, value ? 1u : 0u};
    uint32_t request = gpio;
    int rc = 0;

    if (ioctl(fd, GW_REQUEST, &request) < 0) return -errno;
    if (ioctl(fd, GW_SET_DIR, (uint32_t[2]){gpio, 1u}) < 0)
        rc = -errno;
    else if (ioctl(fd, GW_SET_OUT, pair) < 0)
        rc = -errno;
    if (ioctl(fd, GW_RELEASE, &request) < 0 && !rc) rc = -errno;
    return rc;
}

static int read_gpio(int fd, unsigned gpio, int *value)
{
    uint32_t data[4] = {gpio, 0, 0, 0};
    if (ioctl(fd, GW_GET_IN, data) < 0) return -errno;
    *value = data[1] ? 1 : 0;
    return 0;
}

static int current_target(int fd, char *out, size_t size)
{
    int g4, g14;
    if (read_gpio(fd, 4, &g4) || read_gpio(fd, 14, &g14)) return -EIO;
    if (g4 == 1 && g14 == 0) snprintf(out, size, "wide");
    else if (g4 == 0 && g14 == 1) snprintf(out, size, "tele");
    else snprintf(out, size, "unknown");
    return strcmp(out, "unknown") ? 0 : -EPROTO;
}

int main(int argc, char **argv)
{
    int lockfd = -1, fd = -1, rc = 0;
    char state[16] = "unknown";

    lockfd = open(LOCK, O_RDWR | O_CREAT | O_CLOEXEC, 0600);
    if (lockfd < 0 || flock(lockfd, LOCK_EX) < 0) return 1;
    fd = open("/dev/gpiowave8", O_RDWR | O_CLOEXEC);
    if (fd < 0) { rc = -errno; goto out; }
    if (argc == 2 && !strcmp(argv[1], "state")) {
        rc = current_target(fd, state, sizeof(state));
        if (!rc) { puts(state); FILE *f = fopen(STATE, "w"); if (f) { fprintf(f, "%s\n", state); fclose(f); } }
        goto out;
    }
    if (argc != 3 || strcmp(argv[1], "set") ||
        (strcmp(argv[2], "wide") && strcmp(argv[2], "tele"))) { rc = -EINVAL; goto out; }
    if (!strcmp(argv[2], "wide")) {
        rc = gpio_write(fd, 4, 1);
        if (!rc) rc = gpio_write(fd, 14, 0);
    } else {
        rc = gpio_write(fd, 14, 1);
        if (!rc) rc = gpio_write(fd, 4, 0);
    }
    if (!rc) {
        usleep(600000u);
        rc = current_target(fd, state, sizeof(state));
        if (!rc) { FILE *f = fopen(STATE, "w"); if (f) { fprintf(f, "%s\n", state); fclose(f); } }
    }
out:
    if (fd >= 0) close(fd);
    if (lockfd >= 0) close(lockfd);
    return rc ? 1 : 0;
}
