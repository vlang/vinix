/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_HOSTBASE_V_CONTRACT_H
#define VINIX_LINUXKPI_HOSTBASE_V_CONTRACT_H
#include "host_model_v_contract.h"
#include "host_percpu_abi.h"
#include <linux/limits.h>
struct vmh_string_calls {
    void *(*volatile scan)(const void *, int, size_t);
    size_t (*volatile bounded_length)(const char *, size_t);
};
void vmh_allocation_tests(void);
void vmh_string_tests(void);
_Static_assert(BITS_PER_LONG == 64, "original host word width");
void vmh_bitmap_tests(void);
void vmh_byteorder_tests(void);
void vmh_bit_concurrency_tests(void);
void *vmh_bit_worker(void *);
typedef struct hostbase__Entry vmh_entry;
typedef const struct list_head *vmh_const_list_p;
int vmh_compare_list(void *, vmh_const_list_p, vmh_const_list_p);
void vmh_list_tests(void);
void vmh_tree_tests(void);
typedef long long vmh_s64;
_Static_assert(sizeof(vmh_s64) == 8, "original native atomic64 width");
void vmh_raw_lock_tests(void);
void vmh_concurrency_tests(void);
void vmh_atomic_api_tests(void);
void vmh_reference_tests(void);
void *vmh_concurrent_worker(void *);
void *vmh_message_writer(void *);
void *vmh_message_reader(void *);
void vmh_release_object(struct kref *);
void *vmh_reference_worker(void *);
#ifdef __APPLE__
extern const unsigned char vmh_host_percpu_start __asm__("section$start$__DATA$vinixpcpu");
extern const unsigned char vmh_host_percpu_end __asm__("section$end$__DATA$vinixpcpu");
#else
extern const unsigned char vmh_host_percpu_start __asm__("__start_vinixpcpu");
extern const unsigned char vmh_host_percpu_end __asm__("__stop_vinixpcpu");
#endif
typedef struct hostbase__CpuRecord vmh_cpu_record_type;
extern uint8_t vmh_cpu_byte __PCPU_ATTRS("");
extern uint16_t vmh_cpu_half __PCPU_ATTRS("");
extern uint32_t vmh_cpu_word __PCPU_ATTRS("");
extern uint64_t vmh_cpu_wide __PCPU_ATTRS("");
extern struct hostbase__CpuRecord vmh_cpu_record __PCPU_ATTRS("");
void *vmh_percpu_worker(void *);
void vmh_percpu_tests(void);
void vinix_linuxkpi_percpu_destroy_for_test(void);
#include <linux/delay.h>
int vinix_linuxkpi_host_original_main(int, char **);
void vmh_format_tests(void);
void vmh_taint_initial_tests(void);
void vmh_i915_config_tests(void);
void vmh_kdev_tests(void);
void vmh_qp_table_tests(void);
void vmh_cache_tests(void);
void vmh_string_helpers_tests(void);
void vmh_kstrtox_tests(void);
void vmh_string_tokens_tests(void);
void vmh_test_bitmap_runtime(void);
void vmh_task_tests(void);
void vmh_task_flag_tests(void);
void vmh_task_wait_tests(void);
void vmh_sync_tests(void);
void vmh_ww_mutex_tests(void);
void vmh_seqcount_tests(void);
void vmh_time_tests(void);
void vmh_usleep_range_tests(void);
void vmh_printk_tests(void);
void vmh_warn_tests(void);
void vmh_wait_bit_tests(void);
void vmh_io_tests(void);
void vmh_mutex_io_tests(void);
void vmh_timer_tests(void);
void vmh_workqueue_tests(void);
void vmh_delayed_work_tests(void);
void vmh_unbound_work_tests(void);
void vmh_bound_work_tests(void);
void vmh_srcu_tests(void);
void vmh_printk_cleanup_tests(void);
#endif
