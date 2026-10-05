// SPDX-License-Identifier: GPL-2.0-or-later
// Borrowed ABI layouts and helper declarations for the media model.
#include "../../kernel/c/apple_ans.h"
#include "../../kernel/c/apple_ans_ext2.h"
#define A_CAP 0x0000u
#define A_INTMS 0x000cu
#define A_CC 0x0014u
#define A_CSTS 0x001cu
#define A_AQA 0x0024u
#define A_ASQ 0x0028u
#define A_ACQ 0x0030u
#define A_ACQ_DB 0x1004u
#define A_IOCQ_DB 0x100cu
#define A_PENDING 0x1210u
#define A_BOOT 0x1300u
#define A_MODE 0x1304u
#define A_UNKNOWN 0x24008u
#define A_LINEAR 0x24908u
#define A_ASQ_DB 0x2490cu
#define A_IOSQ_DB 0x24910u
#define A_TCB_NUM 0x28100u
#define A_ASQ_TCB 0x28108u
#define A_IOSQ_TCB 0x28110u
#define A_INVALIDATE 0x28118u
#define A_TCB_STATUS 0x28120u
#define ASC_CPU 0x44u
#define ASC_RUN (1u << 4)
#define MB_TX_CTRL 0x110u
#define MB_RX_CTRL 0x114u
#define MB_TX0 0x800u
#define MB_TX1 0x808u
#define MB_RX0 0x830u
#define MB_RX1 0x838u
#define BOOT_MAGIC 0xde71ce55u
#define QDEPTH 64u
#define PAGE 4096u
#define ALIGNMENT 16384u
#define ASQ 0x00000u
#define ACQ 0x04000u
#define ATCB 0x08000u
#define IOSQ 0x0c000u
#define IOCQ 0x10000u
#define ITCB 0x14000u
#define PRPL 0x18000u
#define BOUNCE 0x20000u
#define BOUNCE_SIZE 0x10000u
#define GPT_SCRATCH 0x30000u
#define GPT_MAX_BYTES 0x20000u
#define SHARED 0x60000u
#define SHARED_SIZE 0x400000u
#define READY_US 5000000u
#define COMMAND_US 5000000u
#define BOOT_US 10000000u
#define SEND_US 20000u
#define TYPE(t) ((uint64_t)(t) << 52)
#define IOVA_MASK ((UINT64_C(1) << 42) - 1)
#define PM_FLAGS (3u << 8)
#define PM_DISABLE (1u << 10)
#define PM_RESET (1u << 31)

/* Internal errors are stable diagnostics, not userspace errno numbers. */
enum { ANS_OK, ANS_CONFIG, ANS_HANDOFF, ANS_TIMEOUT, ANS_PROTOCOL,
    ANS_FIRMWARE, ANS_SART, ANS_COMPLETION, ANS_CAPABILITY, ANS_NAMESPACE,
    ANS_GPT, ANS_RANGE, ANS_READ_ONLY, ANS_STOPPED };

struct ans_ops {
    uint32_t (*read32)(void *, uint64_t);
    void (*write32)(void *, uint64_t, uint32_t);
    uint64_t (*read64)(void *, uint64_t);
    void (*write64)(void *, uint64_t, uint64_t);
    uint64_t (*now)(void *);
    void (*delay)(void *, unsigned);
    /* for_cpu=0: clean/invalidate before DMA; 1: invalidate after DMA.
     * Both include a full completion barrier. All buffers are exclusive. */
    void (*sync)(void *, void *, size_t, int for_cpu);
};
struct ans_partition {
    uint64_t start, blocks, attributes;
    unsigned number;
    uint8_t guid[16], type_guid[16];
};
struct ans_namespace {
    uint32_t id, sector;
    uint64_t blocks;
    unsigned nparts, gpt_complete, gpt_hybrid;
    struct ans_partition parts[VINIX_ANS_MAX_PARTS];
};
struct ans_queue { unsigned head, phase; };
struct ans {
    struct ans_ops ops;
    void *cookie;
    uint64_t nvme, asc, mailbox, sart, reset;
    uint8_t *dma;
    uint64_t physical;
    struct ans_queue queues[2];
    struct ans_namespace ns[VINIX_ANS_MAX_NS];
    unsigned nns, max_transfer, shared_used, stage;
    uint16_t last_status, sart_owned;
    uint64_t shared_addr[9], shared_request[9];
    uint32_t endpoints[8];
    unsigned hello, mapped, ap_requested, iop_power, ap_power;
    int error, dead, started, live;
    unsigned stopping, stopped, ioq_active, policy_set, write_enabled, write_fault;
    unsigned write_ns, write_part, root_selected, root_ns, root_part;
    uint64_t write_start, write_blocks, writes_completed, flushes_completed;
    uint16_t dirty_namespaces;
    uint64_t sart_pa[16];
    unsigned sart_bytes[16];
};

