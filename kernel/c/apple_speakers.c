/* SPDX-License-Identifier: GPL-2.0-only
 *
 * Built-in speakers of the base M1 MacBook Air (J313).
 *
 * Playback runs from a ring buffer through ADMAC into an MCA frontend, out of
 * two I2S ports to a pair of TI TAS5770L amplifiers (TAS2770 family), which
 * are configured over the P.A. Semi I2C controllers. The amplifiers send the
 * voltage across and current through each voice coil back on the same bus;
 * a second MCA frontend captures that, and a thermal model of each speaker
 * turns it into a gain limit. This is the job Asahi Linux splits between the
 * kernel and speakersafetyd; here it all lives in the driver, so the model
 * runs whenever the speakers can make sound.
 *
 * Register sequences follow Asahi Linux: sound/soc/apple/mca.c,
 * drivers/dma/apple-admac.c, drivers/clk/clk-apple-nco.c (Martin Povišer),
 * sound/soc/codecs/tas2770.c, drivers/i2c/busses/i2c-pasemi-core.c,
 * sound/soc/apple/macaudio.c. The protection model and the J313 parameters
 * come from speakersafetyd (conf/apple/j313.conf), The Asahi Linux
 * Contributors, MIT.
 *
 * Safety policy, stricter than running without the daemon on Linux:
 *  - The amplifier gain is fixed at the value macOS uses on this machine.
 *  - Until the sense data has been seen to track the output, and whenever it
 *    stops arriving for 250 ms, the output is held 20 dB down.
 *  - Gaps in the sense data never count as cooling time while playing.
 *  - A modelled temperature past the limit plus headroom, or sense data
 *    that implies negative power, shuts both amplifiers down until reboot.
 *
 * The kernel is built with general registers only: everything is fixed
 * point. Temperatures and power are Q32 (units of 2^-32 degrees and watts).
 */
#include "apple_speakers.h"

#if defined(__AARCH64__) || defined(VINIX_APPLE_SPEAKERS_TEST)

/* ---- geometry ---- */

#define SPK_COUNT          2u
#define PERIOD_FRAMES      512u
#define TX_FRAME_BYTES     4u     /* S16_LE stereo */
#define TX_PERIOD_BYTES    (PERIOD_FRAMES * TX_FRAME_BYTES)
#define SENSE_CHANNELS     4u     /* I left, V left, I right, V right */
#define SENSE_FRAME_BYTES  (SENSE_CHANNELS * 2u)
#define SENSE_PERIOD_BYTES (PERIOD_FRAMES * SENSE_FRAME_BYTES)
#define HW_SLOTS           4u     /* ADMAC descriptor ring depth */
#define TX_LOW_WATER       2u     /* below this many queued, pad with silence */
#define START_PERIODS      2u
#define START_DELAY_US     20000u /* start a short write that never fills two periods */
#define IDLE_STOP_US       3000000u
#define ENERGY_HISTORY     32u
#define WINDOW_CHUNKS      8u
#define MAX_EVENTS         16u

/* ---- P.A. Semi I2C ---- */

#define I2C_MTXFIFO  0x00
#define I2C_MRXFIFO  0x04
#define I2C_SMSTA    0x14
#define I2C_IMASK    0x18
#define I2C_CTL      0x1c
#define I2C_REV      0x28
#define MTX_READ     (1u << 10)
#define MTX_STOP     (1u << 9)
#define MTX_START    (1u << 8)
#define MRX_EMPTY    (1u << 8)
#define SM_XIP       (1u << 28)
#define SM_XEN       (1u << 27)
#define SM_JMD       (1u << 25)
#define SM_JAM       (1u << 24)
#define SM_MTO       (1u << 23)
#define SM_MTA       (1u << 22)
#define SM_MTN       (1u << 21)
#define SM_MRNE      (1u << 19)
#define SM_MTE       (1u << 16)
#define SM_TOM       (1u << 6)
#define CTL_EN       (1u << 11)
#define CTL_MRR      (1u << 10)
#define CTL_MTR      (1u << 9)
#define CTL_UJM      (1u << 8)
#define I2C_BUS_HZ   100000u
#define I2C_TIMEOUT_US 100000u

/* ---- TAS2770 / TAS5770L ---- */

#define TAS_PAGE       0x00
#define TAS_SW_RST     0x01
#define TAS_PWR_CTRL   0x02
#define TAS_PLAY_CFG0  0x03   /* AMP_LEVEL[4:0]: 11 dBV + 0.5 dB/step */
#define TAS_PLAY_CFG2  0x05   /* DVC: 0.5 dB of attenuation per step */
#define TAS_TDM0       0x0a
#define TAS_TDM1       0x0b
#define TAS_TDM2       0x0c
#define TAS_TDM3       0x0d
#define TAS_TDM5       0x0f
#define TAS_TDM6       0x10
#define TAS_REV        0x7d
#define PWR_ACTIVE     0x00
#define PWR_MUTE       0x01
#define PWR_SHUTDOWN   0x02
#define PWR_MODE_MASK  0x03
/* PWR_CTRL bit 2 powers VSENSE down and bit 3 ISENSE; both stay clear. */
#define PWR_SENSE_MASK 0x0c

/* macOS runs the J313 amplifiers at level 10, 16 dBV (macaudio_j313_cfg). */
#define AMP_LEVEL      10u
#define AMP_GAIN_MDB   (11000 + 500 * (int32_t)AMP_LEVEL)
#define ATT_SAFE       40     /* -20 dB, Asahi's general safe level */
#define ATT_MUTE       201    /* -100.5 dB, the bottom of the range */
#define ATT_RAMP_US    5000u  /* releasing attenuation: 0.5 dB per 5 ms */
#define SENSE_STALE_US 250000u

/* ---- NCO ---- */

#define NCO_STRIDE     0x4000
#define NCO_CTRL       0x00
#define NCO_DIV        0x04
#define NCO_INC1       0x08
#define NCO_INC2       0x0c
#define NCO_ACCINIT    0x10
#define NCO_ENABLE     (1u << 31)
#define LFSR_POLY      0xa01u
#define LFSR_INIT      0x7ffu
#define LFSR_SIZE      2048u
#define COARSE_OFFSET  2u

/* ---- MCA ---- */

#define MCA_STRIDE          0x4000
#define MCA_STATUS          0x000
#define MCA_MCLK_EN         (1u << 0)
#define MCA_MCLK_CONF       0x004
#define MCA_SYNCGEN_STATUS  0x100
#define MCA_SYNCGEN_EN      (1u << 0)
#define MCA_SYNCGEN_SEL     0x104
#define MCA_SYNCGEN_HI      0x108
#define MCA_SYNCGEN_LO      0x10c
#define MCA_PORT_ENABLES    0x600
#define PORT_CLOCKS         (3u << 1)
#define PORT_TX_DATA        (1u << 3)
#define MCA_PORT_CLOCK_SEL  0x604
#define MCA_PORT_DATA_SEL   0x608
#define MCA_TXA             0x300
#define MCA_RXB             0x400
#define SERDES_STATUS       0x00
#define SERDES_EN           (1u << 0)
#define SERDES_RST          (1u << 1)
#define TX_CONF             0x04
#define TX_BITSTART         0x08
#define TX_SLOTMASK         0x0c
#define RX_PORT             0x04
#define RX_CONF             0x08
#define RX_BITSTART         0x0c
#define RX_SLOTMASK         0x10
#define CONF_NCHANS         0xfu
#define CONF_WIDTH_MASK     (0x1fu << 4)
#define CONF_WIDTH_16       0x40u
#define CONF_WIDTH_32       0x100u
#define CONF_BCLK_POL       0x400u
#define CONF_UNK1           (1u << 12)
#define CONF_UNK2           (1u << 13)
#define CONF_UNK3           (1u << 14)
#define CONF_NO_FEEDBACK    (1u << 15)
#define CONF_SYNC_SEL       (7u << 16)
#define ADAPTER_A(cl)       (0x8000u * (cl))
#define ADAPTER_B(cl)       (0x8000u * (cl) + 0x4000u)
#define TX_SLOTS            8u     /* BCLK = 256 fs: 8 slots of 32 bits */
#define SENSE_SLOTS         16u    /* the same frame as 16 slots of 16 bits */
#define BCLK_RATIO          256u

/* ---- ADMAC ---- */

#define ADMAC_TX_START      0x0000
#define ADMAC_TX_STOP       0x0004
#define ADMAC_RX_START      0x0008
#define ADMAC_RX_STOP       0x000c
#define ADMAC_TX_SRAM_SIZE  0x0094
#define ADMAC_RX_SRAM_SIZE  0x0098
#define CHAN_BASE(ch)       (0x8000u + (ch) * 0x200u)
#define CHAN_CTL            0x00
#define CHAN_RST_RINGS      (1u << 0)
#define CHAN_INTSTATUS(i)   (0x10u + (i) * 4u)
#define CHAN_INTMASK(i)     (0x20u + (i) * 4u)
#define CHAN_BUS_WIDTH      0x40
#define CHAN_CARVEOUT       0x50
#define CHAN_FIFOCTL        0x54
#define CHAN_RESIDUE        0x64
#define CHAN_DESC_RING      0x70
#define CHAN_REPORT_RING    0x74
#define DESC_WRITE(ch)      (0x10000u + ((ch) / 2u) * 4u + ((ch) & 1u) * 0x4000u)
#define REPORT_READ(ch)     (0x10100u + ((ch) / 2u) * 4u + ((ch) & 1u) * 0x4000u)
#define RING_EMPTY          (1u << 8)
#define RING_FULL           (1u << 9)
#define RING_ERR            (1u << 10)
#define STATUS_DESC_DONE    (1u << 0)
#define STATUS_ERR          (1u << 6)
#define DESC_NOTIFY         (1u << 16)
#define SRAM_BLOCK          2048u
#define BUS_16BIT           0x01u
#define BUS_FRAME_2         0x10u
#define BUS_FRAME_4         0x20u
#define ADMAC_IRQ_INDEX     1u     /* the one output wired on t8103 */

