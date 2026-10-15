// SPDX-License-Identifier: GPL-2.0-or-later
module robustcredsfixture

#include <alloca.h>
#include <errno.h>
#include <grp.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/uio.h>
#include <sys/wait.h>
#include <unistd.h>

@[typedef]
struct C.pthread_t {}
@[typedef]
struct C.sigset_t {}
struct CapHeader {mut: version u32 pid i32}
struct CapData {mut: effective u32 permitted u32 inheritable u32}
struct C.iovec {mut: iov_base voidptr iov_len usize}
struct Counts {mut: calls [6]u64 failures [6]u64}
struct Slabs {mut: sizes [32]u64 live [32]u64 rows i32 large u64}
struct Credentials {mut: uid u32 euid u32 suid u32 gid u32 egid u32 sgid u32 permitted u32 effective u32 dump i32 = 1}
struct Worker {ready i32 release i32 head u64 mut: tid i32}
struct Target {mut: pid i32 tid i32 parent i32 head u64 worker_head u64 memory u64 credentials Credentials}

fn C.alloca(usize) voidptr
fn C.syscall(isize,...) isize
fn C.__errno_location() &i32
fn C.pthread_create(&C.pthread_t,voidptr,fn(voidptr) voidptr,voidptr) i32
fn C.pthread_join(C.pthread_t,voidptr) i32
fn C.sigemptyset(&C.sigset_t) i32
fn C.sigaddset(&C.sigset_t,i32) i32
fn C.pthread_sigmask(i32,&C.sigset_t,&C.sigset_t) i32
fn C.getpid() i32
fn C.getppid() i32
fn C.setsid() i32
fn C.getresuid(&u32,&u32,&u32) i32
fn C.getresgid(&u32,&u32,&u32) i32
fn C.setresuid(u32,u32,u32) i32
fn C.setresgid(u32,u32,u32) i32
fn C.setgroups(usize,voidptr) i32
fn C.prctl(i32,...) i32
fn C.sysconf(i32) isize
fn C.mmap(voidptr,usize,i32,i32,i32,isize) voidptr
fn C.munmap(voidptr,usize) i32
fn C.memset(voidptr,i32,usize) voidptr
fn C.memcpy(voidptr,voidptr,usize) voidptr
fn C.memcmp(voidptr,voidptr,usize) i32
fn C.printf(&char,...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.strcmp(&char,&char) i32
fn C.alarm(u32) u32
fn C.usleep(u32) i32
fn C.pause() i32
fn C.open(&char,i32,...) i32
fn C.close(i32) i32
fn C.read(i32,voidptr,usize) isize
fn C.write(i32,voidptr,usize) isize
fn C.pread(i32,voidptr,usize,i64) isize
fn C.sscanf(&char,&char,...) i32
fn C.pipe2(&i32,i32) i32
fn C.fork() i32
fn C.unshare(i32) i32
fn C.waitpid(i32,&i32,i32) i32
fn C._exit(i32)

fn fatal(stage i32) {C.printf(c'LINUX ROBUSTCREDS FAIL: setup stage=%d errno=%d\n',stage,unsafe{*C.__errno_location()}); C.fflush(unsafe{nil}); C._exit(90)}
fn profile(index i32,base u32,caller bool) Credentials {
 unsafe {
 mut result := Credentials{uid:base,euid:base,suid:base,gid:base,egid:base,sgid:base}
 if caller {
  if index in [1,28,29,30]! {result.euid = 2000}
  if index in [2,27,31]! {result.uid = 2000}
  if index in [3,30]! {result.egid = 2000}
  if index in [4,31]! {result.gid = 2000}
  if index in [13,14,15,20,21,22,23,24,25,26,27,28]! {result.permitted = u32(1)<<19}
  if index in [14,15,21,25,26]! {result.effective = result.permitted}
  if index in [17,18]! {result.permitted = u32(1)<<10}
  if index == 18 {result.effective = result.permitted}
  if index == 19 {result.permitted = u32(1)<<13}
  result.dump = 0
 } else {
  if index == 5 {result.uid = 2000}
  if index == 6 {result.euid = 2000}
  if index == 7 {result.suid = 2000}
  if index == 8 {result.gid = 2000}
  if index == 9 {result.egid = 2000}
  if index == 10 {result.sgid = 2000}
  if index in [11,15,23,25]! {result.uid = 2000; result.euid = 2000; result.suid = 2000}
  if index in [24,26]! {result.gid = 2000; result.egid = 2000; result.sgid = 2000}
  if index in [12,13,14,15]! {result.dump = 0}
  if index in [16,17,18,19,20,21]! {result.permitted = u32(1)<<10}
 }
 return result
 }
}
fn observe(destination &Credentials) {
 unsafe {
  mut value := &Credentials(destination)
  if C.getresuid(&value.uid,&value.euid,&value.suid) != 0 || C.getresgid(&value.gid,&value.egid,&value.sgid) != 0 {fatal(1)}
  header := &CapHeader(C.alloca(usize(sizeof(CapHeader)))); *header = CapHeader{version:0x20080522}
  caps := &CapData(C.alloca(usize(2*sizeof(CapData))))
  if C.syscall(C.SYS_capget,header,caps) != 0 || caps[0].inheritable != 0 || caps[1].effective != 0 || caps[1].permitted != 0 || caps[1].inheritable != 0 {fatal(2)}
  value.permitted = caps[0].permitted; value.effective = caps[0].effective; value.dump = C.prctl(C.PR_GET_DUMPABLE,isize(0),isize(0),isize(0),isize(0))
 }
}
fn credentials(wanted Credentials) {
 unsafe {
  if C.prctl(C.PR_SET_KEEPCAPS,isize(1),isize(0),isize(0),isize(0)) != 0 || C.setgroups(0,nil) != 0 || C.setresgid(wanted.gid,wanted.egid,wanted.sgid) != 0 || C.setresuid(wanted.uid,wanted.euid,wanted.suid) != 0 {fatal(3)}
  header := &CapHeader(C.alloca(usize(sizeof(CapHeader)))); *header = CapHeader{version:0x20080522}
  caps := &CapData(C.alloca(usize(2*sizeof(CapData)))); caps[0] = CapData{effective:wanted.effective,permitted:wanted.permitted}; caps[1] = CapData{}
  if C.syscall(C.SYS_capset,header,caps) != 0 || C.prctl(C.PR_SET_DUMPABLE,isize(wanted.dump),isize(0),isize(0),isize(0)) != 0 {fatal(4)}
  actual := &Credentials(C.alloca(usize(sizeof(Credentials)))); observe(actual)
  if *actual != wanted {fatal(5)}
 }
}
fn allowed(caller Credentials,target Credentials) bool {
 if caller.effective & (u32(1)<<19) != 0 {return true}
 return target.dump == 1 && caller.uid == target.uid && caller.uid == target.euid && caller.uid == target.suid && caller.gid == target.gid && caller.gid == target.egid && caller.gid == target.sgid && target.permitted & ~caller.permitted == 0
}
fn worker(argument voidptr) voidptr {
 unsafe {
  mut state := &Worker(argument); mut original := u64(0); mut length := u64(0)
  if C.syscall(C.SYS_get_robust_list,isize(0),&original,&length) != 0 || length != 24 || C.syscall(C.SYS_set_robust_list,voidptr(state.head),u64(24)) != 0 {fatal(6)}
  state.tid = i32(C.syscall(C.SYS_gettid)); if C.write(state.ready,&state.tid,4) != 4 {fatal(7)}
  mut release := u8(0); if C.read(state.release,&release,1) != 1 || release != `X` || C.syscall(C.SYS_set_robust_list,voidptr(original),u64(24)) != 0 {fatal(8)}
  return nil
 }
}
fn mark(counts &Counts,kind i32,good bool,index i32,ordinary bool,namespace bool,result isize,code i32,expected i32) {
 unsafe {
  mut output := &Counts(counts); output.calls[kind]++
  if !good {output.failures[kind]++; if output.failures[kind] <= 3 {C.printf(c'LINUX ROBUSTCREDS DETAIL: ordinary=%d namespace=%d kind=%d profile=%d result=%ld errno=%d expected=%d\n',i32(ordinary),i32(namespace),kind,index,result,code,expected)}}
 }
}
fn query(counts &Counts,kind i32,pid i32,head u64,permit bool,index i32,ordinary bool,namespace bool,upper bool,shape i32) bool {
 unsafe {
  mut output := [64]u8{}; mut expected := [64]u8{}; C.memset(&output[0],0xa5,64); C.memset(&expected[0],0xa5,64)
  head_ptr := if shape == 1 {u64(0)} else {u64(&output[9])}; len_ptr := if shape == 2 {u64(0)} else {u64(&output[33])}
  wanted := if pid < 0 {i32(C.ESRCH)} else if !permit {i32(C.EPERM)} else if shape != 0 {i32(C.EFAULT)} else {i32(0)}
  if permit && pid >= 0 && shape != 2 {length := u64(24); C.memcpy(&expected[33],&length,8); if shape == 0 {C.memcpy(&expected[9],&head,8)}}
  word := u64(u32(pid))|if upper {u64(0xa5a55a5a)<<32} else {u64(0)}
  mut code := C.__errno_location(); *code = 0; result := C.syscall(C.SYS_get_robust_list,word,voidptr(head_ptr),voidptr(len_ptr)); good := result == if wanted == 0 {isize(0)} else {isize(-1)} && *code == wanted && C.memcmp(&output[0],&expected[0],64) == 0
  mark(counts,kind,good,index,ordinary,namespace,result,*code,wanted); return good
 }
}
fn transfer(counts &Counts,writing bool,target &Target,permit bool,door i32,reply i32,index i32,ordinary bool,namespace bool,bad bool) bool {
 unsafe {
  mut local := [64]u8{}; mut expected := [64]u8{}; C.memset(&local[0],if writing {0x5a} else {0xa5},64); C.memset(&expected[0],if writing {0x5a} else if permit && !bad {0x3c} else {0xa5},64)
  mut here := C.iovec{iov_base:if bad {nil} else {voidptr(&local[9])},iov_len:16}; mut there := C.iovec{iov_base:voidptr(target.memory+9),iov_len:16}
  if !writing && permit && !bad {C.memset(&expected[0],0xa5,64); C.memset(&expected[9],0x3c,16)}
  wanted := if !permit {i32(C.EPERM)} else if bad {i32(C.EFAULT)} else {i32(0)}
  mut code := C.__errno_location(); *code = 0
  result := C.syscall(if writing {C.SYS_process_vm_writev} else {C.SYS_process_vm_readv},isize(target.pid),&here,u64(1),&there,u64(1),u64(0)); saved := *code
  mut good := result == if wanted == 0 {isize(16)} else {isize(-1)} && saved == wanted && C.memcmp(&local[0],&expected[0],64) == 0
  if writing {
   mut seen := [64]u8{}; mut desired := [64]u8{}; C.memset(&desired[0],0x3c,64); if permit {C.memset(&desired[9],0x5a,16)}
   if C.write(door,c'A',1) != 1 || C.read(reply,&seen[0],64) != 64 {fatal(9)}
   good = good && C.memcmp(&seen[0],&desired[0],64) == 0
  }
  mark(counts,if writing {3} else {2},good,index,ordinary,namespace,result,saved,wanted); return good
 }
}
fn checks(counts &Counts,target &Target,caller Credentials,door i32,reply i32,index i32,ordinary bool,namespace bool) bool {
 unsafe {
  permit := allowed(caller,target.credentials); mut good := true
  mut self_head := u64(0); mut length := u64(0)
  if C.syscall(C.SYS_get_robust_list,isize(0),&self_head,&length) != 0 || length != 24 {fatal(10)}
  for upper in [false,true]! {for shape in 0 .. 3 {
   good = query(counts,0,target.pid,target.head,permit,index,ordinary,namespace,upper,i32(shape)) && good
   good = query(counts,1,target.tid,target.worker_head,permit,index,ordinary,namespace,upper,i32(shape)) && good
   for pid in [i32(0),C.getpid()]! {good = query(counts,4,pid,self_head,true,index,ordinary,namespace,upper,i32(shape)) && good}
   for pid in [i32(-1),i32(-2147483647-1)]! {good = query(counts,5,pid,0,false,index,ordinary,namespace,upper,i32(shape)) && good}
  }}
  for bad in [false,true]! {good = transfer(counts,false,target,permit,door,reply,index,ordinary,namespace,bad) && good}
  for bad in [false,true]! {good = transfer(counts,true,target,permit,door,reply,index,ordinary,namespace,bad) && good}
  return good
 }
}
fn trial(counts &Counts,index i32,ordinary bool,namespace bool,announce bool) bool {
 unsafe {
  base := if ordinary {u32(1000)} else {u32(0)}; caller := profile(index,base,true); wanted := profile(index,base,false)
  mut ready := [i32(-1),i32(-1)]!; mut door := [i32(-1),i32(-1)]!; mut replies := [i32(-1),i32(-1)]!
  if C.pipe2(&ready[0],0) != 0 || C.pipe2(&door[0],0) != 0 || C.pipe2(&replies[0],0) != 0 {fatal(11)}
  page := usize(C.sysconf(C._SC_PAGESIZE)); memory := C.mmap(nil,page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0); if u64(memory) == ~u64(0) {fatal(12)}
  owner := C.fork(); if owner < 0 {fatal(13)}
  if owner == 0 {
   C.close(ready[0]); C.close(door[1]); C.close(replies[0]); credentials(wanted); C.memset(memory,0x3c,64)
   mut original := u64(0); mut length := u64(0)
   if C.syscall(C.SYS_get_robust_list,isize(0),&original,&length) != 0 || length != 24 {fatal(14)}
   head := u64(0x12345000); worker_head := u64(0x6789a000)
   if C.syscall(C.SYS_set_robust_list,voidptr(head),u64(24)) != 0 {fatal(15)}
   mut worker_ready := [i32(-1),i32(-1)]!; mut worker_door := [i32(-1),i32(-1)]!
   if C.pipe2(&worker_ready[0],0) != 0 || C.pipe2(&worker_door[0],0) != 0 {fatal(16)}
   state := &Worker(C.alloca(usize(sizeof(Worker)))); *state = Worker{ready:worker_ready[1],release:worker_door[0],head:worker_head}; mut handle := C.pthread_t{}
   if C.pthread_create(&handle,nil,worker,state) != 0 {fatal(17)}
   mut tid := i32(0); if C.read(worker_ready[0],&tid,4) != 4 || tid != state.tid || tid == C.getpid() {fatal(18)}
   target := &Target(C.alloca(usize(sizeof(Target)))); *target = Target{pid:C.getpid(),tid:tid,parent:C.getppid(),head:head,worker_head:worker_head,memory:u64(memory)}; observe(&target.credentials)
   if target.credentials != wanted || C.write(ready[1],target,sizeof(Target)) != isize(sizeof(Target)) {fatal(19)}
   for {
    mut command := u8(0); if C.read(door[0],&command,1) != 1 {fatal(20)}
    if command == `A` {if C.write(replies[1],memory,64) != 64 {fatal(21)}; continue}
    if command != `X` {fatal(22)}; break
   }
   if C.write(worker_door[1],c'X',1) != 1 || C.pthread_join(handle,nil) != 0 || C.syscall(C.SYS_set_robust_list,voidptr(original),u64(24)) != 0 {fatal(23)}
   for fd in [worker_ready[0],worker_ready[1],worker_door[0],worker_door[1],ready[1],door[0],replies[1]]! {if C.close(fd) != 0 {fatal(24)}}
   C._exit(0)
  }
  C.close(ready[1]); C.close(door[0]); C.close(replies[1]); target := &Target(C.alloca(usize(sizeof(Target))))
  if C.read(ready[0],target,sizeof(Target)) != isize(sizeof(Target)) || target.pid != owner || target.parent != C.getpid() || target.credentials != wanted || target.tid <= 0 || target.tid == owner {fatal(25)}
  C.close(ready[0]); mut result_pipe := [i32(-1),i32(-1)]!; if C.pipe2(&result_pipe[0],0) != 0 {fatal(26)}
  actor := C.fork(); if actor < 0 {fatal(27)}
  if actor == 0 {
   C.close(result_pipe[0]); credentials(caller); local := &Counts(C.alloca(usize(sizeof(Counts)))); *local = Counts{}
   passed := checks(local,target,caller,door[1],replies[0],index,ordinary,namespace)
   if C.write(result_pipe[1],local,sizeof(Counts)) != isize(sizeof(Counts)) {fatal(28)}
   for fd in [door[1],replies[0],result_pipe[1]]! {C.close(fd)}; C.fflush(nil); C._exit(if passed {0} else {1})
  }
  C.close(result_pipe[1]); local := &Counts(C.alloca(usize(sizeof(Counts)))); *local = Counts{}
  if C.read(result_pipe[0],local,sizeof(Counts)) != isize(sizeof(Counts)) {fatal(29)}
  C.close(result_pipe[0]); mut status := i32(-1); if C.waitpid(actor,&status,0) != actor || status !in [i32(0),256]! {fatal(30)}
  if C.write(door[1],c'X',1) != 1 || C.close(door[1]) != 0 || C.close(replies[0]) != 0 || C.waitpid(owner,&status,0) != owner || status != 0 || C.munmap(memory,page) != 0 {fatal(31)}
  mut good := true
  for kind in 0 .. 6 {
   if counts != nil {mut output := &Counts(counts); output.calls[kind] += local.calls[kind]; output.failures[kind] += local.failures[kind]}
   if local.failures[kind] != 0 {good = false}
  }
  if announce {C.printf(c'LINUX ROBUSTCREDS PROFILE: ordinary=%d namespace=%d profile=%d caller_uid=%u/%u/%u caller_gid=%u/%u/%u caller_caps=%u/%u target_uid=%u/%u/%u target_gid=%u/%u/%u target_caps=%u/%u dump=%d allowed=%d\n',i32(ordinary),i32(namespace),index,caller.uid,caller.euid,caller.suid,caller.gid,caller.egid,caller.sgid,caller.permitted,caller.effective,wanted.uid,wanted.euid,wanted.suid,wanted.gid,wanted.egid,wanted.sgid,wanted.permitted,wanted.effective,wanted.dump,i32(allowed(caller,wanted))); C.fflush(nil)}
  return good
 }
}

fn storage(ordinary bool,namespace bool) bool {
 unsafe {
  observer := C.open(c'/proc/slabinfo',0); if observer < 0 {return false}; defer {C.close(observer)}
  for index in 0 .. 32 {if !trial(nil,i32(index),ordinary,namespace,false) {return false}}; C.usleep(13000000)
  before := &Slabs(C.alloca(usize(sizeof(Slabs)))); after := &Slabs(C.alloca(usize(sizeof(Slabs))))
  if !snapshot(observer,before) {return false}
  for index in 0 .. 200 {if !trial(nil,i32(index%32),ordinary,namespace,false) {return false}}; C.usleep(13000000)
  if !snapshot(observer,after) {return false}
  mut good := before.rows == after.rows && before.large == after.large
  for index in 0 .. int(before.rows) {
   if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] {good = false}
   C.printf(c'LINUX ROBUSTCREDS SLAB: ordinary=%d namespace=%d size=%lu live=%lu/%lu cycles=200\n',i32(ordinary),i32(namespace),before.sizes[index],before.live[index],after.live[index])
  }
  C.printf(c'LINUX ROBUSTCREDS STORAGE: ordinary=%d namespace=%d cycles=200 big_pages=%lu/%lu %s\n',i32(ordinary),i32(namespace),before.large,after.large,if good {&char(c'PASS')} else {&char(c'FAIL')}); C.fflush(nil); return good
 }
}
fn qualify(counts &Counts,ordinary bool,namespace bool,reference bool) bool {
 unsafe {
  C.alarm(1400); if C.setsid() != C.getpid() {fatal(32)}
  mut blocked := C.sigset_t{}; mut previous := C.sigset_t{}
  if C.sigemptyset(&blocked) != 0 || C.sigaddset(&blocked,C.SIGCHLD) != 0 || C.pthread_sigmask(C.SIG_BLOCK,&blocked,&previous) != 0 {fatal(33)}
  page := u64(C.sysconf(C._SC_PAGESIZE)); if page !in [u64(4096),16384]! {fatal(34)}
  mut good := true; for index in 0 .. 32 {good = trial(counts,i32(index),ordinary,namespace,true) && good}
  C.printf(c'LINUX ROBUSTCREDS COHORT: ordinary=%d namespace=%d self=%d page=%lu profiles=32 targets=32 workers=32 callers=32 cleaned=96\n',i32(ordinary),i32(namespace),C.getpid(),page); C.fflush(nil)
  if good && !reference && !storage(ordinary,namespace) {good = false}
  if C.pthread_sigmask(C.SIG_SETMASK,&previous,nil) != 0 {fatal(35)}
  for kind in 0 .. 6 {C.printf(c'LINUX ROBUSTCREDS CASES: ordinary=%d namespace=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),i32(namespace),kind,counts.calls[kind],counts.failures[kind])}
  C.alarm(0); C.fflush(nil); return good
 }
}

fn snapshot(fd i32, destination &Slabs) bool {
	unsafe {
		mut counts := &Slabs(destination)
		*counts = Slabs{}
		mut data := [4096]char{}
		length := C.pread(fd, &data[0], 4095, 0)
		if length <= 0 || length >= 4096 { return false }
		data[int(length)] = 0
		mut position := 0
		mut large := false
		for position < int(length) {
			mut size := u64(0)
			mut duplicate := u64(0)
			mut live := u64(0)
			mut pages := u64(0)
			if C.sscanf(&data[position], c'size-%lu %lu %lu %lu', &size, &duplicate, &live, &pages) == 4 {
				if counts.rows >= 32 || size != duplicate { return false }
				counts.sizes[counts.rows] = size
				counts.live[counts.rows] = live
				counts.rows++
			} else if C.sscanf(&data[position], c'large - - %lu', &counts.large) == 1 {
				large = true
			}
			for position < int(length) && data[position] != char(10) { position++ }
			position++
		}
		return counts.rows > 0 && large
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
 unsafe {
  if sizeof(Counts) != 96 { fatal(14) }
  reference := argc == 2 && C.strcmp(argv[1],c'--reference') == 0; mut good := true
  for namespace in [false,true]! { for ordinary in [false,true]! {
   mut pipe := [i32(-1),i32(-1)]!; if C.pipe2(&pipe[0],0) != 0 { fatal(15) }
   outer := C.fork(); if outer < 0 { fatal(16) }
   if outer == 0 {
    C.close(pipe[0])
    if namespace {
     if C.unshare(C.CLONE_NEWPID) != 0 { fatal(17) }
     init := C.fork(); if init < 0 { fatal(18) }
     if init > 0 { C.close(pipe[1]); mut status := i32(-1); C._exit(if C.waitpid(init,&status,0) == init && status == 0 {0} else {1}) }
     if C.getpid() != 1 { fatal(19) }
     cohort := C.fork(); if cohort < 0 { fatal(20) }
     if cohort > 0 { C.close(pipe[1]); mut status := i32(-1); C._exit(if C.waitpid(cohort,&status,0) == cohort && status == 0 {0} else {1}) }
    }
    counts := &Counts(C.alloca(usize(sizeof(Counts)))); *counts = Counts{}
    passed := qualify(counts,ordinary,namespace,reference)
    sent := C.write(pipe[1],counts,sizeof(Counts)) == isize(sizeof(Counts)); C.close(pipe[1]); C._exit(if passed && sent {0} else {1})
   }
   C.close(pipe[1]); counts := &Counts(C.alloca(usize(sizeof(Counts)))); *counts = Counts{}
   received := C.read(pipe[0],counts,sizeof(Counts)) == isize(sizeof(Counts)); C.close(pipe[0])
   mut status := i32(-1); completed := C.waitpid(outer,&status,0) == outer && status == 0
   if !received || !completed { good = false }
   if received { for kind in 0 .. 6 {
    C.printf(c'LINUX ROBUSTCREDS FINAL: ordinary=%d namespace=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),i32(namespace),kind,counts.calls[kind],counts.failures[kind])
    if counts.failures[kind] != 0 { good = false }
   } }; C.fflush(nil)
  } }
  if !good { C.puts(c'LINUX ROBUSTCREDS FAIL: robust-list real credentials, permitted capability subset, effective ptrace override or retained storage'); C.fflush(nil); return 1 }
  C.puts(if reference {c'LINUX ROBUSTCREDS REFERENCE: PASS'} else {c'LINUX ROBUSTCREDS: PASS'}); C.fflush(nil); for { C.pause() }
 }; return 0
}
