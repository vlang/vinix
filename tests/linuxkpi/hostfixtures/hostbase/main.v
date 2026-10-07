// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
@[has_globals]
module hostbase
#include "hostbase_v_contract.h"
fn C.usleep_range_state(usize,usize,u32)
fn C.task_is_running(&C.task_struct) bool
fn C.vinix_linuxkpi_time_waiters() usize
fn C.puts(&char) i32
fn C.vmh_format_tests()
fn C.vmh_taint_initial_tests()
fn C.vmh_i915_config_tests()
fn C.vmh_kdev_tests()
fn C.vmh_qp_table_tests()
fn C.vmh_cache_tests()
fn C.vmh_string_helpers_tests()
fn C.vmh_kstrtox_tests()
fn C.vmh_string_tokens_tests()
fn C.vmh_test_bitmap_runtime()
fn C.vmh_task_tests()
fn C.vmh_task_flag_tests()
fn C.vmh_task_wait_tests()
fn C.vmh_sync_tests()
fn C.vmh_ww_mutex_tests()
fn C.vmh_seqcount_tests()
fn C.vmh_time_tests()
fn C.vmh_usleep_range_tests()
fn C.vmh_printk_tests()
fn C.vmh_warn_tests()
fn C.vmh_wait_bit_tests()
fn C.vmh_io_tests()
fn C.vmh_mutex_io_tests()
fn C.vmh_timer_tests()
fn C.vmh_workqueue_tests()
fn C.vmh_delayed_work_tests()
fn C.vmh_unbound_work_tests()
fn C.vmh_bound_work_tests()
fn C.vmh_srcu_tests()
fn C.vmh_printk_cleanup_tests()
@[c_extern] __global C.KTIME_MAX i64
@[c_extern] __global C.NSEC_PER_USEC i64
@[c_extern] __global C.TASK_UNINTERRUPTIBLE u32
@[c_extern] __global C.TASK_IDLE u32
@[c_extern] __global C.NR_CPUS u32
@[export:'vinix_linuxkpi_host_original_main']
pub fn run(argc i32,argv &&char) i32 { unsafe {
 if argc>1 {
  C.vmh_usleep_boundary_check=true;mut model:=C.native_task_model{};C.vmh_sync_model_init(&model,72);C.vmh_native_task=&model
  if C.strcmp(argv[1],c'reversed')==0 { C.usleep_range_state(2,1,C.TASK_UNINTERRUPTIBLE) }
  else if C.strcmp(argv[1],c'huge')==0 { C.usleep_range_state(0,C.ULONG_MAX,C.TASK_UNINTERRUPTIBLE) }
  else if C.strcmp(argv[1],c'clock-horizon')==0 { C.vmh_host_clock_ns=u64(C.KTIME_MAX)+1;C.usleep_range_state(0,0,C.TASK_UNINTERRUPTIBLE) }
  else if C.strcmp(argv[1],c'absolute-overflow')==0 { C.vmh_host_clock_ns=u64(C.KTIME_MAX)-u64(C.NSEC_PER_USEC);C.usleep_range_state(2,2,C.TASK_UNINTERRUPTIBLE) }
  else if C.strcmp(argv[1],c'state')==0 { C.usleep_range_state(0,0,u32(0x4)) }
  else if C.strcmp(argv[1],c'atomic')==0 { C.vmh_interrupts=false;C.usleep_range_state(0,0,C.TASK_UNINTERRUPTIBLE) }
  else if C.strcmp(argv[1],c'valid-horizon')==0 {
   C.vmh_host_clock_ns=u64(C.KTIME_MAX)-u64(C.NSEC_PER_USEC);C.usleep_range_state(0,1,C.TASK_IDLE)
   C.assert(C.task_is_running(C.current) && C.vinix_linuxkpi_time_waiters()==0);C.vmh_native_task=nil;C.vmh_sync_model_destroy(&model);return 0
  };return 77
 }
 C.assert(C.vinix_linuxkpi_percpu_init(0,&C.vmh_host_percpu_start,&C.vmh_host_percpu_end)==-C.EINVAL)
 C.assert(C.vinix_linuxkpi_percpu_init(C.NR_CPUS+1,&C.vmh_host_percpu_start,&C.vmh_host_percpu_end)==-C.EINVAL)
 C.assert(C.vinix_linuxkpi_percpu_init(4,&C.vmh_host_percpu_end,&C.vmh_host_percpu_start)==-C.EINVAL)
 C.vmh_fail_allocation=true;C.assert(C.vinix_linuxkpi_percpu_init(4,&C.vmh_host_percpu_start,&C.vmh_host_percpu_end)==-C.ENOMEM)
 C.assert(C.vmh_live_pages==0);C.vmh_fail_allocation=false;C.assert(C.vinix_linuxkpi_percpu_init(4,&C.vmh_host_percpu_start,&C.vmh_host_percpu_end)==0)
 C.vmh_permanent_pages=C.vmh_live_pages
 C.vmh_format_tests();C.vmh_taint_initial_tests();C.vmh_i915_config_tests();C.vmh_kdev_tests();C.vmh_qp_table_tests()
 allocation_tests();C.vmh_cache_tests();string_tests();C.vmh_string_helpers_tests();C.vmh_kstrtox_tests();C.vmh_string_tokens_tests()
 bitmap_tests();C.vmh_test_bitmap_runtime();bit_concurrency_tests();byteorder_tests();raw_lock_tests();percpu_tests()
 C.vmh_task_tests();C.vmh_task_flag_tests();C.vmh_task_wait_tests();C.vmh_sync_tests();C.vmh_ww_mutex_tests();C.vmh_seqcount_tests()
 C.vmh_time_tests();C.vmh_usleep_range_tests();C.vmh_printk_tests();C.vmh_warn_tests();C.vmh_wait_bit_tests();C.vmh_io_tests();C.vmh_mutex_io_tests()
 C.vmh_timer_tests();C.vmh_workqueue_tests();C.vmh_delayed_work_tests();C.vmh_unbound_work_tests();C.vmh_bound_work_tests();C.vmh_srcu_tests()
 list_tests();tree_tests();concurrency_tests();atomic_api_tests();reference_tests();C.vmh_printk_cleanup_tests()
 C.vinix_linuxkpi_percpu_destroy_for_test();C.assert(C.vmh_live_pages==0)
 C.puts(c'LinuxKPI: PASS (Linux helpers, owned printk/formatting/warnings/taints, allocation/OOM, packed object caches, strings, bitmaps, SMP/IRQ locks, per-CPU storage, task references, wake races, synchronization, sequence counters, wound/wait mutexes, clocks, bit/variable and I/O waits, timers, ordered/delayed/unbound/bound work, runnable concurrency, priority, system queues and SRCU)');return 0
} }