/* ---- Apple GPIO ---- */

#define GPIO_DATA           (1u << 0)
#define GPIO_MODE_MASK      (7u << 1)
#define GPIO_MODE_OUT       (1u << 1)
#define GPIO_PERIPH_MASK    (3u << 5)

/* ---- the protection model (speakersafetyd, conf/apple/j313.conf) ---- */

struct speaker_params {
    int32_t tr_coil_m;      /* thermal resistance, milli-degrees per watt */
    int32_t tr_magnet_m;
    int32_t tau_coil_ms;    /* time constants */
    int32_t tau_magnet_ms;
    int32_t t_limit_m;      /* milli-degrees */
    int32_t t_headroom_m;
    int32_t z_nominal_mohm;
    int32_t is_scale_m;     /* sense full scale: milliamps, millivolts */
    int32_t vs_scale_m;
    uint8_t is_chan;
    uint8_t vs_chan;
};

static const struct speaker_params j313_speakers[SPK_COUNT] = {
    { 29000, 36000, 2400, 80000, 120000, 15000, 4900, 3750, 14000, 0, 1 },
    { 29000, 36000, 2400, 80000, 120000, 15000, 4900, 3750, 14000, 2, 3 },
};

#define T_AMBIENT_M    50000
#define T_HYSTERESIS_M 5000
#define T_WINDOW_M     20000

#define Q32(x)         ((int64_t)(x) << 32)
#define MILLI_TO_Q32(m) (((int64_t)(m) << 32) / 1000)

struct speaker_model {
    int64_t coil;           /* Q32 degrees */
    int64_t magnet;
    int64_t coil_hyst;
    int64_t magnet_hyst;
    int32_t gain_mdb;
};

/* ---- events for the V layer to print ---- */

enum {
    SPK_EV_NONE = 0,
    SPK_EV_AMP,             /* a = amp, b = revision */
    SPK_EV_VERIFIED,        /* sense data tracks the output: limit lifted */
    SPK_EV_STALE,           /* a = ms since the last sense data */
    SPK_EV_DEAD,            /* a = speaker: output but no measured voltage */
    SPK_EV_GAIN,            /* a = model gain mdB */
    SPK_EV_FAULT_TEMP,      /* a = speaker, b = milli-degrees */
    SPK_EV_FAULT_POWER,     /* a = speaker, b = milliwatts */
    SPK_EV_FAULT_I2C,       /* a = amp, b = error */
    SPK_EV_DMA_ERROR,       /* a = channel */
    SPK_EV_SERDES,          /* a = cluster: reset bit stuck */
    SPK_EV_POWER,           /* a = cluster, b = on: domain did not switch */
};

struct speaker_event {
    int32_t code;
    int32_t a;
    int32_t b;
};

/* ---- driver state ---- */

struct spk_io {
    uint32_t (*read32)(void *cookie, uint64_t address);
    void (*write32)(void *cookie, uint64_t address, uint32_t value);
    uint64_t (*now_us)(void *cookie);
    void (*delay_us)(void *cookie, uint32_t us);
    void (*clean)(void *cookie, uint64_t address, uint32_t length);
    void (*invalidate)(void *cookie, uint64_t address, uint32_t length);
    int (*power)(void *cookie, uint32_t cluster, int on);
    void *cookie;
};

enum { ST_OFF = 0, ST_IDLE, ST_PREPARED, ST_RUNNING, ST_FAULT };

struct speakers {
    struct spk_io io;
    struct vinix_apple_speakers_config cfg;
    int state;
    int clocks_on;          /* start_clocks ran; hardware_stop undoes it */
    uint32_t powered;       /* MCA clusters whose power domains are on */
    uint32_t rate;
    uint32_t i2c_div;
    uint32_t i2c_rev[SPK_COUNT];
    uint32_t amp_rev[SPK_COUNT];

    /* playback ring, byte positions since the stream was configured */
    uint32_t tx_ring;
    uint64_t written;
    uint64_t queued;
    uint64_t played;
    uint32_t reserved;
    uint64_t scaled_to;     /* volume applied up to here */
    uint64_t measured_to;   /* output energy accounted up to here */
    int draining;
    uint64_t drain_target;
    uint32_t volume;
    uint64_t first_write_us;
    uint64_t silence_since_us;
    uint64_t period_energy[ENERGY_HISTORY][SPK_COUNT];
    uint64_t period_tag[ENERGY_HISTORY];

    /* sense ring, in periods */
    uint32_t sense_periods;
    uint64_t sense_queued;
    uint64_t sense_done;
    uint64_t sense_origin;  /* playback frame at which sense capture began */

    /* protection */
    struct speaker_model model[SPK_COUNT];
    int32_t min_gain_mdb;
    int64_t alpha_coil;     /* Q48, per sample */
    int64_t alpha_magnet;
    int64_t power_factor;   /* sense product to Q32 watts, times 10^6 */
    uint64_t expect_q32;    /* output power to sense-LSB power, 0 dB */
    uint64_t last_model_us;
    uint64_t last_sense_us;
    uint64_t window_expected[WINDOW_CHUNKS][SPK_COUNT];
    uint64_t window_measured[WINDOW_CHUNKS][SPK_COUNT];
    int live[SPK_COUNT];
    int dead[SPK_COUNT];
    int verified;
    int stale_reported;
    int32_t applied_att;
    int32_t reported_gain;
    uint64_t last_ramp_us;
    uint32_t i2c_failures;

    uint64_t underruns;
    uint64_t sense_chunks;
    uint64_t dma_errors;

    struct speaker_event events[MAX_EVENTS];
    uint32_t event_head;
    uint32_t event_count;
};

/* ---- small helpers ---- */

static uint32_t rd(struct speakers *s, uint64_t address)
{
    return s->io.read32(s->io.cookie, address);
}

static void wr(struct speakers *s, uint64_t address, uint32_t value)
{
    s->io.write32(s->io.cookie, address, value);
}

static void modify(struct speakers *s, uint64_t address, uint32_t mask, uint32_t value)
{
    wr(s, address, (rd(s, address) & ~mask) | (value & mask));
}

static uint64_t now_us(struct speakers *s)
{
    return s->io.now_us(s->io.cookie);
}

static void delay_us(struct speakers *s, uint32_t us)
{
    s->io.delay_us(s->io.cookie, us);
}

static void post(struct speakers *s, int32_t code, int32_t a, int32_t b)
{
    uint32_t slot;
    if (s->event_count == MAX_EVENTS) {
        /* Keep the newest: drop the oldest. */
        s->event_head = (s->event_head + 1) % MAX_EVENTS;
        s->event_count--;
    }
    slot = (s->event_head + s->event_count) % MAX_EVENTS;
    s->events[slot].code = code;
    s->events[slot].a = a;
    s->events[slot].b = b;
    s->event_count++;
}

static int take_event(struct speakers *s, struct speaker_event *out)
{
    if (!s->event_count)
        return 0;
    *out = s->events[s->event_head];
    s->event_head = (s->event_head + 1) % MAX_EVENTS;
    s->event_count--;
    return 1;
}

static int64_t mul_q48(int64_t a, int64_t b)
{
    __int128 p = (__int128)a * b;
    return (int64_t)((p + ((__int128)1 << 47)) >> 48);
}

static uint64_t mul_q32u(uint64_t a, uint64_t b)
{
    unsigned __int128 p = (unsigned __int128)a * b;
    return (uint64_t)((p + (1u << 31)) >> 32);
}

/* ---- fixed-point logarithms ---- */

static const uint64_t pow2_frac_q32[16] = {
    6074001000ull, 5107605667ull, 4683695048ull, 4485121744ull,
    4389014833ull, 4341736423ull, 4318288544ull, 4306612134ull,
    4300785774ull, 4297875550ull, 4296421177ull, 4295694175ull,
    4295330720ull, 4295149004ull, 4295058149ull, 4295012722ull,
};

/* log2(x) in Q16, x > 0. */
static int64_t log2_q16(uint64_t x)
{
    int64_t n = 63;
    uint64_t y;
    int64_t result;
    int bit;
    while (!(x & (1ull << 63))) {
        x <<= 1;
        n--;
    }
    /* x now holds the mantissa in Q63 of [1, 2). Keep 32 bits of it. */
    y = x >> 31;                /* Q32 */
    result = n << 16;
    for (bit = 15; bit >= 0; bit--) {
        y = (uint64_t)(((unsigned __int128)y * y) >> 32);
        if (y >= (2ull << 32)) {
            y >>= 1;
            result |= (int64_t)1 << bit;
        }
    }
    return result;
}

/* 10^(mdb/10000) in Q32: power ratio of a level in milli-decibels. */
static uint64_t db_to_power_q32(int32_t mdb)
{
    /* 10^(x/10) = 2^(x * log2(10) / 10); exponent in Q16. */
    int64_t e = ((int64_t)mdb * 3321928 * 65536) / 10000000000ll;
    int64_t whole = e >> 16;    /* floor, also for negative e */
    uint32_t frac = (uint32_t)(e & 0xffff);
    uint64_t value = 1ull << 32;
    int bit;
    for (bit = 0; bit < 16; bit++)
        if (frac & (0x8000u >> bit))
            value = mul_q32u(value, pow2_frac_q32[bit]);
    if (whole >= 0) {
        if (whole > 30)
            return ~0ull;
        return value << whole;
    }
    if (whole < -63)
        return 0;
    return value >> -whole;
}

/* ---- I2C ---- */

static uint64_t i2c_base(struct speakers *s, int amp)
{
    return s->cfg.i2c[amp];
}

static void i2c_reset(struct speakers *s, int amp)
{
    uint32_t value = CTL_MTR | CTL_MRR | CTL_UJM | (s->i2c_div & 0xff);
    if (s->i2c_rev[amp] >= 6)
        value |= CTL_EN;
    wr(s, i2c_base(s, amp) + I2C_CTL, value);
}

