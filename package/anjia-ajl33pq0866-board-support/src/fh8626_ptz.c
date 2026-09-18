#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <linux/ioctl.h>
#include <sched.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define PWM_DEVICE "/dev/fh_pwm"
#define PINCTRL_FILE "/proc/driver/pinctrl"
#define LOCK_FILE "/var/run/fh8626-ptz.lock"
#define PWM_IOCTL_MAGIC 'p'
#define DISABLE_PWM _IOWR(PWM_IOCTL_MAGIC,1,uint32_t)
#define SET_PWM_DUTY_CYCLE _IOWR(PWM_IOCTL_MAGIC,2,uint32_t)
#define ENABLE_MUL_PWM _IOWR(PWM_IOCTL_MAGIC,6,uint32_t)
#define WAIT_PWM_FINISHALL _IOWR(PWM_IOCTL_MAGIC,12,uint32_t)

struct fh_pwm_config {
    uint32_t period_ns, duty_ns, pulses, stop, delay_ns;
    uint32_t phase_ns, percent, finish_once, finish_all;
};
struct fh_pwm_status { uint32_t done_cnt, total_cnt, busy, error; };
struct fh_pwm_chip_data {
    int32_t id;
    struct fh_pwm_config config;
    struct fh_pwm_status status;
};
struct axis {
    const char *name;
    int pwm[4], gpio[4], mux[4];
    uint32_t normal_ns;
    int invert;
};
typedef int (*ioctl_fn)(void *, unsigned long, void *);
struct backend { ioctl_fn call; void *opaque; };

static struct axis axes[2] = {
    {"pan",  {11,10,9,6}, {51,50,6,3}, {0,0,0,1}, 15000000U, 1},
    {"tilt", {5,4,3,7},   {2,1,0,7},   {1,2,2,1}, 25000000U, 0}
};
static int pwm_fd = -1, lock_fd = -1, skip_hardware_setup;
static volatile sig_atomic_t stop_requested;
static struct backend backend;

_Static_assert(sizeof(struct fh_pwm_chip_data) == 56, "FH PWM ABI size");

static int real_ioctl(void *opaque, unsigned long request, void *argument)
{
    (void)opaque;
    return ioctl(pwm_fd, request, argument);
}

static int pwm_call(unsigned long request, void *argument)
{
    return backend.call(backend.opaque, request, argument);
}

static int write_text(const char *path, const char *value)
{
    int fd = open(path, O_WRONLY | O_CLOEXEC);
    ssize_t written;
    size_t len = strlen(value);

    if (fd < 0)
        return -1;
    written = write(fd, value, len);
    if (close(fd) || written != (ssize_t)len) {
        errno = EIO;
        return -1;
    }
    return 0;
}

static int gpio_low_one(int gpio)
{
    char path[96], value[16];

    snprintf(path, sizeof(path), "/sys/class/gpio/GPIO%d", gpio);
    if (access(path, F_OK)) {
        snprintf(value, sizeof(value), "%d\n", gpio);
        if (write_text("/sys/class/gpio/export", value) && errno != EBUSY)
            return -1;
    }

    snprintf(path, sizeof(path), "/sys/class/gpio/GPIO%d/direction", gpio);
    if (write_text(path, "out\n"))
        return -1;
    snprintf(path, sizeof(path), "/sys/class/gpio/GPIO%d/value", gpio);
    return write_text(path, "0\n");
}

static int mux(const char *kind, int number, int index)
{
    char value[64];

    snprintf(value, sizeof(value), "mux,%s%d,%s%d,%d\n",
             kind, number, kind, number, index);
    return write_text(PINCTRL_FILE, value);
}

static int axis_gpio_low(const struct axis *axis)
{
    int i, rc = 0;

    if (skip_hardware_setup)
        return 0;
    for (i = 0; i < 4; i++)
        if (gpio_low_one(axis->gpio[i]))
            rc = -1;
    for (i = 0; i < 4; i++)
        if (mux("GPIO", axis->gpio[i], 0))
            rc = -1;
    return rc;
}

static int axis_pwm_mux(const struct axis *axis)
{
    int i;

    if (skip_hardware_setup)
        return 0;
    for (i = 0; i < 4; i++)
        if (mux("PWM", axis->pwm[i], axis->mux[i]))
            return -1;
    return 0;
}

