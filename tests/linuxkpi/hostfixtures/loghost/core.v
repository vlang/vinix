// SPDX-License-Identifier: GPL-2.0-only
// Independent native task/clock/console logger model and original record goldens.
@[translated]
@[has_globals]
module loghost
#include "loghost_v_contract.h"
@[typedef] struct C.vml_native_va {}
@[typedef] struct C.vml_const_record_p {}
struct C.vml_volatile_scalar { mut: value i32 }
struct C.vinix_linuxkpi_printk_record { mut: sequence u64 caller u64 format_status u32 length u16 level u8 flags u8 text [1024]char }
struct C.vinix_linuxkpi_printk_state { mut: submitted u64 retired u64 dropped u64 truncated u64 format_errors u64 queued u32 in_flight bool worker_live bool paused bool key_ready bool }
type LoggerSink = fn(C.vml_const_record_p,voidptr)
struct LoggerCapture { mut: records [128]C.vinix_linuxkpi_printk_record count u32 hold u32 entered u32 release u32 self_flush i32 self_shutdown i32 self_pause i32 }
struct LoggerProducer { mut: index u32 }
struct LoggerFlusher { mut: model C.native_task_model snapshot u64 entered u32 done u32 result i32 }
struct LoggerVaDescriptor { fmt &char va voidptr }
fn C.calloc(usize,usize) voidptr
fn C.malloc(usize) voidptr
fn C.free(voidptr)
fn C.usleep(u32) i32
fn C.sscanf(&char,&char,...) i32
fn C.vmh_host_time_advance(C.vmh_u64)
fn C.__atomic_sub_fetch(voidptr,...) u64
fn C.__atomic_fetch_or(voidptr,...) u64
fn C.vinix_linuxkpi_irq_save() usize
fn C.vinix_linuxkpi_irq_restore(usize)
fn C.vinix_linuxkpi_preempt_disable()
fn C.vinix_linuxkpi_preempt_enable_no_resched()
fn C.vinix_linuxkpi_printk_get_state(&C.vinix_linuxkpi_printk_state)
fn C.vinix_linuxkpi_printk_snapshot() u64
fn C.vinix_linuxkpi_printk_bootstrap() i32
fn C.vinix_linuxkpi_printk_flush(u64,u32) i32
fn C.vinix_linuxkpi_printk_shutdown() i32
fn C.vinix_linuxkpi_printk_test_pause(bool,u32) i32
fn C.vinix_linuxkpi_printk_test_sink(LoggerSink,voidptr) i32
fn C.vinix_linuxkpi_printk_test_fail_create(bool)
fn C.vinix_linuxkpi_time_waiters() u32
fn C.vprintk_emit(i32,i32,voidptr,&char,C.vml_native_va) i32
fn C._printk(&char,...) i32
fn C._printk_deferred(&char,...) i32
fn C.vinix_linuxkpi_warn_format(&char,i32,&char,...)
fn C.test_taint(u32) i32
fn C.vml_logger_ticks(voidptr) voidptr
fn C.vml_logger_sink(C.vml_const_record_p,voidptr)
fn C.vml_logger_produce(voidptr) voidptr
fn C.vml_logger_flush_thread(voidptr) voidptr
fn C.vml_logger_emit(i32,i32,voidptr,&char,...) i32
fn C.vml_logger_nested(&char,...) i32
@[c_extern] __global C.suppress_printk i32
__global vml_logger_workers = u32(0)
__global vml_logger_key_attempts = u32(0)
__global vml_logger_key_available = false
__global vml_logger_tick_stop = false
@[cinit] __global vml_console_lock C.pthread_mutex_t = C.vmh_mutex_initializer
__global vml_console_bytes = u32(0)
fn native_word(bits u64) C.vmh_u64 { unsafe { mut value:=C.vmh_u64{}; C.memcpy(&value,&bits,sizeof(value)); return value } }
@[export:'vinix_linuxkpi_host_logger_enter']
pub fn logger_enter() { unsafe {
 model:=&C.native_task_model(C.calloc(1,sizeof(C.native_task_model))); C.assert(model!=nil); C.vmh_sync_model_init(model,80); model.heap_owned=true; C.vmh_native_task=model; C.vmh_current_cpu=0; C.__atomic_add_fetch(&vml_logger_workers,u32(1),3)
} }
@[export:'vinix_linuxkpi_host_logger_leave']
pub fn logger_leave() { unsafe {
 model:=C.vmh_native_task; C.assert(model!=nil && model.pins==1 && C.vinix_linuxkpi_may_sleep()); C.__atomic_store_n(&model.dead,true,3); C.vinix_linuxkpi_task_dead(&model.storage[0]); C.__atomic_sub_fetch(&vml_logger_workers,u32(1),3); C.vmh_native_task=nil
} }
@[export:'vinix_linuxkpi_log_write']
pub fn log_write(native_text C.vmh_const_char_p,length usize) { unsafe {
 mut text:=&char(nil); C.memcpy(&text,&native_text,sizeof(text)); C.assert(C.vinix_linuxkpi_may_sleep()); C.assert(C.pthread_mutex_lock(&vml_console_lock)==0); C.assert(length!=0 && text[length-1]==10); C.__atomic_add_fetch(&vml_console_bytes,u32(length),3); C.assert(C.pthread_mutex_unlock(&vml_console_lock)==0)
} }
@[export:'vinix_linuxkpi_log_key']
pub fn log_key(key &C.vmh_u64) bool { unsafe {
 C.assert(C.vinix_linuxkpi_may_sleep()); C.__atomic_add_fetch(&vml_logger_key_attempts,u32(1),0); if C.__atomic_load_n(&vml_logger_key_available,2)==0 { return false }
 key_words:=[u64(0x0706050403020100),u64(0x0f0e0d0c0b0a0908)]!; C.memcpy(key,&key_words[0],sizeof(key_words)); return true
} }
@[export:'vinix_linuxkpi_log_caller']
pub fn log_caller() C.vmh_u64 { return native_word(0) }
@[export:'vml_logger_ticks']
pub fn logger_ticks(argument voidptr) voidptr { unsafe {
 for C.__atomic_load_n(&vml_logger_tick_stop,2)==0 { C.vmh_host_time_advance(native_word(1)); C.usleep(1000) }; return nil
} }
@[export:'vml_logger_sink']
pub fn logger_sink(native_record C.vml_const_record_p,argument voidptr) { unsafe {
 mut record:=&C.vinix_linuxkpi_printk_record(nil); C.memcpy(&record,&native_record,sizeof(record)); capture:=&LoggerCapture(argument)
 C.assert(C.vinix_linuxkpi_may_sleep() && record.length<1024); C.assert(record.text[record.length]==0); index:=capture.count; C.assert(index<capture.records.len); capture.records[index]=*record
 capture.self_flush=C.vinix_linuxkpi_printk_flush(record.sequence,0); capture.self_shutdown=C.vinix_linuxkpi_printk_shutdown(); capture.self_pause=C.vinix_linuxkpi_printk_test_pause(true,0)
 if index<32 && u32(C.__atomic_load_n(&capture.hold,2))&(u32(1)<<index)!=0 { C.__atomic_fetch_or(&capture.entered,u32(1)<<index,3); for u32(C.__atomic_load_n(&capture.release,2))&(u32(1)<<index)==0 { C.sched_yield() } }
 C.__atomic_store_n(&capture.count,index+1,3)
} }
fn logger_install(capture &LoggerCapture) { unsafe {
 C.assert(C.vinix_linuxkpi_printk_test_pause(true,2000)==0); *capture=LoggerCapture{}; C.assert(C.vinix_linuxkpi_printk_test_sink(C.vml_logger_sink,capture)==0)
} }
fn logger_finish(capture &LoggerCapture,count u32) { unsafe {
 C.assert(C.vinix_linuxkpi_printk_test_pause(false,0)==0); C.assert(C.vinix_linuxkpi_printk_flush(C.vinix_linuxkpi_printk_snapshot(),2000)==0); C.assert(C.__atomic_load_n(&capture.count,2)==count)
 C.assert(capture.self_flush==-i32(C.EDEADLK) && capture.self_shutdown==-i32(C.EDEADLK) && capture.self_pause==-i32(C.EDEADLK))
 C.assert(C.vinix_linuxkpi_printk_test_pause(true,2000)==0); C.assert(C.vinix_linuxkpi_printk_test_sink(LoggerSink(nil),nil)==0)
} }
@[export:'vml_logger_emit_entry']
pub fn logger_emit_entry(facility i32,level i32,info voidptr,fmt &char,args voidptr) i32 { unsafe { return C.vprintk_emit(facility,level,info,fmt,*&C.vml_native_va(args)) } }
@[export:'vml_logger_nested_entry']
pub fn logger_nested_entry(fmt &char,args voidptr) i32 { unsafe { nested:=LoggerVaDescriptor{fmt,args}; return C._printk(c'\x01\x34nested:%pV',&nested) } }
@[export:'vml_logger_produce']
pub fn logger_produce(argument voidptr) voidptr { unsafe {
 producer:=&LoggerProducer(argument); C.vmh_current_cpu=producer.index
 for i:=u32(0); i<16; i++ { flags:=C.vinix_linuxkpi_irq_save(); C.vinix_linuxkpi_preempt_disable(); depth:=C.vmh_preempt_depth
  C.assert(C._printk(c'\x01\x35producer %u:%u\n',producer.index,i)>=12); C.assert(!C.vmh_interrupts && C.vmh_preempt_depth==depth); C.vinix_linuxkpi_preempt_enable_no_resched(); C.vinix_linuxkpi_irq_restore(flags); C.assert(C.vmh_interrupts && C.vmh_preempt_depth==0)
 }; return nil
} }
@[export:'vml_logger_flush_thread']
pub fn logger_flush_thread(argument voidptr) voidptr { unsafe {
 test:=&LoggerFlusher(argument); C.vmh_native_task=&test.model; C.__atomic_store_n(&test.entered,u32(1),3); test.result=C.vinix_linuxkpi_printk_flush(test.snapshot,2000); C.__atomic_store_n(&test.done,u32(1),3); C.vmh_native_task=nil; return nil
} }
@[export:'vmh_printk_tests']
pub fn printk_tests() { unsafe {
 pages:=C.vmh_live_pages; mut controller:=C.native_task_model{}; C.vmh_sync_model_init(&controller,81); C.vmh_native_task=&controller
 mut before:=C.vinix_linuxkpi_printk_state{}; mut state:=C.vinix_linuxkpi_printk_state{}; C.vinix_linuxkpi_printk_get_state(&before); C.assert(!before.worker_live)
 C.assert(C._printk(c'\x01\x36preboot\n')==7); preboot:=C.vinix_linuxkpi_printk_snapshot(); C.assert(C.vinix_linuxkpi_printk_flush(preboot,0)==-i32(C.ENODEV)); C.vinix_linuxkpi_printk_test_fail_create(true)
 C.assert(C.vinix_linuxkpi_printk_bootstrap()==-i32(C.ENOMEM) && vml_logger_workers==0); C.vinix_linuxkpi_printk_get_state(&state)
 preboot_queued:=if before.queued<64 { before.queued+1 } else { before.queued }; C.assert(!state.worker_live && state.submitted==preboot && state.queued==preboot_queued)
 mut ticker:=C.pthread_t{}; vml_logger_tick_stop=false; C.assert(C.pthread_create(&ticker,nil,C.vml_logger_ticks,nil)==0); C.assert(C.vinix_linuxkpi_printk_bootstrap()==0); C.assert(C.vinix_linuxkpi_printk_bootstrap()==0 && vml_logger_workers==1)
 C.assert(C.vinix_linuxkpi_printk_flush(preboot,2000)==0); C.assert(vml_console_bytes>=8); C.assert(C.vinix_linuxkpi_printk_flush(preboot+1,0)==-i32(C.EINVAL)); C.vinix_linuxkpi_printk_get_state(&before)
 mut capture:=LoggerCapture{}; logger_install(&capture)
 C.assert(C.pthread_mutex_lock(&vml_console_lock)==0); C.assert(C.pthread_mutex_lock(&controller.queue_lock)==0); allocation_before:=C.vmh_fail_allocation; C.vmh_fail_allocation=true
 flags:=C.vinix_linuxkpi_irq_save(); C.vinix_linuxkpi_preempt_disable(); C.assert(C._printk(c'%s%sowned %d\n',c'\x01\x35',c'\x01\x63',i32(7))==7)
 C.assert(!C.vmh_interrupts && C.vmh_preempt_depth==1 && C.vmh_live_pages==pages); C.assert(C.vinix_linuxkpi_printk_flush(C.vinix_linuxkpi_printk_snapshot(),0)==-i32(C.EWOULDBLOCK)); C.vinix_linuxkpi_preempt_enable_no_resched(); C.vinix_linuxkpi_irq_restore(flags); C.vmh_fail_allocation=allocation_before
 C.assert(C.pthread_mutex_unlock(&controller.queue_lock)==0); C.assert(C.pthread_mutex_unlock(&vml_console_lock)==0)
 borrowed:=&char(C.malloc(16)); C.assert(borrowed!=nil); C.memcpy(borrowed,c'short-lived',12); C.assert(C._printk(c'\x01\x36%s\n',borrowed)==11); C.memset(borrowed,88,12); C.free(borrowed)
 C.assert(C.vml_logger_nested(c'%s %d\n',c'args',i32(-9))==14); C.assert(C.vml_logger_emit(0,C.LOGLEVEL_ERR,nil,c'\x01\x37\x65xplicit\n')==8); C.assert(C._printk_deferred(c'deferred\n')==8)
 mut large:=[1124]char{}; C.memset(&large[0],97,sizeof(large)-1); large[sizeof(large)-1]=0; C.assert(C._printk(c'%s',&large[0])==1023)
 mut untouched:=C.vml_volatile_scalar{value:1234}; invalid:=&char(c'before%nnever'); C.assert(C._printk(invalid,&untouched.value)==6 && untouched.value==1234); C.suppress_printk=1; C.assert(C._printk(c'suppressed %s',&char(1))==0); C.suppress_printk=0
 C.assert(C.vml_logger_emit(1,C.LOGLEVEL_DEFAULT,nil,c'facility')==-i32(C.EOPNOTSUPP)); C.assert(C.vml_logger_emit(0,C.LOGLEVEL_DEFAULT,voidptr(1),c'device')==-i32(C.EOPNOTSUPP)); C.assert(C.vml_logger_emit(0,8,nil,c'level')==-i32(C.EINVAL))
 C.vinix_linuxkpi_printk_get_state(&state); C.assert(state.queued==7 && state.truncated==before.truncated+1 && state.format_errors==before.format_errors+1); C.assert(C.vinix_linuxkpi_printk_flush(state.submitted,0)==-i32(C.ETIMEDOUT)); logger_finish(&capture,7)
 C.assert(C.strcmp(&capture.records[0].text[0],c'owned 7')==0 && capture.records[0].level==5); C.assert(capture.records[0].flags==u8(C.VINIX_PRINTK_CONT|C.VINIX_PRINTK_NEWLINE)); C.assert(C.strcmp(&capture.records[1].text[0],c'short-lived')==0); C.assert(C.strcmp(&capture.records[2].text[0],c'nested:args -9')==0)
 C.assert(capture.records[3].level==u8(C.LOGLEVEL_ERR) && capture.records[4].level==4); C.assert(capture.records[5].flags&u8(C.VINIX_PRINTK_TRUNCATED)!=0); C.assert(capture.records[6].format_status&u32(C.VINIX_FORMAT_INVALID)!=0)
 logger_install(&capture); C.vinix_linuxkpi_warn_format(c'fixture.c',17,nil); C.vinix_linuxkpi_warn_format(c'fixture.c',18,c'owned warning %d\n',i32(-12)); C.assert(C.test_taint(C.TAINT_WARN)!=0); logger_finish(&capture,2)
 C.assert(C.strcmp(&capture.records[0].text[0],c'linuxkpi: warning at fixture.c:17')==0); C.assert(C.strcmp(&capture.records[1].text[0],c'linuxkpi: warning at fixture.c:18: owned warning -12')==0); C.assert(capture.records[0].level==u8(C.LOGLEVEL_WARNING) && capture.records[1].level==u8(C.LOGLEVEL_WARNING))
 logger_install(&capture); mut producers:=[4]LoggerProducer{}; mut producer_threads:=[4]C.pthread_t{}
 for i:=u32(0); i<4; i++ { producers[i].index=i; C.assert(C.pthread_create(&producer_threads[i],nil,C.vml_logger_produce,&producers[i])==0) }; for i:=u32(0); i<4; i++ { C.assert(C.pthread_join(producer_threads[i],nil)==0) }; logger_finish(&capture,64)
 mut seen:=[4]u32{}; for i:=u32(0); i<capture.count; i++ { mut index:=u32(0); mut value:=u32(0); C.assert(C.sscanf(&capture.records[i].text[0],c'producer %u:%u',&index,&value)==2); C.assert(index<4 && value<16 && seen[index]&(u32(1)<<value)==0); seen[index]|=u32(1)<<value; if i!=0 { C.assert(capture.records[i].sequence==capture.records[i-1].sequence+1) } }; for i:=u32(0); i<4; i++ { C.assert(seen[i]==0xffff) }
 logger_install(&capture); capture.hold=1; C.assert(C._printk(c'held')==4); held:=C.vinix_linuxkpi_printk_snapshot(); C.assert(C.vinix_linuxkpi_printk_test_pause(false,0)==0)
 for C.__atomic_load_n(&capture.entered,2)==0 { C.sched_yield() }; for i:=u32(0); i<80; i++ { C.assert(C._printk(c'overflow %u',i)>=10) }; overflow:=C.vinix_linuxkpi_printk_snapshot(); C.vinix_linuxkpi_printk_get_state(&state)
 C.assert(state.in_flight && state.retired==held-1 && state.dropped==before.dropped+16); C.assert(state.queued==64 && C.vinix_linuxkpi_printk_flush(held,0)==-i32(C.ETIMEDOUT)); C.__atomic_store_n(&capture.release,u32(1),3); C.assert(C.vinix_linuxkpi_printk_flush(overflow,2000)==0)
 C.assert(capture.count==65 && C.strcmp(&capture.records[1].text[0],c'overflow 16')==0); C.assert(C.strcmp(&capture.records[64].text[0],c'overflow 79')==0); logger_finish(&capture,65)
 logger_install(&capture); capture.hold=3; C.assert(C._printk(c'old')==3); mut flusher:=LoggerFlusher{snapshot:C.vinix_linuxkpi_printk_snapshot()}; C.vmh_sync_model_init(&flusher.model,82); C.assert(C.vinix_linuxkpi_printk_test_pause(false,0)==0)
 for C.__atomic_load_n(&capture.entered,2)==0 { C.sched_yield() }; mut flush_thread:=C.pthread_t{}; C.assert(C.pthread_create(&flush_thread,nil,C.vml_logger_flush_thread,&flusher)==0); for C.__atomic_load_n(&flusher.entered,2)==0 { C.sched_yield() }; C.assert(C.__atomic_load_n(&flusher.done,2)==0)
 C.assert(C._printk(c'late')==4); C.__atomic_fetch_or(&capture.release,u32(1),3); for u32(C.__atomic_load_n(&capture.entered,2))&2==0 { C.sched_yield() }; C.assert(C.pthread_join(flush_thread,nil)==0 && flusher.result==0); C.vmh_sync_model_destroy(&flusher.model)
 C.vinix_linuxkpi_printk_get_state(&state); C.assert(state.in_flight && state.retired==flusher.snapshot && capture.count==1); C.__atomic_fetch_or(&capture.release,u32(2),3); C.assert(C.vinix_linuxkpi_printk_flush(C.vinix_linuxkpi_printk_snapshot(),2000)==0); logger_finish(&capture,2)
 C.__atomic_store_n(&vml_logger_key_available,true,3); for { C.vinix_linuxkpi_printk_get_state(&state); if state.key_ready { break }; C.sched_yield() }; C.assert(C.__atomic_load_n(&vml_logger_key_attempts,2)!=0)
 C.assert(C.vinix_linuxkpi_printk_test_pause(false,0)==0); C.assert(C.vinix_linuxkpi_printk_shutdown()==0 && vml_logger_workers==0); C.assert(C.vinix_linuxkpi_printk_shutdown()==0); C.vinix_linuxkpi_printk_get_state(&state)
 C.assert(!state.worker_live && !state.in_flight && state.queued==0 && state.retired==state.submitted && state.dropped==before.dropped+16)
 C.assert(C.vinix_linuxkpi_printk_bootstrap()==0 && vml_logger_workers==1); C.assert(C._printk(c'\x01\x36reuse\n')==5); C.assert(C.vinix_linuxkpi_printk_flush(C.vinix_linuxkpi_printk_snapshot(),2000)==0); C.assert(C.vinix_linuxkpi_printk_shutdown()==0 && vml_logger_workers==0)
 C.__atomic_store_n(&vml_logger_tick_stop,true,3); C.assert(C.pthread_join(ticker,nil)==0); C.assert(C.vinix_linuxkpi_time_waiters()==0 && C.vmh_live_pages==pages); C.vmh_sync_model_destroy(&controller); C.vmh_native_task=nil
} }
@[export:'vmh_printk_cleanup_tests']
pub fn printk_cleanup_tests() { unsafe {
 pages:=C.vmh_live_pages; mut controller:=C.native_task_model{}; C.vmh_sync_model_init(&controller,83); C.vmh_native_task=&controller; C.assert(C.__atomic_load_n(&vml_logger_workers,2)==0); C.__atomic_store_n(&vml_logger_tick_stop,false,3)
 mut ticker:=C.pthread_t{}; C.assert(C.pthread_create(&ticker,nil,C.vml_logger_ticks,nil)==0); C.assert(C.vinix_linuxkpi_printk_bootstrap()==0); snapshot:=C.vinix_linuxkpi_printk_snapshot(); C.assert(C.vinix_linuxkpi_printk_flush(snapshot,2000)==0); C.assert(C.vinix_linuxkpi_printk_shutdown()==0)
 C.__atomic_store_n(&vml_logger_tick_stop,true,3); C.assert(C.pthread_join(ticker,nil)==0); mut state:=C.vinix_linuxkpi_printk_state{}; C.vinix_linuxkpi_printk_get_state(&state); C.assert(!state.worker_live && !state.in_flight && state.queued==0 && state.retired==state.submitted)
 C.assert(C.__atomic_load_n(&vml_logger_workers,2)==0); C.assert(C.vinix_linuxkpi_time_waiters()==0 && C.vmh_live_pages==pages); C.vmh_sync_model_destroy(&controller); C.vmh_native_task=nil
} }