static int i2c_clear(struct speakers *s, int amp)
{
    uint64_t base = i2c_base(s, amp);
    uint64_t start = now_us(s);
    uint32_t status;
    for (;;) {
        status = rd(s, base + I2C_SMSTA);
        if (!(status & (SM_XIP | SM_JAM)))
            break;
        if (now_us(s) - start > I2C_TIMEOUT_US)
            return -1;
        delay_us(s, 50);
    }
    if ((status & (SM_MRNE | SM_JMD | SM_MTO | SM_TOM | SM_MTN | SM_MTA)) ||
        !(status & SM_MTE))
        i2c_reset(s, amp);
    wr(s, base + I2C_SMSTA, status);
    return 0;
}

static int i2c_wait(struct speakers *s, int amp)
{
    uint64_t base = i2c_base(s, amp);
    uint64_t start = now_us(s);
    uint32_t status;
    for (;;) {
        status = rd(s, base + I2C_SMSTA);
        if (status & SM_XEN)
            break;
        if (now_us(s) - start > I2C_TIMEOUT_US)
            return -2;
        delay_us(s, 10);
    }
    if (status & SM_TOM)
        return -3;
    if (status & SM_MTO)
        return -4;
    if (status & SM_XIP)
        return -5;
    if (status & SM_MTA)
        return -6;
    if (status & SM_MTN)
        return -7;
    wr(s, base + I2C_SMSTA, SM_XEN);
    return 0;
}

static int i2c_write(struct speakers *s, int amp, uint8_t reg, uint8_t value)
{
    uint64_t base = i2c_base(s, amp);
    uint32_t address = s->cfg.amp_address[amp];
    int error = i2c_clear(s, amp);
    if (error)
        return error;
    wr(s, base + I2C_MTXFIFO, MTX_START | (address << 1));
    wr(s, base + I2C_MTXFIFO, reg);
    wr(s, base + I2C_MTXFIFO, value | MTX_STOP);
    error = i2c_wait(s, amp);
    if (error)
        i2c_reset(s, amp);
    return error;
}

/* Register address write without a stop, then a repeated-start read of one
 * byte: the two-message transfer regmap-i2c issues. */
static int i2c_read(struct speakers *s, int amp, uint8_t reg, uint8_t *value)
{
    uint64_t base = i2c_base(s, amp);
    uint32_t address = s->cfg.amp_address[amp];
    uint32_t data;
    int error = i2c_clear(s, amp);
    if (error)
        return error;
    wr(s, base + I2C_MTXFIFO, MTX_START | (address << 1));
    wr(s, base + I2C_MTXFIFO, reg);
    wr(s, base + I2C_MTXFIFO, MTX_START | (address << 1) | 1);
    wr(s, base + I2C_MTXFIFO, 1 | MTX_READ | MTX_STOP);
    error = i2c_wait(s, amp);
    if (error) {
        i2c_reset(s, amp);
        return error;
    }
    data = rd(s, base + I2C_MRXFIFO);
    if (data & MRX_EMPTY) {
        i2c_reset(s, amp);
        return -8;
    }
    *value = (uint8_t)data;
    return 0;
}

static int tas_update(struct speakers *s, int amp, uint8_t reg, uint8_t mask, uint8_t value)
{
    uint8_t current;
    int error = i2c_read(s, amp, reg, &current);
    if (error)
        return error;
    return i2c_write(s, amp, reg, (uint8_t)((current & ~mask) | (value & mask)));
}

static int tas_expect(struct speakers *s, int amp, uint8_t reg, uint8_t mask, uint8_t value)
{
    uint8_t current;
    int error = i2c_read(s, amp, reg, &current);
    if (error)
        return error;
    return (current & mask) == (value & mask) ? 0 : -9;
}

static int tas_power(struct speakers *s, int amp, uint8_t mode)
{
    return tas_update(s, amp, TAS_PWR_CTRL, PWR_MODE_MASK | PWR_SENSE_MASK, mode);
}

static int tas_init(struct speakers *s, int amp)
{
    uint8_t slot = (uint8_t)amp;   /* left plays slot 0, right slot 1 */
    uint8_t rev;
    int error;
    if ((error = i2c_write(s, amp, TAS_PAGE, 0)))
        return error;
    if ((error = i2c_write(s, amp, TAS_SW_RST, 1)))
        return error;
    delay_us(s, 2000);
    if ((error = i2c_write(s, amp, TAS_PAGE, 0)))
        return error;
    if ((error = i2c_read(s, amp, TAS_REV, &rev)))
        return error;
    s->amp_rev[amp] = rev;
    /* Sense can only be powered through shutdown: power it with the
     * amplifier off, and leave it there until a stream starts. */
    if ((error = tas_power(s, amp, PWR_SHUTDOWN)))
        return error;
    if ((error = i2c_write(s, amp, TAS_PLAY_CFG2, ATT_MUTE)))
        return error;
    /* I2S with both clocks inverted: data on the falling edge, one bit of
     * offset, frame sync starting a frame on its rising edge. */
    if ((error = tas_update(s, amp, TAS_TDM1, 0x3f, 0x03)))
        return error;
    /* ASI1 plays the left slot; 16-bit words in 32-bit slots. */
    if ((error = tas_update(s, amp, TAS_TDM2, 0x3f, 0x12)))
        return error;
    if ((error = i2c_write(s, amp, TAS_TDM3, (uint8_t)(slot << 4 | slot))))
        return error;
    /* TDM4, the bus keeper for unused sense slots, stays at its reset value.
     * The J313 device tree asks for "zero", but macaudio applies idle modes
     * only to backends with several amplifiers, and each J313 backend has
     * one: the default is what sense capture has always run with. */
    if ((error = tas_update(s, amp, TAS_TDM5, 0x7f, (uint8_t)(0x40 | s->cfg.vmon_slot[amp]))))
        return error;
    if ((error = tas_update(s, amp, TAS_TDM6, 0x7f, (uint8_t)(0x40 | s->cfg.imon_slot[amp]))))
        return error;
    if ((error = tas_update(s, amp, TAS_PLAY_CFG0, 0x1f, AMP_LEVEL)))
        return error;
    /* The model's power limit depends on the gain: read it back. */
    if ((error = tas_expect(s, amp, TAS_PLAY_CFG0, 0x1f, AMP_LEVEL)))
        return error;
    if ((error = tas_expect(s, amp, TAS_PLAY_CFG2, 0xff, ATT_MUTE)))
        return error;
    return tas_expect(s, amp, TAS_PWR_CTRL, 0x0f, PWR_SHUTDOWN);
}

static int tas_set_rate(struct speakers *s, int amp)
{
    /* FPOL clear; 44.1 kHz family in bit 5; the 44.1/48 kHz ramp rate. */
    uint8_t value = (uint8_t)(0x06 | (s->rate == 44100 ? 0x20 : 0));
    return tas_update(s, amp, TAS_TDM0, 0x2f, value);
}

/* ---- GPIO ---- */

static void sdz_set(struct speakers *s, int enabled)
{
    modify(s, s->cfg.shutdown_gpio, GPIO_PERIPH_MASK | GPIO_MODE_MASK | GPIO_DATA,
        GPIO_MODE_OUT | (enabled ? GPIO_DATA : 0));
}

/* ---- NCO ---- */

static uint32_t lfsr_step(uint32_t state)
{
    return (state & 1) ? (state >> 1) ^ (LFSR_POLY >> 1) : state >> 1;
}

/* The coarse divisor is counted in a Galois LFSR: the register takes the
 * LFSR state that many steps before the end of its period. */
static uint32_t nco_div_register(uint32_t div)
{
    uint32_t index = div / 4 - COARSE_OFFSET;
    uint32_t state = 0;
    uint32_t i;
    if (index) {
        state = LFSR_INIT;
        for (i = 0; i < LFSR_SIZE - index; i++)
            state = lfsr_step(state);
    }
    return (state << 2) | (div % 4);
}

static int nco_set_rate(struct speakers *s, uint32_t channel, uint32_t rate)
{
    uint64_t base = s->cfg.nco + (uint64_t)channel * NCO_STRIDE;
    uint64_t twice = 2ull * s->cfg.nco_ref_hz;
    uint32_t div, inc1, inc2, ctrl;
    if (!rate)
        return -1;
    div = (uint32_t)(twice / rate);
    if (div / 4 < COARSE_OFFSET || div / 4 >= COARSE_OFFSET + LFSR_SIZE)
        return -1;
    inc1 = (uint32_t)(twice - (uint64_t)div * rate);
    inc2 = inc1 - rate;
    ctrl = rd(s, base + NCO_CTRL);
    wr(s, base + NCO_CTRL, ctrl & ~NCO_ENABLE);
    wr(s, base + NCO_DIV, nco_div_register(div));
    wr(s, base + NCO_INC1, inc1);
    wr(s, base + NCO_INC2, inc2);
    wr(s, base + NCO_ACCINIT, 1u << 31);
    if (ctrl & NCO_ENABLE)
        wr(s, base + NCO_CTRL, ctrl | NCO_ENABLE);
    return 0;
}

static void nco_enable(struct speakers *s, uint32_t channel, int enable)
{
    uint64_t base = s->cfg.nco + (uint64_t)channel * NCO_STRIDE;
    modify(s, base + NCO_CTRL, NCO_ENABLE, enable ? NCO_ENABLE : 0);
}

/* ---- MCA ---- */

static uint64_t cluster(struct speakers *s, uint32_t n)
{
    return s->cfg.mca_clusters + (uint64_t)n * MCA_STRIDE;
}

/* The cluster power domains are externally clocked: they change state only
 * while their clock runs. So a domain goes on after its clock starts and off
 * before it stops, as mca_fe_enable_clocks and mca_fe_disable_clocks order
 * it. Nothing in a cluster but its port block is touched while it is off. */
