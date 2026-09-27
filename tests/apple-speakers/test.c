/* SPDX-License-Identifier: GPL-2.0-only
 *
 * Host tests for the J313 speaker driver. They compile the production
 * kernel/c/apple_speakers.c against a simulated machine: two TAS5770L
 * amplifiers behind P.A. Semi I2C FIFOs, ADMAC descriptor and report rings
 * that move real samples in simulated time, and V/I sense derived from what
 * the amplifiers are actually playing. The protection model is checked
 * against a double-precision port of speakersafetyd.
 */
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define VINIX_APPLE_SPEAKERS_TEST
#include "../../kernel/c/apple_speakers.c"

#define FAKE_MCA    0x10000000ull
#define FAKE_SWITCH 0x11000000ull
#define FAKE_ADMAC  0x12000000ull
#define FAKE_NCO    0x13000000ull
#define FAKE_I2C0   0x14000000ull
#define FAKE_I2C1   0x14100000ull
#define FAKE_GPIO   (0x15000000ull + 181 * 4)
#define TX_CH       4u
#define SENSE_CH    11u

static unsigned tests;

/* ---- plain registers ---- */

#define REG_SLOTS 4096
static uint64_t reg_key[REG_SLOTS];
static uint32_t reg_val[REG_SLOTS];

static uint32_t *reg_slot(uint64_t address)
{
    uint32_t h = (uint32_t)((address * 0x9e3779b97f4a7c15ull) >> 52) % REG_SLOTS;
    while (reg_key[h] && reg_key[h] != address)
        h = (h + 1) % REG_SLOTS;
    reg_key[h] = address;
    return &reg_val[h];
}

static uint32_t reg_get(uint64_t address) { return *reg_slot(address); }
static void reg_set(uint64_t address, uint32_t value) { *reg_slot(address) = value; }

/* ---- amplifiers ---- */

enum { MODE_NORMAL, MODE_DEAD, MODE_INVERTED, MODE_STALLED };

struct fake_amp {
    uint8_t regs[128];
    uint8_t address;
    int resets;
    int fail_writes;          /* NACK every write while set */
    int writes_to_dvc;
};

struct fake_bus {
    struct fake_amp *amp;
    uint32_t smsta;
    uint32_t rx[16];
    int rx_count;
    int selected;             /* address matched */
    int reading;
    int have_pointer;
    uint8_t pointer;
    int nack;
    uint32_t ctl;
};

static struct fake_amp amps[2];
static struct fake_bus buses[2];

static void amp_defaults(struct fake_amp *a)
{
    memset(a->regs, 0, sizeof(a->regs));
    a->regs[TAS_PWR_CTRL] = 0x0e;
    a->regs[TAS_PLAY_CFG0] = 0x10;
    a->regs[TAS_PLAY_CFG2] = 0x00;
    a->regs[TAS_TDM0] = 0x09;
    a->regs[TAS_TDM1] = 0x02;
    a->regs[TAS_TDM2] = 0x0a;
    a->regs[TAS_TDM3] = 0x10;
    a->regs[0x0e] = 0x13;
    a->regs[TAS_TDM5] = 0x02;
    a->regs[TAS_TDM6] = 0x00;
    a->regs[TAS_REV] = 0x21;
}

static void bus_write(struct fake_bus *b, uint64_t offset, uint32_t value)
{
    if (offset == I2C_SMSTA) {
        b->smsta &= ~value;
        return;
    }
    if (offset == I2C_CTL) {
        b->ctl = value;
        if (value & CTL_MRR)
            b->rx_count = 0;
        return;
    }
    if (offset != I2C_MTXFIFO)
        return;
    if (value & MTX_START) {
        uint8_t address = (uint8_t)((value >> 1) & 0x7f);
        b->selected = address == b->amp->address;
        b->reading = value & 1;
        if (!b->selected)
            b->nack = 1;
        if (!b->reading)
            b->have_pointer = 0;
        return;
    }
    if (value & MTX_READ) {
        uint32_t n = value & 0xff, i;
        for (i = 0; i < n && b->selected; i++)
            b->rx[b->rx_count++] = b->amp->regs[(b->pointer + i) & 0x7f];
    } else if (b->selected) {
        uint8_t byte = (uint8_t)value;
        if (!b->have_pointer) {
            b->pointer = byte;
            b->have_pointer = 1;
        } else if (b->amp->fail_writes) {
            b->nack = 1;
        } else {
            b->amp->regs[b->pointer & 0x7f] = byte;
            if (b->pointer == TAS_SW_RST && (byte & 1)) {
                amp_defaults(b->amp);
                b->amp->resets++;
            }
            if (b->pointer == TAS_PLAY_CFG2)
                b->amp->writes_to_dvc++;
            b->pointer++;
        }
    }
    if (value & MTX_STOP) {
        b->smsta |= SM_XEN | (b->nack ? SM_MTN : 0);
        b->nack = 0;
        b->selected = 0;
    }
}

static uint32_t bus_read(struct fake_bus *b, uint64_t offset)
{
    if (offset == I2C_SMSTA)
        return b->smsta | SM_MTE;
    if (offset == I2C_REV)
        return 7;
    if (offset == I2C_MRXFIFO) {
        uint32_t v;
        if (!b->rx_count)
            return MRX_EMPTY;
        v = b->rx[0];
        memmove(b->rx, b->rx + 1, (size_t)(b->rx_count - 1) * sizeof(b->rx[0]));
        b->rx_count--;
        return v;
    }
    return 0;
}

/* ---- ADMAC ---- */

struct fake_desc {
    uint64_t address;
    uint32_t length;
};

struct fake_chan {
    struct fake_desc ring[4];
    int count;
    uint32_t words[4];
    int nwords;
    int reports;
    int report_words;
    int running;
    uint32_t progress;
    uint64_t starved;         /* frames the channel ran with nothing queued */
};

