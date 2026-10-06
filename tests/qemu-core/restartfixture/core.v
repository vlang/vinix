// SPDX-License-Identifier: BSD-2-Clause
// Independent syscall restart fixture from pinned test.c:620-670.
@[translated]
module restartfixture
#include <restartfixture_v_contract.h>
@[typedef] struct C.sigset_t {}
struct C.sigaction { mut:
 sa_handler fn(i32)
 sa_flags i32
 sa_mask C.sigset_t
}
struct C.timespec { mut: tv_sec i64 tv_nsec i64 }
@[c_extern] __global C.errno i32
fn C.printf(&char,...) i32
fn C.puts(&char) i32
fn C.pipe(&i32) i32
fn C.fork() i32
fn C.close(i32) i32
fn C.memset(voidptr,i32,usize) voidptr
fn C.sigemptyset(&C.sigset_t) i32
fn C.sigaction(i32,&C.sigaction,&C.sigaction) i32
fn C.signal(i32,fn(i32)) fn(i32)
fn C._exit(i32)
fn C.read(i32,voidptr,usize) isize
fn C.write(i32,voidptr,usize) isize
fn C.nanosleep(&C.timespec,&C.timespec) i32
fn C.kill(i32,i32) i32
fn C.reap_ok(i32) i32
fn C.vqr_restart_handler(i32)
fn check(ok bool,line i32,expression &char) bool {
 if !ok { unsafe { C.printf(c'QEMU CORE FAIL line %d: %s (errno=%d)\n',line,expression,C.errno) } }
 return ok
}
@[export:'vqr_restart_handler']
pub fn restart_handler(signal i32) { _=signal }
fn interrupted_read(restart i32) i32 { unsafe {
 mut channel:=[2]i32{}
 if !check(C.pipe(&channel[0])==0,632,c'pipe(channel) == 0') { return 1 }
 child:=C.fork();if !check(child>=0,634,c'child >= 0') { return 1 }
 if child==0 {
  C.close(channel[1]);mut action:=C.sigaction{};C.memset(&action,0,sizeof(C.sigaction))
  action.sa_handler=C.vqr_restart_handler;action.sa_flags=if restart!=0 { i32(C.SA_RESTART) } else { i32(0) }
  C.sigemptyset(&action.sa_mask);if C.sigaction(C.SIGUSR1,&action,nil)!=0 { C._exit(2) }
  mut byte:=u8(0);got:=C.read(channel[0],&byte,1)
  if restart!=0 { C._exit(if got==1 && byte==`r` { 0 } else { 3 }) }
  C._exit(if got == -1 && C.errno==C.EINTR { 0 } else { 4 })
 }
 C.close(channel[0]);mut delay:=C.timespec{tv_sec:0,tv_nsec:200000000}
 C.nanosleep(&delay,nil);if !check(C.kill(child,C.SIGUSR1)==0,653,c'kill(child, SIGUSR1) == 0') { return 1 }
 C.nanosleep(&delay,nil);C.signal(C.SIGPIPE,C.SIG_IGN)
 C.write(channel[1],c'r',1);C.close(channel[1])
 if !check(C.reap_ok(child)==0,659,c'reap_ok(child) == 0') { return 1 }
 return 0
} }
@[export:'test_syscall_restart']
pub fn syscall_restart() i32 { unsafe {
 if !check(interrupted_read(1)==0,665,c'interrupted_read(1) == 0') { return 1 }
 if !check(interrupted_read(0)==0,666,c'interrupted_read(0) == 0') { return 1 }
 C.puts(c'QEMU CORE PASS: SA_RESTART restarts an interrupted read');return 0
} }