static int cluster_on(struct speakers *s, uint32_t n)
{
    if (!s->io.power(s->io.cookie, n, 1)) {
        post(s, SPK_EV_POWER, (int32_t)n, 1);
        return 0;
    }
    s->powered |= 1u << n;
    return 1;
}

static void cluster_off(struct speakers *s, uint32_t n)
{
    if (!(s->powered & (1u << n)))
        return;
    s->powered &= ~(1u << n);
    if (!s->io.power(s->io.cookie, n, 0))
        post(s, SPK_EV_POWER, (int32_t)n, 0);
}

/* I2S, CPU provides the clocks, both inverted (macaudio's DAI format). */
static void mca_set_format(struct speakers *s, uint32_t n)
{
    uint64_t c = cluster(s, n);
    modify(s, c + MCA_TXA + TX_CONF, CONF_BCLK_POL, 0);
    modify(s, c + MCA_RXB + RX_CONF, CONF_BCLK_POL, 0);
    wr(s, c + MCA_TXA + TX_BITSTART, 1);
    wr(s, c + MCA_RXB + RX_BITSTART, 1);
}

static uint32_t adapter_value(uint32_t channels)
{
    uint32_t pad = 32 - 16;
    return (channels << 20) | (2u << 5) | (2u << 13) | pad | (pad << 8);
}

static void mca_configure_tx(struct speakers *s)
{
    uint32_t t = s->cfg.tx_cluster;
    uint64_t c = cluster(s, t);
    uint64_t serdes = c + MCA_TXA;
    modify(s, serdes + TX_CONF,
        CONF_WIDTH_MASK | CONF_NCHANS | CONF_SYNC_SEL | CONF_UNK1 | CONF_UNK2 | CONF_UNK3,
        (TX_SLOTS - 1) | CONF_WIDTH_32 | ((t + 1) << 16) | CONF_UNK1 | CONF_UNK2 | CONF_UNK3);
    wr(s, serdes + TX_SLOTMASK, 0xffffffffu);
    wr(s, serdes + TX_SLOTMASK + 0x4, ~0x3u);    /* two channels of eight slots */
    wr(s, serdes + TX_SLOTMASK + 0x8, 0xffffffffu);
    wr(s, serdes + TX_SLOTMASK + 0xc, ~0xffu);
    wr(s, s->cfg.mca_switch + ADAPTER_A(t), adapter_value(2));
    wr(s, c + MCA_SYNCGEN_HI, BCLK_RATIO / 2 - 1);
    wr(s, c + MCA_SYNCGEN_LO, (BCLK_RATIO + 1) / 2 - 1);
    wr(s, c + MCA_MCLK_CONF, 1u << 8);
}

static void mca_configure_sense(struct speakers *s)
{
    uint32_t n = s->cfg.sense_cluster;
    uint64_t c = cluster(s, n);
    uint64_t serdes = c + MCA_RXB;
    modify(s, serdes + RX_CONF,
        CONF_WIDTH_MASK | CONF_NCHANS | CONF_SYNC_SEL | CONF_UNK1 | CONF_UNK2 | CONF_UNK3 |
        CONF_NO_FEEDBACK,
        (SENSE_SLOTS - 1) | CONF_WIDTH_16 | ((n + 1) << 16) | CONF_UNK1 | CONF_UNK2 |
        CONF_NO_FEEDBACK);
    wr(s, serdes + RX_SLOTMASK, 0xffffffffu);
    wr(s, serdes + RX_SLOTMASK + 0x4, ~0xfu);    /* four channels of sixteen */
    wr(s, serdes + RX_PORT, s->cfg.port_mask);
    wr(s, s->cfg.mca_switch + ADAPTER_B(n), adapter_value(SENSE_CHANNELS));
    wr(s, c + MCA_SYNCGEN_HI, BCLK_RATIO / 2 - 1);
    wr(s, c + MCA_SYNCGEN_LO, (BCLK_RATIO + 1) / 2 - 1);
    wr(s, c + MCA_MCLK_CONF, 1u << 8);
}

static void mca_ports(struct speakers *s, int on)
{
    uint32_t p;
    for (p = 0; p < s->cfg.mca_cluster_count; p++) {
        uint64_t c;
        if (!(s->cfg.port_mask & (1u << p)))
            continue;
        c = cluster(s, p);
        if (on) {
            wr(s, c + MCA_PORT_DATA_SEL, 1u << (s->cfg.tx_cluster * 2));
            modify(s, c + MCA_PORT_ENABLES, PORT_TX_DATA, PORT_TX_DATA);
            wr(s, c + MCA_PORT_CLOCK_SEL, (s->cfg.tx_cluster + 1) << 8);
            modify(s, c + MCA_PORT_ENABLES, PORT_CLOCKS, PORT_CLOCKS);
        } else {
            modify(s, c + MCA_PORT_ENABLES, PORT_TX_DATA, 0);
            wr(s, c + MCA_PORT_DATA_SEL, 0);
            modify(s, c + MCA_PORT_ENABLES, PORT_CLOCKS, 0);
            wr(s, c + MCA_PORT_CLOCK_SEL, 0);
        }
    }
}

static uint32_t lowest_port(uint32_t mask)
{
    uint32_t p = 0;
    while (!(mask & 1u)) {
        mask >>= 1;
        p++;
    }
    return p;
}

/* Reset the serializer with its sync input parked, as mca_fe_early_trigger
 * does before ADMAC starts. */
static void serdes_reset(struct speakers *s, uint32_t n, uint32_t unit, uint32_t conf)
{
    uint64_t serdes = cluster(s, n) + unit;
    modify(s, serdes + conf, CONF_SYNC_SEL, 0);
    modify(s, serdes + conf, CONF_SYNC_SEL, 7u << 16);
    modify(s, serdes + SERDES_STATUS, SERDES_EN | SERDES_RST, SERDES_RST);
    delay_us(s, 50);
    if (rd(s, serdes + SERDES_STATUS) & SERDES_RST)
        post(s, SPK_EV_SERDES, (int32_t)n, 0);
    modify(s, serdes + conf, CONF_SYNC_SEL, 0);
    modify(s, serdes + conf, CONF_SYNC_SEL, (n + 1) << 16);
    delay_us(s, 100);
}

static void serdes_enable(struct speakers *s, uint32_t n, uint32_t unit, int enable)
{
    uint64_t serdes = cluster(s, n) + unit;
    if (enable)
        modify(s, serdes + SERDES_STATUS, SERDES_EN | SERDES_RST, SERDES_EN);
    else
        modify(s, serdes + SERDES_STATUS, SERDES_EN, 0);
}

/* ---- ADMAC ---- */

static uint64_t chan(struct speakers *s, uint32_t ch)
{
    return s->cfg.admac + CHAN_BASE(ch);
}

static int admac_setup(struct speakers *s, uint32_t ch, uint32_t frame)
{
    uint32_t sram = rd(s, s->cfg.admac + ((ch & 1) ? ADMAC_RX_SRAM_SIZE : ADMAC_TX_SRAM_SIZE));
    uint32_t width;
    if (sram < SRAM_BLOCK)
        return -1;
    /* This driver owns the whole controller: the first block of each SRAM. */
    wr(s, chan(s, ch) + CHAN_CARVEOUT, SRAM_BLOCK << 16);
    width = rd(s, chan(s, ch) + CHAN_BUS_WIDTH) & ~0xffu;
    wr(s, chan(s, ch) + CHAN_BUS_WIDTH, width | BUS_16BIT | frame);
    wr(s, chan(s, ch) + CHAN_FIFOCTL, ((0x30u * 2) << 16) | (0x18u * 2));
    return 0;
}

static void admac_reset_rings(struct speakers *s, uint32_t ch)
{
    wr(s, chan(s, ch) + CHAN_CTL, CHAN_RST_RINGS);
    wr(s, chan(s, ch) + CHAN_CTL, 0);
}

static void admac_descriptor(struct speakers *s, uint32_t ch, uint64_t iova, uint32_t length)
{
    uint64_t port = s->cfg.admac + DESC_WRITE(ch);
    wr(s, port, (uint32_t)iova);
    wr(s, port, (uint32_t)(iova >> 32));
    wr(s, port, length);
    wr(s, port, DESC_NOTIFY);
}

static void admac_run(struct speakers *s, uint32_t ch, int run)
{
    uint32_t bit = 1u << (ch / 2);
    if (run) {
        /* Asahi's apple-admac driver unmasks this output only because its
         * IRQ handler drains the report ring and acknowledges every level
         * interrupt.  Vinix deliberately polls the rings from the speaker
         * service thread, so an unmasked descriptor-done interrupt would
         * remain asserted between polls and trap a CPU in an IRQ storm as
         * soon as the first period completed. */
        wr(s, chan(s, ch) + CHAN_INTSTATUS(ADMAC_IRQ_INDEX), STATUS_DESC_DONE | STATUS_ERR);
        wr(s, chan(s, ch) + CHAN_INTMASK(ADMAC_IRQ_INDEX), 0);
        wr(s, s->cfg.admac + ((ch & 1) ? ADMAC_RX_START : ADMAC_TX_START), bit);
    } else {
        wr(s, s->cfg.admac + ((ch & 1) ? ADMAC_RX_STOP : ADMAC_TX_STOP), bit);
        admac_reset_rings(s, ch);
        wr(s, chan(s, ch) + CHAN_INTMASK(ADMAC_IRQ_INDEX), 0);
    }
}

/* Completed descriptors since the last call. */
static uint32_t admac_reap(struct speakers *s, uint32_t ch)
{
    uint64_t c = chan(s, ch);
    uint64_t port = s->cfg.admac + REPORT_READ(ch);
    uint32_t n = 0;
    if (rd(s, c + CHAN_DESC_RING) & RING_ERR) {
        wr(s, c + CHAN_DESC_RING, RING_ERR);
        s->dma_errors++;
        post(s, SPK_EV_DMA_ERROR, (int32_t)ch, 0);
    }
    if (rd(s, c + CHAN_REPORT_RING) & RING_ERR) {
        wr(s, c + CHAN_REPORT_RING, RING_ERR);
        s->dma_errors++;
        post(s, SPK_EV_DMA_ERROR, (int32_t)ch, 1);
    }
    while (n < HW_SLOTS && !(rd(s, c + CHAN_REPORT_RING) & RING_EMPTY)) {
        (void)rd(s, port);
        (void)rd(s, port);
        (void)rd(s, port);
        (void)rd(s, port);
        n++;
    }
    if (n)
        wr(s, c + CHAN_INTSTATUS(ADMAC_IRQ_INDEX), STATUS_DESC_DONE);
    return n;
}

