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
#define LOCK "/tmp/fh8626_lens.lock"

static int gpio_write(int fd, unsigned gpio, int value)
{
    uint32_t pair[2] = {gpio, value ? 1u : 0u};
    uint32_t request = gpio;
    int rc = 0;

    if (ioctl(fd, GW_REQUEST, &request) < 0)
        return -errno;
    if (ioctl(fd, GW_SET_DIR, (uint32_t[2]){gpio, 1u}) < 0)
        rc = -errno;
    else if (ioctl(fd, GW_SET_OUT, pair) < 0)
        rc = -errno;
    if (ioctl(fd, GW_RELEASE, &request) < 0 && !rc)
        rc = -errno;
    return rc;
}

static int read_gpio(int fd, unsigned gpio, int *value)
{
    uint32_t data[4] = {gpio, 0, 0, 0};

    if (ioctl(fd, GW_GET_IN, data) < 0)
        return -errno;
    *value = data[1] ? 1 : 0;
    return 0;
}

static int current_target(int fd, const char **target)
{
    int gpio4, gpio14;

    if (read_gpio(fd, 4, &gpio4) || read_gpio(fd, 14, &gpio14))
        return -EIO;
    if (gpio4 == 1 && gpio14 == 0)
        *target = "wide";
    else if (gpio4 == 0 && gpio14 == 1)
        *target = "tele";
    else
        return -EPROTO;
    return 0;
}

static int set_target(int fd, const char *target)
{
    int rc;

    /*
     * This is only the physical selector. The media owner must coordinate
     * active VENC channels, mirror/flip and exposure state around the switch.
     */
    if (!strcmp(target, "wide")) {
        rc = gpio_write(fd, 4, 1);
        if (!rc)
            rc = gpio_write(fd, 14, 0);
    } else {
        rc = gpio_write(fd, 14, 1);
        if (!rc)
            rc = gpio_write(fd, 4, 0);
    }

    if (!rc)
        usleep(60000u);
    return rc;
}

int main(int argc, char **argv)
{
    int lockfd = -1, fd = -1, rc = 0;
    const char *target = NULL;

    lockfd = open(LOCK, O_RDWR | O_CREAT | O_CLOEXEC, 0600);
    if (lockfd < 0 || flock(lockfd, LOCK_EX) < 0)
        return 1;

    fd = open("/dev/gpiowave8", O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        rc = -errno;
        goto out;
    }

    if (argc == 2 && !strcmp(argv[1], "state")) {
        rc = current_target(fd, &target);
        if (!rc)
            puts(target);
        goto out;
    }

    if (argc != 3 || strcmp(argv[1], "set") ||
        (strcmp(argv[2], "wide") && strcmp(argv[2], "tele"))) {
        fprintf(stderr, "usage: %s state | set wide|tele\n", argv[0]);
        rc = -EINVAL;
        goto out;
    }

    rc = set_target(fd, argv[2]);

out:
    if (fd >= 0)
        close(fd);
    if (lockfd >= 0)
        close(lockfd);
    return rc ? 1 : 0;
}
