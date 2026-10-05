/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_BRCM_M1_H
#define VINIX_BRCM_M1_H
#include "brcm_wifi.h"
/* Private, kernel-only platform contract. All register pointers are mapped
 * Device memory. PCI window is the DT non-prefetchable 32-bit range. */
struct bw_m1_plan {
    uint64_t config, config_size, rc, port, phy, gpio, dart;
    uint64_t window, window_bus, window_size;
    uint64_t pool_cpu, pool_physical, tables_cpu, tables_physical;
    uint32_t sid, gpio_active_low;
    const uint8_t *calibration, *seed;
    size_t calibration_len, seed_len;
    uint8_t mac[6];
    char antenna[16];
};
#define BW_IOCTL_STATUS 0x5700u
#define BW_IOCTL_UPLOAD 0x5701u
#define BW_IOCTL_BOOT   0x5702u
#define BW_IOCTL_JOIN   0x5703u
#define BW_IOCTL_STOP   0x5704u
#define BW_IOCTL_RADIO  0x5705u
#define BW_IOCTL_SCAN   0x5706u
#define BW_IOCTL_NETWORKS 0x5707u
#define BW_STATUS_SIZE 256u
#define BW_UPLOAD_SIZE 4112u
#define BW_JOIN_SIZE 104u
#define BW_MANIFEST_SIZE 128u
/* Fixed-size UAPI byte arrays, no embedded pointers. Integer fields LE.
 * STATUS: state@0,error@4,revision@8,dart_error@12,rx64@16,tx64@24,
 *         MAC@32,OTP module@40,vendor@56,revision@72,silicon@88,
 *         antenna@104,board@120 (32 bytes),drops64@152,
 *         radio_on@160,scanning@164,network_count@168,scan_error@172.
 * UPLOAD: part@0,total@4,offset@8,count@12,data[4096]@16.
 *         part 0 firmware,1 NVRAM text,2 CLM,3 TXCAP.
 * BOOT: revision@0,module[16]@8,vendor[16]@24,modrev[16]@40,
 *       antenna[16]@56,board[32]@72; other bytes MUST be zero.
 * JOIN: SSID length32@0,passphrase length32@4,SSID[32]@8,password[64]@40.
 * RADIO: enabled32@0; zero takes the firmware radio down, one brings it up.
 * SCAN: no argument; starts an asynchronous all-channel scan.
 * NETWORKS: version32@0,count32@4,scanning32@8,error32@12, then 32
 *           entries of 48 bytes: ssid_len8@0,secure8@1,channel16@2,
 *           rssi16@4,BSSID[6]@8,SSID[32]@16. Unused entries are zero.
 */
int brcm_m1_prepare(const struct bw_m1_plan *);
int brcm_m1_status(uint8_t *output);
int brcm_m1_upload(const uint8_t *chunk);
int brcm_m1_boot(const uint8_t *manifest);
int brcm_m1_join(const uint8_t *request);
int brcm_m1_radio(const uint8_t *request);
int brcm_m1_scan(void);
int brcm_m1_networks(uint8_t *output);
int brcm_m1_poll(void);
int brcm_m1_read(uint8_t *, size_t);
int brcm_m1_write(const uint8_t *, size_t);
void brcm_m1_stop(void);
#endif
