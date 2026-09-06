/* SPDX-License-Identifier: ISC
 * Experimental BCM4378 FullMAC PCIe driver for Vinix.
 * The caller owns the PCIe host, DART mapping, firmware files and serialization.
 * Firmware/DMA addresses are never CPU pointers. See tests/m1-wifi/README.md.
 */
#ifndef VINIX_BRCM_WIFI_H
#define VINIX_BRCM_WIFI_H
#include <stddef.h>
#include <stdint.h>

#define BW_POOL_MIN (4u * 1024u * 1024u)
#define BW_MAX_FRAME 1514u
#define BW_RX_COUNT 512u
#define BW_TX_COUNT 128u
#define BW_CTL_COUNT 8u
#define BW_CTL_SIZE 8192u
#define BW_PACKET_COUNT (BW_RX_COUNT + 2u * BW_CTL_COUNT)
#define BW_MAX_CORES 32u

enum bw_space { BW_CONFIG, BW_REGS, BW_TCM };
enum bw_state { BW_OFF, BW_CHIP, BW_BOOTING, BW_READY, BW_JOINING, BW_LINK, BW_FAULT };
enum bw_error { BW_OK = 0, BW_EINVAL = -1, BW_ENOSPC = -2, BW_EIO = -3,
    BW_ETIME = -4, BW_EPROTO = -5, BW_ENOTSUP = -6, BW_ENOLINK = -7 };

struct bw_ops {
    uint32_t (*read)(void *, unsigned space, uint32_t offset, unsigned width);
    void (*write)(void *, unsigned space, uint32_t offset, unsigned width, uint32_t value);
    uint64_t (*time_us)(void *);
    void (*delay_us)(void *, uint32_t);
    /* DMA sync is required even on machines where ordinary RAM is coherent.
     * to_device: clean/invalidate before publishing ownership to the device.
     * to_cpu: invalidate after observing a device-written completion/index.
     * Each allocated area is isolated on at least 128-byte cache boundaries. */
    void (*sync)(void *, void *cpu, size_t length, int to_device);
    /* Must disable PCI bus mastering and drain/quiesce before return.
     * The driver NEVER frees or reuses the DMA pool after a fatal error. */
    void (*stop_dma)(void *);
    void (*receive)(void *, const uint8_t *ethernet, size_t length);
};
struct bw_core { uint32_t base, wrap; uint16_t id; uint8_t rev; };
struct bw_mem { uint8_t *cpu; uint64_t dma; size_t len; };
struct bw_ring {
    struct bw_mem mem;
    uint32_t wi, ri;
    uint16_t count, item, read, write;
    uint8_t dma_indices;
};
struct bw_packet { struct bw_mem mem; uint32_t token; uint8_t owner, kind; };
struct bw_otp { char module[16], vendor[16], revision[16], silicon[16]; };
struct bw_firmware {
    const uint8_t *code, *nvram, *clm, *txcap, *calibration, *seed;
    size_t code_len, nvram_len, clm_len, txcap_len, calibration_len, seed_len;
    uint8_t silicon_revision;
    uint8_t mac[6];
};
struct bw_device {
    struct bw_ops ops;
    void *cookie;
    enum bw_state state;
    int error;
    uint32_t regs_size, tcm_size, ram_base, ram_size, shared, flags, rx_offset;
    uint32_t ring_info, h2d_mb, d2h_mb;
    uint16_t submission_count, completion_count, max_rx;
    uint8_t revision, pcie_revision, version, index_size, mb_via_ctl;
    struct bw_core cores[BW_MAX_CORES];
    unsigned core_count;
    struct bw_otp otp;
    struct bw_mem pool, indices[4];
    size_t allocated;
    struct bw_ring rings[6]; /* five common rings and station best-effort TX */
    struct bw_packet rx[BW_PACKET_COUNT], tx[BW_TX_COUNT];
    struct bw_mem request;
    uint32_t next_token;
    uint16_t transaction, reply_length;
    int16_t reply_status;
    uint32_t reply_command;
    uint8_t request_busy, reply_ready, flow_pending, flow_open;
    uint8_t associated, keyed, mac[6], bssid[6];
    uint64_t join_deadline, flow_deadline, rx_frames, tx_frames, bad_completions;
    uint8_t reply[BW_CTL_SIZE];
};

/* Initialize software only. Pool must already be isolated by DART; bus master
 * remains disabled until platform code has established that isolation. */
int bw_init(struct bw_device *, const struct bw_ops *, void *cookie,
    void *pool_cpu, uint64_t pool_dma, size_t pool_len,
    uint32_t registers_size, uint32_t tcm_size);
/* Probe only accesses the declared endpoint. Reads core inventory and OTP;
 * it does not upload firmware or turn on the radio. */
int bw_probe(struct bw_device *);
int bw_start(struct bw_device *, const struct bw_firmware *);
int bw_join_wpa2(struct bw_device *, const uint8_t *ssid, size_t ssid_len,
    const uint8_t *passphrase, size_t passphrase_len);
int bw_disconnect(struct bw_device *);
int bw_poll(struct bw_device *, unsigned budget);
int bw_transmit(struct bw_device *, const uint8_t *ethernet, size_t length);
void bw_stop(struct bw_device *);

/* Bounded, host-testable parsers. NVRAM input is board-specific text; output
 * includes double NUL, padding, and the Broadcom complement length token. */
int bw_nvram_pack(const uint8_t *, size_t, uint8_t *, size_t, size_t *);
int bw_otp_parse(const uint8_t *, size_t, struct bw_otp *);
const char *bw_state_name(enum bw_state);
#endif
