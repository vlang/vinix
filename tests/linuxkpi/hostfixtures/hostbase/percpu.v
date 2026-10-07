// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
@[has_globals]
module hostbase
#include "hostbase_v_contract.h"
@[aligned:64]
struct CpuRecord {
mut:
 counter usize
 bytes [15]u8
}
struct CpuWorker {
 cpu u32
 dynamic &CpuRecord
}
@[export:'vmh_cpu_byte'] __global cpu_byte u8 = 0x37
@[export:'vmh_cpu_half'] __global cpu_half u16 = 0x1234
@[export:'vmh_cpu_word'] __global cpu_word u32 = 0x12345678
@[export:'vmh_cpu_wide'] __global cpu_wide u64 = 0x123456789abcdef0
@[cinit; export:'vmh_cpu_record'] __global cpu_record CpuRecord = CpuRecord{counter:17,bytes:[u8(1),2,3,0,0,0,0,0,0,0,0,0,0,0,0]!}
@[c_extern] __global C.vmh_host_percpu_start u8
@[c_extern] __global C.vmh_host_percpu_end u8
@[c_extern] __global C.vmh_cpu_record_type i32
@[c_extern] __global C.EBUSY i32
@[c_extern] __global C.EINVAL i32
fn C.vinix_linuxkpi_percpu_init(u32,voidptr,voidptr) i32
fn C.vinix_linuxkpi_percpu_destroy_for_test()
fn C.__alloc_percpu(usize,usize) voidptr
fn C.__alloc_percpu_gfp(usize,usize,u32) voidptr
fn C.alloc_percpu(i32) voidptr
fn C.free_percpu(voidptr)
fn C.per_cpu_ptr(voidptr,u32) voidptr
fn C.per_cpu(u64,u32) u64
fn C.this_cpu_read(u64) u64
fn C.this_cpu_inc(u64)
fn C.this_cpu_add(u64,u64)
fn C.this_cpu_write(u8,u8)
fn C.this_cpu_try_cmpxchg(u32,&u32,u32) bool
fn C.this_cpu_xchg(u16,u16) u16
fn C.this_cpu_read_stable(u16) u16
fn C.vmh_get_cpu_var_address(u16) &u16
fn C.put_cpu_var(u16)
fn C.get_cpu_ptr(voidptr) voidptr
fn C.put_cpu_ptr(voidptr)
fn C.preempt_disable()
fn C.preempt_enable()
fn C.preempt_enable_no_resched()
fn C.preemptible() bool
fn C.preempt_count() i32
fn C.this_cpu_or(u8,u8)
fn C.this_cpu_ptr(voidptr) voidptr
fn C.vmh_percpu_worker(voidptr) voidptr
@[export:'vmh_percpu_worker']
pub fn percpu_worker(argument voidptr) voidptr { unsafe {
 worker:=&CpuWorker(argument);C.vmh_current_cpu=worker.cpu
 C.assert(C.preemptible() && C.preempt_count()==0)
 C.assert(C.this_cpu_read(cpu_byte)==0x37 && C.this_cpu_read(cpu_half)==0x1234)
 C.assert(C.this_cpu_read(cpu_word)==0x12345678);C.assert(C.this_cpu_read(cpu_wide)==u64(0x123456789abcdef0))
 pinned:=&usize(C.get_cpu_ptr(&cpu_record.counter));C.assert(C.preempt_count()==1 && !C.preemptible() && *pinned==17)
 C.preempt_disable();C.assert(C.preempt_count()==2);C.preempt_enable_no_resched();C.assert(C.preempt_count()==1)
 C.put_cpu_ptr(pinned);C.assert(C.preemptible())
 for i:=u32(0);i<20000;i++ { C.this_cpu_inc(cpu_wide);C.this_cpu_add(cpu_record.counter,3);C.this_cpu_inc(worker.dynamic.counter)
  C.this_cpu_write(cpu_byte,u8(i));C.assert(C.preempt_count()==0 && C.vmh_interrupts)
 }
 mut expected:=u32(0);C.assert(!C.this_cpu_try_cmpxchg(cpu_word,&expected,1) && expected==u32(0x12345678))
 C.assert(C.this_cpu_try_cmpxchg(cpu_word,&expected,worker.cpu+1))
 C.assert(C.this_cpu_xchg(cpu_half,7)==0x1234 && C.this_cpu_read_stable(cpu_half)==7)
 half_ptr:= C.vmh_get_cpu_var_address(cpu_half);*half_ptr=9
 C.assert(C.preempt_count()==1);C.put_cpu_var(cpu_half)
 mut flags:=usize(0);C.local_irq_save(flags);C.this_cpu_or(cpu_byte,0x80)
 C.assert(C.irqs_disabled() && C.preempt_count()==0);C.local_irq_restore(flags)
 C.preempt_disable();(&u8(C.this_cpu_ptr(&worker.dynamic.bytes[3])))[0]=u8(worker.cpu+1);C.preempt_enable();return nil
} }
@[export:'vmh_percpu_tests']
pub fn percpu_tests() { unsafe {
 C.assert(C.vinix_linuxkpi_percpu_init(4,&C.vmh_host_percpu_start,&C.vmh_host_percpu_end)==-C.EBUSY)
 C.assert(C.__alloc_percpu(0,8)==nil && C.__alloc_percpu(8,0)==nil && C.__alloc_percpu(8,3)==nil)
 C.assert(C.__alloc_percpu(8,8192)==nil && C.__alloc_percpu(C.SIZE_MAX,8)==nil)
 C.assert(C.__alloc_percpu(C.SIZE_MAX/2,8)==nil);C.assert(C.__alloc_percpu_gfp(8,8,C.GFP_KERNEL|C.__GFP_DMA32)==nil)
 C.vmh_fail_allocation=true;C.assert(C.alloc_percpu(C.vmh_cpu_record_type)==nil);C.vmh_fail_allocation=false;C.free_percpu(nil)
 C.assert(C.per_cpu_ptr(&u8(nil),0)==nil)
 for align:=usize(1);align<=4096;align*=2 {
  buffer:=&u8(C.__alloc_percpu_gfp(align+1,align,C.GFP_ATOMIC));C.assert(buffer!=nil && !C.vmh_last_reclaim)
  for cpu:=u32(0);cpu<4;cpu++ { slot:=&u8(C.per_cpu_ptr(buffer,cpu));C.assert(usize(slot)%align==0 && C.memchr_inv(slot,0,align+1)==nil);C.memset(slot,i32(cpu+1),align+1) }
  for cpu:=u32(0);cpu<4;cpu++ { C.assert(C.memchr_inv(C.per_cpu_ptr(buffer,cpu),i32(cpu+1),align+1)==nil) }
  C.free_percpu(buffer)
 }
 dynamic:=&CpuRecord(C.alloc_percpu(C.vmh_cpu_record_type));C.assert(dynamic!=nil)
 mut workers:=[4]CpuWorker{};mut threads:=[4]C.pthread_t{}
 for cpu:=u32(0);cpu<4;cpu++ {
  C.assert(usize(C.per_cpu_ptr(&cpu_record,cpu))%64==0);C.assert(C.memchr_inv(C.per_cpu_ptr(dynamic,cpu),0,sizeof(CpuRecord))==nil)
  C.assert(usize(C.per_cpu_ptr(&cpu_record.bytes[3],cpu))==usize(&(&CpuRecord(C.per_cpu_ptr(&cpu_record,cpu))).bytes[3]))
  workers[cpu]=CpuWorker{cpu,dynamic};C.assert(C.pthread_create(&threads[cpu],nil,C.vmh_percpu_worker,&workers[cpu])==0)
 }
 for cpu:=u32(0);cpu<4;cpu++ { C.assert(C.pthread_join(threads[cpu],nil)==0) }
 for cpu:=u32(0);cpu<4;cpu++ {
  C.assert(C.per_cpu(cpu_wide,cpu)==u64(0x123456789abcdef0)+20000)
  C.assert(C.per_cpu(cpu_record.counter,cpu)==17+60000)
  C.assert(C.per_cpu(cpu_word,cpu)==cpu+1 && C.per_cpu(cpu_half,cpu)==9)
  C.assert((&CpuRecord(C.per_cpu_ptr(dynamic,cpu))).counter==20000)
  C.assert(*(&u8(C.per_cpu_ptr(&dynamic.bytes[3],cpu)))==cpu+1)
 }
 C.free_percpu(dynamic);C.assert(C.vmh_live_pages==C.vmh_permanent_pages && C.preemptible())
} }
