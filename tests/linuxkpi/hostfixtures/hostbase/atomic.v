// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
@[has_globals]
module hostbase
#include "hostbase_v_contract.h"
@[typedef] struct C.spinlock_t {}
@[typedef] struct C.raw_spinlock_t {}
@[typedef] struct C.atomic64_t {}
@[typedef] struct C.atomic_long_t {}
@[typedef] struct C.refcount_t {}
@[typedef] struct C.vmh_s64 {}
struct C.kref {}
fn C.raw_spin_is_locked(&C.raw_spinlock_t) bool
fn C.irqs_disabled() bool
fn C.irqs_disabled_flags(usize) bool
fn C.raw_spin_trylock_irqsave(&C.raw_spinlock_t,usize) bool
fn C.raw_spin_unlock_irqrestore(&C.raw_spinlock_t,usize)
fn C.raw_spin_lock_irqsave(&C.raw_spinlock_t,usize)
fn C.raw_spin_lock(&C.raw_spinlock_t)
fn C.raw_spin_unlock(&C.raw_spinlock_t)
fn C.raw_spin_lock_irq(&C.raw_spinlock_t)
fn C.raw_spin_unlock_irq(&C.raw_spinlock_t)
fn C.local_irq_save(usize)
fn C.local_irq_restore(usize)
fn C.ATOMIC_INIT(i32) C.atomic_t
fn C.__SPIN_LOCK_UNLOCKED(C.spinlock_t) C.spinlock_t
fn C.spin_lock_irqsave(&C.spinlock_t,usize)
fn C.spin_unlock_irqrestore(&C.spinlock_t,usize)
fn C.spin_lock_init(&C.spinlock_t)
fn C.spin_trylock(&C.spinlock_t) bool
fn C.atomic_inc(&C.atomic_t)
fn C.atomic_read(&C.atomic_t) i32
fn C.atomic_cmpxchg(&C.atomic_t,i32,i32) i32
fn C.atomic_xchg(&C.atomic_t,i32) i32
fn C.atomic_dec_and_test(&C.atomic_t) bool
fn C.ATOMIC64_INIT(C.vmh_s64) C.atomic64_t
fn C.atomic64_inc_return(&C.atomic64_t) C.vmh_s64
fn C.atomic_fetch_inc_relaxed(&C.atomic_t) i32
fn C.atomic_try_cmpxchg_acquire(&C.atomic_t,&i32,i32) bool
fn C.atomic_try_cmpxchg_release(&C.atomic_t,&i32,i32) bool
fn C.atomic_fetch_andnot(i32,&C.atomic_t) i32
fn C.atomic_or(i32,&C.atomic_t)
fn C.atomic_fetch_xor_acquire(i32,&C.atomic_t) i32
fn C.atomic_add_unless(&C.atomic_t,i32,i32) bool
fn C.atomic_set(&C.atomic_t,i32)
fn C.atomic_inc_not_zero(&C.atomic_t) bool
fn C.atomic64_set(&C.atomic64_t,C.vmh_s64)
fn C.atomic64_add_return_relaxed(C.vmh_s64,&C.atomic64_t) C.vmh_s64
fn C.atomic64_try_cmpxchg_relaxed(&C.atomic64_t,&C.vmh_s64,C.vmh_s64) bool
fn C.atomic64_try_cmpxchg(&C.atomic64_t,&C.vmh_s64,C.vmh_s64) bool
fn C.ATOMIC_LONG_INIT(isize) C.atomic_long_t
fn C.REFCOUNT_INIT(u32) C.refcount_t
fn C.atomic_long_set(&C.atomic_long_t,isize)
fn C.atomic_long_fetch_add_release(isize,&C.atomic_long_t) isize
fn C.atomic_long_read_acquire(&C.atomic_long_t) isize
fn C.xchg(&usize,usize) usize
fn C.cmpxchg_acquire(&usize,usize,usize) usize
fn C.try_cmpxchg_release(&usize,&usize,usize) bool
fn C.try_cmpxchg(&usize,&usize,usize) bool
fn C.atomic_cond_read_acquire(&C.atomic_t,bool) i32
fn C.atomic_set_release(&C.atomic_t,i32)
fn C.atomic_fetch_inc(&C.atomic_t) i32
fn C.refcount_inc_not_zero(&C.refcount_t) bool
fn C.refcount_inc(&C.refcount_t)
fn C.refcount_read(&C.refcount_t) u32
fn C.refcount_dec_and_test(&C.refcount_t) bool
fn C.refcount_set(&C.refcount_t,u32)
fn C.refcount_add(u32,&C.refcount_t)
fn C.refcount_sub_and_test(u32,&C.refcount_t) bool
fn C.refcount_dec_if_one(&C.refcount_t) bool
fn C.refcount_dec_and_lock_irqsave(&C.refcount_t,&C.spinlock_t,&usize) bool
fn C.kref_init(&C.kref)
fn C.kref_get(&C.kref)
fn C.kref_put(&C.kref,fn(&C.kref)) i32
fn C.kzalloc(usize,u32) voidptr
fn C.vmh_concurrent_worker(voidptr) voidptr
fn C.vmh_message_writer(voidptr) voidptr
fn C.vmh_message_reader(voidptr) voidptr
fn C.vmh_release_object(&C.kref)
fn C.vmh_reference_worker(voidptr) voidptr
@[c_extern] __global C.INT_MIN i32
@[c_extern] __global C.VAL i32
@[c_extern] __global C.REFCOUNT_SATURATED u32
@[cinit] __global (
 counter C.atomic_t = C.ATOMIC_INIT(0)
 concurrent_lock C.spinlock_t = C.__SPIN_LOCK_UNLOCKED(concurrent_lock)
 published C.atomic_t = C.ATOMIC_INIT(0)
 releases C.atomic_t = C.ATOMIC_INIT(0)
)
__global locked_count u32
__global message [2]u64
fn native_s64(bits i64) C.vmh_s64 { unsafe { mut value:=C.vmh_s64{};C.memcpy(&value,&bits,8);return value } }
fn signed_bits(native C.vmh_s64) i64 { unsafe { mut value:=i64(0);C.memcpy(&value,&native,8);return value } }
@[export:'vmh_raw_lock_tests']
pub fn raw_lock_tests() { unsafe {
 mut guard:=C.raw_spinlock_t{};mut flags:=usize(0);mut nested:=usize(0)
 C.assert(!C.raw_spin_is_locked(&guard) && !C.irqs_disabled());C.assert(C.raw_spin_trylock_irqsave(&guard,flags))
 C.assert(C.raw_spin_is_locked(&guard) && C.irqs_disabled() && C.vmh_preempt_depth==1);C.assert(!C.raw_spin_trylock_irqsave(&guard,nested))
 C.assert(C.irqs_disabled() && C.vmh_preempt_depth==1 && C.irqs_disabled_flags(nested));C.raw_spin_unlock_irqrestore(&guard,flags)
 C.assert(!C.irqs_disabled() && C.vmh_preempt_depth==0);C.raw_spin_lock(&guard);mut acquired:=usize(0)
 C.assert(!C.raw_spin_trylock_irqsave(&guard,acquired));C.assert(!C.irqs_disabled() && C.vmh_preempt_depth==1);C.raw_spin_unlock(&guard)
 C.local_irq_save(flags);C.raw_spin_lock_irqsave(&guard,nested);C.raw_spin_unlock_irqrestore(&guard,nested)
 C.assert(C.irqs_disabled() && C.vmh_preempt_depth==0);C.local_irq_restore(flags);C.raw_spin_lock_irq(&guard)
 C.assert(C.irqs_disabled() && C.vmh_preempt_depth==1);C.raw_spin_unlock_irq(&guard);C.assert(!C.irqs_disabled() && C.vmh_preempt_depth==0)
} }
@[export:'vmh_concurrent_worker']
pub fn concurrent_worker(argument voidptr) voidptr { unsafe {
 for i:=i32(0);i<50000;i++ { mut flags:=usize(0);C.atomic_inc(&counter);C.spin_lock_irqsave(&concurrent_lock,flags)
  C.assert(!C.vmh_interrupts && C.vmh_preempt_depth==1);locked_count++;C.spin_unlock_irqrestore(&concurrent_lock,flags)
  C.assert(C.vmh_interrupts && C.vmh_preempt_depth==0)
 };return nil
} }
@[export:'vmh_concurrency_tests']
pub fn concurrency_tests() { unsafe {
 mut threads:=[4]C.pthread_t{};for i:=usize(0);i<4;i++ { C.assert(C.pthread_create(&threads[i],nil,C.vmh_concurrent_worker,nil)==0) }
 for i:=usize(0);i<4;i++ { C.assert(C.pthread_join(threads[i],nil)==0) }
 C.assert(C.atomic_read(&counter)==200000 && locked_count==200000);C.assert(C.atomic_cmpxchg(&counter,0,7)==200000)
 C.assert(C.atomic_cmpxchg(&counter,200000,7)==200000);C.assert(C.atomic_xchg(&counter,1)==7 && C.atomic_dec_and_test(&counter))
 mut big:=C.ATOMIC64_INIT(native_s64(i64(1)<<40));C.assert(signed_bits(C.atomic64_inc_return(&big))==(i64(1)<<40)+1)
 mut outer:=C.spinlock_t{};mut inner:=C.spinlock_t{};C.spin_lock_init(&outer);C.spin_lock_init(&inner)
 mut outer_flags:=usize(0);mut inner_flags:=usize(0);C.spin_lock_irqsave(&outer,outer_flags);C.assert(!C.spin_trylock(&outer) && C.vmh_preempt_depth==1)
 C.spin_lock_irqsave(&inner,inner_flags);C.assert(C.vmh_preempt_depth==2 && !C.vmh_interrupts)
 C.spin_unlock_irqrestore(&inner,inner_flags);C.assert(C.vmh_preempt_depth==1 && !C.vmh_interrupts)
 C.spin_unlock_irqrestore(&outer,outer_flags);C.assert(C.vmh_preempt_depth==0 && C.vmh_interrupts)
} }
@[export:'vmh_atomic_api_tests']
pub fn atomic_api_tests() { unsafe {
 mut value:=C.ATOMIC_INIT(C.INT_MAX);C.assert(C.atomic_fetch_inc_relaxed(&value)==C.INT_MAX);C.assert(C.atomic_read(&value)==C.INT_MIN)
 mut old:=i32(7);C.assert(!C.atomic_try_cmpxchg_acquire(&value,&old,4) && old==C.INT_MIN);C.assert(C.atomic_try_cmpxchg_release(&value,&old,4))
 C.assert(C.atomic_fetch_andnot(1,&value)==4 && C.atomic_read(&value)==4);C.atomic_or(3,&value)
 C.assert(C.atomic_fetch_xor_acquire(2,&value)==7 && C.atomic_read(&value)==5);C.assert(C.atomic_add_unless(&value,-1,0) && C.atomic_read(&value)==4)
 C.atomic_set(&value,0);C.assert(!C.atomic_inc_not_zero(&value))
 mut big:=C.ATOMIC64_INIT(native_s64(i64(0x7fffffffffffffff)))
 C.assert(signed_bits(C.atomic64_add_return_relaxed(native_s64(1),&big))==(-i64(0x7fffffffffffffff)-1))
 mut previous:=native_s64(0);C.assert(!C.atomic64_try_cmpxchg_relaxed(&big,&previous,native_s64(0)) && signed_bits(previous)==(-i64(0x7fffffffffffffff)-1))
 C.assert(C.atomic64_try_cmpxchg(&big,&previous,native_s64(0)))
 mut wide:=C.ATOMIC_LONG_INIT(isize(1)<<40);C.assert(C.atomic_long_fetch_add_release(isize(1)<<40,&wide)==isize(1)<<40)
 C.assert(C.atomic_long_read_acquire(&wide)==isize(1)<<41);mut bits:=usize(7);C.assert(C.xchg(&bits,usize(9))==7)
 C.assert(C.cmpxchg_acquire(&bits,usize(9),usize(11))==9 && bits==11);mut expected:=usize(0)
 C.assert(!C.try_cmpxchg_release(&bits,&expected,usize(0)) && expected==11);C.assert(C.try_cmpxchg(&bits,&expected,usize(0)) && bits==0)
} }
@[export:'vmh_message_writer']
pub fn message_writer(argument voidptr) voidptr { unsafe {
 for i:=u64(1);i<=20000;i++ { C.atomic_cond_read_acquire(&published,C.VAL==0);message[0]=i;message[1]=~i;C.atomic_set_release(&published,1) };return nil
} }
@[export:'vmh_message_reader']
pub fn message_reader(argument voidptr) voidptr { unsafe {
 for i:=u64(1);i<=20000;i++ { C.atomic_cond_read_acquire(&published,C.VAL==1);C.assert(message[0]==i && message[1]==~i);C.atomic_set_release(&published,0) };return nil
} }
struct SharedObject { mut: refs C.kref completed [4]u32 }
struct ReferenceWorker { object &SharedObject index u32 }
@[export:'vmh_release_object']
pub fn release_object(refs &C.kref) { unsafe {
 object:=&SharedObject(refs);for i:=usize(0);i<4;i++ { C.assert(object.completed[i]==i+1) };C.assert(C.atomic_fetch_inc(&releases)==0);C.kfree(object)
} }
@[export:'vmh_reference_worker']
pub fn reference_worker(argument voidptr) voidptr { unsafe {
 worker:=&ReferenceWorker(argument);object:=worker.object
 for i:=i32(0);i<30000;i++ { C.kref_get(&object.refs);C.assert(C.kref_put(&object.refs,C.vmh_release_object)==0) }
 object.completed[worker.index]=worker.index+1;C.kref_put(&object.refs,C.vmh_release_object);return nil
} }
@[export:'vmh_reference_tests']
pub fn reference_tests() { unsafe {
 warnings_before:=C.atomic_read(&C.vmh_refcount_warnings);mut refs:=C.REFCOUNT_INIT(0)
 C.assert(!C.refcount_inc_not_zero(&refs) && C.atomic_read(&C.vmh_refcount_warnings)==warnings_before);C.refcount_inc(&refs)
 C.assert(C.refcount_read(&refs)==u32(C.REFCOUNT_SATURATED));C.assert(!C.refcount_dec_and_test(&refs));C.refcount_set(&refs,1)
 C.refcount_add(u32(C.INT_MAX),&refs);C.assert(C.refcount_read(&refs)==u32(C.REFCOUNT_SATURATED));C.refcount_set(&refs,1)
 C.assert(!C.refcount_sub_and_test(2,&refs));C.assert(C.refcount_read(&refs)==u32(C.REFCOUNT_SATURATED))
 C.assert(C.atomic_read(&C.vmh_refcount_warnings)==warnings_before+4);C.refcount_set(&refs,1)
 C.assert(C.refcount_dec_if_one(&refs) && !C.refcount_dec_if_one(&refs));mut guard:=C.spinlock_t{};C.spin_lock_init(&guard);mut flags:=usize(0)
 C.refcount_set(&refs,2);C.assert(!C.refcount_dec_and_lock_irqsave(&refs,&guard,&flags));C.assert(C.vmh_interrupts && C.vmh_preempt_depth==0 && C.refcount_read(&refs)==1)
 C.assert(C.refcount_dec_and_lock_irqsave(&refs,&guard,&flags));C.assert(!C.vmh_interrupts && C.vmh_preempt_depth==1 && C.refcount_read(&refs)==0)
 C.spin_unlock_irqrestore(&guard,flags);C.assert(C.vmh_interrupts && C.vmh_preempt_depth==0)
 object:=&SharedObject(C.kzalloc(sizeof(SharedObject),C.GFP_KERNEL));C.assert(object!=nil);C.kref_init(&object.refs)
 mut workers:=[4]ReferenceWorker{};mut threads:=[4]C.pthread_t{}
 for i:=usize(0);i<4;i++ { workers[i]=ReferenceWorker{object,u32(i)};C.kref_get(&object.refs);C.assert(C.pthread_create(&threads[i],nil,C.vmh_reference_worker,&workers[i])==0) }
 C.kref_put(&object.refs,C.vmh_release_object);for i:=usize(0);i<4;i++ { C.assert(C.pthread_join(threads[i],nil)==0) }
 C.assert(C.atomic_read(&releases)==1 && C.vmh_live_pages==C.vmh_permanent_pages);mut writer:=C.pthread_t{};mut reader:=C.pthread_t{}
 C.assert(C.pthread_create(&writer,nil,C.vmh_message_writer,nil)==0);C.assert(C.pthread_create(&reader,nil,C.vmh_message_reader,nil)==0)
 C.assert(C.pthread_join(writer,nil)==0 && C.pthread_join(reader,nil)==0)
} }