static struct fake_chan chans[24];

static void admac_write(uint64_t offset, uint32_t value)
{
    uint32_t i;
    if (offset == ADMAC_TX_START || offset == ADMAC_RX_START ||
        offset == ADMAC_TX_STOP || offset == ADMAC_RX_STOP) {
        for (i = 0; i < 12; i++) {
            if (!(value & (1u << i)))
                continue;
            chans[i * 2 + (offset == ADMAC_RX_START || offset == ADMAC_RX_STOP)].running =
                offset == ADMAC_TX_START || offset == ADMAC_RX_START;
        }
        return;
    }
    if (offset >= 0x10000 && offset < 0x10100 + 0x4000 + 0x100) {
        for (i = 0; i < 24; i++) {
            if (offset == DESC_WRITE(i)) {
                struct fake_chan *c = &chans[i];
                c->words[c->nwords++] = value;
                if (c->nwords == 4) {
                    assert(c->count < 4);
                    assert(c->words[3] == DESC_NOTIFY);
                    c->ring[c->count].address = c->words[0] | (uint64_t)c->words[1] << 32;
                    c->ring[c->count].length = c->words[2];
                    c->count++;
                    c->nwords = 0;
                }
                return;
            }
        }
    }
    for (i = 0; i < 24; i++) {
        if (offset == CHAN_BASE(i) + CHAN_CTL && (value & CHAN_RST_RINGS)) {
            chans[i].count = chans[i].reports = chans[i].nwords = 0;
            chans[i].report_words = 0;
            chans[i].progress = 0;
            return;
        }
    }
    reg_set(FAKE_ADMAC + offset, value);
}

static uint32_t admac_read(uint64_t offset)
{
    uint32_t i;
    if (offset == ADMAC_TX_SRAM_SIZE || offset == ADMAC_RX_SRAM_SIZE)
        return 0x4000;
    for (i = 0; i < 24; i++) {
        struct fake_chan *c = &chans[i];
        if (offset == CHAN_BASE(i) + CHAN_DESC_RING)
            return (c->count == 4 ? RING_FULL : 0) | (c->count == 0 ? RING_EMPTY : 0);
        if (offset == CHAN_BASE(i) + CHAN_REPORT_RING)
            return c->reports ? 0 : RING_EMPTY;
        if (offset == CHAN_BASE(i) + CHAN_RESIDUE)
            return c->count ? c->ring[0].length - c->progress : 0;
        if (offset == REPORT_READ(i)) {
            assert(c->reports > 0);
            if (++c->report_words == 4) {
                c->report_words = 0;
                c->reports--;
            }
            return 0;
        }
    }
    return reg_get(FAKE_ADMAC + offset);
}

/* ---- the machine ---- */

static uint64_t now;          /* microseconds */
static uint64_t frac_frames;
static int sense_mode;
static int16_t *played;       /* everything that reached the amplifiers */
static size_t played_count, played_capacity;
static double peak_voltage = 8.92; /* 16 dBV RMS full scale */
static struct speakers sut;

static double amp_voltage(int amp, int16_t sample)
{
    struct fake_amp *a = &amps[amp];
    double level, att;
    if ((a->regs[TAS_PWR_CTRL] & 3) != PWR_ACTIVE || !(reg_get(FAKE_GPIO) & GPIO_DATA))
        return 0;
    level = pow(10.0, (11.0 + 0.5 * (a->regs[TAS_PLAY_CFG0] & 0x1f) - 16.0) / 20.0);
    att = pow(10.0, -0.5 * a->regs[TAS_PLAY_CFG2] / 20.0);
    return sample / 32768.0 * peak_voltage * level * att;
}

static int16_t quantize(double value, double full_scale)
{
    double lsb = value / full_scale * 32768.0;
    if (lsb > 32767)
        lsb = 32767;
    if (lsb < -32768)
        lsb = -32768;
    return (int16_t)lrint(lsb);
}

static void hw_frames(uint64_t frames)
{
    struct fake_chan *tx = &chans[TX_CH], *rx = &chans[SENSE_CH];
    while (frames--) {
        int16_t out[2] = {0, 0};
        double v[2];
        int i;
        if (tx->running) {
            if (tx->count) {
                const int16_t *p = (const int16_t *)(uintptr_t)(tx->ring[0].address + tx->progress);
                out[0] = p[0];
                out[1] = p[1];
                tx->progress += 4;
                if (tx->progress == tx->ring[0].length) {
                    memmove(tx->ring, tx->ring + 1, 3 * sizeof(tx->ring[0]));
                    tx->count--;
                    tx->progress = 0;
                    tx->reports++;
                    assert(tx->reports <= 4);
                }
            } else {
                tx->starved++;
            }
            if (played_count + 2 > played_capacity) {
                played_capacity = played_capacity ? played_capacity * 2 : 1 << 16;
                played = realloc(played, played_capacity * sizeof(*played));
            }
            played[played_count++] = out[0];
            played[played_count++] = out[1];
        }
        for (i = 0; i < 2; i++)
            v[i] = amp_voltage(i, out[i]);
        if (rx->running && rx->count && sense_mode != MODE_STALLED) {
            int16_t *p = (int16_t *)(uintptr_t)(rx->ring[0].address + rx->progress);
            for (i = 0; i < 2; i++) {
                double volts = sense_mode == MODE_DEAD ? 0 : v[i];
                double amps_ = volts / 4.9;
                if (sense_mode == MODE_INVERTED)
                    amps_ = -amps_;
                p[i * 2] = quantize(amps_, 3.75);
                p[i * 2 + 1] = quantize(volts, 14.0);
            }
            rx->progress += 8;
            if (rx->progress == rx->ring[0].length) {
                memmove(rx->ring, rx->ring + 1, 3 * sizeof(rx->ring[0]));
                rx->count--;
                rx->progress = 0;
                rx->reports++;
                assert(rx->reports <= 4);
            }
        }
    }
}