/* ---- protection model ---- */

static void model_rate(struct speakers *s)
{
    const struct speaker_params *p = &j313_speakers[0];
    /* alpha = step / (tau + step) = 1 / (tau * rate + 1), in Q48. */
    s->alpha_coil = (int64_t)((1000ull << 48) /
        ((uint64_t)p->tau_coil_ms * s->rate + 1000));
    s->alpha_magnet = (int64_t)((1000ull << 48) /
        ((uint64_t)p->tau_magnet_ms * s->rate + 1000));
}

static void model_reset(struct speakers *s)
{
    uint32_t i;
    for (i = 0; i < SPK_COUNT; i++) {
        const struct speaker_params *p = &j313_speakers[i];
        struct speaker_model *m = &s->model[i];
        /* speakersafetyd's cold boot: warm, but not warm enough to limit.
         * Whatever played before this kernel is unknown. */
        int64_t coil = MILLI_TO_Q32(p->t_limit_m - T_WINDOW_M) - Q32(1);
        m->coil = coil;
        m->magnet = MILLI_TO_Q32(T_AMBIENT_M) +
            (coil - MILLI_TO_Q32(T_AMBIENT_M)) * p->tr_magnet_m /
            (p->tr_magnet_m + p->tr_coil_m);
        m->coil_hyst = 0;
        m->magnet_hyst = 0;
        m->gain_mdb = 0;
    }
}

/* The model with no power: c' = (1-ac) c + ac m, m' = (1-am) m, relative to
 * ambient. Raise that step to `samples` by squaring and apply it once. */
static void model_cool(struct speakers *s, uint64_t samples)
{
    const uint64_t one = 1ull << 62;
    uint64_t ac = (uint64_t)s->alpha_coil << 14;     /* Q48 -> Q62 */
    uint64_t am = (uint64_t)s->alpha_magnet << 14;
    uint64_t a = one - ac, b = ac, d = one - am;     /* step matrix */
    uint64_t ra = one, rb = 0, rd_ = one;            /* result: identity */
    uint32_t i;
    if (!samples)
        return;
    while (samples) {
        if (samples & 1) {
            /* result = result * step */
            uint64_t na = (uint64_t)(((unsigned __int128)ra * a) >> 62);
            uint64_t nb = (uint64_t)((((unsigned __int128)ra * b) +
                ((unsigned __int128)rb * d)) >> 62);
            uint64_t nd = (uint64_t)(((unsigned __int128)rd_ * d) >> 62);
            ra = na;
            rb = nb;
            rd_ = nd;
        }
        {
            uint64_t na = (uint64_t)(((unsigned __int128)a * a) >> 62);
            uint64_t nb = (uint64_t)((((unsigned __int128)a * b) +
                ((unsigned __int128)b * d)) >> 62);
            uint64_t nd = (uint64_t)(((unsigned __int128)d * d) >> 62);
            a = na;
            b = nb;
            d = nd;
        }
        samples >>= 1;
    }
    for (i = 0; i < SPK_COUNT; i++) {
        struct speaker_model *m = &s->model[i];
        int64_t c = m->coil - MILLI_TO_Q32(T_AMBIENT_M);
        int64_t g = m->magnet - MILLI_TO_Q32(T_AMBIENT_M);
        int64_t nc = (int64_t)(((__int128)c * (int64_t)ra + (__int128)g * (int64_t)rb) >> 62);
        int64_t ng = (int64_t)(((__int128)g * (int64_t)rd_) >> 62);
        m->coil = MILLI_TO_Q32(T_AMBIENT_M) + nc;
        m->magnet = MILLI_TO_Q32(T_AMBIENT_M) + ng;
    }
}

static void model_idle(struct speakers *s)
{
    uint64_t now = now_us(s);
    uint64_t elapsed = now - s->last_model_us;
    /* Only time with the amplifiers shut down counts as cooling. */
    model_cool(s, elapsed * s->rate / 1000000);
    s->last_model_us = now;
}

static int32_t min_gain_mdb(void)
{
    const struct speaker_params *p = &j313_speakers[0];
    /* max power / peak power, speakersafetyd's min_gain:
     *   ((t_limit - t_ambient) / (tr_magnet + tr_coil)) /
     *   (10^(amp_gain/10) / z * 2)                                    */
    uint64_t num = (uint64_t)(p->t_limit_m - T_AMBIENT_M) * (uint64_t)p->z_nominal_mohm;
    uint64_t den = (uint64_t)(p->tr_magnet_m + p->tr_coil_m) * 2u * 1000u;
    int64_t diff = log2_q16(num) - log2_q16(den);
    int64_t mdb = diff * 30103 / (65536 * 10) - AMP_GAIN_MDB;
    return mdb > 0 ? 0 : (int32_t)mdb;
}

/* Run the model over one chunk of sense data. 0, or a fault event code. */
static int model_run(struct speakers *s, uint32_t n, const int16_t *frames, uint32_t count,
    int32_t *fault_value)
{
    const struct speaker_params *p = &j313_speakers[n];
    struct speaker_model *m = &s->model[n];
    const int64_t ambient = MILLI_TO_Q32(T_AMBIENT_M);
    const int64_t ceiling = MILLI_TO_Q32(p->t_limit_m + p->t_headroom_m);
    int64_t sum = 0, average, temp, excess;
    uint32_t f;
    for (f = 0; f < count; f++) {
        int32_t v = frames[f * SENSE_CHANNELS + p->vs_chan];
        int32_t i = frames[f * SENSE_CHANNELS + p->is_chan];
        int64_t power = (int64_t)v * i * s->power_factor / 1000000;
        int64_t coil_target = m->magnet + power * p->tr_coil_m / 1000;
        int64_t magnet_target = ambient + power * p->tr_magnet_m / 1000;
        m->coil += mul_q48(coil_target - m->coil, s->alpha_coil);
        m->magnet += mul_q48(magnet_target - m->magnet, s->alpha_magnet);
        if (m->coil > ceiling || m->magnet > ceiling) {
            int64_t hot = m->coil > m->magnet ? m->coil : m->magnet;
            *fault_value = (int32_t)((hot * 1000) >> 32);
            return SPK_EV_FAULT_TEMP;
        }
        sum += power;
    }
    average = count ? sum / (int64_t)count : 0;
    /* Only rounding should make the average negative. */
    if (average < -(Q32(1) / 100)) {
        *fault_value = (int32_t)((average * 1000) >> 32);
        return SPK_EV_FAULT_POWER;
    }
    if (m->coil_hyst < m->coil)
        m->coil_hyst = m->coil;
    if (m->coil_hyst > m->coil + MILLI_TO_Q32(T_HYSTERESIS_M))
        m->coil_hyst = m->coil + MILLI_TO_Q32(T_HYSTERESIS_M);
    if (m->magnet_hyst < m->magnet)
        m->magnet_hyst = m->magnet;
    if (m->magnet_hyst > m->magnet + MILLI_TO_Q32(T_HYSTERESIS_M))
        m->magnet_hyst = m->magnet + MILLI_TO_Q32(T_HYSTERESIS_M);
    temp = m->coil_hyst > m->magnet_hyst ? m->coil_hyst : m->magnet_hyst;
    excess = temp - MILLI_TO_Q32(p->t_limit_m - T_WINDOW_M);
    if (excess <= 0) {
        m->gain_mdb = 0;
    } else {
        int64_t gain = (int64_t)s->min_gain_mdb * excess / MILLI_TO_Q32(T_WINDOW_M);
        m->gain_mdb = gain > -10 ? 0 : (gain < -100000 ? -100000 : (int32_t)gain);
    }
    return 0;
}

static int32_t model_gain(struct speakers *s)
{
    int32_t gain = 0;
    uint32_t i;
    for (i = 0; i < SPK_COUNT; i++)
        if (s->model[i].gain_mdb < gain)
            gain = s->model[i].gain_mdb;
    return gain;
}

/* ---- amplifier state ---- */

static void fault_shutdown(struct speakers *s);

static int set_attenuation(struct speakers *s, int32_t att)
{
    uint32_t i;
    int failed = 0;
    if (att < 0)
        att = 0;
    if (att > ATT_MUTE)
        att = ATT_MUTE;
    for (i = 0; i < SPK_COUNT; i++) {
        int error = i2c_write(s, (int)i, TAS_PLAY_CFG2, (uint8_t)att);
        if (error) {
            failed = 1;
            post(s, SPK_EV_FAULT_I2C, (int32_t)i, error);
        }
    }
    if (failed) {
        /* A write that should have made it quieter must not be lost. */
        if (++s->i2c_failures >= 3 || att > s->applied_att)
            fault_shutdown(s);
        return -1;
    }
    s->i2c_failures = 0;
    s->applied_att = att;
    return 0;
}

