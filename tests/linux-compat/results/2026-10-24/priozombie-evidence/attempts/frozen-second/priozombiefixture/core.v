// SPDX-License-Identifier: GPL-2.0-or-later
module priozombiefixture

#include <errno.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

@[typedef]
struct C.pthread_t {}
@[typedef]
struct C.siginfo_t { si_pid i32 si_status i32 si_code i32 }
struct Totals { mut: checks i32 failures i32 }
struct Worker { door i32 report i32 mut: leader_tid i32 }
struct Peer { pid i32 door i32 report i32 uid u32 }
fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.getpriority(i32,u32) i32
fn C.setpriority(i32,u32,i32) i32
fn C.setresuid(u32,u32,u32) i32
fn C.setpgid(i32,i32) i32
fn C.getpid() i32
fn C.pipe(&i32) i32
fn C.read(i32,voidptr,usize) isize
fn C.write(i32,voidptr,usize) isize
fn C.close(i32) i32
fn C.fork() i32
fn C.waitpid(i32,&i32,i32) i32
fn C.waitid(i32,u32,&C.siginfo_t,i32) i32
fn C._exit(i32)
fn C.alarm(u32) u32
fn C.pause() i32
fn C.sched_yield() i32
fn C.pthread_create(&C.pthread_t,voidptr,fn (voidptr) voidptr,voidptr) i32
fn C.__atomic_load_n(&i32,i32) i32
fn C.printf(&char,...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.strcmp(&char,&char) i32

fn fatal(stage i32) {
 C.printf(c'LINUX PRIOZOMBIE FAIL: setup stage=%d errno=%d\n',stage,unsafe{*C.__errno_location()})
 C.fflush(unsafe{nil}); C._exit(90)
}
fn check(mut t Totals, ok bool, stage i32) {
 t.checks++
 if !ok { t.failures++; if t.failures <= 20 { C.printf(c'LINUX PRIOZOMBIE MISMATCH: stage=%d\n',stage); C.fflush(unsafe{nil}) } }
}
fn token(fd i32) { mut value := u8(0); if C.read(fd,unsafe{&value},1) != 1 || value != `X` {fatal(1)} }
fn signal(fd i32) { if C.write(fd,c'X',1) != 1 {fatal(2)} }
fn worker(arg voidptr) voidptr {
 unsafe {
  state := &Worker(arg)
  if C.setpriority(0,0,17) != 0 {fatal(3)}
  // The leader uses raw exit; clear_child_tid proves it started retiring.
  if state.leader_tid != 0 { for C.__atomic_load_n(&state.leader_tid,2) != 0 { C.sched_yield() } }
  signal(state.report); token(state.door)
  C._exit(0)
 }
 return unsafe{nil}
}
fn start(mode i32) Peer {
 unsafe {
  mut door := [i32(-1),-1]!; mut report := [i32(-1),-1]!
  if C.pipe(&door[0]) != 0 || C.pipe(&report[0]) != 0 {fatal(4)}
  uid := u32(42110 + mode)
  pid := C.fork(); if pid < 0 {fatal(5)}
  if pid == 0 {
   C.close(door[1]); C.close(report[0])
   if C.setpgid(0,0) != 0 || C.setpriority(0,0,if mode == 1 {-1} else {7}) != 0 || C.setresuid(uid,uid,0) != 0 {fatal(6)}
   if mode == 0 { signal(report[1]); token(door[0]); C._exit(0) }
   mut state := Worker{door:door[0],report:report[1],leader_tid:if mode == 1 {C.getpid()} else {0}}
   if mode == 1 && C.syscall(C.SYS_set_tid_address,&state.leader_tid) != C.getpid() {fatal(7)}
   mut task := C.pthread_t{}
   if C.pthread_create(&task,nil,worker,&state) != 0 {fatal(8)}
   if mode == 1 { C.syscall(C.SYS_exit,u64(0)); fatal(9) }
   for { C.pause() }
  }
  C.close(door[0]); C.close(report[1]); token(report[0])
  return Peer{pid,door[1],report[0],uid}
 }
}
fn get(mut t Totals, which i32, who u32, nice i32, code i32, stage i32) {
 unsafe {
  for high in [u64(0),0x1234567800000000,0xffffffff00000000]! {
   slot := C.__errno_location(); *slot = 0
   raw := C.syscall(C.SYS_getpriority,high | u64(u32(which)),high | u64(who))
   check(mut t,raw == if code == 0 {isize(20 - nice)} else {isize(-1)} && *slot == code,stage)
  }
  slot := C.__errno_location(); *slot = 0
  value := C.getpriority(which,who)
  check(mut t,value == if code == 0 {nice} else {i32(-1)} && *slot == code,stage + 1)
 }
}
fn all(mut t Totals, peer Peer, nice i32, code i32, stage i32) {
 get(mut t,0,u32(peer.pid),nice,code,stage)
 get(mut t,1,u32(peer.pid),nice,code,stage + 2)
 get(mut t,2,peer.uid,nice,code,stage + 4)
}
fn set(mut t Totals, which i32, who u32, nice i32, code i32, stage i32) {
 unsafe {
  for high in [u64(0),0x1234567800000000,0xffffffff00000000]! {
   slot := C.__errno_location(); *slot = 0
   raw := C.syscall(C.SYS_setpriority,high | u64(u32(which)),high | u64(who),high | u64(u32(nice)))
   check(mut t,raw == if code == 0 {isize(0)} else {isize(-1)} && *slot == code,stage)
  }
  slot := C.__errno_location(); *slot = 0
  ret := C.setpriority(which,who,nice)
  check(mut t,ret == if code == 0 {i32(0)} else {i32(-1)} && *slot == code,stage + 1)
 }
}
fn exercise(mut t Totals, mode i32) {
 unsafe {
  peer := start(mode)
  signal(peer.door); C.close(peer.door); C.close(peer.report)
  mut info := C.siginfo_t{}
  if C.waitid(C.P_PID,u32(peer.pid),&info,C.WEXITED | C.WNOWAIT) != 0 || info.si_pid != peer.pid || info.si_code != C.CLD_EXITED || info.si_status != 0 {fatal(10)}
  all(mut t,peer,if mode == 1 {-1} else {7},0,100 + mode * 100)
  for which in [i32(0),1,2]! {
   who := if which == 2 {peer.uid} else {u32(peer.pid)}
   set(mut t,which,who,10 + which,0,110)
   all(mut t,peer,10 + which,0,120)
  }
  if C.setresuid(peer.uid,peer.uid,0) != 0 {fatal(11)}
  for which in [i32(0),1,2]! {
   who := if which == 2 {peer.uid} else {u32(peer.pid)}
   set(mut t,which,who,14,0,130)
   set(mut t,which,who,13,C.EACCES,140)
   all(mut t,peer,14,0,150)
  }
  if C.setresuid(0,0,0) != 0 || C.setresuid(42199,42199,0) != 0 {fatal(12)}
  for which in [i32(0),1,2]! {
   who := if which == 2 {peer.uid} else {u32(peer.pid)}
   set(mut t,which,who,19,C.EPERM,160)
   all(mut t,peer,14,0,170)
  }
  if C.setresuid(0,0,0) != 0 {fatal(13)}
  for nice in [i32(-2147483647 - 1),-21,-20,-1,0,19,20,2147483647]! {
   wanted := if nice < -20 {-20} else if nice > 19 {19} else {nice}
   for which in [i32(0),1,2]! {
    who := if which == 2 {peer.uid} else {u32(peer.pid)}
    set(mut t,which,who,nice,0,180)
    all(mut t,peer,wanted,0,190)
   }
  }
  mut status := i32(-1)
  if C.waitpid(peer.pid,&status,0) != peer.pid || status != 0 {fatal(14)}
  all(mut t,peer,0,C.ESRCH,200)
  for which in [i32(0),1,2]! {set(mut t,which,if which == 2 {peer.uid} else {u32(peer.pid)},19,C.ESRCH,210)}
 }
}
@[export:'main']
pub fn run(argc i32,argv &&char) i32 {
 unsafe {
  C.alarm(90)
  reference := argc > 1 && C.strcmp(argv[1],c'--reference') == 0
  mut t := Totals{}
  for mode := 0; mode < 3; mode++ {exercise(mut t,mode)}
  C.printf(c'LINUX PRIOZOMBIE SUMMARY: checks=%d failures=%d\n',t.checks,t.failures)
  if t.failures != 0 {C.puts(c'LINUX PRIOZOMBIE: FAIL'); C.fflush(nil); return 1}
  C.puts(if reference {c'LINUX PRIOZOMBIE REFERENCE: PASS'} else {c'LINUX PRIOZOMBIE: PASS'}); C.fflush(nil)
  for {C.pause()}
 }
 return 0
}