static void advance(uint64_t us)
{
    uint64_t rate = sut.rate ? sut.rate : 48000;
    uint64_t total = us * rate + frac_frames;
    now += us;
    frac_frames = total % 1000000;
    hw_frames(total / 1000000);
}

static uint32_t io_read(void *cookie, uint64_t address)
{
    (void)cookie;
    if (address >= FAKE_I2C0 && address < FAKE_I2C0 + 0x4000)
        return bus_read(&buses[0], address - FAKE_I2C0);
    if (address >= FAKE_I2C1 && address < FAKE_I2C1 + 0x4000)
        return bus_read(&buses[1], address - FAKE_I2C1);
    if (address >= FAKE_ADMAC && address < FAKE_ADMAC + 0x34000)
        return admac_read(address - FAKE_ADMAC);
    if (address >= FAKE_MCA && address < FAKE_MCA + 0x18000) {
        uint32_t off = (uint32_t)((address - FAKE_MCA) % MCA_STRIDE);
        uint32_t v = reg_get(address);
        if (off == MCA_TXA + SERDES_STATUS || off == MCA_RXB + SERDES_STATUS) {
            reg_set(address, v & ~SERDES_RST);   /* reset completes at once */
            return v & ~SERDES_RST;
        }
        return v;
    }
    return reg_get(address);
}

static void io_write(void *cookie, uint64_t address, uint32_t value)
{
    (void)cookie;
    if (address >= FAKE_I2C0 && address < FAKE_I2C0 + 0x4000) {
        bus_write(&buses[0], address - FAKE_I2C0, value);
        return;
    }
    if (address >= FAKE_I2C1 && address < FAKE_I2C1 + 0x4000) {
        bus_write(&buses[1], address - FAKE_I2C1, value);
        return;
    }
    if (address >= FAKE_ADMAC && address < FAKE_ADMAC + 0x34000) {
        admac_write(address - FAKE_ADMAC, value);
        return;
    }
    reg_set(address, value);
}

static uint64_t io_now(void *cookie) { (void)cookie; return now; }
static void io_delay(void *cookie, uint32_t us) { (void)cookie; advance(us); }
static void io_cache(void *cookie, uint64_t a, uint32_t n) { (void)cookie; (void)a; (void)n; }

static uint8_t *tx_memory, *sense_memory;

static struct vinix_apple_speakers_config machine_config(void)
{
    struct vinix_apple_speakers_config c;
    memset(&c, 0, sizeof(c));
    c.mca_clusters = FAKE_MCA;
    c.mca_cluster_count = 6;
    c.mca_switch = FAKE_SWITCH;
    c.admac = FAKE_ADMAC;
    c.admac_channels = 24;
    c.nco = FAKE_NCO;
    c.nco_channels = 5;
    c.nco_ref_hz = 900000000;
    c.tx_cluster = 1;
    c.sense_cluster = 2;
    c.tx_nco = 1;
    c.sense_nco = 2;
    c.tx_dma = TX_CH;
    c.sense_dma = SENSE_CH;
    c.port_mask = 3;
    c.i2c[0] = FAKE_I2C0;
    c.i2c[1] = FAKE_I2C1;
    c.i2c_ref_hz = 24000000;
    c.amp_address[0] = 0x31;
    c.amp_address[1] = 0x34;
    c.imon_slot[0] = 0;
    c.vmon_slot[0] = 2;
    c.imon_slot[1] = 4;
    c.vmon_slot[1] = 6;
    c.shutdown_gpio = FAKE_GPIO;
    c.tx_buffer = c.tx_iova = (uint64_t)(uintptr_t)tx_memory;
    c.tx_bytes = 16384;
    c.sense_buffer = c.sense_iova = (uint64_t)(uintptr_t)sense_memory;
    c.sense_bytes = 32768;
    return c;
}

static void boot(void)
{
    struct vinix_apple_speakers_config c;
    memset(reg_key, 0, sizeof(reg_key));
    memset(reg_val, 0, sizeof(reg_val));
    memset(chans, 0, sizeof(chans));
    memset(buses, 0, sizeof(buses));
    memset(&sut, 0, sizeof(sut));
    amp_defaults(&amps[0]);
    amp_defaults(&amps[1]);
    amps[0].address = 0x31;
    amps[1].address = 0x34;
    amps[0].resets = amps[1].resets = 0;
    amps[0].fail_writes = amps[1].fail_writes = 0;
    amps[0].writes_to_dvc = amps[1].writes_to_dvc = 0;
    buses[0].amp = &amps[0];
    buses[1].amp = &amps[1];
    if (!tx_memory) {
        tx_memory = aligned_alloc(16384, 16384);
        sense_memory = aligned_alloc(16384, 32768);
    }
    memset(tx_memory, 0x55, 16384);
    memset(sense_memory, 0x55, 32768);
    now = 1000000;
    frac_frames = 0;
    played_count = 0;
    sense_mode = MODE_NORMAL;
    sut.io = (struct spk_io){io_read, io_write, io_now, io_delay, io_cache, io_cache, 0};
    c = machine_config();
    assert(init(&sut, &c) == 1);
}

/* ---- the program playing sound ---- */

static double tone_phase;
static double tone_level = 0.5;
static double tone_hz = 1000;