static void axis_disable(const struct axis *axis)
{
    struct fh_pwm_chip_data data;
    int i;

    if (!backend.call)
        return;
    memset(&data, 0, sizeof(data));
    for (i = 0; i < 4; i++) {
        data.id = axis->pwm[i];
        (void)pwm_call(DISABLE_PWM, &data);
    }
    (void)axis_gpio_low(axis);
}

static void cleanup(void)
{
    if (pwm_fd >= 0) {
        axis_disable(&axes[0]);
        axis_disable(&axes[1]);
        close(pwm_fd);
    }
    pwm_fd = -1;
    if (lock_fd >= 0)
        close(lock_fd);
    lock_fd = -1;
}

static void on_signal(int sig)
{
    (void)sig;
    stop_requested = 1;
}

static int parse_int(const char *text, int *value)
{
    char *end;
    long parsed;

    errno = 0;
    parsed = strtol(text, &end, 10);
    if (errno || end == text || *end || parsed < INT32_MIN || parsed > INT32_MAX)
        return -1;
    *value = (int)parsed;
    return 0;
}

static int env_value(const char *key, char *value, size_t size)
{
    char command[96];
    FILE *pipe;
    int status;
    size_t len;

    snprintf(command, sizeof(command), "fw_printenv -n %s 2>/dev/null", key);
    pipe = popen(command, "r");
    if (!pipe)
        return -1;
    if (!fgets(value, (int)size, pipe)) {
        pclose(pipe);
        return -1;
    }
    status = pclose(pipe);
    if (status)
        return -1;

    len = strlen(value);
    while (len && (value[len - 1] == '\n' || value[len - 1] == '\r'))
        value[--len] = 0;
    return len ? 0 : -1;
}

static void apply_axis_inversion(struct axis *axis)
{
    int value;

    if (!axis->invert)
        return;
    value = axis->pwm[1];
    axis->pwm[1] = axis->pwm[3];
    axis->pwm[3] = value;
    value = axis->mux[1];
    axis->mux[1] = axis->mux[3];
    axis->mux[3] = value;
}

static void load_board_config(void)
{
    char value[128];
    unsigned low, high, normal;
    int parsed;

    if (!env_value("pan_period", value, sizeof(value)) &&
        sscanf(value, "%u,%u,%u", &low, &high, &normal) == 3 &&
        low > 70 && low <= 1000000 && high >= low && high <= 1000000 &&
        normal >= low && normal <= high)
        axes[0].normal_ns = normal * 1000U;

    if (!env_value("tilt_period", value, sizeof(value)) &&
        sscanf(value, "%u,%u,%u", &low, &high, &normal) == 3 &&
        low > 70 && low <= 1000000 && high >= low && high <= 1000000 &&
        normal >= low && normal <= high)
        axes[1].normal_ns = normal * 1000U;

    if (!env_value("pan_invert", value, sizeof(value)) ||
        !env_value("pwm_invert", value, sizeof(value))) {
        if (!parse_int(value, &parsed))
            axes[0].invert = !!parsed;
    }
    if (!env_value("tilt_invert", value, sizeof(value)) &&
        !parse_int(value, &parsed))
        axes[1].invert = !!parsed;

    apply_axis_inversion(&axes[0]);
    apply_axis_inversion(&axes[1]);
}

static uint32_t step_period(uint32_t timing, int step, int total)
{
    uint32_t base = timing - 70000U;

    if (step < 2 || step >= total - 2)
        return 4 * base;
    if (step < 4 || step >= total - 5)
        return 2 * base;
    return base;
}

static int configure_cycle(const struct axis *axis, int direction,
                           uint32_t period, int terminal)
{
    struct fh_pwm_chip_data data;
    uint32_t quarter = period / 4;
    uint32_t forward[4] = {0, quarter, 2 * quarter, 3 * quarter};
    uint32_t reverse[4] = {3 * quarter, 2 * quarter, quarter, 0};
    uint32_t *phase = direction > 0 ? forward : reverse;
    uint32_t duty = period / 2;
    int i;

    for (i = 0; i < 4; i++) {
        memset(&data, 0, sizeof(data));
        data.id = axis->pwm[i];
        data.config.period_ns = period;
        data.config.duty_ns = duty;
        data.config.pulses = 1;
        data.config.stop = !terminal && phase[i] + duty > period ? 3U : 0U;
        data.config.phase_ns = phase[i];
        data.config.finish_all = i == 0;
        if (pwm_call(SET_PWM_DUTY_CYCLE, &data))
            return -1;
    }
    return 0;
}

