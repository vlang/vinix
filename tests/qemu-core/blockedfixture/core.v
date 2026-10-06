// SPDX-License-Identifier: BSD-2-Clause
// Independent blocked-thread exit/exec fixture, original lines671-708.
@[translated]
@[has_globals]
module blockedfixture
#include <blockedfixture_v_contract.h>
@[typedef] struct C.pthread_t {}
@[typedef] struct C.pthread_attr_t {}
struct C.timespec { mut: tv_sec i64 tv_nsec i64 }
@[c_extern] __global C.errno i32
__global blocked_channel [2]i32
fn C.printf(&char,...) i32
fn C.puts(&char) i32
fn C.read(i32,voidptr,usize) isize
fn C.pipe(&i32) i32
fn C.pthread_create(&C.pthread_t,&C.pthread_attr_t,fn(voidptr)voidptr,voidptr) i32
fn C.fork() i32
fn C._exit(i32)
fn C.nanosleep(&C.timespec,&C.timespec) i32
fn C.execv(&char,&&char) i32
fn C.reap_ok(i32) i32
fn C.vqb_block_in_read(voidptr) voidptr
fn check(ok bool,line i32,expression &char) bool {
 if !ok { unsafe { C.printf(c'QEMU CORE FAIL line %d: %s (errno=%d)\n',line,expression,C.errno) } }
 return ok
}
@[export:'vqb_block_in_read']
pub fn block_in_read(argument voidptr) voidptr { unsafe {
 fd:=*(&i32(argument));mut byte:=i8(0);C.read(fd,&byte,1);return nil
} }
@[export:'test_exit_takes_down_blocked_threads']
pub fn exit_takes_down_blocked_threads() i32 { unsafe {
 for exec_instead:=i32(0);exec_instead<2;exec_instead++ {
  child:=C.fork()
  if !check(child>=0,687,c'child >= 0') { return 1 }
  if child==0 {
   if C.pipe(&blocked_channel[0])!=0 { C._exit(2) }
   mut sleeper:=C.pthread_t{}
   if C.pthread_create(&sleeper,nil,C.vqb_block_in_read,&blocked_channel[0])!=0 { C._exit(3) }
   mut settle:=C.timespec{tv_nsec:100000000};C.nanosleep(&settle,nil)
   if exec_instead!=0 {
    mut argv:=[3]&char{};argv[0]=&char(c'/sbin/init');argv[1]=&char(c'--exec-memory-probe')
    C.execv(argv[0],&argv[0]);C._exit(4)
   }
   C._exit(0)
  }
  if !check(C.reap_ok(child)==0,704,c'reap_ok(child) == 0') { return 1 }
 }
 C.puts(c'QEMU CORE PASS: exit and exec take down threads blocked in the kernel');return 0
} }