static uint32_t feed(uint32_t max_bytes)
{
    uint32_t total = 0;
    for (;;) {
        uint32_t n, i;
        uint8_t *p = reserve(&sut, &n);
        if (!n || total >= max_bytes) {
            commit(&sut, 0);
            return total;
        }
        if (n > max_bytes - total)
            n = max_bytes - total;
        n &= ~3u;
        if (!n) {
            commit(&sut, 0);
            return total;
        }
        for (i = 0; i < n; i += 4) {
            int16_t v = (int16_t)lrint(sin(tone_phase) * tone_level * 32767);
            tone_phase += 2 * M_PI * tone_hz / sut.rate;
            memcpy(p + i, &v, 2);
            memcpy(p + i + 2, &v, 2);
        }
        commit(&sut, n);
        total += n;
    }
}

/* The V service thread: start when asked, then service every 2 ms. */
static uint32_t pump(uint64_t us, int keep_feeding)
{
    uint32_t flags = 0;
    uint64_t end = now + us;
    while (now < end) {
        if (keep_feeding)
            feed(~0u);
        if (wants_start(&sut)) {
            uint32_t mask = start_clocks(&sut);
            assert(mask == ((1u << 1) | (1u << 2)));
            assert(start_stream(&sut) == 1);
        }
        flags |= service(&sut);
        advance(2000);
    }
    return flags;
}

static int count_events(int code)
{
    uint32_t i;
    int n = 0;
    for (i = 0; i < sut.event_count; i++)
        if (sut.events[(sut.event_head + i) % MAX_EVENTS].code == code)
            n++;
    return n;
}

static void clear_events(void)
{
    struct speaker_event e;
    while (take_event(&sut, &e)) {
    }
}

/* ---- reference model: speakersafetyd's Speaker, in doubles ---- */

struct reference {
    double coil, magnet, coil_hyst, magnet_hyst, gain, min_gain;
};

static void reference_init(struct reference *r)
{
    double max_pwr = (120.0 - 50.0) / (36.0 + 29.0);
    double peak_pwr = pow(10.0, 16.0 / 10.0) / 4.9 * 2.0;
    r->coil = 120.0 - 20.0 - 1.0;
    r->magnet = 50.0 + (r->coil - 50.0) * (36.0 / (36.0 + 29.0));
    r->coil_hyst = r->magnet_hyst = 0;
    r->gain = 0;
    r->min_gain = fmin(10.0 * log10(max_pwr / peak_pwr), 0.0);
}

static void reference_run(struct reference *r, const int16_t *buf, uint32_t frames, int vs, int is,
    double rate)
{
    double step = 1.0 / rate;
    double alpha_coil = step / (2.4 + step), alpha_magnet = step / (80.0 + step);
    double temp, reduction;
    uint32_t f;
    for (f = 0; f < frames; f++) {
        double v = buf[f * 4 + vs] / 32768.0 * 14.0;
        double i = buf[f * 4 + is] / 32768.0 * 3.75;
        double p = v * i;
        double coil_target = r->magnet + p * 29.0;
        double magnet_target = 50.0 + p * 36.0;
        r->coil = coil_target * alpha_coil + r->coil * (1 - alpha_coil);
        r->magnet = magnet_target * alpha_magnet + r->magnet * (1 - alpha_magnet);
    }
    r->coil_hyst = fmin(fmax(r->coil_hyst, r->coil), r->coil + 5.0);
    r->magnet_hyst = fmin(fmax(r->magnet_hyst, r->magnet), r->magnet + 5.0);
    temp = fmax(r->coil_hyst, r->magnet_hyst);
    reduction = (temp - (120.0 - 20.0)) / 20.0;
    r->gain = r->min_gain * fmax(reduction, 0.0);
    if (r->gain > -0.01)
        r->gain = 0;
}

static void reference_skip(struct reference *r, double t)
{
    double c = r->coil - 50.0, m = r->magnet - 50.0;
    double eta = 1.0 / (1.0 - 2.4 / 80.0);
    double a = exp(-t / 2.4) * (c - eta * m);
    double b = exp(-t / 80.0) * m;
    r->coil = 50.0 + a + b * eta;
    r->magnet = 50.0 + b;
}

static double q32_to_c(int64_t v) { return (double)v / 4294967296.0; }

/* ---- tests ---- */

static void test_fixed_point_math(void)
{
    uint64_t x;
    int32_t mdb;
    for (x = 1; x < (1ull << 62); x = x * 3 + 7) {
        double want = log2((double)x);
        double got = log2_q16(x) / 65536.0;
        assert(fabs(got - want) < 1e-4);
    }
    for (mdb = -110000; mdb <= 20000; mdb += 137) {
        double want = pow(10.0, mdb / 10000.0);
        double got = db_to_power_q32(mdb) / 4294967296.0;
        assert(fabs(got - want) <= want * 2e-4 + 1e-9);
    }
    {
        struct reference r;
        reference_init(&r);
        assert(abs(min_gain_mdb() - (int32_t)lrint(r.min_gain * 1000)) <= 3);
        assert(min_gain_mdb() < -11700 && min_gain_mdb() > -11900);
    }
    tests++;
}

/* The LFSR divisor encoding, against Linux's precomputed tables. */
static void test_nco(void)
{
    uint16_t fwd[LFSR_SIZE], inv[LFSR_SIZE];
    uint32_t state = LFSR_INIT, div, rates[2] = {12288000, 11289600}, r;
    int i;
    for (i = LFSR_SIZE - 1; i > 0; i--) {
        state = lfsr_step(state);
        fwd[i] = (uint16_t)state;
        inv[state] = (uint16_t)i;
    }
    fwd[0] = inv[0] = 0;
    for (div = 8; div < 4 * (2 + LFSR_SIZE); div++) {
        uint32_t want = ((uint32_t)fwd[div / 4 - 2] << 2) | (div % 4);
        assert(nco_div_register(div) == want);
    }
    boot();
    for (r = 0; r < 2; r++) {
        uint64_t base = FAKE_NCO + NCO_STRIDE;
        uint32_t reg, inc1, inc2, incbase, d;
        double got;
        assert(nco_set_rate(&sut, 1, rates[r]) == 0);
        reg = reg_get(base + NCO_DIV);
        inc1 = reg_get(base + NCO_INC1);
        inc2 = reg_get(base + NCO_INC2);
        d = (inv[(reg >> 2) & 0x7ff] + 2u) * 4u + (reg & 3);
        incbase = inc1 - inc2;
        got = 900000000.0 * 2 * incbase / ((double)d * incbase + inc1);
        assert(fabs(got - rates[r]) < 1.0);
        assert(reg_get(base + NCO_ACCINIT) == 1u << 31);
    }
    tests++;
}

