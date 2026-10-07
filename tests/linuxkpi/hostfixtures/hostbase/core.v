// SPDX-License-Identifier: GPL-2.0-or-later
// Original allocation, guarded strings and simple bitmap oracle.
@[translated]
@[has_globals]
module hostbase
#include "hostbase_v_contract.h"
fn C.type_max(i32) u64
fn C.GENMASK_ULL(i32,i32) u64
fn C.vinix_linuxkpi_selftest() i32
fn C.kmalloc(usize,u32) voidptr
fn C.kmalloc_array(usize,usize,u32) voidptr
fn C.kcalloc(usize,usize,u32) voidptr
fn C.krealloc(voidptr,usize,u32) voidptr
fn C.kmemdup(voidptr,usize,u32) voidptr
fn C.kfree(voidptr)
fn C.ksize(voidptr) usize
fn C.ERR_PTR(isize) voidptr
fn C.PTR_ERR(voidptr) isize
fn C.IS_ERR(voidptr) bool
fn C.IS_ERR_OR_NULL(voidptr) bool
fn C.PTR_ERR_OR_ZERO(voidptr) i32
fn C.memchr(voidptr,i32,usize) voidptr
fn C.memchr_inv(voidptr,i32,usize) voidptr
fn C.strnlen(&char,usize) usize
fn C.strscpy(&char,&char,usize) isize
fn C.strscpy_pad(&char,&char,usize) isize
fn C.kstrdup(&char,u32) &char
fn C.kstrndup(&char,usize,u32) &char
fn C.kmemdup_nul(voidptr,usize,u32) &char
fn C.sysconf(i32) isize
fn C.mmap(voidptr,usize,i32,i32,i32,isize) voidptr
fn C.mprotect(voidptr,usize,i32) i32
fn C.munmap(voidptr,usize) i32
@[c_extern] __global (
 C.s8 i32 C.u8 i32 C.s64 i32 C.u64 i32
 C.GFP_KERNEL u32 C.GFP_ATOMIC u32 C.GFP_NOWAIT u32 C.GFP_NOFS u32 C.GFP_NOIO u32
 C.__GFP_DMA32 u32 C.__GFP_NOFAIL u32 C.__GFP_ACCOUNT u32 C.__GFP_ZERO u32
 C.ZERO_SIZE_PTR voidptr C.ENOMEM i32 C.E2BIG i32 C.INT_MAX i32
 C._SC_PAGESIZE i32 C.PROT_READ i32 C.PROT_WRITE i32 C.PROT_NONE i32
 C.MAP_PRIVATE i32 C.MAP_ANON i32 C.MAP_FAILED voidptr
)
struct C.vmh_string_calls { mut: scan fn(voidptr,i32,usize) voidptr bounded_length fn(&char,usize) usize }
@[export:'vmh_allocation_tests']
pub fn allocation_tests() { unsafe {
 C.assert(C.type_max(C.s8)==127 && C.type_max(C.u8)==255)
 C.assert(C.type_max(C.s64)==u64(0x7fffffffffffffff) && C.type_max(C.u64)==~u64(0))
 C.assert(C.GENMASK_ULL(39,21)==u64(0x000000ffffe00000));C.assert(C.vinix_linuxkpi_selftest()==0)
 C.assert(C.vmh_live_pages==C.vmh_permanent_pages);C.assert(C.kmalloc(0,C.GFP_KERNEL)==voidptr(C.ZERO_SIZE_PTR))
 C.assert(C.ksize(voidptr(C.ZERO_SIZE_PTR))==0);C.kfree(nil);C.kfree(voidptr(C.ZERO_SIZE_PTR))
 C.assert(C.kmalloc(~usize(0),C.GFP_KERNEL)==nil);C.assert(C.kmalloc_array(~usize(0),2,C.GFP_KERNEL)==nil)
 C.assert(C.kcalloc(2,~usize(0),C.GFP_KERNEL)==nil)
 non_reclaiming:=[C.GFP_ATOMIC,C.GFP_NOWAIT,C.GFP_NOFS,C.GFP_NOIO]!
 for i:=usize(0);i<4;i++ { ptr:=C.kmalloc(32,non_reclaiming[i]);C.assert(ptr!=nil && !C.vmh_last_reclaim);C.kfree(ptr) }
 C.vmh_interrupts=false;atomic_ptr:=C.kmalloc(32,C.GFP_KERNEL);C.assert(atomic_ptr!=nil && !C.vmh_last_reclaim);C.kfree(atomic_ptr);C.vmh_interrupts=true
 C.assert(C.kmalloc(32,C.GFP_KERNEL|C.__GFP_DMA32)==nil);C.assert(C.kmalloc(32,C.GFP_KERNEL|C.__GFP_NOFAIL)==nil)
 C.assert(C.kmalloc(32,C.GFP_KERNEL|C.__GFP_ACCOUNT)==nil)
 for n:=usize(16);n<=16384;n*=2 { ptr:=C.kmalloc(n,C.GFP_KERNEL);C.assert(ptr!=nil && usize(ptr)%n==0 && C.vmh_last_reclaim);C.kfree(ptr) }
 for n:=usize(1);n<25000;n=n*2+1 {
  ptr:=&u8(C.kcalloc(n,1,C.GFP_KERNEL));C.assert(ptr!=nil && usize(ptr)%16==0 && C.ksize(ptr)==n)
  for i:=usize(0);i<n;i++ { C.assert(ptr[i]==0) };C.memset(ptr,0x6f,n);C.vmh_fail_allocation=true
  C.assert(C.krealloc(ptr,n+17,C.GFP_KERNEL)==nil);for i:=usize(0);i<n;i++ { C.assert(ptr[i]==0x6f) };C.vmh_fail_allocation=false
  grown:=&u8(C.krealloc(ptr,n+17,C.GFP_KERNEL|C.__GFP_ZERO));C.assert(grown!=nil && C.ksize(grown)==n+17)
  for i:=usize(0);i<n+17;i++ { C.assert(grown[i]==if i<n { u8(0x6f) } else { u8(0) }) }
  duplicate:=C.kmemdup(grown,n+17,C.GFP_KERNEL);C.assert(duplicate!=nil && C.memcmp(duplicate,grown,n+17)==0);C.kfree(duplicate)
  C.assert(C.krealloc(grown,0,C.GFP_KERNEL)==voidptr(C.ZERO_SIZE_PTR));C.assert(C.vmh_live_pages==C.vmh_permanent_pages)
 }
 C.assert(C.PTR_ERR(C.ERR_PTR(-isize(C.ENOMEM)))==-isize(C.ENOMEM));C.assert(C.IS_ERR(C.ERR_PTR(-isize(C.ENOMEM))) && C.IS_ERR_OR_NULL(nil))
 C.assert(!C.IS_ERR(voidptr(4096)) && C.PTR_ERR_OR_ZERO(voidptr(4096))==0)
} }
@[export:'vmh_string_tests']
pub fn string_tests() { unsafe {
 mut calls:=C.vmh_string_calls{scan:C.memchr,bounded_length:C.strnlen}
 bytes:=[u8(0xff),0x80,0,0xff,0x42]!
 C.assert(usize(calls.scan(&bytes[0],0x1ff,sizeof(bytes)))==usize(&bytes[0]))
 C.assert(usize(calls.scan(&bytes[0],0x42,sizeof(bytes)))==usize(&bytes[4]))
 C.assert(calls.scan(&bytes[0],1,sizeof(bytes))==nil && calls.scan(nil,0,0)==nil)
 C.assert(usize(C.memchr_inv(&bytes[0],0xff,sizeof(bytes)))==usize(&bytes[1]))
 C.assert(C.memchr_inv(&bytes[0],0xff,1)==nil && C.memchr_inv(nil,0,0)==nil)
 C.assert(calls.bounded_length(c'',1)==0 && calls.bounded_length(c'abc',2)==2)
 page:=usize(C.sysconf(C._SC_PAGESIZE));source:=&char(C.mmap(nil,page*2,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANON,-1,0))
 destination:=&char(C.mmap(nil,page*2,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANON,-1,0));C.assert(voidptr(source)!=voidptr(C.MAP_FAILED) && voidptr(destination)!=voidptr(C.MAP_FAILED))
 C.assert(C.mprotect(source+page,page,C.PROT_NONE)==0);C.assert(C.mprotect(destination+page,page,C.PROT_NONE)==0)
 C.assert(calls.scan(source+page,0,0)==nil && calls.bounded_length(source+page,0)==0)
 C.assert(C.strscpy(destination+page,source+page,0)==-isize(C.E2BIG));C.assert(C.strscpy(destination+page,source+page,usize(C.INT_MAX)+1)==-isize(C.E2BIG))
 for n:=usize(1);n<=32;n++ {
  src:=source+page-n;dst:=destination+page-n;C.memset(src,97,n);C.memset(dst,0x5a,n)
  C.assert(calls.bounded_length(src,n)==n && calls.scan(src,0,n)==nil);C.assert(C.strscpy(dst,src,n)==-isize(C.E2BIG) && dst[n-1]==0)
  for i:=usize(0);i<n-1;i++ { C.assert(dst[i]==97) };src[n-1]=0;C.assert(C.strscpy(dst,src,n)==isize(n)-1 && C.memcmp(src,dst,n)==0)
  copy:=C.kstrdup(src,C.GFP_KERNEL);C.assert(copy!=nil && C.memcmp(copy,src,n)==0);C.kfree(copy)
 }
 C.assert(C.munmap(source,page*2)==0 && C.munmap(destination,page*2)==0)
 mut padded:=[12]char{};C.memset(&padded[0],0x5a,sizeof(padded));C.assert(C.strscpy_pad(&padded[0],c'abc',sizeof(padded))==3)
 C.assert(C.memcmp(&padded[0],c'abc',3)==0 && C.memchr_inv(&padded[3],0,sizeof(padded)-3)==nil)
 C.memset(&padded[0],0x5a,sizeof(padded));C.assert(C.strscpy_pad(&padded[0],c'abcdefghijklm',3)==-isize(C.E2BIG))
 C.assert(C.memcmp(&padded[0],c'ab\x00',3)==0 && C.memchr_inv(&padded[3],0x5a,sizeof(padded)-3)==nil)
 mut copy:=C.kstrndup(c'abcd',2,C.GFP_KERNEL);C.assert(copy!=nil && C.strcmp(copy,c'ab')==0);C.kfree(copy)
 copy=C.kmemdup_nul(&char(&bytes[0]),sizeof(bytes),C.GFP_KERNEL);C.assert(copy!=nil && C.memcmp(copy,&bytes[0],sizeof(bytes))==0 && copy[sizeof(bytes)]==0);C.kfree(copy)
 copy=C.kmemdup_nul(nil,0,C.GFP_KERNEL);C.assert(copy!=nil && copy[0]==0);C.kfree(copy)
 C.assert(C.kmemdup_nul(nil,~usize(0),C.GFP_KERNEL)==nil);C.assert(C.kstrdup(nil,C.GFP_KERNEL)==nil && C.kstrndup(nil,1,C.GFP_KERNEL)==nil)
 C.vmh_fail_allocation=true;C.assert(C.kstrdup(c'failed',C.GFP_KERNEL)==nil && C.kstrndup(c'failed',3,C.GFP_KERNEL)==nil)
 C.assert(C.kmemdup_nul(c'failed',6,C.GFP_KERNEL)==nil);C.vmh_fail_allocation=false;C.assert(C.vmh_live_pages==C.vmh_permanent_pages)
} }