static void apply_policy(struct speakers *s, uint64_t now)
{
    int fresh = now - s->last_sense_us <= SENSE_STALE_US;
    int any_live = 0, any_dead = 0;
    int32_t gain = model_gain(s);
    int32_t model_att, target;
    uint32_t i;
    for (i = 0; i < SPK_COUNT; i++) {
        any_live |= s->live[i];
        any_dead |= s->dead[i];
    }
    if (!fresh && !s->stale_reported) {
        s->stale_reported = 1;
        post(s, SPK_EV_STALE, (int32_t)((now - s->last_sense_us) / 1000), 0);
    }
    if (fresh && any_live && !any_dead) {
        if (!s->verified)
            post(s, SPK_EV_VERIFIED, 0, 0);
        s->verified = 1;
    } else {
        s->verified = 0;
    }
    if (gain != s->reported_gain) {
        /* Report entering, leaving and whole-decibel steps of limiting. */
        if (gain == 0 || s->reported_gain == 0 || gain / 1000 != s->reported_gain / 1000)
            post(s, SPK_EV_GAIN, gain, 0);
        s->reported_gain = gain;
    }
    model_att = (-gain + 499) / 500;
    target = s->verified ? model_att : (model_att > ATT_SAFE ? model_att : ATT_SAFE);
    if (target > s->applied_att) {
        set_attenuation(s, target);
        s->last_ramp_us = now;
    } else if (target < s->applied_att && now - s->last_ramp_us >= ATT_RAMP_US) {
        set_attenuation(s, s->applied_att - 1);
        s->last_ramp_us = now;
    }
}

/* ---- playback ring ---- */

static uint8_t *tx_at(struct speakers *s, uint64_t position)
{
    return (uint8_t *)(uintptr_t)(s->cfg.tx_buffer + position % s->tx_ring);
}

static void tx_submit(struct speakers *s)
{
    uint32_t offset = (uint32_t)(s->queued % s->tx_ring);
    s->io.clean(s->io.cookie, s->cfg.tx_buffer + offset, TX_PERIOD_BYTES);
    admac_descriptor(s, s->cfg.tx_dma, s->cfg.tx_iova + offset, TX_PERIOD_BYTES);
    s->queued += TX_PERIOD_BYTES;
}

static uint64_t *energy_slot(struct speakers *s, uint64_t period)
{
    uint32_t slot = (uint32_t)(period % ENERGY_HISTORY);
    if (s->period_tag[slot] != period + 1) {
        s->period_tag[slot] = period + 1;
        s->period_energy[slot][0] = 0;
        s->period_energy[slot][1] = 0;
    }
    return s->period_energy[slot];
}

/* Scale and account for whole samples and frames up to `written`. */
static void tx_account(struct speakers *s)
{
    uint64_t end = s->written & ~1ull;
    while (s->scaled_to < end) {
        int16_t *sample = (int16_t *)(void *)tx_at(s, s->scaled_to);
        if (s->volume < 100)
            *sample = (int16_t)((int32_t)*sample * (int32_t)s->volume / 100);
        s->scaled_to += 2;
    }
    end = s->written & ~(uint64_t)(TX_FRAME_BYTES - 1);
    while (s->measured_to < end) {
        const int16_t *frame = (const int16_t *)(const void *)tx_at(s, s->measured_to);
        uint64_t *energy = energy_slot(s, s->measured_to / TX_PERIOD_BYTES);
        energy[0] += (uint64_t)((int32_t)frame[0] * frame[0]);
        energy[1] += (uint64_t)((int32_t)frame[1] * frame[1]);
        s->measured_to += TX_FRAME_BYTES;
    }
}

/* Complete the period being written with silence. */
static void tx_pad(struct speakers *s)
{
    uint64_t end = (s->written / TX_PERIOD_BYTES + 1) * TX_PERIOD_BYTES;
    if (s->written % TX_PERIOD_BYTES == 0 && s->written > s->queued)
        return;
    if (s->written == s->queued)
        end = s->queued + TX_PERIOD_BYTES;
    while (s->written < end) {
        *tx_at(s, s->written) = 0;
        s->written++;
    }
    s->scaled_to = s->written;
    tx_account(s);
}

static uint32_t tx_service(struct speakers *s, uint64_t now)
{
    uint32_t flags = 0;
    uint32_t done = admac_reap(s, s->cfg.tx_dma);
    if (done) {
        s->played += (uint64_t)done * TX_PERIOD_BYTES;
        if (s->played > s->queued)
            s->played = s->queued;
        flags |= VINIX_SPK_SERVICE_PROGRESS;
    }
    while (s->queued - s->played < (uint64_t)HW_SLOTS * TX_PERIOD_BYTES) {
        if (s->written - s->queued >= TX_PERIOD_BYTES) {
            tx_submit(s);
            s->silence_since_us = 0;
            continue;
        }
        if (s->queued - s->played < (uint64_t)TX_LOW_WATER * TX_PERIOD_BYTES && !s->reserved) {
            int empty = s->written == s->queued;
            if (!s->draining)
                s->underruns++;
            tx_pad(s);
            tx_submit(s);
            if (empty && !s->silence_since_us)
                s->silence_since_us = now ? now : 1;
            else if (!empty)
                s->silence_since_us = 0;
            continue;
        }
        break;
    }
    if (s->draining && s->played >= s->drain_target)
        flags |= VINIX_SPK_SERVICE_DRAINED;
    return flags;
}

/* ---- sense ring ---- */

static uint64_t sense_iova(struct speakers *s, uint64_t period)
{
    return s->cfg.sense_iova + (period % s->sense_periods) * SENSE_PERIOD_BYTES;
}

static void sense_submit(struct speakers *s)
{
    admac_descriptor(s, s->cfg.sense_dma, sense_iova(s, s->sense_queued), SENSE_PERIOD_BYTES);
    s->sense_queued++;
}

/* Output energy that should have been measured during sense chunk `k`,
 * per speaker, in sense-voltage LSB squared. */
static void expected_energy(struct speakers *s, uint64_t k, uint64_t out[SPK_COUNT])
{
    uint64_t start = s->sense_origin + k * PERIOD_FRAMES;
    uint64_t first = start / PERIOD_FRAMES;
    uint64_t w_second = start % PERIOD_FRAMES;
    uint64_t w_first = PERIOD_FRAMES - w_second;
    uint64_t scale = mul_q32u(s->expect_q32, db_to_power_q32(-500 * s->applied_att));
    uint32_t i;
    for (i = 0; i < SPK_COUNT; i++) {
        uint64_t e = 0;
        uint32_t slot = (uint32_t)(first % ENERGY_HISTORY);
        if (s->period_tag[slot] == first + 1)
            e += s->period_energy[slot][i] / PERIOD_FRAMES * w_first;
        slot = (uint32_t)((first + 1) % ENERGY_HISTORY);
        if (w_second && s->period_tag[slot] == first + 2)
            e += s->period_energy[slot][i] / PERIOD_FRAMES * w_second;
        out[i] = mul_q32u(e, scale);
    }
}

/* Liveness: output that should have produced a measurable voltage must have.
 * Judged over a window of chunks so the two streams need not align exactly. */
static void check_liveness(struct speakers *s, uint64_t k, const int16_t *frames)
{
    const uint64_t window_frames = (uint64_t)WINDOW_CHUNKS * PERIOD_FRAMES;
    /* 50 mV and 100 mV RMS, in sense LSB (14 V full scale) squared. */
    const uint64_t judge = 13690ull * window_frames;
    const uint64_t condemn = 54760ull * window_frames;
    uint64_t expected[SPK_COUNT];
    uint32_t slot = (uint32_t)(k % WINDOW_CHUNKS);
    uint32_t i, f, c;
    expected_energy(s, k, expected);
    for (i = 0; i < SPK_COUNT; i++) {
        const struct speaker_params *p = &j313_speakers[i];
        uint64_t measured = 0, total_expected = 0, total_measured = 0;
        for (f = 0; f < PERIOD_FRAMES; f++) {
            int32_t v = frames[f * SENSE_CHANNELS + p->vs_chan];
            measured += (uint64_t)(v * v);
        }
        s->window_expected[slot][i] = expected[i];
        s->window_measured[slot][i] = measured;
        if (k + 1 < WINDOW_CHUNKS)
            continue;
        for (c = 0; c < WINDOW_CHUNKS; c++) {
            total_expected += s->window_expected[c][i];
            total_measured += s->window_measured[c][i];
        }
        if (total_expected >= judge && total_measured * 100 >= total_expected * 9) {
            s->live[i] = 1;          /* at least 30% of the expected RMS */
            s->dead[i] = 0;
        } else if (total_expected >= condemn && total_measured * 100 < total_expected) {
            if (!s->dead[i])
                post(s, SPK_EV_DEAD, (int32_t)i, 0);
            s->dead[i] = 1;          /* under 10% of it */
        }
    }
}

static void sense_service(struct speakers *s, uint64_t now)
{
    uint32_t done = admac_reap(s, s->cfg.sense_dma);
    while (done--) {
        uint64_t k = s->sense_done;
        uint64_t address = s->cfg.sense_buffer + (k % s->sense_periods) * SENSE_PERIOD_BYTES;
        const int16_t *frames = (const int16_t *)(uintptr_t)address;
        uint32_t i;
        s->io.invalidate(s->io.cookie, address, SENSE_PERIOD_BYTES);
        for (i = 0; i < SPK_COUNT; i++) {
            int32_t value = 0;
            int code = model_run(s, i, frames, PERIOD_FRAMES, &value);
            if (code) {
                post(s, code, (int32_t)i, value);
                fault_shutdown(s);
                return;
            }
        }
        check_liveness(s, k, frames);
        s->sense_done++;
        s->sense_chunks++;
        s->last_sense_us = now;
        s->stale_reported = 0;
        sense_submit(s);
    }
}

/* ---- stream control ---- */

static void reset_positions(struct speakers *s)
{
    uint32_t i;
    s->written = s->queued = s->played = 0;
    s->scaled_to = s->measured_to = 0;
    s->reserved = 0;
    s->draining = 0;
    s->drain_target = 0;
    s->first_write_us = 0;
    s->silence_since_us = 0;
    for (i = 0; i < ENERGY_HISTORY; i++)
        s->period_tag[i] = 0;
}

