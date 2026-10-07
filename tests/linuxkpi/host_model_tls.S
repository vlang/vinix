/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Native thread-local storage and initialization only. Algorithms live in V. */
#ifdef __APPLE__
.macro VMH_TLS_ZERO name, bytes, alignment
.tbss _\name\()$tlv$init, \bytes, \alignment
.section __DATA,__thread_vars,thread_local_variables
.globl _\name
_\name:
.quad __tlv_bootstrap
.quad 0
.quad _\name\()$tlv$init
.endm
.section __DATA,__thread_data,thread_local_regular
_vmh_interrupts$tlv$init:
.byte 1
.section __DATA,__thread_vars,thread_local_variables
.globl _vmh_interrupts
_vmh_interrupts:
.quad __tlv_bootstrap
.quad 0
.quad _vmh_interrupts$tlv$init
#else
#if defined(__aarch64__)
#define VMH_TLS_TYPE %tls_object
#define VMH_TLS_SECTION %progbits
#define VMH_TLS_ZERO_SECTION %nobits
#else
#define VMH_TLS_TYPE @tls_object
#define VMH_TLS_SECTION @progbits
#define VMH_TLS_ZERO_SECTION @nobits
#endif
.macro VMH_TLS_ZERO name, bytes, alignment
.section .tbss,"awT",VMH_TLS_ZERO_SECTION
.p2align \alignment
.globl \name
.type \name,VMH_TLS_TYPE
.size \name,\bytes
\name:
.zero \bytes
.endm
.section .tdata,"awT",VMH_TLS_SECTION
.globl vmh_interrupts
.type vmh_interrupts,VMH_TLS_TYPE
.size vmh_interrupts,1
vmh_interrupts:
.byte 1
#endif
VMH_TLS_ZERO vmh_resched_pending,1,0
VMH_TLS_ZERO vmh_preempt_depth,4,2
VMH_TLS_ZERO vmh_current_cpu,4,2
VMH_TLS_ZERO vmh_current_worker_nice,4,2
VMH_TLS_ZERO vmh_host_irq_restore_hook,8,3
VMH_TLS_ZERO vmh_timer_sync_spins,8,3
VMH_TLS_ZERO vmh_host_clock_read_hook,8,3
VMH_TLS_ZERO vmh_native_task,8,3
/* Additional original fixture-local TLS is declared as borrowed opaque views. */
VMH_TLS_ZERO vmh_wait_bit_test_current,8,3
VMH_TLS_ZERO vmh_mutex_io_current,8,3
VMH_TLS_ZERO vmh_host_iowait_before_block,8,3
VMH_TLS_ZERO vmh_io_test_current,8,3
VMH_TLS_ZERO vmh_expiry_test,8,3
VMH_TLS_ZERO vmh_usleep_host_current,8,3
#ifdef __APPLE__
.subsections_via_symbols
#else
.section .note.GNU-stack,"",VMH_TLS_SECTION
#endif