static void test_amplifier_setup(void)
{
    int i;
    boot();
    for (i = 0; i < 2; i++) {
        uint8_t *r = amps[i].regs;
        assert(amps[i].resets == 1);
        assert((r[TAS_PLAY_CFG0] & 0x1f) == AMP_LEVEL);
        assert(r[TAS_PLAY_CFG2] == ATT_MUTE);
        assert((r[TAS_PWR_CTRL] & 0x0f) == PWR_SHUTDOWN);
        assert(r[TAS_TDM1] == 0x03);
        assert((r[TAS_TDM2] & 0x3f) == 0x12);
        assert(r[TAS_TDM3] == (i ? 0x11 : 0x00));
        assert(r[0x0e] == 0x13);                 /* reset value, as Linux leaves it */
        assert(r[TAS_TDM5] == (i ? 0x46 : 0x42));
        assert(r[TAS_TDM6] == (i ? 0x44 : 0x40));
    }
    assert((reg_get(FAKE_GPIO) & (GPIO_MODE_MASK | GPIO_DATA)) == (GPIO_MODE_OUT | GPIO_DATA));
    assert(buses[0].ctl == (CTL_MTR | CTL_MRR | CTL_UJM | CTL_EN | 15));
    assert(buses[1].ctl == buses[0].ctl);
    assert(reg_get(FAKE_ADMAC + CHAN_BASE(TX_CH) + CHAN_CARVEOUT) == SRAM_BLOCK << 16);
    assert((reg_get(FAKE_ADMAC + CHAN_BASE(TX_CH) + CHAN_BUS_WIDTH) & 0xff) == 0x11);
    assert((reg_get(FAKE_ADMAC + CHAN_BASE(SENSE_CH) + CHAN_BUS_WIDTH) & 0xff) == 0x21);
    assert(count_events(SPK_EV_AMP) == 2);

    /* An amplifier that does not answer fails init and drops the line. */
    memset(&sut, 0, sizeof(sut));
    amps[1].address = 0x35;
    sut.io = (struct spk_io){io_read, io_write, io_now, io_delay, io_cache, io_cache, 0};
    {
        struct vinix_apple_speakers_config c = machine_config();
        assert(init(&sut, &c) == 0);
    }
    assert(!(reg_get(FAKE_GPIO) & GPIO_DATA));
    tests++;
}

static void test_stream_registers(void)
{
    uint64_t tx = FAKE_MCA + MCA_STRIDE, sense = FAKE_MCA + 2 * MCA_STRIDE;
    uint32_t p;
    boot();
    assert(configure(&sut, 48000) == 1);
    feed(3 * TX_PERIOD_BYTES);
    assert(wants_start(&sut));
    assert(start_clocks(&sut) == 6);
    assert(start_stream(&sut) == 1);
    assert((reg_get(tx + MCA_TXA + TX_CONF) & 0x7ffff) ==
        (7 | CONF_WIDTH_32 | (2u << 16) | CONF_UNK1 | CONF_UNK2 | CONF_UNK3));
    assert(reg_get(tx + MCA_TXA + TX_BITSTART) == 1);
    assert(reg_get(tx + MCA_TXA + TX_SLOTMASK + 4) == ~3u);
    assert(reg_get(tx + MCA_TXA + TX_SLOTMASK + 0xc) == ~0xffu);
    assert(reg_get(tx + MCA_TXA + SERDES_STATUS) == SERDES_EN);
    assert(reg_get(FAKE_SWITCH + 0x8000) == 0x205050);
    assert(reg_get(tx + MCA_SYNCGEN_HI) == 127 && reg_get(tx + MCA_SYNCGEN_LO) == 127);
    assert(reg_get(tx + MCA_SYNCGEN_SEL) == 2);
    assert(reg_get(tx + MCA_SYNCGEN_STATUS) & MCA_SYNCGEN_EN);
    assert(reg_get(tx + MCA_STATUS) & MCA_MCLK_EN);
    assert(reg_get(tx + MCA_MCLK_CONF) == 0x100);
    for (p = 0; p < 2; p++) {
        uint64_t port = FAKE_MCA + p * MCA_STRIDE;
        assert(reg_get(port + MCA_PORT_DATA_SEL) == 4);
        assert(reg_get(port + MCA_PORT_CLOCK_SEL) == 0x200);
        assert(reg_get(port + MCA_PORT_ENABLES) == 0xe);
    }
    assert((reg_get(sense + MCA_RXB + RX_CONF) & 0x7ffff) ==
        (15 | CONF_WIDTH_16 | (3u << 16) | CONF_UNK1 | CONF_UNK2 | CONF_NO_FEEDBACK));
    assert(reg_get(sense + MCA_RXB + RX_PORT) == 3);
    assert(reg_get(sense + MCA_RXB + RX_SLOTMASK + 4) == ~0xfu);
    assert(reg_get(sense + MCA_SYNCGEN_SEL) == 7);
    assert(reg_get(sense + MCA_RXB + SERDES_STATUS) == SERDES_EN);
    assert(reg_get(FAKE_SWITCH + 0x10000 + 0x4000) == 0x405050);
    assert(reg_get(FAKE_NCO + NCO_STRIDE + NCO_CTRL) & NCO_ENABLE);
    assert(chans[TX_CH].running && chans[SENSE_CH].running);
    assert(chans[TX_CH].count >= 3 && chans[SENSE_CH].count == 4);
    /* This driver polls report rings.  Unlike Asahi's IRQ-driven driver it
     * must not unmask IRQ output 1: the first completed descriptor would
     * otherwise leave a level interrupt asserted with no registered
     * handler. */
    assert(reg_get(FAKE_ADMAC + CHAN_BASE(TX_CH) + CHAN_INTMASK(ADMAC_IRQ_INDEX)) == 0);
    assert(reg_get(FAKE_ADMAC + CHAN_BASE(SENSE_CH) + CHAN_INTMASK(ADMAC_IRQ_INDEX)) == 0);
    assert(amps[0].regs[TAS_PWR_CTRL] == PWR_ACTIVE && amps[1].regs[TAS_PWR_CTRL] == PWR_ACTIVE);
    assert(amps[0].regs[TAS_PLAY_CFG2] == ATT_SAFE);
    assert(amps[0].regs[TAS_TDM0] == 0x06);

    stop(&sut);
    assert(!chans[TX_CH].running && !chans[SENSE_CH].running);
    assert((amps[0].regs[TAS_PWR_CTRL] & 3) == PWR_SHUTDOWN);
    assert(amps[1].regs[TAS_PLAY_CFG2] == ATT_MUTE);
    assert(!(reg_get(tx + MCA_STATUS) & MCA_MCLK_EN));
    assert(!(reg_get(FAKE_NCO + NCO_STRIDE + NCO_CTRL) & NCO_ENABLE));
    assert(reg_get(FAKE_MCA + MCA_PORT_ENABLES) == 0);
    assert(sut.state == ST_IDLE);

    assert(configure(&sut, 44100) == 1);
    feed(3 * TX_PERIOD_BYTES);
    start_clocks(&sut);
    start_stream(&sut);
    assert(amps[1].regs[TAS_TDM0] == 0x26);
    assert(configure(&sut, 32000) == 0);
    tests++;
}