static void hardware_stop(struct speakers *s)
{
    uint32_t i;
    uint64_t tx = cluster(s, s->cfg.tx_cluster);
    for (i = 0; i < SPK_COUNT; i++)
        (void)tas_power(s, (int)i, PWR_MUTE);
    delay_us(s, 1000);
    for (i = 0; i < SPK_COUNT; i++)
        (void)tas_power(s, (int)i, PWR_SHUTDOWN);
    /* Sense is clocked through the speaker port: power it down while that
     * still runs. */
    if (s->powered & (1u << s->cfg.sense_cluster)) {
        serdes_enable(s, s->cfg.sense_cluster, MCA_RXB, 0);
        modify(s, cluster(s, s->cfg.sense_cluster) + MCA_SYNCGEN_STATUS, MCA_SYNCGEN_EN, 0);
    }
    admac_run(s, s->cfg.sense_dma, 0);
    cluster_off(s, s->cfg.sense_cluster);
    if (s->powered & (1u << s->cfg.tx_cluster)) {
        serdes_enable(s, s->cfg.tx_cluster, MCA_TXA, 0);
        modify(s, tx + MCA_SYNCGEN_STATUS, MCA_SYNCGEN_EN, 0);
        modify(s, tx + MCA_STATUS, MCA_MCLK_EN, 0);
    }
    admac_run(s, s->cfg.tx_dma, 0);
    cluster_off(s, s->cfg.tx_cluster);
    nco_enable(s, s->cfg.tx_nco, 0);
    mca_ports(s, 0);
    s->clocks_on = 0;
}

static void fault_shutdown(struct speakers *s)
{
    int was_running = s->state == ST_RUNNING || s->clocks_on;
    /* The shutdown line first: it needs no I2C to work. */
    sdz_set(s, 0);
    s->state = ST_FAULT;
    if (was_running)
        hardware_stop(s);
}

static int configure(struct speakers *s, uint32_t rate)
{
    if (s->state == ST_OFF || s->state == ST_FAULT || s->state == ST_RUNNING)
        return 0;
    if (rate != 44100 && rate != 48000)
        return 0;
    s->rate = rate;
    model_rate(s);
    reset_positions(s);
    s->state = ST_PREPARED;
    return 1;
}

static int wants_start(struct speakers *s)
{
    if (s->state != ST_PREPARED || s->written == 0)
        return 0;
    return s->written - s->queued >= (uint64_t)START_PERIODS * TX_PERIOD_BYTES ||
        s->draining || now_us(s) - s->first_write_us >= START_DELAY_US;
}

static int start_clocks(struct speakers *s)
{
    uint32_t i;
    if (s->state != ST_PREPARED)
        return 0;
    model_idle(s);
    for (i = 0; i < SPK_COUNT; i++) {
        int error = tas_set_rate(s, (int)i);
        if (!error)
            error = i2c_write(s, (int)i, TAS_PLAY_CFG2, ATT_SAFE);
        if (error) {
            post(s, SPK_EV_FAULT_I2C, (int32_t)i, error);
            fault_shutdown(s);
            return 0;
        }
    }
    s->applied_att = ATT_SAFE;
    if (nco_set_rate(s, s->cfg.tx_nco, BCLK_RATIO * s->rate) ||
        nco_set_rate(s, s->cfg.sense_nco, BCLK_RATIO * s->rate))
        return 0;
    mca_ports(s, 1);
    nco_enable(s, s->cfg.tx_nco, 1);
    s->clocks_on = 1;
    if (!cluster_on(s, s->cfg.tx_cluster))
        return 0;
    mca_set_format(s, s->cfg.tx_cluster);
    mca_configure_tx(s);
    return 1;
}

static int start_stream(struct speakers *s)
{
    uint64_t tx = cluster(s, s->cfg.tx_cluster);
    uint64_t sense = cluster(s, s->cfg.sense_cluster);
    uint32_t i, residue;
    uint64_t position;
    if (s->state != ST_PREPARED)
        return 0;
    wr(s, tx + MCA_SYNCGEN_SEL, s->cfg.tx_cluster + 1);
    modify(s, tx + MCA_SYNCGEN_STATUS, MCA_SYNCGEN_EN, MCA_SYNCGEN_EN);
    modify(s, tx + MCA_STATUS, MCA_MCLK_EN, MCA_MCLK_EN);
    delay_us(s, 1000);
    for (i = 0; i < SPK_COUNT; i++) {
        int error = tas_power(s, (int)i, PWR_ACTIVE);
        if (error) {
            post(s, SPK_EV_FAULT_I2C, (int32_t)i, error);
            s->state = ST_RUNNING;
            fault_shutdown(s);
            return 0;
        }
    }

    /* Playback: the first period, the channel, then the rest of the ring. */
    serdes_reset(s, s->cfg.tx_cluster, MCA_TXA, TX_CONF);
    admac_reset_rings(s, s->cfg.tx_dma);
    tx_pad(s);
    tx_submit(s);
    admac_run(s, s->cfg.tx_dma, 1);
    while (s->queued - s->played < (uint64_t)HW_SLOTS * TX_PERIOD_BYTES &&
        s->written - s->queued >= TX_PERIOD_BYTES && !(rd(s, chan(s, s->cfg.tx_dma) +
        CHAN_DESC_RING) & RING_FULL))
        tx_submit(s);
    serdes_enable(s, s->cfg.tx_cluster, MCA_TXA, 1);

    /* Sense: a clock consumer framed by the first speaker port, which runs
     * now. */
    if (!cluster_on(s, s->cfg.sense_cluster))
        return 0;
    mca_set_format(s, s->cfg.sense_cluster);
    mca_configure_sense(s);
    wr(s, sense + MCA_SYNCGEN_SEL, lowest_port(s->cfg.port_mask) + 6 + 1);
    modify(s, sense + MCA_SYNCGEN_STATUS, MCA_SYNCGEN_EN, MCA_SYNCGEN_EN);
    serdes_reset(s, s->cfg.sense_cluster, MCA_RXB, RX_CONF);
    admac_reset_rings(s, s->cfg.sense_dma);
    s->sense_queued = s->sense_done = 0;
    sense_submit(s);
    admac_run(s, s->cfg.sense_dma, 1);
    while (s->sense_queued < HW_SLOTS)
        sense_submit(s);
    /* Where playback is now, so each sense chunk can be matched with the
     * output it measured. */
    s->played += (uint64_t)admac_reap(s, s->cfg.tx_dma) * TX_PERIOD_BYTES;
    residue = rd(s, chan(s, s->cfg.tx_dma) + CHAN_RESIDUE);
    position = s->played + (residue <= TX_PERIOD_BYTES ? TX_PERIOD_BYTES - residue : 0);
    serdes_enable(s, s->cfg.sense_cluster, MCA_RXB, 1);
    s->sense_origin = position / TX_FRAME_BYTES;

    for (i = 0; i < SPK_COUNT; i++) {
        s->live[i] = 0;
        s->dead[i] = 0;
    }
    for (i = 0; i < WINDOW_CHUNKS; i++) {
        s->window_expected[i][0] = s->window_expected[i][1] = 0;
        s->window_measured[i][0] = s->window_measured[i][1] = 0;
    }
    s->verified = 0;
    s->stale_reported = 0;
    s->last_sense_us = now_us(s);
    s->last_ramp_us = s->last_sense_us;
    s->state = ST_RUNNING;
    return 1;
}

static void stop(struct speakers *s)
{
    if (s->state == ST_RUNNING || (s->state == ST_PREPARED && s->clocks_on)) {
        uint32_t i;
        hardware_stop(s);
        /* The amplifiers are shut down; the next start sets the level. */
        for (i = 0; i < SPK_COUNT; i++)
            (void)i2c_write(s, (int)i, TAS_PLAY_CFG2, ATT_MUTE);
        s->applied_att = ATT_MUTE;
        s->last_model_us = now_us(s);
    }
    if (s->state == ST_RUNNING || s->state == ST_PREPARED)
        s->state = ST_IDLE;
    reset_positions(s);
}

static uint32_t service(struct speakers *s)
{
    uint64_t now;
    uint32_t flags;
    if (s->state == ST_FAULT)
        return VINIX_SPK_SERVICE_FAULT;
    if (s->state != ST_RUNNING)
        return 0;
    now = now_us(s);
    flags = tx_service(s, now) | VINIX_SPK_SERVICE_RUNNING;
    sense_service(s, now);
    if (s->state == ST_FAULT)
        return VINIX_SPK_SERVICE_FAULT | VINIX_SPK_SERVICE_PROGRESS;
    apply_policy(s, now);
    if (s->state == ST_FAULT)
        return VINIX_SPK_SERVICE_FAULT | VINIX_SPK_SERVICE_PROGRESS;
    if (s->silence_since_us && !s->draining && !s->reserved &&
        now - s->silence_since_us >= IDLE_STOP_US)
        flags |= VINIX_SPK_SERVICE_IDLE;
    return flags;
}

static uint32_t room(struct speakers *s)
{
    uint64_t used;
    if (s->state != ST_PREPARED && s->state != ST_RUNNING)
        return 0;
    used = s->written - s->played;
    return used >= s->tx_ring ? 0 : (uint32_t)(s->tx_ring - used);
}

static uint8_t *reserve(struct speakers *s, uint32_t *length)
{
    uint32_t available = room(s);
    uint32_t contiguous = s->tx_ring - (uint32_t)(s->written % s->tx_ring);
    if (s->draining)
        available = 0;
    if (available > contiguous)
        available = contiguous;
    *length = available;
    s->reserved = available;
    return available ? tx_at(s, s->written) : 0;
}

static void commit(struct speakers *s, uint32_t bytes)
{
    if (bytes > s->reserved)
        bytes = s->reserved;
    s->reserved = 0;
    if (!bytes)
        return;
    if (!s->written)
        s->first_write_us = now_us(s);
    s->written += bytes;
    tx_account(s);
}

static void drain(struct speakers *s)
{
    if (s->state != ST_PREPARED && s->state != ST_RUNNING)
        return;
    if (s->written % TX_PERIOD_BYTES)
        tx_pad(s);
    s->draining = 1;
    s->drain_target = s->written;
}

