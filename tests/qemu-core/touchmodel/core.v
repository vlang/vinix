// SPDX-License-Identifier: BSD-2-Clause
// Shared host API inputs; real mappings, fork, protection and threads remain OS calls.
@[translated]
@[has_globals]
module touchmodel
#include <touch-model-native-abi.h>
struct C.sysinfo { mut: freeram u64 }
@[typedef] struct C.pthread_mutex_t {}
@[typedef] struct C.pthread_cond_t {}
@[typedef] struct C.vqt_const_void_p {}
@[typedef] struct C.pthread_barrier_t { mut:
 lock C.pthread_mutex_t
 changed C.pthread_cond_t
 participants u32
 arrived u32
 generation u32
}
@[c_extern] __global C.errno i32
fn C.assert(bool)
fn C.__atomic_fetch_add(&u32,u32,i32) u32
fn C.memset(voidptr,i32,usize) voidptr
fn C.memcpy(voidptr,voidptr,usize) voidptr
fn C.mmap(voidptr,usize,i32,i32,i32,i64) voidptr
fn C.munmap(voidptr,usize) i32
fn C.mprotect(voidptr,usize,i32) i32
fn C.pthread_mutex_init(&C.pthread_mutex_t,voidptr) i32
fn C.pthread_mutex_lock(&C.pthread_mutex_t) i32
fn C.pthread_mutex_unlock(&C.pthread_mutex_t) i32
fn C.pthread_mutex_destroy(&C.pthread_mutex_t) i32
fn C.pthread_cond_init(&C.pthread_cond_t,voidptr) i32
fn C.pthread_cond_wait(&C.pthread_cond_t,&C.pthread_mutex_t) i32
fn C.pthread_cond_broadcast(&C.pthread_cond_t) i32
fn C.pthread_cond_destroy(&C.pthread_cond_t) i32
fn C.pipe(&i32) i32
fn C.close(i32) i32
fn C.read(i32,voidptr,usize) isize
fn C.write(i32,voidptr,usize) isize
fn C.fork() i32
fn C._exit(i32)
fn C.fflush(voidptr) i32
fn C.puts(&char) i32
fn C.original_test_anonymous_first_touch() i32
fn C.test_anonymous_first_touch() i32
fn C.reap_ok(i32) i32
fn C.original_reap_ok(i32) i32
__global (
 info_calls i32
 info_failure i32
 event_count u32
 events [32]u64
)
fn event(kind u64,argument u64) { unsafe {
 slot:=u32(C.__atomic_fetch_add(&event_count,u32(1),0))
 C.assert(slot<32)
 events[slot]=(kind<<56)^argument
} }
@[export:'vqt_host_sysinfo']
pub fn information(out &C.sysinfo) i32 { unsafe {
 info_calls++;event(1,u64(info_calls))
 if info_calls==info_failure { C.errno=C.EIO;return -1 }
 C.memset(out,0,sizeof(C.sysinfo))
 // External Linux free-memory input, independent of C/V implementation.
 out.freeram=if info_calls==4 { u64(96*1024*1024) } else { u64(100*1024*1024) }
 return 0
} }
@[export:'vqt_host_mmap']
pub fn map(address voidptr,length usize,protection i32,flags i32,fd i32,offset i64) voidptr { unsafe {
 event(2,u64(length) ^ (u64(u32(protection))<<40) ^ (u64(u32(flags))<<24))
 // Darwin has no Linux MAP_POPULATE. Native guest comparisons prove population.
 return C.mmap(address,length,protection,flags & ~i32(C.MAP_POPULATE),fd,offset)
} }
@[export:'vqt_host_munmap']
pub fn unmap(address voidptr,length usize) i32 { unsafe { event(3,u64(length));return C.munmap(address,length) } }
@[export:'vqt_host_mprotect']
pub fn protect(address voidptr,length usize,protection i32) i32 { unsafe { event(4,u64(length) ^ (u64(u32(protection))<<40));return C.mprotect(address,length,protection) } }
@[export:'vqt_host_barrier_init']
pub fn barrier_init(barrier &C.pthread_barrier_t,native_attributes C.vqt_const_void_p,count u32) i32 { unsafe {
 mut attributes:=voidptr(nil);C.memcpy(&attributes,&native_attributes,sizeof(C.vqt_const_void_p))
 C.assert(attributes==nil && count==3);event(5,u64(count))
 result:=C.pthread_mutex_init(&barrier.lock,nil);if result!=0 { return result }
 condition:=C.pthread_cond_init(&barrier.changed,nil)
 if condition!=0 { C.pthread_mutex_destroy(&barrier.lock);return condition }
 barrier.participants=count;barrier.arrived=0;barrier.generation=0;return 0
} }
@[export:'vqt_host_barrier_wait']
pub fn barrier_wait(barrier &C.pthread_barrier_t) i32 { unsafe {
 C.assert(C.pthread_mutex_lock(&barrier.lock)==0);event(6,u64(barrier.participants))
 generation:=barrier.generation;barrier.arrived++
 if barrier.arrived==barrier.participants {
  barrier.arrived=0;barrier.generation++;C.assert(C.pthread_cond_broadcast(&barrier.changed)==0)
  C.assert(C.pthread_mutex_unlock(&barrier.lock)==0);return C.PTHREAD_BARRIER_SERIAL_THREAD
 }
 for barrier.generation==generation { C.assert(C.pthread_cond_wait(&barrier.changed,&barrier.lock)==0) }
 C.assert(C.pthread_mutex_unlock(&barrier.lock)==0);return 0
} }
@[export:'vqt_host_barrier_destroy']
pub fn barrier_destroy(barrier &C.pthread_barrier_t) i32 { unsafe {
 event(7,0);C.assert(barrier.arrived==0)
 result:=C.pthread_cond_destroy(&barrier.changed);if result!=0 { return result }
 return C.pthread_mutex_destroy(&barrier.lock)
} }
fn attempt(original bool,failure i32) [36]u64 { unsafe {
 mut endpoints:=[2]i32{};C.assert(C.pipe(&endpoints[0])==0);C.fflush(nil)
 child:=C.fork();C.assert(child>=0)
 if child==0 {
  C.close(endpoints[0]);info_calls=0;info_failure=failure;event_count=0;C.errno=C.E2BIG
  result:=if original { C.original_test_anonymous_first_touch() } else { C.test_anonymous_first_touch() }
  mut report:=[36]u64{};report[0]=u64(result);report[1]=u64(u32(C.errno));report[2]=u64(info_calls);report[3]=u64(event_count)
  for i in 0..32 { report[4+i]=events[i] }
  C.assert(C.write(endpoints[1],&report[0],sizeof(report))==isize(sizeof(report)));C.fflush(nil);C._exit(0)
 }
 C.close(endpoints[1]);mut report:=[36]u64{}
 C.assert(C.read(endpoints[0],&report[0],sizeof(report))==isize(sizeof(report)))
 C.assert(C.close(endpoints[0])==0 && C.reap_ok(child)==0);return report
} }
@[export:'reap_ok']
pub fn reap(child i32) i32 { return C.original_reap_ok(child) }
@[export:'main']
pub fn main_entry() i32 { unsafe {
 for failure:=i32(0);failure<=4;failure++ {
  original:=attempt(true,failure);ported:=attempt(false,failure)
  for field in 0..36 { C.assert(original[field]==ported[field]) }
  C.assert(ported[0]==if failure==0 { u64(0) } else { u64(1) })
 }
 C.puts(c'QEMU CORE TOUCH HOST DIFFERENTIAL PASS: five native mapping/thread cases');return 0
} }