/* What is written comes out, in order, with no gaps while it is kept fed. */
static void test_playback_is_exact(void)
{
    size_t i, first;
    uint32_t flags;
    int16_t *expect;
    uint64_t total;
    boot();
    assert(configure(&sut, 48000) == 1);
    tone_phase = 0.5;   /* no leading zero sample to confuse alignment */
    tone_level = 0.25;
    flags = pump(1000000, 1);
    assert(flags & VINIX_SPK_SERVICE_PROGRESS);
    assert(!(flags & VINIX_SPK_SERVICE_FAULT));
    assert(sut.underruns == 0);
    assert(chans[TX_CH].starved == 0);
    total = sut.written;
    drain(&sut);
    flags = pump(200000, 0);
    assert(flags & VINIX_SPK_SERVICE_DRAINED);
    assert(drained(&sut));
    assert(sut.played >= total);
    /* Regenerate the tone and find it in what was played. */
    expect = malloc(total / 2 * sizeof(*expect));
    tone_phase = 0.5;
    for (i = 0; i < total / 4; i++) {
        int16_t v = (int16_t)lrint(sin(tone_phase) * tone_level * 32767);
        tone_phase += 2 * M_PI * tone_hz / 48000;
        expect[2 * i] = expect[2 * i + 1] = v;
    }
    for (first = 0; first < played_count && played[first] == 0; first++) {
    }
    first &= ~(size_t)1;
    assert(played_count - first >= total / 2);
    assert(memcmp(played + first, expect, total) == 0);
    free(expect);
    tests++;
}

/* Sense that tracks the output lifts the -20 dB hold, gradually. */
static void test_verification_releases_hold(void)
{
    uint64_t start;
    boot();
    configure(&sut, 48000);
    tone_level = 0.3;
    pump(40000, 1);
    assert(sut.state == ST_RUNNING);
    assert(amps[0].regs[TAS_PLAY_CFG2] == ATT_SAFE);
    start = now;
    while (!sut.verified && now - start < 1000000)
        pump(2000, 1);
    assert(sut.verified);
    assert(now - start < 300000);
    assert(count_events(SPK_EV_VERIFIED) == 1);
    assert(amps[0].regs[TAS_PLAY_CFG2] > 30);  /* not a jump */
    pump(400000, 1);
    assert(amps[0].regs[TAS_PLAY_CFG2] == 0 && amps[1].regs[TAS_PLAY_CFG2] == 0);
    assert(sut.live[0] && sut.live[1]);
    tests++;
}

/* A sense path that returns nothing never lifts the hold. */
static void test_dead_sense_keeps_hold(void)
{
    boot();
    sense_mode = MODE_DEAD;
    configure(&sut, 48000);
    tone_level = 0.5;
    pump(2000000, 1);
    assert(!sut.verified);
    assert(amps[0].regs[TAS_PLAY_CFG2] >= ATT_SAFE);
    assert(amps[1].regs[TAS_PLAY_CFG2] >= ATT_SAFE);
    assert(count_events(SPK_EV_DEAD) >= 1);
    assert(sut.state == ST_RUNNING);
    tests++;
}

/* Silence cannot verify: nothing is lifted until real output is measured. */
static void test_silence_does_not_verify(void)
{
    boot();
    configure(&sut, 48000);
    tone_level = 0.0;
    pump(1000000, 1);
    assert(!sut.verified);
    assert(amps[0].regs[TAS_PLAY_CFG2] == ATT_SAFE);
    tests++;
}

