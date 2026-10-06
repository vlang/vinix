// SPDX-License-Identifier: GPL-2.0-only
#include "../../kernel/c/apple_speakers.h"
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
#define CHAN_CTL            0x00
#define CHAN_RST_RINGS      (1u << 0)
#define CHAN_BUS_WIDTH      0x40
#define CHAN_CARVEOUT       0x50
#define CHAN_FIFOCTL        0x54
#define CHAN_RESIDUE        0x64
#define CHAN_DESC_RING      0x70
#define CHAN_REPORT_RING    0x74
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

#define T_AMBIENT_M    50000
#define T_HYSTERESIS_M 5000
#define T_WINDOW_M     20000

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

uint32_t vinix_spk_core_rd(struct speakers *s, uint64_t address);
void vinix_spk_core_wr(struct speakers *s, uint64_t address, uint32_t value);
void vinix_spk_core_modify(struct speakers *s, uint64_t address, uint32_t mask, uint32_t value);
uint64_t vinix_spk_core_now_us(struct speakers *s);
void vinix_spk_core_delay_us(struct speakers *s, uint32_t us);
void vinix_spk_core_post(struct speakers *s, int32_t code, int32_t a, int32_t b);
int vinix_spk_core_take_event(struct speakers *s, struct speaker_event *out);
int64_t vinix_spk_core_mul_q48(int64_t a, int64_t b);
uint64_t vinix_spk_core_mul_q32u(uint64_t a, uint64_t b);
int64_t vinix_spk_core_log2_q16(uint64_t x);
uint64_t vinix_spk_core_db_to_power_q32(int32_t mdb);
uint64_t vinix_spk_core_i2c_base(struct speakers *s, int amp);
void vinix_spk_core_i2c_reset(struct speakers *s, int amp);
int vinix_spk_core_i2c_clear(struct speakers *s, int amp);
int vinix_spk_core_i2c_wait(struct speakers *s, int amp);
int vinix_spk_core_i2c_write(struct speakers *s, int amp, uint8_t reg, uint8_t value);
int vinix_spk_core_i2c_read(struct speakers *s, int amp, uint8_t reg, uint8_t *value);
int vinix_spk_core_tas_update(struct speakers *s, int amp, uint8_t reg, uint8_t mask, uint8_t value);
int vinix_spk_core_tas_expect(struct speakers *s, int amp, uint8_t reg, uint8_t mask, uint8_t value);
int vinix_spk_core_tas_power(struct speakers *s, int amp, uint8_t mode);
int vinix_spk_core_tas_init(struct speakers *s, int amp);
int vinix_spk_core_tas_set_rate(struct speakers *s, int amp);
void vinix_spk_core_sdz_set(struct speakers *s, int enabled);
uint32_t vinix_spk_core_lfsr_step(uint32_t state);
uint32_t vinix_spk_core_nco_div_register(uint32_t div);
int vinix_spk_core_nco_set_rate(struct speakers *s, uint32_t channel, uint32_t rate);
void vinix_spk_core_nco_enable(struct speakers *s, uint32_t channel, int enable);
uint64_t vinix_spk_core_cluster(struct speakers *s, uint32_t n);
int vinix_spk_core_cluster_on(struct speakers *s, uint32_t n);
void vinix_spk_core_cluster_off(struct speakers *s, uint32_t n);
void vinix_spk_core_mca_set_format(struct speakers *s, uint32_t n);
uint32_t vinix_spk_core_adapter_value(uint32_t channels);
void vinix_spk_core_mca_configure_tx(struct speakers *s);
void vinix_spk_core_mca_configure_sense(struct speakers *s);
void vinix_spk_core_mca_ports(struct speakers *s, int on);
uint32_t vinix_spk_core_lowest_port(uint32_t mask);
void vinix_spk_core_serdes_reset(struct speakers *s, uint32_t n, uint32_t unit, uint32_t conf);
void vinix_spk_core_serdes_enable(struct speakers *s, uint32_t n, uint32_t unit, int enable);
uint64_t vinix_spk_core_chan(struct speakers *s, uint32_t ch);
int vinix_spk_core_admac_setup(struct speakers *s, uint32_t ch, uint32_t frame);
void vinix_spk_core_admac_reset_rings(struct speakers *s, uint32_t ch);
void vinix_spk_core_admac_descriptor(struct speakers *s, uint32_t ch, uint64_t iova, uint32_t length);
void vinix_spk_core_admac_run(struct speakers *s, uint32_t ch, int run);
uint32_t vinix_spk_core_admac_reap(struct speakers *s, uint32_t ch);
void vinix_spk_core_model_rate(struct speakers *s);
void vinix_spk_core_model_reset(struct speakers *s);
void vinix_spk_core_model_cool(struct speakers *s, uint64_t samples);
void vinix_spk_core_model_idle(struct speakers *s);
int32_t vinix_spk_core_min_gain_mdb(void);
int vinix_spk_core_model_run(struct speakers *s, uint32_t n, const int16_t *frames, uint32_t count,
    int32_t *fault_value);
