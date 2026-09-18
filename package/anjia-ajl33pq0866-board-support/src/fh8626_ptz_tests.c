#define FH8626_PTZ_TEST 1
#include "fh8626_ptz.c"

#define MAX_EVENTS 4096

struct event {
    unsigned long request;
    int id;
    uint32_t value;
    struct fh_pwm_config config;
};
struct recorder {
    struct event events[MAX_EVENTS];
    int count;
};
static int failures;

#define CHECK(x) do { \
    if (!(x)) { \
        fprintf(stderr, "FAIL %s:%d: %s\n", __func__, __LINE__, #x); \
        failures++; \
        return; \
    } \
} while (0)

static int record_ioctl(void *opaque, unsigned long request, void *argument)
{
    struct recorder *recorder = opaque;
    struct event *event;

    if (recorder->count >= MAX_EVENTS) {
        errno = ENOSPC;
        return -1;
    }

    event = &recorder->events[recorder->count++];
    memset(event, 0, sizeof(*event));
    event->request = request;

    if (request == SET_PWM_DUTY_CYCLE || request == DISABLE_PWM) {
        struct fh_pwm_chip_data *data = argument;
        event->id = data->id;
        event->config = data->config;
    } else {
        event->value = *(uint32_t *)argument;
    }
    return 0;
}

static void reset(struct recorder *recorder)
{
    memset(recorder, 0, sizeof(*recorder));
    backend = (struct backend){record_ioctl, recorder};
    skip_hardware_setup = 1;
    stop_requested = 0;
}

static int motion_events(const struct recorder *recorder)
{
    int i, count = 0;

    for (i = 0; i < recorder->count; i++)
        if (recorder->events[i].request != DISABLE_PWM)
            count++;
    return count;
}

static void test_cycle_contract(void)
{
    struct recorder recorder;
    uint32_t base = 1000000U - 70000U;
    uint32_t expected[12] = {
        4*base,4*base,2*base,2*base,base,base,
        base,2*base,2*base,2*base,4*base,4*base
    };
    int cycle, channel;

    reset(&recorder);
    CHECK(run_axis_steps_at(&axes[0], 12, 1000000U) == 0);
    CHECK(motion_events(&recorder) == 12 * 6);

    for (cycle = 0; cycle < 12; cycle++) {
        int offset = cycle * 6;
        for (channel = 0; channel < 4; channel++) {
            struct event *event = &recorder.events[offset + channel];
            uint32_t quarter = expected[cycle] / 4;

            CHECK(event->request == SET_PWM_DUTY_CYCLE);
            CHECK(event->id == axes[0].pwm[channel]);
            CHECK(event->config.pulses == 1);
            CHECK(event->config.finish_all == (uint32_t)(channel == 0));
            CHECK(event->config.period_ns == expected[cycle]);
            CHECK(event->config.duty_ns == expected[cycle] / 2);
            CHECK(event->config.phase_ns == (uint32_t)channel * quarter);
            CHECK(event->config.stop ==
                  (uint32_t)(cycle < 11 && channel == 3 ? 3 : 0));
        }
        CHECK(recorder.events[offset + 4].request == ENABLE_MUL_PWM);
        CHECK(recorder.events[offset + 4].value ==
              ((1U << 11) | (1U << 10) | (1U << 9) | (1U << 6)));
        CHECK(recorder.events[offset + 5].request == WAIT_PWM_FINISHALL);
        CHECK(recorder.events[offset + 5].value == 11);
    }
}

static void test_negative_and_channel_invert(void)
{
    struct recorder recorder;
    struct axis axis = axes[0];
    uint32_t period, quarter;
    int channel, ids[4] = {11,6,9,10};

    reset(&recorder);
    CHECK(run_axis_steps_at(&axis, -1, 1000000U) == 0);
    period = 4 * (1000000U - 70000U);
    quarter = period / 4;
    for (channel = 0; channel < 4; channel++)
        CHECK(recorder.events[channel].config.phase_ns ==
              (uint32_t)(3 - channel) * quarter);

    reset(&recorder);
    apply_axis_inversion(&axis);
    CHECK(run_axis_steps_at(&axis, 1, 1000000U) == 0);
    for (channel = 0; channel < 4; channel++) {
        CHECK(recorder.events[channel].id == ids[channel]);
        CHECK(recorder.events[channel].config.phase_ns ==
              (uint32_t)channel * quarter);
    }
    CHECK(axis.mux[1] == 1 && axis.mux[3] == 0);
}

static void test_relative_move_is_serial_and_stateless(void)
{
    struct recorder recorder;
    int i, first_pan = -1, first_tilt = -1;
    int enables = 0, waits = 0;

    reset(&recorder);
    CHECK(run_move(2, 1, 5000000U) == 0);

    for (i = 0; i < recorder.count; i++) {
        struct event *event = &recorder.events[i];

        if (event->request == SET_PWM_DUTY_CYCLE) {
            if (first_pan < 0 && event->id == axes[0].pwm[0])
                first_pan = i;
            if (first_tilt < 0 && event->id == axes[1].pwm[0])
                first_tilt = i;
        } else if (event->request == ENABLE_MUL_PWM) {
            enables++;
        } else if (event->request == WAIT_PWM_FINISHALL) {
            waits++;
        }
    }

    CHECK(first_pan >= 0);
    CHECK(first_tilt > first_pan);
    CHECK(enables == 3);
    CHECK(waits == 3);
    CHECK(recorder.events[first_pan].config.period_ns ==
          4 * (5000000U - 70000U));
    CHECK(recorder.events[first_tilt].config.period_ns ==
          4 * (5000000U - 70000U));

    reset(&recorder);
    CHECK(run_move(0, 0, 0) == 0);
    CHECK(motion_events(&recorder) == 0);
}

int main(void)
{
    test_cycle_contract();
    test_negative_and_channel_invert();
    test_relative_move_is_serial_and_stateless();

    if (failures) {
        fprintf(stderr, "%d test(s) failed\n", failures);
        return 1;
    }
    puts("fh8626 PTZ tests: PASS");
    return 0;
}