/* Sense data that stops arriving restores the hold at once. */
static void test_stale_sense_restores_hold(void)
{
    uint64_t start;
    boot();
    configure(&sut, 48000);
    tone_level = 0.3;
    pump(800000, 1);
    assert(sut.verified && amps[0].regs[TAS_PLAY_CFG2] == 0);
    sense_mode = MODE_STALLED;
    start = now;
    while (amps[0].regs[TAS_PLAY_CFG2] < ATT_SAFE && now - start < 1000000)
        pump(2000, 1);
    assert(amps[0].regs[TAS_PLAY_CFG2] >= ATT_SAFE);
    assert(now - start >= 250000 && now - start < 300000);
    assert(count_events(SPK_EV_STALE) == 1);
    sense_mode = MODE_NORMAL;
    pump(800000, 1);
    assert(sut.verified && amps[0].regs[TAS_PLAY_CFG2] == 0);
    tests++;
}

/* Current flowing the wrong way is impossible: the amplifiers go off. */
static void test_negative_power_faults(void)
{
    uint32_t n;
    boot();
    sense_mode = MODE_INVERTED;
    configure(&sut, 48000);
    tone_level = 0.5;
    pump(200000, 1);
    assert(sut.state == ST_FAULT);
    assert(count_events(SPK_EV_FAULT_POWER) >= 1);
    assert(!(reg_get(FAKE_GPIO) & GPIO_DATA));
    assert((amps[0].regs[TAS_PWR_CTRL] & 3) == PWR_SHUTDOWN);
    assert(!chans[TX_CH].running);
    assert(!reserve(&sut, &n) && n == 0);
    commit(&sut, 0);
    assert(configure(&sut, 48000) == 0);
    assert(service(&sut) == VINIX_SPK_SERVICE_FAULT);
    tests++;
}

/* Loud, sustained output heats the model and the gain comes down. */
static void test_thermal_limiting(void)
{
    struct vinix_apple_speakers_status st;
    int32_t limited_att = 0;
    boot();
    configure(&sut, 48000);
    tone_level = 1.0;
    tone_hz = 200;
    pump(20000000, 1);
    get_status(&sut, &st);
    assert(st.model_gain_mdb < -1000);
    limited_att = amps[0].regs[TAS_PLAY_CFG2];
    assert(limited_att >= (-st.model_gain_mdb + 499) / 500);
    assert(st.coil_mc[0] > 100000 && st.coil_mc[0] < 135000);
    assert(sut.state == ST_RUNNING);
    assert(count_events(SPK_EV_GAIN) >= 1);
    /* It settles below the limit rather than running away. */
    pump(60000000, 1);
    get_status(&sut, &st);
    assert(st.coil_mc[0] < 125000 && st.coil_mc[1] < 125000);
    assert(sut.state == ST_RUNNING);
    tone_hz = 1000;
    tests++;
}

/* The fixed-point model against speakersafetyd's, sample for sample. */
static void test_model_matches_reference(void)
{
    static int16_t chunk[PERIOD_FRAMES * SENSE_CHANNELS];
    struct reference ref[2];
    uint32_t k, f, i;
    uint64_t seed = 12345;
    boot();
    sut.rate = 48000;
    model_rate(&sut);
    reference_init(&ref[0]);
    reference_init(&ref[1]);
    int limited = 0;
    for (k = 0; k < 48000 * 90 / PERIOD_FRAMES; k++) {
        double burst = (k / 400) % 2 ? 0.9 : 0.15;
        for (f = 0; f < PERIOD_FRAMES; f++) {
            for (i = 0; i < 2; i++) {
                double v, a;
                seed = seed * 6364136223846793005ull + 1442695040888963407ull;
                /* About 1 W in the bursts: into the limiting range, short
                 * of the fault. */
                v = sin((k * PERIOD_FRAMES + f) * 0.05 * (i + 1)) * burst * 14.0 * 0.25;
                v += ((double)(seed >> 40) / (1 << 24) - 0.5) * 0.2;
                a = v / 4.9 * (1.0 + 0.1 * i);
                chunk[f * 4 + i * 2] = quantize(a, 3.75);
                chunk[f * 4 + i * 2 + 1] = quantize(v, 14.0);
            }
        }
        for (i = 0; i < 2; i++) {
            int32_t value = 0;
            int code = model_run(&sut, i, chunk, PERIOD_FRAMES, &value);
            assert(code == 0);
            reference_run(&ref[i], chunk, PERIOD_FRAMES, (int)i * 2 + 1, (int)i * 2, 48000);
            assert(fabs(q32_to_c(sut.model[i].coil) - ref[i].coil) < 0.005);
            assert(fabs(q32_to_c(sut.model[i].magnet) - ref[i].magnet) < 0.005);
            assert(abs(sut.model[i].gain_mdb - (int32_t)lrint(ref[i].gain * 1000)) <= 20);
            limited |= sut.model[i].gain_mdb < -1000;
        }
    }
    assert(limited);  /* the comparison covered the limiting range */
    /* Cooling over idle gaps, against the closed form. */
    {
        double gaps[] = {0.01, 0.5, 3, 30, 600, 36000};
        for (k = 0; k < sizeof(gaps) / sizeof(gaps[0]); k++) {
            model_cool(&sut, (uint64_t)(gaps[k] * 48000));
            for (i = 0; i < 2; i++) {
                reference_skip(&ref[i], (double)(uint64_t)(gaps[k] * 48000) / 48000);
                if (getenv("SPK_DEBUG"))
                    fprintf(stderr, "gap %g spk %u coil %.6f ref %.6f magnet %.6f ref %.6f\n",
                        gaps[k], i, q32_to_c(sut.model[i].coil), ref[i].coil,
                        q32_to_c(sut.model[i].magnet), ref[i].magnet);
                assert(fabs(q32_to_c(sut.model[i].coil) - ref[i].coil) < 0.005);
                assert(fabs(q32_to_c(sut.model[i].magnet) - ref[i].magnet) < 0.005);
            }
        }
        assert(fabs(q32_to_c(sut.model[0].coil) - 50.0) < 0.01);
    }
    tests++;
}

