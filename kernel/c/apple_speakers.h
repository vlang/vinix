/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef VINIX_APPLE_SPEAKERS_H
#define VINIX_APPLE_SPEAKERS_H

#include <stddef.h>
#include <stdint.h>

/* The base M1 MacBook Air (J313) speaker path: two TAS5770L amplifiers fed
 * by the MCA I2S block through ADMAC, with a speaker protection model driven
 * by the amplifiers' own voltage and current sense data.
 *
 * Every address is a mapped kernel virtual address, except the two IOVAs,
 * which are what ADMAC sees through the SIO DART. The V platform layer
 * validates the device tree, powers the blocks and maps them before calling
 * vinix_apple_speakers_init(). All functions are serialized by that layer. */

/* Switches the power domain of MCA cluster `cluster` on or off; 1 on
 * success. The cluster domains are externally clocked and change state only
 * while their clock runs, so the driver calls this itself at the one point in
 * the start and stop sequences where that holds. */
typedef int (*vinix_apple_speakers_power_fn)(uint32_t cluster, int on);

struct vinix_apple_speakers_config {
    uint64_t mca_clusters;      /* MCA reg[0]: one 0x4000 window per cluster */
    uint32_t mca_cluster_count;
    uint64_t mca_switch;        /* MCA reg[1]: DMA adapters */
    uint64_t admac;
    uint32_t admac_channels;
    uint64_t nco;
    uint32_t nco_channels;
    uint32_t nco_ref_hz;

    uint32_t tx_cluster;        /* frontend that serializes playback */
    uint32_t sense_cluster;     /* frontend that captures V/I sense */
    uint32_t tx_nco;            /* clock channels feeding those clusters */
    uint32_t sense_nco;
    uint32_t tx_dma;            /* ADMAC channels: even = TX, odd = RX */
    uint32_t sense_dma;
    uint32_t port_mask;         /* I2S ports wired to the amplifiers */

    uint64_t i2c[2];            /* left, right amplifier buses */
    uint32_t i2c_ref_hz;
    uint8_t amp_address[2];
    uint8_t imon_slot[2];
    uint8_t vmon_slot[2];
    uint64_t shutdown_gpio;     /* pin register of the shared SDZ line */

    uint64_t tx_buffer;         /* CPU address, 16 KiB aligned */
    uint64_t tx_iova;
    uint32_t tx_bytes;
    uint64_t sense_buffer;
    uint64_t sense_iova;
    uint32_t sense_bytes;

    vinix_apple_speakers_power_fn cluster_power;
};

#define VINIX_SPK_SERVICE_RUNNING   1u  /* keep calling service */
#define VINIX_SPK_SERVICE_PROGRESS  2u  /* playback advanced; wake writers */
#define VINIX_SPK_SERVICE_DRAINED   4u  /* everything written has played */
#define VINIX_SPK_SERVICE_FAULT     8u  /* speakers shut down for safety */
#define VINIX_SPK_SERVICE_IDLE     16u  /* only silence for a while: stop */

struct vinix_apple_speakers_status {
    int32_t coil_mc[2];         /* modelled temperatures, milli-degrees C */
    int32_t magnet_mc[2];
    int32_t model_gain_mdb;     /* reduction the model asks for */
    int32_t applied_att;        /* amplifier attenuation, 0.5 dB steps */
    int32_t verified;
    int32_t fault;
    uint64_t underruns;
    uint64_t sense_chunks;
    uint64_t dma_errors;
};

/* 1 on success. Resets and configures both amplifiers, leaves them shut down
 * and muted, and sets up the DMA channels. Nothing plays until start. */
int vinix_apple_speakers_init(const struct vinix_apple_speakers_config *cfg);

/* Prepare for a stream at `rate` Hz, S16_LE stereo. 0 if unsupported. */
int vinix_apple_speakers_configure(uint32_t rate);

/* Stream start, in two halves, each 1 on success: the clocks and the
 * playback cluster, then the amplifiers, DMA and sense capture. The caller
 * stops the stream if either fails. */
int vinix_apple_speakers_start_clocks(void);
int vinix_apple_speakers_start_stream(void);
void vinix_apple_speakers_stop(void);

/* Whether the service loop wants the stream started: enough is queued, or a
 * drain was requested. */
int vinix_apple_speakers_wants_start(void);

/* One pass of the playback, sense and protection loop. */
uint32_t vinix_apple_speakers_service(void);

/* Writer interface. reserve returns a contiguous writable span of the ring
 * (0 bytes when full); commit publishes what was copied into it, applying
 * the software volume. */
uint8_t *vinix_apple_speakers_reserve(uint32_t *length);
void vinix_apple_speakers_commit(uint32_t bytes);
uint32_t vinix_apple_speakers_room(void);
void vinix_apple_speakers_drain(void);
int vinix_apple_speakers_drained(void);
void vinix_apple_speakers_set_volume(uint32_t percent);
int vinix_apple_speakers_running(void);
int vinix_apple_speakers_active(void);   /* configured or running */
int vinix_apple_speakers_faulted(void);
/* A stream that cannot start is a fault too: shut down, stay down. */
void vinix_apple_speakers_fail(void);

void vinix_apple_speakers_get_status(struct vinix_apple_speakers_status *out);

/* Pops the oldest driver event into {code, a, b}; 0 when there is none.
 * Codes: 1 amp found (amp, revision), 2 sense verified, 3 sense stale (ms),
 * 4 sense dead (speaker), 5 model gain (mdB), 6 over temperature (speaker,
 * milli-degrees), 7 negative power (speaker, mW), 8 I2C error (amp, error),
 * 9 DMA error (channel, ring), 10 serializer reset stuck (cluster),
 * 11 cluster power domain did not switch (cluster, on). */
int vinix_apple_speakers_take_event(int32_t out[3]);

#endif
