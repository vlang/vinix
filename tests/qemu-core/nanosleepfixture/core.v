// SPDX-License-Identifier: BSD-2-Clause
// Independent interrupted nanosleep fixture from original lines74/82-86/710-743.
@[translated]
@[has_globals]
module nanosleepfixture

#include <nanosleepfixture_v_contract.h>

struct C.vqn_volatile_signal { mut: value i32 }
@[typedef] struct C.sigset_t {}
struct C.sigaction { mut:
 sa_handler fn(i32)
 sa_mask C.sigset_t
}
struct C.timespec { mut: tv_sec i64 tv_nsec i64 }
@[c_extern] __global C.errno i32
__global qemu_remainder_interrupts C.vqn_volatile_signal

fn C.printf(&char,...) i32
fn C.puts(&char) i32
fn C.memset(voidptr,i32,usize) voidptr
fn C.sigemptyset(&C.sigset_t) i32
fn C.sigaction(i32,&C.sigaction,&C.sigaction) i32
fn C.getpid() i32
fn C.fork() i32
fn C.nanosleep(&C.timespec,&C.timespec) i32
fn C._exit(i32)
fn C.kill(i32,i32) i32
fn C.reap_ok(i32) i32
fn C.vqn_nanosleep_interrupt(i32)

fn check(ok bool,line i32,expression &char) bool {
 if !ok { unsafe { C.printf(c'QEMU CORE FAIL line %d: %s (errno=%d)\n',line,expression,C.errno) } }
 return ok
}

@[export:'vqn_nanosleep_interrupt']
pub fn interrupt(signal i32) { _=signal;unsafe { qemu_remainder_interrupts.value++ } }

@[export:'test_interrupted_nanosleep_remaining']
pub fn interrupted_nanosleep_remaining() i32 { unsafe {
 mut action:=C.sigaction{};C.memset(&action,0,sizeof(C.sigaction))
 action.sa_handler=C.vqn_nanosleep_interrupt;C.sigemptyset(&action.sa_mask)
 if !check(C.sigaction(C.SIGUSR1,&action,nil)==0,720,c'sigaction(SIGUSR1, &action, NULL) == 0') { return 1 }
 parent:=C.getpid();child:=C.fork()
 if !check(child>=0,724,c'child >= 0') { return 1 }
 if child==0 {
  mut delay:=C.timespec{tv_nsec:20000000};C.nanosleep(&delay,nil)
  C._exit(if C.kill(parent,C.SIGUSR1)==0 { 0 } else { 1 })
 }
 mut request:=C.timespec{tv_sec:1};mut remaining:=C.timespec{tv_sec:-1,tv_nsec:-1}
 C.errno=0
 if !check(C.nanosleep(&request,&remaining)== -1,734,c'nanosleep(&request, &remaining) == -1') { return 1 }
 if !check(C.errno==C.EINTR,735,c'errno == EINTR') { return 1 }
 if !check(qemu_remainder_interrupts.value==1,736,c'nanosleep_interrupts == 1') { return 1 }
 if !check(remaining.tv_sec==0,737,c'remaining.tv_sec == 0') { return 1 }
 if !check(remaining.tv_nsec>0 && remaining.tv_nsec<1000000000,738,c'remaining.tv_nsec > 0 && remaining.tv_nsec < 1000000000L') { return 1 }
 if !check(C.nanosleep(&remaining,nil)==0,739,c'nanosleep(&remaining, NULL) == 0') { return 1 }
 if !check(C.reap_ok(child)==0,740,c'reap_ok(child) == 0') { return 1 }
 C.puts(c'QEMU CORE PASS: interrupted nanosleep returns a relative remainder');return 0
} }