/* A runaway reading past limit + headroom shuts everything down. */
static void test_overtemperature_faults(void)
{
    static int16_t chunk[PERIOD_FRAMES * SENSE_CHANNELS];
    uint32_t f, k;
    int code = 0;
    boot();
    configure(&sut, 48000);
    tone_level = 0.3;
    pump(100000, 1);
    for (f = 0; f < PERIOD_FRAMES; f++) {
        chunk[f * 4 + 0] = 32767;
        chunk[f * 4 + 1] = 32767;
        chunk[f * 4 + 2] = 0;
        chunk[f * 4 + 3] = 0;
    }
    for (k = 0; k < 10000 && !code; k++) {
        int32_t value = 0;
        code = model_run(&sut, 0, chunk, PERIOD_FRAMES, &value);
        if (code)
            assert(value > 135000);
    }
    assert(code == SPK_EV_FAULT_TEMP);
    tests++;
}

/* A writer that falls behind gets silence, not a repeat of old audio, and a
 * stream left alone that long asks to be stopped. */
static void test_underrun_and_idle(void)
{
    size_t i, before;
    uint32_t flags;
    boot();
    configure(&sut, 48000);
    tone_level = 0.25;
    pump(300000, 1);
    before = played_count;
    flags = pump(500000, 0);
    assert(sut.underruns > 0);
    assert(chans[TX_CH].starved == 0);
    for (i = before + 4 * TX_PERIOD_BYTES; i < played_count; i++)
        assert(played[i] == 0);
    assert(!(flags & VINIX_SPK_SERVICE_IDLE));
    flags = pump(3000000, 0);
    assert(flags & VINIX_SPK_SERVICE_IDLE);
    tests++;
}

/* The volume control scales what is played. */
static void test_software_volume(void)
{
    int16_t *p;
    uint32_t n;
    boot();
    configure(&sut, 48000);
    sut.volume = 50;
    p = (int16_t *)(void *)reserve(&sut, &n);
    assert(n >= 8);
    p[0] = 1000;
    p[1] = -2000;
    p[2] = 32767;
    p[3] = -32768;
    commit(&sut, 8);
    assert(p[0] == 500 && p[1] == -1000 && p[2] == 16383 && p[3] == -16384);
    tests++;
}

/* An I2C write that should have made it quieter and was lost is a fault. */
static void test_lost_attenuation_faults(void)
{
    boot();
    configure(&sut, 48000);
    tone_level = 0.3;
    pump(800000, 1);
    assert(sut.verified && amps[0].regs[TAS_PLAY_CFG2] == 0);
    amps[1].fail_writes = 1;
    sense_mode = MODE_STALLED;
    pump(400000, 1);
    assert(sut.state == ST_FAULT);
    assert(!(reg_get(FAKE_GPIO) & GPIO_DATA));
    assert(count_events(SPK_EV_FAULT_I2C) >= 1);
    tests++;
}

/* A start abandoned after the clocks came up still turns them off. */
static void test_abandoned_start_stops_clocks(void)
{
    uint64_t tx = FAKE_MCA + MCA_STRIDE;
    boot();
    configure(&sut, 48000);
    feed(3 * TX_PERIOD_BYTES);
    assert(start_clocks(&sut));
    assert(reg_get(FAKE_NCO + NCO_STRIDE + NCO_CTRL) & NCO_ENABLE);
    stop(&sut);
    assert(!(reg_get(FAKE_NCO + NCO_STRIDE + NCO_CTRL) & NCO_ENABLE));
    assert(reg_get(FAKE_MCA + MCA_PORT_ENABLES) == 0);
    assert(!(reg_get(tx + MCA_STATUS) & MCA_MCLK_EN));
    configure(&sut, 48000);
    feed(3 * TX_PERIOD_BYTES);
    assert(start_clocks(&sut));
    fault_shutdown(&sut);
    assert(sut.state == ST_FAULT && !sut.clocks_on);
    assert(!(reg_get(FAKE_NCO + NCO_STRIDE + NCO_CTRL) & NCO_ENABLE));
    assert(!(reg_get(FAKE_GPIO) & GPIO_DATA));
    tests++;
}

/* Time between streams cools the model; time playing never does. */
static void test_idle_cooling_between_streams(void)
{
    int64_t before;
    boot();
    configure(&sut, 48000);
    tone_level = 0.3;
    pump(500000, 1);
    stop(&sut);
    before = sut.model[0].coil;
    advance(60000000);
    configure(&sut, 48000);
    feed(3 * TX_PERIOD_BYTES);
    start_clocks(&sut);
    assert(sut.model[0].coil < before - Q32(5));
    clear_events();
    tests++;
}

int main(void)
{
    test_fixed_point_math();
    test_nco();
    test_amplifier_setup();
    test_stream_registers();
    test_playback_is_exact();
    test_verification_releases_hold();
    test_dead_sense_keeps_hold();
    test_silence_does_not_verify();
    test_stale_sense_restores_hold();
    test_negative_power_faults();
    test_thermal_limiting();
    test_model_matches_reference();
    test_overtemperature_faults();
    test_underrun_and_idle();
    test_software_volume();
    test_lost_attenuation_faults();
    test_idle_cooling_between_streams();
    test_abandoned_start_stops_clocks();
    free(played);
    printf("apple-speakers: %u tests passed\n", tests);
    return 0;
}
