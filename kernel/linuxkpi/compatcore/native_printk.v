// SPDX-License-Identifier: GPL-2.0-only
// Native logger storage, initializer and task/thread adapters are all V.
@[translated]
module compatcore

import abiargs

fn C.vinix_linuxkpi_log_write(&char, usize)
fn C.vinix_linuxkpi_log_key(&u64) bool
fn C.vinix_linuxkpi_host_logger_enter()
fn C.vinix_linuxkpi_host_logger_leave()
@[c: 'pthread_exit']
fn C.vkr_native_thread_exit(voidptr)
fn C._printk(&char, ...voidptr) i32

@[typedef]
struct C.vkr_const_printk_record {}

type LogSinkABI = fn (&C.vkr_const_printk_record, voidptr)

@[export: 'console_printk']
__global vkr_native_log_levels = [i32(7), i32(4), i32(1), i32(7)]!
@[export: 'suppress_printk']
__global vkr_native_suppress i32
@[export: 'oops_in_progress']
__global vkr_native_oops i32
@[cinit]
__global vkr_native_log_mutex = C.vkw_mutex{
 wait_list: C.vkw_list{
  next: unsafe { &vkr_native_log_mutex.wait_list }
  prev: unsafe { &vkr_native_log_mutex.wait_list }
 }
}
@[cinit]
__global vkr_native_log_completion = C.vkw_completion{
 @wait: C.vkw_swait_head{
  task_list: C.vkw_list{
   next: unsafe { &vkr_native_log_completion.@wait.task_list }
   prev: unsafe { &vkr_native_log_completion.@wait.task_list }
  }
 }
}
__global vkr_native_log_thread u64

@[export: 'vkr_log_lifecycle']
pub fn vkr_log_lifecycle() voidptr { unsafe { return &vkr_native_log_mutex } }
@[export: 'vkr_log_ready']
pub fn vkr_log_ready() voidptr { unsafe { return &vkr_native_log_completion } }
@[export: 'vkr_log_reinit']
pub fn vkr_log_reinit(p voidptr) { unsafe { (&C.vkw_completion(p)).done = 0 } }
@[export: 'vkr_log_complete']
pub fn vkr_log_complete(p voidptr) { complete(p) }
@[export: 'vkr_log_wait']
pub fn vkr_log_wait(p voidptr) { wait_for_completion(p) }
@[export: 'vkr_log_current_get']
pub fn vkr_log_current_get() voidptr { return C.vkwq_get_current() }
@[export: 'vkr_log_task_put']
pub fn vkr_log_task_put(p voidptr) { C.vkwq_put_task(p) }
@[export: 'vkr_log_create']
pub fn vkr_log_create(worker fn (voidptr) voidptr, arg voidptr) i32 {
 unsafe { return C.vkwq_pthread_create(&vkr_native_log_thread, voidptr(worker), arg) }
}
@[export: 'vkr_log_join']
pub fn vkr_log_join() i32 { unsafe { return C.vkwq_pthread_join(vkr_native_log_thread) } }
@[export: 'vkr_log_exit']
pub fn vkr_log_exit() { C.vkr_native_thread_exit(unsafe { nil }) }
@[export: 'vkr_log_host_enter']
pub fn vkr_log_host_enter() { if C.VINIX_LINUXKPI_LOG_HOST == 1 { C.vinix_linuxkpi_host_logger_enter() } }
@[export: 'vkr_log_host_leave']
pub fn vkr_log_host_leave() { if C.VINIX_LINUXKPI_LOG_HOST == 1 { C.vinix_linuxkpi_host_logger_leave() } }
@[export: 'vkr_log_suppress']
pub fn vkr_log_suppress() i32 { unsafe { return C.vkp_load_signed(&vkr_native_suppress, 0) } }
@[export: 'vkr_log_console']
pub fn vkr_log_console(index u32) i32 { unsafe { return C.vkp_load_signed(&vkr_native_log_levels[index], 0) } }
@[export: 'vkr_log_call_sink']
pub fn vkr_log_call_sink(sink voidptr, record voidptr, arg voidptr) {
 unsafe { call := LogSinkABI(sink); call(&C.vkr_const_printk_record(record), arg) }
}
@[export: 'vkr_log_write']
pub fn vkr_log_write(text voidptr, size usize) { unsafe { C.vinix_linuxkpi_log_write(&char(text), size) } }
@[export: 'vkr_log_key']
pub fn vkr_log_key(key voidptr) bool { unsafe { return C.vinix_linuxkpi_log_key(&u64(key)) } }

@[export: 'vprintk_emit']
pub fn native_vprintk_emit(facility i32, level i32, dev voidptr, fmt &char, args voidptr) i32 {
 mut local := unsafe { nil }
 return vkr_log_emit(facility, level, dev, fmt, abiargs.parameter(args, unsafe { &local }))
}
@[export: 'vprintk']
pub fn native_vprintk(fmt &char, args voidptr) i32 { return native_vprintk_emit(0, -1, unsafe { nil }, fmt, args) }

@[export: 'vinix_linuxkpi_printk_entry']
pub fn native_printk(fmt &char, args voidptr) i32 { return vkr_log_emit(0, -1, unsafe { nil }, fmt, args) }
@[export: 'vinix_linuxkpi_printk_deferred_entry']
pub fn native_printk_deferred(fmt &char, args voidptr) i32 { return vkr_log_emit(0, -2, unsafe { nil }, fmt, args) }
@[export: 'vinix_linuxkpi_warn_entry']
pub fn native_warn(file &char, line i32, fmt &char, args voidptr) {
 add_taint(9, 0)
 unsafe {
  if usize(fmt) == 0 {
   C._printk(c'\x01\x34linuxkpi: warning at %s:%d\n', file, voidptr(i64(line)))
   return
  }
  mut nested := VaDescriptor{fmt: fmt, va: args}
  C._printk(c'\x01\x34linuxkpi: warning at %s:%d: %pV', file, voidptr(i64(line)), &nested)
 }
}