static int drained(struct speakers *s)
{
    if (s->state == ST_RUNNING)
        return s->draining && s->played >= s->drain_target;
    return s->state != ST_PREPARED || s->written == 0;
}

static int init(struct speakers *s, const struct vinix_apple_speakers_config *cfg)
{
    const struct speaker_params *p = &j313_speakers[0];
    uint32_t i;
    s->cfg = *cfg;
    s->state = ST_OFF;
    if (cfg->tx_cluster >= cfg->mca_cluster_count || cfg->sense_cluster >= cfg->mca_cluster_count ||
        cfg->tx_cluster == cfg->sense_cluster || !cfg->port_mask ||
        cfg->port_mask >> cfg->mca_cluster_count || (cfg->port_mask & (1u << cfg->sense_cluster)) ||
        cfg->tx_nco >= cfg->nco_channels || cfg->sense_nco >= cfg->nco_channels ||
        (cfg->tx_dma & 1) || !(cfg->sense_dma & 1) || cfg->tx_dma >= cfg->admac_channels ||
        cfg->sense_dma >= cfg->admac_channels || !cfg->nco_ref_hz || !cfg->i2c_ref_hz ||
        (cfg->tx_buffer | cfg->tx_iova | cfg->sense_buffer | cfg->sense_iova) & 0x3fff ||
        cfg->tx_bytes < 8 * TX_PERIOD_BYTES || cfg->sense_bytes < 8 * SENSE_PERIOD_BYTES)
        return 0;
    for (i = 0; i < SPK_COUNT; i++)
        if (!cfg->i2c[i] || cfg->amp_address[i] > 0x7f || cfg->imon_slot[i] > 0x3f ||
            cfg->vmon_slot[i] > 0x3f)
            return 0;
    s->tx_ring = cfg->tx_bytes / TX_PERIOD_BYTES * TX_PERIOD_BYTES;
    s->sense_periods = cfg->sense_bytes / SENSE_PERIOD_BYTES;
    s->volume = 100;
    s->min_gain_mdb = min_gain_mdb();
    /* sense product (LSB^2) to Q32 watts, times 10^6: is * vs * 4 */
    s->power_factor = (int64_t)p->is_scale_m * p->vs_scale_m * 4;
    /* Output at full scale reaches at least 10^(gain/20) volts; in sense
     * LSB: (that / vs_scale)^2. */
    s->expect_q32 = db_to_power_q32(AMP_GAIN_MDB) * 1000000ull /
        ((uint64_t)p->vs_scale_m * (uint64_t)p->vs_scale_m);
    s->i2c_div = (cfg->i2c_ref_hz + 16 * I2C_BUS_HZ - 1) / (16 * I2C_BUS_HZ);
    if (s->i2c_div < 4 || s->i2c_div > 0xff)
        return 0;
    s->io.clean(s->io.cookie, cfg->tx_buffer, cfg->tx_bytes);
    s->io.clean(s->io.cookie, cfg->sense_buffer, cfg->sense_bytes);

    for (i = 0; i < SPK_COUNT; i++) {
        s->i2c_rev[i] = rd(s, cfg->i2c[i] + I2C_REV);
        wr(s, cfg->i2c[i] + I2C_IMASK, 0);
        i2c_reset(s, (int)i);
    }
    /* Both amplifiers share one shutdown line: cycle it, then reset each. */
    sdz_set(s, 0);
    delay_us(s, 5000);
    sdz_set(s, 1);
    delay_us(s, 2000);
    for (i = 0; i < SPK_COUNT; i++) {
        int error = tas_init(s, (int)i);
        if (error) {
            post(s, SPK_EV_FAULT_I2C, (int32_t)i, error);
            sdz_set(s, 0);
            return 0;
        }
        post(s, SPK_EV_AMP, (int32_t)i, (int32_t)s->amp_rev[i]);
    }
    if (admac_setup(s, cfg->tx_dma, BUS_FRAME_2) || admac_setup(s, cfg->sense_dma, BUS_FRAME_4)) {
        sdz_set(s, 0);
        return 0;
    }
    s->rate = 48000;
    model_rate(s);
    model_reset(s);
    s->last_model_us = now_us(s);
    s->applied_att = ATT_MUTE;
    s->state = ST_IDLE;
    return 1;
}

static void get_status(struct speakers *s, struct vinix_apple_speakers_status *out)
{
    uint32_t i;
    for (i = 0; i < SPK_COUNT; i++) {
        out->coil_mc[i] = (int32_t)((s->model[i].coil * 1000) >> 32);
        out->magnet_mc[i] = (int32_t)((s->model[i].magnet * 1000) >> 32);
    }
    out->model_gain_mdb = model_gain(s);
    out->applied_att = s->applied_att;
    out->verified = s->verified;
    out->fault = s->state == ST_FAULT;
    out->underruns = s->underruns;
    out->sense_chunks = s->sense_chunks;
    out->dma_errors = s->dma_errors;
}

#ifdef __AARCH64__
/* Width-exact MMIO, as for the other Apple drivers. */
extern uint32_t vinix_mmio_read32(void *);
extern void vinix_mmio_write32(void *, uint32_t);

static struct speakers speakers;
static uint64_t counter_frequency;
static uint64_t cache_line;

static uint32_t kernel_read32(void *cookie, uint64_t address)
{
    uint32_t v;
    (void)cookie;
    v = vinix_mmio_read32((void *)(uintptr_t)address);
    __asm__ volatile("dmb ish" ::: "memory");
    return v;
}

static void kernel_write32(void *cookie, uint64_t address, uint32_t value)
{
    (void)cookie;
    __asm__ volatile("dmb ish" ::: "memory");
    vinix_mmio_write32((void *)(uintptr_t)address, value);
}

static uint64_t kernel_now_us(void *cookie)
{
    uint64_t count;
    (void)cookie;
    __asm__ volatile("mrs %0, cntvct_el0" : "=r"(count));
    return (count / counter_frequency) * 1000000 +
        (count % counter_frequency) * 1000000 / counter_frequency;
}

static void kernel_delay_us(void *cookie, uint32_t us)
{
    uint64_t start = kernel_now_us(cookie);
    while (kernel_now_us(cookie) - start < us)
        __asm__ volatile("yield" ::: "memory");
}

/* ADMAC does not snoop the CPU caches: push playback out to memory before
 * it is queued, and drop stale lines before reading what it captured. */
static void kernel_clean(void *cookie, uint64_t address, uint32_t length)
{
    uint64_t a = address & ~(cache_line - 1);
    (void)cookie;
    __asm__ volatile("dsb sy" ::: "memory");
    for (; a < address + length; a += cache_line)
        __asm__ volatile("dc civac, %0" :: "r"(a) : "memory");
    __asm__ volatile("dsb sy" ::: "memory");
}

static void kernel_invalidate(void *cookie, uint64_t address, uint32_t length)
{
    uint64_t a = address & ~(cache_line - 1);
    (void)cookie;
    __asm__ volatile("dsb sy" ::: "memory");
    for (; a < address + length; a += cache_line)
        __asm__ volatile("dc ivac, %0" :: "r"(a) : "memory");
    __asm__ volatile("dsb sy" ::: "memory");
}

static int kernel_power(void *cookie, uint32_t cluster, int on)
{
    (void)cookie;
    return speakers.cfg.cluster_power(cluster, on);
}

int vinix_apple_speakers_init(const struct vinix_apple_speakers_config *cfg)
{
    uint64_t ctr;
    if (!cfg || !cfg->cluster_power || speakers.state != ST_OFF)
        return 0;
    __asm__ volatile("mrs %0, cntfrq_el0" : "=r"(counter_frequency));
    __asm__ volatile("mrs %0, ctr_el0" : "=r"(ctr));
    cache_line = 4ull << ((ctr >> 16) & 0xf);
    if (!counter_frequency)
        return 0;
    speakers.io = (struct spk_io){kernel_read32, kernel_write32, kernel_now_us,
        kernel_delay_us, kernel_clean, kernel_invalidate, kernel_power, 0};
    return init(&speakers, cfg);
}

int vinix_apple_speakers_configure(uint32_t rate) { return configure(&speakers, rate); }
int vinix_apple_speakers_start_clocks(void) { return start_clocks(&speakers); }
int vinix_apple_speakers_start_stream(void) { return start_stream(&speakers); }
void vinix_apple_speakers_stop(void) { stop(&speakers); }
int vinix_apple_speakers_wants_start(void) { return wants_start(&speakers); }
uint32_t vinix_apple_speakers_service(void) { return service(&speakers); }
uint8_t *vinix_apple_speakers_reserve(uint32_t *length) { return reserve(&speakers, length); }
void vinix_apple_speakers_commit(uint32_t bytes) { commit(&speakers, bytes); }
uint32_t vinix_apple_speakers_room(void) { return room(&speakers); }
void vinix_apple_speakers_drain(void) { drain(&speakers); }
int vinix_apple_speakers_drained(void) { return drained(&speakers); }
int vinix_apple_speakers_running(void) { return speakers.state == ST_RUNNING; }
int vinix_apple_speakers_active(void)
{
    return speakers.state == ST_PREPARED || speakers.state == ST_RUNNING;
}
int vinix_apple_speakers_faulted(void) { return speakers.state == ST_FAULT; }
void vinix_apple_speakers_fail(void) { fault_shutdown(&speakers); }

void vinix_apple_speakers_set_volume(uint32_t percent)
{
    speakers.volume = percent > 100 ? 100 : percent;
}

void vinix_apple_speakers_get_status(struct vinix_apple_speakers_status *out)
{
    get_status(&speakers, out);
}

int vinix_apple_speakers_take_event(int32_t out[3])
{
    struct speaker_event e;
    if (!take_event(&speakers, &e))
        return 0;
    out[0] = e.code;
    out[1] = e.a;
    out[2] = e.b;
    return 1;
}
#endif /* __AARCH64__ */
#endif /* __AARCH64__ || VINIX_APPLE_SPEAKERS_TEST */
