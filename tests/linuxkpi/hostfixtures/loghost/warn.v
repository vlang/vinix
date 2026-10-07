// SPDX-License-Identifier: GPL-2.0-only
// Exercise actual public warning macros against the owned-record logger.
@[translated]
@[has_globals]
module loghost
#include "loghost_v_contract.h"
fn C.WARN(i32,&char,...) bool
fn C.WARN_ON(i32) bool
fn C.WARN_ONCE(i32,&char,...) bool
fn C.WARN_ON_ONCE(i32) bool
fn C.vinix_linuxkpi_refcount_warning(i32)
fn C.get_taint() usize
fn C.add_taint(u32,i32)
fn C.strncmp(&char,&char,usize) i32
fn C.strstr(&char,&char) &char
fn C.vml_warn_produce(voidptr) voidptr
__global vml_warn_conditions = u32(0)
__global vml_warn_arguments = u32(0)
__global vml_warn_formats = u32(0)
struct WarnProducer { mut: index u32 ready &u32 start &u32 taints bool }
fn warn_condition(value i32) i32 { unsafe { C.__atomic_add_fetch(&vml_warn_conditions,u32(1),0); return value } }
fn warn_argument(value u32) u32 { unsafe { C.__atomic_add_fetch(&vml_warn_arguments,u32(1),0); return value } }
fn warn_owned_format() &char { unsafe { C.__atomic_add_fetch(&vml_warn_formats,u32(1),0); return c'owned warning=%s value=%u\n' } }
fn warn_once_format() &char { unsafe { C.__atomic_add_fetch(&vml_warn_formats,u32(1),0); return c'parallel owned %u\n' } }
// Four producers share these exact native macro callsites. False conditions
// preserve the once slot and do not evaluate the format or its arguments.
fn warn_once_call(condition i32,index u32) bool { return C.WARN_ONCE(warn_condition(condition),warn_once_format(),warn_argument(index)) }
fn warn_on_once_call(condition i32) bool { return C.WARN_ON_ONCE(warn_condition(condition)) }
@[export:'vml_warn_produce']
pub fn warn_produce(argument voidptr) voidptr { unsafe {
 producer:=&WarnProducer(argument); C.vmh_current_cpu=producer.index; C.assert(C.vmh_interrupts && C.vmh_preempt_depth==0); C.__atomic_add_fetch(producer.ready,u32(1),3)
 for C.__atomic_load_n(producer.start,2)==0 { C.sched_yield() }
 if !producer.taints { for i:=u32(0); i<64; i++ { condition:=if i&1!=0 { i32(-7) } else { i32(0) }; C.assert(warn_once_call(condition,producer.index)==(condition!=0)); C.assert(warn_on_once_call(condition)==(condition!=0)) } }
 else { for i:=u32(0); i<1024; i++ { flags:=C.vinix_linuxkpi_irq_save(); C.vinix_linuxkpi_preempt_disable(); C.vinix_linuxkpi_preempt_disable()
  for bit:=producer.index; bit<u32(C.TAINT_FLAGS_COUNT); bit+=4 { C.add_taint(bit,if i&1!=0 { i32(C.LOCKDEP_NOW_UNRELIABLE) } else { i32(C.LOCKDEP_STILL_OK) }); C.assert(C.test_taint(bit)==1) }
  C.assert(!C.vmh_interrupts && C.vmh_preempt_depth==2); C.vinix_linuxkpi_preempt_enable_no_resched(); C.vinix_linuxkpi_preempt_enable_no_resched(); C.vinix_linuxkpi_irq_restore(flags); C.assert(C.vmh_interrupts && C.vmh_preempt_depth==0)
 } }; return nil
} }
fn warn_parallel(taints bool) { unsafe {
 mut ready:=u32(0); mut start:=u32(0); mut producers:=[4]WarnProducer{}; mut threads:=[4]C.pthread_t{}
 for i:=u32(0); i<producers.len; i++ { producers[i]=WarnProducer{i,&ready,&start,taints}; C.assert(C.pthread_create(&threads[i],nil,C.vml_warn_produce,&producers[i])==0) }
 for C.__atomic_load_n(&ready,2)!=producers.len { C.sched_yield() }; C.__atomic_store_n(&start,u32(1),3)
 for i:=u32(0); i<producers.len; i++ { C.assert(C.pthread_join(threads[i],nil)==0) }
} }
fn warn_record(record &C.vinix_linuxkpi_printk_record) { unsafe {
 C.assert(record.level==u8(C.LOGLEVEL_WARNING) && record.caller==0); C.assert(record.format_status==0 && record.flags==u8(C.VINIX_PRINTK_NEWLINE)); C.assert(record.length==C.strlen(&record.text[0])); C.assert(C.strncmp(&record.text[0],c'linuxkpi: warning at ',20)==0)
} }
@[export:'vmh_taint_initial_tests']
pub fn taint_initial_tests() { unsafe {
 C.assert(C.vmh_native_task==nil && C.vmh_interrupts && C.vmh_preempt_depth==0); C.assert(C.get_taint()==0 && C.test_taint(C.TAINT_WARN)==0)
 pages:=C.vmh_live_pages; mut before:=C.vinix_linuxkpi_printk_state{}; mut state:=C.vinix_linuxkpi_printk_state{}; C.vinix_linuxkpi_printk_get_state(&before); C.assert(!before.worker_live && !before.in_flight)
 C.assert(C.pthread_mutex_lock(&vml_console_lock)==0); allocation_before:=C.vmh_fail_allocation; C.vmh_fail_allocation=true; flags:=C.vinix_linuxkpi_irq_save(); C.vinix_linuxkpi_preempt_disable(); C.vinix_linuxkpi_preempt_disable(); C.vinix_linuxkpi_refcount_warning(C.REFCOUNT_DEC_LEAK)
 C.assert(C.get_taint()==usize(1)<<C.TAINT_WARN && C.test_taint(C.TAINT_WARN)==1); C.vinix_linuxkpi_printk_get_state(&state); C.assert(state.submitted==before.submitted+1 && state.queued==before.queued+1); C.assert(state.dropped==before.dropped && !state.worker_live && !state.in_flight)
 C.assert(!C.vmh_interrupts && C.vmh_preempt_depth==2 && C.vmh_live_pages==pages); C.vinix_linuxkpi_preempt_enable_no_resched(); C.vinix_linuxkpi_preempt_enable_no_resched(); C.vinix_linuxkpi_irq_restore(flags); C.vmh_fail_allocation=allocation_before
 C.assert(C.pthread_mutex_unlock(&vml_console_lock)==0); C.assert(C.vmh_interrupts && C.vmh_preempt_depth==0 && C.vmh_live_pages==pages)
} }
@[export:'vmh_warn_tests']
pub fn warn_tests() { unsafe {
 pages:=C.vmh_live_pages; mut controller:=C.native_task_model{}; C.vmh_sync_model_init(&controller,84); C.vmh_native_task=&controller; C.assert(C.vmh_interrupts && C.vmh_preempt_depth==0)
 C.assert(C.TAINT_FLAGS_COUNT==19 && C.TAINT_FLAGS_MAX==usize(0x7ffff)); C.assert(C.__atomic_load_n(&vml_logger_workers,2)==0); C.__atomic_store_n(&vml_logger_tick_stop,false,3)
 mut ticker:=C.pthread_t{}; C.assert(C.pthread_create(&ticker,nil,C.vml_logger_ticks,nil)==0); C.assert(C.vinix_linuxkpi_printk_bootstrap()==0); C.assert(C.vinix_linuxkpi_printk_flush(C.vinix_linuxkpi_printk_snapshot(),2000)==0)
 mut capture:=LoggerCapture{}; mut before:=C.vinix_linuxkpi_printk_state{}; mut state:=C.vinix_linuxkpi_printk_state{}; logger_install(&capture); C.vinix_linuxkpi_printk_get_state(&before); mut taint_before:=C.get_taint()
 vml_warn_conditions=0; vml_warn_arguments=0; vml_warn_formats=0
 C.assert(!C.WARN(warn_condition(0),warn_owned_format(),&char(1),warn_argument(0))); C.assert(vml_warn_conditions==1 && vml_warn_arguments==0 && vml_warn_formats==0); C.assert(C.get_taint()==taint_before); C.assert(C.vinix_linuxkpi_printk_snapshot()==before.submitted)
 borrowed:=&char(C.malloc(16)); C.assert(borrowed!=nil); C.memcpy(borrowed,c'short-lived',12); C.assert(C.WARN(warn_condition(7),warn_owned_format(),borrowed,warn_argument(12))); C.memset(borrowed,88,16); C.free(borrowed)
 C.assert(C.WARN_ON(warn_condition(-8))); C.assert(!C.WARN_ON(warn_condition(0)))
 C.assert(C.pthread_mutex_lock(&vml_console_lock)==0); C.assert(C.pthread_mutex_lock(&controller.queue_lock)==0); mut allocation_before:=C.vmh_fail_allocation; C.vmh_fail_allocation=true; mut flags:=C.vinix_linuxkpi_irq_save(); C.vinix_linuxkpi_preempt_disable(); C.vinix_linuxkpi_preempt_disable()
 C.assert(C.WARN(warn_condition(5),c'atomic warning value=%u\n',warn_argument(5))); C.assert(C.WARN_ON(warn_condition(3))); C.assert(!C.vmh_interrupts && C.vmh_preempt_depth==2 && C.vmh_live_pages==pages); C.assert(C.test_taint(C.TAINT_WARN)==1); C.assert(C.get_taint()==(taint_before|(usize(1)<<C.TAINT_WARN)))
 C.assert(C.vinix_linuxkpi_printk_flush(C.vinix_linuxkpi_printk_snapshot(),0)==-i32(C.EWOULDBLOCK)); C.vinix_linuxkpi_preempt_enable_no_resched(); C.vinix_linuxkpi_preempt_enable_no_resched(); C.vinix_linuxkpi_irq_restore(flags); C.vmh_fail_allocation=allocation_before; C.assert(C.pthread_mutex_unlock(&controller.queue_lock)==0); C.assert(C.pthread_mutex_unlock(&vml_console_lock)==0)
 C.vinix_linuxkpi_refcount_warning(C.REFCOUNT_DEC_LEAK); C.assert(vml_warn_conditions==6 && vml_warn_arguments==2 && vml_warn_formats==1); C.vinix_linuxkpi_printk_get_state(&state); C.assert(state.submitted==before.submitted+5 && state.dropped==before.dropped); logger_finish(&capture,5)
 for i:=u32(0); i<4; i++ { warn_record(&capture.records[i]) }; C.assert(C.strstr(&capture.records[0].text[0],c': owned warning=short-lived value=12')!=nil); C.assert(C.strstr(&capture.records[2].text[0],c': atomic warning value=5')!=nil)
 C.assert(C.strcmp(&capture.records[4].text[0],c'linuxkpi: refcount saturated after invalid operation 4; retaining object')==0); C.assert(capture.records[4].level==u8(C.LOGLEVEL_WARNING))
 logger_install(&capture); C.vinix_linuxkpi_printk_get_state(&before); vml_warn_conditions=0; vml_warn_arguments=0; vml_warn_formats=0
 C.assert(!warn_once_call(0,99)); C.assert(!warn_on_once_call(0)); C.assert(vml_warn_arguments==0 && vml_warn_formats==0); C.assert(C.vinix_linuxkpi_printk_snapshot()==before.submitted)
 warn_parallel(false); C.assert(vml_warn_conditions==2+4*64*2); C.assert(vml_warn_arguments==1 && vml_warn_formats==1); C.vinix_linuxkpi_printk_get_state(&state); C.assert(state.submitted==before.submitted+2 && state.dropped==before.dropped); logger_finish(&capture,2)
 mut formatted:=u32(0); for i:=u32(0); i<capture.count; i++ { warn_record(&capture.records[i]); mut body:=C.strstr(&capture.records[i].text[0],c': parallel owned '); if body!=nil { body+=17; C.assert(body[0]>=48 && body[0]<=51 && body[1]==0); formatted++ } }; C.assert(formatted==1)
 C.assert(C.pthread_mutex_lock(&vml_console_lock)==0); C.assert(C.pthread_mutex_lock(&controller.queue_lock)==0); allocation_before=C.vmh_fail_allocation; C.vmh_fail_allocation=true; flags=C.vinix_linuxkpi_irq_save(); C.vinix_linuxkpi_preempt_disable(); C.vinix_linuxkpi_preempt_disable()
 C.add_taint(C.TAINT_TEST,C.LOCKDEP_NOW_UNRELIABLE); C.assert(C.test_taint(C.TAINT_TEST)==1); taint_before=C.get_taint(); C.assert(!C.vmh_interrupts && C.vmh_preempt_depth==2 && C.vmh_live_pages==pages)
 C.vinix_linuxkpi_preempt_enable_no_resched(); C.vinix_linuxkpi_preempt_enable_no_resched(); C.vinix_linuxkpi_irq_restore(flags); C.vmh_fail_allocation=allocation_before; C.assert(C.pthread_mutex_unlock(&controller.queue_lock)==0); C.assert(C.pthread_mutex_unlock(&vml_console_lock)==0)
 no_log:=C.vinix_linuxkpi_printk_snapshot(); warn_parallel(true); C.assert(C.get_taint()==(taint_before|usize(C.TAINT_FLAGS_MAX))); for bit:=u32(0); bit<u32(C.TAINT_FLAGS_COUNT); bit++ { C.assert(C.test_taint(bit)==1) }; C.assert(C.vinix_linuxkpi_printk_snapshot()==no_log && C.vmh_live_pages==pages)
 C.assert(C.vinix_linuxkpi_printk_test_pause(false,0)==0); C.assert(C.vinix_linuxkpi_printk_shutdown()==0); C.__atomic_store_n(&vml_logger_tick_stop,true,3); C.assert(C.pthread_join(ticker,nil)==0); C.vinix_linuxkpi_printk_get_state(&state)
 C.assert(!state.worker_live && !state.in_flight && state.queued==0 && state.retired==state.submitted); C.assert(C.__atomic_load_n(&vml_logger_workers,2)==0); C.assert(C.vinix_linuxkpi_time_waiters()==0 && C.vmh_live_pages==pages); C.vmh_sync_model_destroy(&controller); C.vmh_native_task=nil
} }