struct ans_policy { unsigned flags; uint8_t write_guid[16], root_guid[16]; };
struct ans_gpt {
    uint64_t first, last, table;
    uint32_t entries, entry_size, table_crc;
    uint8_t guid[16];
};
struct a_deadline { uint64_t start, last; unsigned stalls; };
uint16_t a_le16(const uint8_t *p);
uint32_t a_le32(const uint8_t *p);
uint64_t a_le64(const uint8_t *p);
void a_put16(uint8_t *p, uint16_t v);
void a_put32(uint8_t *p, uint32_t v);
void a_put64(uint8_t *p, uint64_t v);
void a_zero(void *p, size_t n);
void a_copy(void *d, const void *s, size_t n);
int a_equal(const uint8_t *a, const uint8_t *b, size_t n);
int a_fail(struct ans *a, int error);
uint32_t a_r32(struct ans *a, uint64_t base, unsigned off);
void a_w32(struct ans *a, uint64_t base, unsigned off, uint32_t v);
void a_sync(struct ans *a, unsigned off, size_t n, int cpu);
struct a_deadline a_begin(struct ans *a);
int a_expired(struct ans *a, struct a_deadline *d, uint64_t us);
int a_sart_allow(struct ans *a, uint64_t pa, unsigned bytes);
int a_send(struct ans *a, unsigned ep, uint64_t msg);
int a_buffer_request(struct ans *a, unsigned ep, uint64_t msg);
int a_pump(struct ans *a);
int a_boot_rtkit(struct ans *a);
int a_wait32(struct ans *a, unsigned reg, uint32_t mask, uint32_t value,
    uint64_t timeout);
int a_command_allowed(unsigned q, const uint8_t c[64]);
int a_authorize(struct ans *a, unsigned q, const uint8_t c[64]);
int a_submit(struct ans *a, unsigned qid, uint8_t c[64], uint32_t *result);
void a_data_prps(struct ans *a, uint8_t c[64], unsigned bytes);
int a_identify(struct ans *a, uint32_t id, unsigned cns);
int a_parse_namespace(struct ans_namespace *ns, uint32_t id, const uint8_t *p);
int a_read_bytes(struct ans *a, unsigned index, void *buffer, uint64_t offset, size_t count);
int a_start(struct ans *a);
int a_root_disk(void *cookie, void *buffer, uint64_t offset, size_t count);
int a_open_root(struct ans *a, void *context, size_t size);
int a_data_disk(void *cookie, void *buffer, uint64_t offset, size_t count);
int a_data_store(void *cookie, const void *buffer, uint64_t offset, size_t count);
uint32_t a_kernel_read32(void *cookie, uint64_t p);
uint64_t a_kernel_read64(void *cookie, uint64_t p);
void a_kernel_write32(void *cookie, uint64_t p, uint32_t v);
void a_kernel_write64(void *cookie, uint64_t p, uint64_t v);
uint64_t a_kernel_now(void *cookie);
void a_kernel_delay(void *cookie, unsigned us);
void a_kernel_sync(void *cookie, void *buffer, size_t n, int cpu);
int a_hex(unsigned char c);
int a_guid_parse(const char *s, size_t n, uint8_t guid[16]);
void a_guid_format(const uint8_t guid[16], char out[37]);
int a_space(char c);
int a_token(const char *s, size_t n, const char *l, size_t bytes);
int a_prefix(const char *s, size_t n, const char *p, size_t bytes);
int a_parse_policy(const char *s, size_t n, struct ans_policy *out);
int a_linux_partition(const struct ans_partition *p);
int a_find_guid(struct ans *a, const uint8_t guid[16], unsigned *ns, unsigned *part);
int a_apply_policy(struct ans *a, const struct ans_policy *p);
uint32_t a_crc32(const uint8_t *p, size_t n);
int a_gpt_header(const struct ans_namespace *ns, uint8_t *p,
    uint64_t lba, struct ans_gpt *out);
int a_gpt_entries(struct ans_namespace *ns, const struct ans_gpt *h,
    const uint8_t *table);
int a_scan_gpt(struct ans *a, unsigned index);
int a_flush_ns(struct ans *a, unsigned index);
int a_flush_all(struct ans *a);
int a_write_partition(struct ans *a, unsigned index, unsigned part,
    const void *buffer, uint64_t offset, size_t count);
int a_power_state(struct ans *a, int ap, unsigned state);
int a_shutdown(struct ans *a);
