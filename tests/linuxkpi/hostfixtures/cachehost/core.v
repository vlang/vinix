// SPDX-License-Identifier: GPL-2.0-only
// Independent constructor, geometry, private refill and concurrent cache tests.
@[translated]
@[has_globals]
module cachehost
#include "cachehost_v_contract.h"
struct C.kmem_cache {}
type CacheCtor = fn (voidptr)
fn C.kmem_cache_create(&char,usize,usize,usize,CacheCtor) &C.kmem_cache
fn C.kmem_cache_destroy(&C.kmem_cache)
fn C.kmem_cache_zalloc(&C.kmem_cache,u32) voidptr
fn C.kmem_cache_alloc(&C.kmem_cache,u32) voidptr
fn C.kmem_cache_free(&C.kmem_cache,voidptr)
fn C.kmem_cache_size(&C.kmem_cache) usize
fn C.kmem_cache_shrink(&C.kmem_cache) i32
fn C.vinix_linuxkpi_alloc_gfp_pages(usize,u32) voidptr
fn C.vinix_linuxkpi_free_pages(voidptr,usize)
fn C.vinix_linuxkpi_page_size() usize
fn C.vinix_linuxkpi_irq_save() usize
fn C.vinix_linuxkpi_irq_restore(usize)
fn C.vinix_linuxkpi_preempt_disable()
fn C.vinix_linuxkpi_preempt_enable()
fn C.memchr_inv(voidptr,i32,usize) voidptr
fn C.atomic_read(&C.atomic_t) i32
fn C.pthread_cond_wait(&C.pthread_cond_t,&C.pthread_mutex_t) i32
fn C.pthread_cond_broadcast(&C.pthread_cond_t) i32
fn C.vmc_cache_ctor(voidptr)
fn C.vmc_cache_gated_ctor(voidptr)
fn C.vmc_cache_refill_thread(voidptr) voidptr
fn C.vmc_cache_stress_thread(voidptr) voidptr
const magic = u64(0x6b70692d63616368)
struct CacheObject { mut: magic u64 generation u32 payload [85]u8 }
__global vmc_ctor_calls = u32(0)
__global vmc_irq_ctor_calls = u32(0)
__global vmc_preempt_ctor_calls = u32(0)
struct CacheGeometry { size u32 hardware_alignment u32 }
const cases = [CacheGeometry{1,16},CacheGeometry{7,16},CacheGeometry{16,16},CacheGeometry{17,32},CacheGeometry{32,32},CacheGeometry{33,64},CacheGeometry{64,64},CacheGeometry{65,64},CacheGeometry{4095,64},CacheGeometry{4096,64},CacheGeometry{4097,64},CacheGeometry{8193,64}]!
fn cache_test_page_policy() { unsafe {
 before:=C.vmh_live_pages; C.__atomic_store_n(&C.vmh_last_reclaim,false,0); C.__atomic_store_n(&C.vmh_allocation_failure_after,i32(1),0)
 C.assert(C.vinix_linuxkpi_alloc_gfp_pages(0,C.GFP_KERNEL)==nil)
 C.assert(C.vinix_linuxkpi_alloc_gfp_pages(~usize(0)/C.vinix_linuxkpi_page_size()+1,C.GFP_KERNEL)==nil)
 C.assert(C.vinix_linuxkpi_alloc_gfp_pages(1,C.GFP_KERNEL|C.__GFP_DMA32)==nil)
 C.assert(C.__atomic_load_n(&C.vmh_allocation_failure_after,0)==1)
 C.assert(C.__atomic_load_n(&C.vmh_last_reclaim,0)==0 && C.vmh_live_pages==before)
 C.__atomic_store_n(&C.vmh_allocation_failure_after,i32(-1),0)
 flags:=[u32(C.GFP_KERNEL),u32(C.GFP_ATOMIC),u32(C.GFP_NOWAIT),u32(C.GFP_NOFS),u32(C.GFP_NOIO)]!
 for i:=u32(0); i<flags.len; i++ { pages:=C.vinix_linuxkpi_alloc_gfp_pages(1,flags[i]); C.assert(pages!=nil && (C.__atomic_load_n(&C.vmh_last_reclaim,0)!=0)==(i==0)); C.vinix_linuxkpi_free_pages(pages,1) }
 C.assert(C.vmh_live_pages==before)
} }
@[export:'vmc_cache_ctor']
pub fn cache_test_ctor(object voidptr) { unsafe {
 value:=&CacheObject(object); value.magic=magic; value.generation=0; C.memset(&value.payload[0],0x3c,sizeof(value.payload))
 C.__atomic_add_fetch(&vmc_ctor_calls,u32(1),0)
 if !C.vmh_interrupts { C.__atomic_add_fetch(&vmc_irq_ctor_calls,u32(1),0) }
 if C.vmh_preempt_depth!=0 { C.__atomic_add_fetch(&vmc_preempt_ctor_calls,u32(1),0) }
} }
fn cache_test_geometry_boundaries() { unsafe {
 before:=C.vmh_live_pages
 for hardware:=u32(0); hardware<2; hardware++ { for index:=u32(0); index<cases.len; index++ {
  size:=cases[index].size; alignment:=if hardware!=0 { cases[index].hardware_alignment } else { u32(16) }
  cache:=C.kmem_cache_create(c'geometry-boundary',size,0,if hardware!=0 { usize(C.SLAB_HWCACHE_ALIGN) } else { usize(0) },CacheCtor(nil))
  C.assert(cache!=nil && C.kmem_cache_size(cache)==size)
  mut objects:=[4]&u8{}; objects[0]=&u8(C.kmem_cache_zalloc(cache,C.GFP_KERNEL)); C.assert(objects[0]!=nil); populated:=C.vmh_live_pages
  if size<=65 { C.__atomic_store_n(&C.vmh_allocation_failure_after,i32(0),0) }
  for i:=u32(1); i<objects.len; i++ { objects[i]=&u8(C.kmem_cache_zalloc(cache,C.GFP_KERNEL)); C.assert(objects[i]!=nil) }
  C.__atomic_store_n(&C.vmh_allocation_failure_after,i32(-1),0); if size<=65 { C.assert(C.vmh_live_pages==populated) }
  for i:=u32(0); i<objects.len; i++ { C.assert(usize(objects[i])&(alignment-1)==0); C.assert(C.memchr_inv(objects[i],0,size)==nil); for j:=u32(0); j<i; j++ { C.assert(objects[i]!=objects[j]) }; C.memset(objects[i],i32(i+1),size) }
  C.assert(C.kmem_cache_shrink(cache)==1)
  for i:=u32(0); i<objects.len; i++ { C.assert(C.memchr_inv(objects[i],i32(i+1),size)==nil); C.kmem_cache_free(cache,objects[i]) }
  C.assert(C.kmem_cache_shrink(cache)==0); C.kmem_cache_destroy(cache); C.assert(C.vmh_live_pages==before)
 } }
} }
fn cache_test_basic() { unsafe {
 before:=C.vmh_live_pages; cache_test_page_policy(); cache_test_geometry_boundaries()
 rejected:=[usize(C.SLAB_TYPESAFE_BY_RCU),usize(C.SLAB_RECLAIM_ACCOUNT),usize(C.SLAB_CACHE_DMA),usize(C.SLAB_CACHE_DMA32),usize(C.SLAB_PANIC),usize(C.SLAB_RED_ZONE),usize(C.SLAB_POISON),usize(C.SLAB_STORE_USER),usize(C.SLAB_TRACE),usize(C.SLAB_NO_MERGE),usize(C.SLAB_NO_USER_FLAGS)]!
 for i:=u32(0); i<rejected.len; i++ { C.assert(C.kmem_cache_create(c'unsupported',97,0,rejected[i],CacheCtor(nil))==nil) }
 C.assert(C.kmem_cache_create(nil,97,0,0,CacheCtor(nil))==nil); C.assert(C.kmem_cache_create(c'empty',0,0,0,CacheCtor(nil))==nil); C.assert(C.kmem_cache_create(c'unaligned',97,3,0,CacheCtor(nil))==nil)
 mut irq:=C.vinix_linuxkpi_irq_save(); C.assert(C.kmem_cache_create(c'atomic-create',97,0,0,CacheCtor(nil))==nil); C.vinix_linuxkpi_irq_restore(irq)
 for stage:=i32(0); stage<2; stage++ { C.__atomic_store_n(&C.vmh_allocation_failure_after,stage,0); C.assert(C.kmem_cache_create(c'create-rollback',97,0,0,CacheCtor(nil))==nil); C.__atomic_store_n(&C.vmh_allocation_failure_after,i32(-1),0); C.assert(C.vmh_live_pages==before) }
 alignments:=[u32(0),16,64,256,4096,8192]!
 for i:=u32(0); i<alignments.len; i++ {
  cache:=C.kmem_cache_create(c'alignment',97,alignments[i],C.SLAB_HWCACHE_ALIGN,CacheCtor(nil)); C.assert(cache!=nil && C.kmem_cache_size(cache)==97)
  object:=&u8(C.kmem_cache_zalloc(cache,C.GFP_KERNEL)); alignment:=if alignments[i]>64 { alignments[i] } else { u32(64) }
  C.assert(object!=nil && usize(object)&(alignment-1)==0); C.assert(C.memchr_inv(object,0,97)==nil); C.memset(object,0xe1,97)
  C.assert(C.kmem_cache_shrink(cache)==1); C.assert(C.memchr_inv(object,0xe1,97)==nil); C.kmem_cache_free(cache,object); C.kmem_cache_free(cache,nil); C.assert(C.kmem_cache_shrink(cache)==0); C.kmem_cache_destroy(cache); C.assert(C.vmh_live_pages==before)
 }
 atomic_cache:=C.kmem_cache_create(c'atomic-refill',sizeof(CacheObject),0,0,C.vmc_cache_ctor); C.assert(atomic_cache!=nil)
 mut calls_before:=vmc_ctor_calls; irq_calls_before:=vmc_irq_ctor_calls; irq=C.vinix_linuxkpi_irq_save()
 mut atomic_object:=&CacheObject(C.kmem_cache_alloc(atomic_cache,C.GFP_KERNEL)); C.assert(atomic_object!=nil && atomic_object.magic==magic)
 C.assert(!C.vmh_interrupts && C.vmh_preempt_depth==0 && C.__atomic_load_n(&C.vmh_last_reclaim,0)==0); C.vinix_linuxkpi_irq_restore(irq)
 C.assert(vmc_ctor_calls>calls_before); C.assert(vmc_ctor_calls-calls_before==vmc_irq_ctor_calls-irq_calls_before)
 C.kmem_cache_free(atomic_cache,atomic_object); C.assert(C.kmem_cache_shrink(atomic_cache)==0)
 calls_before=vmc_ctor_calls; pinned_calls_before:=vmc_preempt_ctor_calls; C.vinix_linuxkpi_preempt_disable()
 atomic_object=&CacheObject(C.kmem_cache_alloc(atomic_cache,C.GFP_KERNEL)); C.assert(atomic_object!=nil && C.vmh_interrupts && C.vmh_preempt_depth==1)
 C.assert(C.__atomic_load_n(&C.vmh_last_reclaim,0)==0); C.vinix_linuxkpi_preempt_enable()
 C.assert(vmc_ctor_calls>calls_before); C.assert(vmc_ctor_calls-calls_before==vmc_preempt_ctor_calls-pinned_calls_before)
 C.kmem_cache_free(atomic_cache,atomic_object); C.kmem_cache_destroy(atomic_cache); C.assert(C.vmh_live_pages==before)
 mut objects:=[256]&CacheObject{}
 cache:=C.kmem_cache_create(c'constructor',sizeof(CacheObject),0,C.SLAB_HWCACHE_ALIGN,C.vmc_cache_ctor); C.assert(cache!=nil && C.kmem_cache_size(cache)==sizeof(CacheObject))
 descriptor_pages:=C.vmh_live_pages; C.__atomic_store_n(&C.vmh_allocation_failure_after,i32(0),0); C.assert(C.kmem_cache_alloc(cache,C.GFP_KERNEL)==nil)
 C.assert(C.vmh_live_pages==descriptor_pages && C.kmem_cache_shrink(cache)==0); C.__atomic_store_n(&C.vmh_allocation_failure_after,i32(-1),0)
 objects[0]=&CacheObject(C.kmem_cache_alloc(cache,C.GFP_KERNEL)); C.assert(objects[0]!=nil); constructors:=u32(C.__atomic_load_n(&vmc_ctor_calls,2)); C.__atomic_store_n(&C.vmh_allocation_failure_after,i32(0),0)
 mut count:=u32(1)
 for count<objects.len { objects[count]=&CacheObject(C.kmem_cache_alloc(cache,C.GFP_ATOMIC)); if objects[count]==nil { break }; count++ }
 C.assert(count>1 && count<objects.len); C.assert(C.__atomic_load_n(&C.vmh_last_reclaim,0)==0); C.assert(C.__atomic_load_n(&vmc_ctor_calls,2)==constructors)
 for i:=u32(0); i<count; i++ { C.assert(objects[i].magic==magic && objects[i].generation==0); objects[i].generation=i+17; C.memset(&objects[i].payload[0],0xb7,sizeof(objects[i].payload)); for j:=u32(0); j<i; j++ { C.assert(usize(objects[j])!=usize(objects[i])) } }
 only_free:=objects[0]; C.kmem_cache_free(cache,only_free)
 bad_gfp:=[u32(C.GFP_KERNEL|C.__GFP_DMA32),u32(C.GFP_KERNEL|C.__GFP_NOFAIL),u32(C.GFP_KERNEL|C.__GFP_ACCOUNT),u32(C.GFP_KERNEL|C.__GFP_HIGHMEM)]!
 for i:=u32(0); i<bad_gfp.len; i++ { C.assert(C.kmem_cache_alloc(cache,bad_gfp[i])==nil) }
 irq=C.vinix_linuxkpi_irq_save(); objects[0]=&CacheObject(C.kmem_cache_alloc(cache,C.GFP_KERNEL)); C.assert(usize(objects[0])==usize(only_free) && !C.vmh_interrupts && C.vmh_preempt_depth==0); C.vinix_linuxkpi_irq_restore(irq)
 C.assert(objects[0].magic==magic && objects[0].generation==17); C.assert(C.memchr_inv(&objects[0].payload[0],0xb7,sizeof(objects[0].payload))==nil); C.assert(C.kmem_cache_shrink(cache)==1)
 for i:=u32(0); i<count; i++ { C.kmem_cache_free(cache,objects[i]) }; C.assert(C.vmh_live_pages>descriptor_pages); C.assert(C.kmem_cache_shrink(cache)==0 && C.vmh_live_pages==descriptor_pages); C.assert(C.kmem_cache_alloc(cache,C.GFP_NOWAIT)==nil); C.__atomic_store_n(&C.vmh_allocation_failure_after,i32(-1),0)
 warnings:=C.atomic_read(&C.vmh_time_warnings); mut zeroed:=&CacheObject(C.kmem_cache_zalloc(cache,C.GFP_KERNEL))
 C.assert(zeroed!=nil && C.memchr_inv(zeroed,0,sizeof(CacheObject))==nil); C.assert(C.atomic_read(&C.vmh_time_warnings)==warnings+1); C.kmem_cache_free(cache,zeroed)
 zeroed=&CacheObject(C.kmem_cache_zalloc(cache,C.GFP_ATOMIC)); C.assert(zeroed!=nil && C.memchr_inv(zeroed,0,sizeof(CacheObject))==nil); C.assert(C.atomic_read(&C.vmh_time_warnings)==warnings+1); C.kmem_cache_free(cache,zeroed); C.kmem_cache_destroy(cache); C.assert(C.vmh_live_pages==before); C.kmem_cache_destroy(nil)
} }
struct CacheGate { mut: lock C.pthread_mutex_t changed C.pthread_cond_t entered bool release bool claimed u32 }
__global vmc_ctor_gate = &CacheGate(unsafe { nil })
@[export:'vmc_cache_gated_ctor']
pub fn cache_test_gated_ctor(object voidptr) { unsafe {
 cache_test_ctor(object); gate:=vmc_ctor_gate; mut expected:=u32(0)
 if gate==nil || !C.__atomic_compare_exchange_n(&gate.claimed,&expected,u32(1),false,4,0) { return }
 C.assert(C.vmh_interrupts && C.vmh_preempt_depth==0 && C.pthread_mutex_lock(&gate.lock)==0)
 gate.entered=true; C.assert(C.pthread_cond_broadcast(&gate.changed)==0)
 for !gate.release { C.assert(C.pthread_cond_wait(&gate.changed,&gate.lock)==0) }; C.assert(C.pthread_mutex_unlock(&gate.lock)==0)
} }
struct CacheRefill { mut: cache &C.kmem_cache object &CacheObject done u32 }
@[export:'vmc_cache_refill_thread']
pub fn cache_test_refill_thread(argument voidptr) voidptr { unsafe {
 test:=&CacheRefill(argument); test.object=&CacheObject(C.kmem_cache_alloc(test.cache,C.GFP_KERNEL)); C.assert(test.object!=nil && test.object.magic==magic); C.__atomic_store_n(&test.done,u32(1),3); return nil
} }
fn cache_test_private_refill() { unsafe {
 before:=C.vmh_live_pages; mut gate:=CacheGate{lock:C.vmh_mutex_initializer,changed:C.vmh_condition_initializer}
 cache:=C.kmem_cache_create(c'private-refill',sizeof(CacheObject),0,0,C.vmc_cache_gated_ctor); C.assert(cache!=nil); vmc_ctor_gate=&gate
 mut tests:=[CacheRefill{cache:cache},CacheRefill{cache:cache}]!; mut threads:=[2]C.pthread_t{}
 C.assert(C.pthread_create(&threads[0],nil,C.vmc_cache_refill_thread,&tests[0])==0); C.assert(C.pthread_mutex_lock(&gate.lock)==0)
 for !gate.entered { C.assert(C.pthread_cond_wait(&gate.changed,&gate.lock)==0) }; C.assert(C.pthread_mutex_unlock(&gate.lock)==0); C.assert(C.kmem_cache_shrink(cache)==1)
 C.assert(C.pthread_create(&threads[1],nil,C.vmc_cache_refill_thread,&tests[1])==0)
 for spin:=u32(0); C.__atomic_load_n(&tests[1].done,2)==0; spin++ { C.assert(spin<1000000); C.sched_yield() }
 C.assert(tests[1].object.magic==magic && tests[0].done==0); C.assert(C.kmem_cache_shrink(cache)==1)
 C.assert(C.pthread_mutex_lock(&gate.lock)==0); gate.release=true; C.assert(C.pthread_cond_broadcast(&gate.changed)==0); C.assert(C.pthread_mutex_unlock(&gate.lock)==0)
 for i:=u32(0); i<2; i++ { C.assert(C.pthread_join(threads[i],nil)==0) }; vmc_ctor_gate=nil
 C.assert(usize(tests[0].object)!=usize(tests[1].object) && tests[0].object.magic==magic); for i:=u32(0); i<2; i++ { C.kmem_cache_free(cache,tests[i].object) }
 C.assert(C.kmem_cache_shrink(cache)==0); C.kmem_cache_destroy(cache); C.assert(C.pthread_cond_destroy(&gate.changed)==0 && C.pthread_mutex_destroy(&gate.lock)==0); C.assert(C.vmh_live_pages==before)
} }
struct CacheStress { mut: cache &C.kmem_cache index u32 start &u32 }
@[export:'vmc_cache_stress_thread']
pub fn cache_test_stress_thread(argument voidptr) voidptr { unsafe {
 test:=&CacheStress(argument); C.vmh_current_cpu=test.index
 for C.__atomic_load_n(test.start,2)==0 { C.sched_yield() }
 for repeat:=u32(0); repeat<100; repeat++ { mut objects:=[16]&CacheObject{}
  for i:=u32(0); i<objects.len; i++ { mut irq:=usize(0); if repeat&1!=0 { irq=C.vinix_linuxkpi_irq_save() }
   objects[i]=&CacheObject(C.kmem_cache_alloc(test.cache,if repeat&1!=0 { u32(C.GFP_ATOMIC) } else { u32(C.GFP_KERNEL) })); C.assert(objects[i]!=nil && objects[i].magic==magic)
   C.assert(C.vmh_interrupts==(repeat&1==0) && C.vmh_preempt_depth==0); if repeat&1!=0 { C.vinix_linuxkpi_irq_restore(irq) }
   objects[i].generation=test.index+1; C.memset(&objects[i].payload[0],i32(test.index),sizeof(objects[i].payload))
  }
  for i:=u32(0); i<objects.len; i++ { C.assert(objects[i].generation==test.index+1); C.assert(C.memchr_inv(&objects[i].payload[0],i32(test.index),sizeof(objects[i].payload))==nil); C.kmem_cache_free(test.cache,objects[i]) }; C.sched_yield()
 }; return nil
} }
@[export:'vmh_cache_tests']
pub fn cache_tests() { unsafe {
 before:=C.vmh_live_pages; cache_test_basic(); cache_test_private_refill()
 cache:=C.kmem_cache_create(c'concurrent',sizeof(CacheObject),0,C.SLAB_HWCACHE_ALIGN,C.vmc_cache_ctor); C.assert(cache!=nil)
 mut tests:=[4]CacheStress{}; mut threads:=[4]C.pthread_t{}; mut start:=u32(0)
 for i:=u32(0); i<tests.len; i++ { tests[i]=CacheStress{cache:cache,index:i,start:&start}; C.assert(C.pthread_create(&threads[i],nil,C.vmc_cache_stress_thread,&tests[i])==0) }
 C.__atomic_store_n(&start,u32(1),3)
 for i:=u32(0); i<1000; i++ { left:=C.kmem_cache_shrink(cache); C.assert(left==0 || left==1); C.sched_yield() }
 for i:=u32(0); i<tests.len; i++ { C.assert(C.pthread_join(threads[i],nil)==0) }
 C.assert(C.kmem_cache_shrink(cache)==0); C.kmem_cache_destroy(cache); C.assert(C.vmh_live_pages==before && C.vmh_interrupts && C.vmh_preempt_depth==0)
} }