int32_t vinix_spk_core_model_gain(struct speakers *s);
int vinix_spk_core_set_attenuation(struct speakers *s, int32_t att);
void vinix_spk_core_apply_policy(struct speakers *s, uint64_t now);
uint8_t *vinix_spk_core_tx_at(struct speakers *s, uint64_t position);
void vinix_spk_core_tx_submit(struct speakers *s);
uint64_t *vinix_spk_core_energy_slot(struct speakers *s, uint64_t period);
void vinix_spk_core_tx_account(struct speakers *s);
void vinix_spk_core_tx_pad(struct speakers *s);
uint32_t vinix_spk_core_tx_service(struct speakers *s, uint64_t now);
uint64_t vinix_spk_core_sense_iova(struct speakers *s, uint64_t period);
void vinix_spk_core_sense_submit(struct speakers *s);
void vinix_spk_core_expected_energy(struct speakers *s, uint64_t k, uint64_t out[SPK_COUNT]);
void vinix_spk_core_check_liveness(struct speakers *s, uint64_t k, const int16_t *frames);
void vinix_spk_core_sense_service(struct speakers *s, uint64_t now);
void vinix_spk_core_reset_positions(struct speakers *s);
void vinix_spk_core_hardware_stop(struct speakers *s);
void vinix_spk_core_fault_shutdown(struct speakers *s);
int vinix_spk_core_configure(struct speakers *s, uint32_t rate);
int vinix_spk_core_wants_start(struct speakers *s);
int vinix_spk_core_start_clocks(struct speakers *s);
int vinix_spk_core_start_stream(struct speakers *s);
void vinix_spk_core_stop(struct speakers *s);
uint32_t vinix_spk_core_service(struct speakers *s);
uint32_t vinix_spk_core_room(struct speakers *s);
uint8_t *vinix_spk_core_reserve(struct speakers *s, uint32_t *length);
void vinix_spk_core_commit(struct speakers *s, uint32_t bytes);
void vinix_spk_core_drain(struct speakers *s);
int vinix_spk_core_drained(struct speakers *s);
int vinix_spk_core_c_init(struct speakers *s, const struct vinix_apple_speakers_config *cfg);
void vinix_spk_core_get_status(struct speakers *s, struct vinix_apple_speakers_status *out);
uint32_t vinix_spk_core_kernel_read32(void *cookie, uint64_t address);
void vinix_spk_core_kernel_write32(void *cookie, uint64_t address, uint32_t value);
uint64_t vinix_spk_core_kernel_now_us(void *cookie);
void vinix_spk_core_kernel_delay_us(void *cookie, uint32_t us);
void vinix_spk_core_kernel_clean(void *cookie, uint64_t address, uint32_t length);
void vinix_spk_core_kernel_invalidate(void *cookie, uint64_t address, uint32_t length);
int vinix_spk_core_kernel_power(void *cookie, uint32_t cluster, int on);