static int run_axis_steps_at(const struct axis *axis, int signed_steps,
                             uint32_t timing)
{
    uint32_t mask = 0, wait;
    int direction, total, step = 0, i;

    if (!signed_steps)
        return 0;
    if (signed_steps < -8192 || signed_steps > 8192) {
        errno = ERANGE;
        return -1;
    }

    direction = signed_steps > 0 ? 1 : -1;
    total = signed_steps > 0 ? signed_steps : -signed_steps;

    if (axis_gpio_low(axis) || axis_pwm_mux(axis))
        goto fail;

    for (i = 0; i < 4; i++)
        mask |= 1U << axis->pwm[i];
    wait = (uint32_t)axis->pwm[0];

    for (step = 0; step < total; step++) {
        uint32_t period = step_period(timing, step, total);

        if (stop_requested) {
            errno = EINTR;
            goto fail;
        }
        if (configure_cycle(axis, direction, period, step == total - 1) ||
            pwm_call(ENABLE_MUL_PWM, &mask) ||
            pwm_call(WAIT_PWM_FINISHALL, &wait))
            goto fail;
    }

    axis_disable(axis);
    return 0;

fail:
    fprintf(stderr, "%s failed after %d/%d cycles: %s\n",
            axis->name, step, total, strerror(errno));
    axis_disable(axis);
    return -1;
}

static int run_move(int pan_steps, int tilt_steps)
{
    if (run_axis_steps_at(&axes[0], pan_steps, axes[0].normal_ns))
        return -1;
    return run_axis_steps_at(&axes[1], tilt_steps, axes[1].normal_ns);
}

static int acquire(void)
{
    lock_fd = open(LOCK_FILE, O_RDWR | O_CREAT | O_CLOEXEC, 0644);
    if (lock_fd < 0 || flock(lock_fd, LOCK_EX | LOCK_NB)) {
        errno = EBUSY;
        fprintf(stderr, "PTZ owner is busy\n");
        return -1;
    }

    pwm_fd = open(PWM_DEVICE, O_RDWR | O_CLOEXEC);
    if (pwm_fd < 0)
        return -1;
    backend = (struct backend){real_ioctl, NULL};
    return 0;
}

static int busy(void)
{
    int fd = open(LOCK_FILE, O_RDWR | O_CREAT | O_CLOEXEC, 0644);
    int is_busy;

    if (fd < 0)
        return 0;
    is_busy = flock(fd, LOCK_EX | LOCK_NB) && errno == EWOULDBLOCK;
    close(fd);
    return is_busy;
}

#ifndef FH8626_PTZ_TEST
static void usage(const char *program)
{
    fprintf(stderr, "usage: %s status | move PAN_STEPS TILT_STEPS\n", program);
}

static void enable_motor_realtime(void)
{
    struct sched_param param;

    memset(&param, 0, sizeof(param));
    param.sched_priority = 20;
    if (sched_setscheduler(0, SCHED_FIFO, &param))
        fprintf(stderr, "warning: cannot enable PTZ real-time scheduling: %s\n",
                strerror(errno));
}

int main(int argc, char **argv)
{
    int pan, tilt, rc;

    load_board_config();

    if (argc == 2 && !strcmp(argv[1], "status")) {
        printf("busy=%d\n", busy());
        return 0;
    }

    if (argc != 4 || strcmp(argv[1], "move") ||
        parse_int(argv[2], &pan) || parse_int(argv[3], &tilt)) {
        usage(argv[0]);
        return 2;
    }

    enable_motor_realtime();
    atexit(cleanup);
    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);
    signal(SIGHUP, on_signal);

    if (acquire())
        return errno == EBUSY ? 2 : 1;

    rc = run_move(pan, tilt);
    return rc ? 1 : 0;
}
#endif
