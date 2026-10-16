// SPDX-License-Identifier: GPL-2.0-or-later
module cloneparentfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

@[typedef]
struct C.sigset_t {}
struct Counts {mut: calls [6]u64 failures [6]u64 forks [2]u64}
struct CapHeader {mut: version u32 pid i32}
struct CapData {mut: effective u32 permitted u32 inheritable u32}
struct Slabs {mut: sizes [32]u64 live [32]u64 rows i32 large u64}
struct Args {mut: flags u64 pidfd u64 child_tid u64 parent_tid u64 exit_signal u64 stack u64 stack_size u64 tls u64 set_tid u64 set_tid_size u64 cgroup u64}
struct State {self i32 page u64 input u64 reap_fd i32 ack_fd i32 is_init bool}
struct Child {pid i32 tid i32 parent i32 uid u32}
struct Outcome {result i64 code i32 expected i32 guarded bool child bool}

fn C.alloca(usize) voidptr
fn C.syscall(isize,...) isize
fn C.__errno_location() &i32
fn C.sigemptyset(&C.sigset_t) i32
fn C.sigaddset(&C.sigset_t,i32) i32
fn C.pthread_sigmask(i32,&C.sigset_t,&C.sigset_t) i32
fn C.getpid() i32
fn C.getppid() i32
fn C.getuid() u32
fn C.geteuid() u32
fn C.setsid() i32
fn C.setgroups(usize,voidptr) i32
fn C.setgid(u32) i32
fn C.setresuid(u32,u32,u32) i32
fn C.sysconf(i32) isize
fn C.mmap(voidptr,usize,i32,i32,i32,isize) voidptr
fn C.munmap(voidptr,usize) i32
fn C.mprotect(voidptr,usize,i32) i32
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

fn fatal(stage i32) {C.printf(c'LINUX CLONEPARENT FAIL: setup stage=%d errno=%d\n',stage,unsafe{*C.__errno_location()}); C.fflush(unsafe{nil}); C._exit(90)}
fn count(_class i32) i32 {return 36}

fn drop_namespace_capability() {unsafe {
 header := &CapHeader(C.alloca(usize(sizeof(CapHeader)))); *header = CapHeader{version:0x20080522}
 data := &CapData(C.alloca(usize(2*sizeof(CapData)))); C.memset(data,0,usize(2*sizeof(CapData)))
 if C.syscall(C.SYS_capget,header,data) != 0 {fatal(23)}
 data[0].effective &= ~(u32(1)<<21)
 if C.syscall(C.SYS_capset,header,data) != 0 || C.syscall(C.SYS_capget,header,data) != 0 || data[0].effective & (u32(1)<<21) != 0 {fatal(24)}
}}

fn attempt(state &State,class i32,index i32) Outcome {
 unsafe {
  placement := index%3; choice := index/3
  offset := if placement == 0 {u64(128)} else if placement == 1 {u64(129)} else {state.page-88}
  source := state.input+offset
  if C.mprotect(voidptr(state.input),usize(2*state.page),C.PROT_READ|C.PROT_WRITE) != 0 {fatal(1)}
  C.memset(voidptr(state.input),0xa5,usize(2*state.page))
  args := &Args(C.alloca(usize(sizeof(Args)))); *args = Args{flags:u64(0x8000),exit_signal:0,cgroup:0x7fffffff}
  mut size := u64(88); mut pointer := source; mut wanted := i32(C.EINVAL)
  if class == 0 || class == 2 || class == 5 {
   size = [u64(64),72,80,88]![choice%4]
   args.flags |= [u64(0),0x100000000,0x800000]![choice/4]
   if class == 0 {wanted = if state.is_init {C.EINVAL} else {0}}
   if class == 2 {args.flags |= 0x20000000; wanted = if state.is_init {C.EINVAL} else {C.EPERM}}
   if class == 5 {args.flags &= ~u64(0x8000); args.exit_signal = 17; wanted = 0}
  }
  if class == 1 {
   args.flags |= [u64(0),9,17,64]![choice%4] | [u64(0),u64(1)<<32,~u64(0xffffffff)]![choice/4]
   wanted = if state.is_init {C.EINVAL} else {0}
  }
  if class == 3 {
   match choice {
    0 {pointer = 0; size = 0}
    1 {pointer = 0; size = 64; wanted = C.EFAULT}
    2 {pointer = 1; wanted = C.EFAULT}
    3 {pointer = state.input+state.page; wanted = C.EFAULT}
    4 {pointer = state.input+state.page-80; wanted = C.EFAULT}
    5 {pointer = ~u64(0)-31; wanted = C.EFAULT}
    6 {pointer = 0; size = state.page+1; wanted = C.E2BIG}
    7 {args.set_tid = 1; args.set_tid_size = 1; wanted = C.EFAULT}
    8 {args.set_tid = state.input+512}
    9 {args.set_tid_size = 1}
    10 {args.exit_signal = 65}
    else {args.flags |= 0x200000000; args.cgroup = 0x80000000}
   }
  }
  if class == 4 {
   match choice {
    0 {args.flags |= u64(1)<<34}
    1 {args.flags |= u64(1)<<63}
    2 {args.flags |= 1}
    3 {args.flags |= 0x00400000}
    4 {args.flags |= 0x800}
    5 {args.flags |= 0x10000}
    6 {args.flags |= 0x100000800}
    7 {args.exit_signal = 17}
    8 {args.exit_signal = 64}
    9 {args.exit_signal = 1}
    10 {args.flags |= 2}
    else {args.flags |= 4}
   }
  }

  C.memcpy(voidptr(source),args,88)
  // The complete structure/vector import precedes the init-parent guard.
  if class == 3 && pointer >= state.input+state.page-88 && pointer < state.input+state.page {C.memcpy(voidptr(pointer),args,88)}
  expected := &u8(C.alloca(usize(2*state.page))); C.memcpy(expected,voidptr(state.input),usize(2*state.page))
  if C.mprotect(voidptr(state.input),usize(state.page),C.PROT_READ) != 0 || C.mprotect(voidptr(state.input+state.page),usize(state.page),C.PROT_NONE) != 0 {fatal(2)}
  mut pipe := [i32(-1),i32(-1)]!; if C.pipe2(&pipe[0],0) != 0 {fatal(3)}
  mut code := C.__errno_location(); *code = 0
  result := if class == 1 {C.syscall(C.SYS_clone,args.flags,u64(0),u64(0),u64(0),u64(0))} else {C.syscall(C.SYS_clone3,voidptr(pointer),size)}; error := *code
  if result == 0 {
   reply := Child{pid:C.getpid(),tid:i32(C.syscall(C.SYS_gettid)),parent:C.getppid(),uid:C.getuid()}
   C.close(pipe[0]); if C.write(pipe[1],&reply,sizeof(Child)) != isize(sizeof(Child)) {C._exit(91)}
   C._exit(37)
  }
  if C.close(pipe[1]) != 0 {fatal(4)}
  mut child_ok := false
  if result > 0 {
   reply := &Child(C.alloca(usize(sizeof(Child)))); *reply = Child{}
   received := C.read(pipe[0],reply,sizeof(Child)) == isize(sizeof(Child))
   mut reaped := false
   parent_requested := args.flags & u64(0x8000) != 0
   if parent_requested {
    mut request := u8(1); mut ack := i32(-1)
    if C.write(state.reap_fd,&request,1) != 1 || C.read(state.ack_fd,&ack,sizeof(i32)) != isize(sizeof(i32)) {fatal(34)}
    reaped = ack == 0
   } else {mut status := i32(-1); reaped = C.waitpid(i32(result),&status,0) == i32(result) && status == 37<<8}
   expected_parent := if parent_requested {if state.is_init {i32(0)} else {i32(1)}} else {state.self}
   child_ok = received && reaped && reply.pid == result && reply.tid == result && reply.parent == expected_parent && reply.uid == C.getuid()
  } else if result != -1 {fatal(5)}
  if C.close(pipe[0]) != 0 || C.mprotect(voidptr(state.input),usize(2*state.page),C.PROT_READ|C.PROT_WRITE) != 0 {fatal(6)}
  guarded := C.memcmp(expected,voidptr(state.input),usize(2*state.page)) == 0
  // Rejected calls cannot leave a child behind, even if an errno happened
  // to match after partially creating one. The cohort has no other children.
  mut status := i32(-1); *code = 0
  empty := C.waitpid(-1,&status,C.WNOHANG); no_children := empty == -1 && *code == C.ECHILD
  return Outcome{result:i64(result),code:error,expected:wanted,guarded:guarded&&no_children,child:child_ok}
 }
}
fn run_case(counts &Counts,state &State,class i32,index i32,ordinary bool,namespace bool) bool {
 outcome := attempt(state,class,index)
 good := outcome.guarded && if outcome.expected == 0 {outcome.result > 1 && outcome.code == 0 && outcome.child} else {outcome.result == -1 && outcome.code == outcome.expected && !outcome.child}
 if counts != unsafe{nil} {unsafe {
  mut output := &Counts(counts); output.calls[class]++
  if outcome.result > 0 && outcome.child {output.forks[if outcome.expected == 0 {0} else {1}]++}
  if !good {output.failures[class]++; if output.failures[class] <= 3 {C.printf(c'LINUX CLONEPARENT DETAIL: ordinary=%d init=%d kind=%d index=%d result=%ld errno=%d expected=%d guarded=%d child=%d\n',i32(ordinary),i32(namespace),class,index,outcome.result,outcome.code,outcome.expected,i32(outcome.guarded),i32(outcome.child))}}
 }}
 return good
}
fn cycle(state &State,index i32) bool {
 // The original EPERM and corrected EINVAL requests both refuse before creating
 // a child. All phases use identical inputs and ordinary fork/reap lifecycles.
 outcome := attempt(state,2,i32(index%36))
 if !outcome.guarded || outcome.result != -1 || outcome.child || (outcome.code != C.EPERM && outcome.code != C.EINVAL) {return false}
 return run_case(unsafe{nil},state,5,i32(index%36),false,state.is_init)
}

fn qualify(counts &Counts,ordinary bool,namespace bool,reference bool,reap i32,ack i32) bool {
 unsafe {
  C.alarm(1100)
  if ordinary && (C.setgroups(0,nil) != 0 || C.setgid(1000) != 0 || C.setresuid(1000,1000,1000) != 0) {fatal(7)}
  uid := if ordinary {u32(1000)} else {u32(0)}
  if C.getuid() != uid || C.geteuid() != uid || C.setsid() != C.getpid() {fatal(8)}
  drop_namespace_capability()
  C.printf(c'LINUX CLONEPARENT CAPS: ordinary=%d init=%d sysadmin=0\n',i32(ordinary),i32(namespace))
  mut blocked := C.sigset_t{}; mut previous := C.sigset_t{}
  if C.sigemptyset(&blocked) != 0 || C.sigaddset(&blocked,C.SIGCHLD) != 0 || C.pthread_sigmask(C.SIG_BLOCK,&blocked,&previous) != 0 {fatal(9)}
  page := u64(C.sysconf(C._SC_PAGESIZE)); if page != 4096 && page != 16384 {fatal(10)}
  input := C.mmap(nil,usize(2*page),C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0)
  if u64(input) == ~u64(0) {fatal(11)}
  state := &State(C.alloca(usize(sizeof(State)))); *state = State{self:C.getpid(),page:page,input:u64(input),reap_fd:reap,ack_fd:ack,is_init:namespace}
  if state.self != if namespace {1} else {2} {fatal(35)}
  mut good := true
  for class in 0 .. 6 {for index in 0 .. count(i32(class)) {if !run_case(counts,state,i32(class),i32(index),ordinary,namespace) {good = false}}}
  C.printf(c'LINUX CLONEPARENT COHORT: ordinary=%d init=%d self=%d uid=%u page=%lu raw=216 classes=6 layouts=3\n',i32(ordinary),i32(namespace),state.self,uid,page); C.fflush(nil)
  if !reference && !storage(state,ordinary,namespace) {good = false}
  if C.munmap(input,usize(2*page)) != 0 {fatal(12)}
  if C.pthread_sigmask(C.SIG_SETMASK,&previous,nil) != 0 {fatal(13)}
  for class in 0 .. 6 {C.printf(c'LINUX CLONEPARENT CASES: ordinary=%d init=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),i32(namespace),class,counts.calls[class],counts.failures[class])}
  C.printf(c'LINUX CLONEPARENT CHILDREN: ordinary=%d init=%d valid=%lu unexpected=%lu\n',i32(ordinary),i32(namespace),counts.forks[0],counts.forks[1])
  C.alarm(0); C.fflush(nil); return good
 }
}

fn storage(state &State,ordinary bool,namespace bool) bool {
 unsafe {
  observer := C.open(c'/proc/slabinfo',0); if observer < 0 {return false}; defer {C.close(observer)}
  for index in 0 .. 64 {if !cycle(state,i32(index)) {return false}}; C.usleep(13000000)
  before := &Slabs(C.alloca(usize(sizeof(Slabs)))); after := &Slabs(C.alloca(usize(sizeof(Slabs))))
  if !snapshot(observer,before) {return false}
  for index in 0 .. 200 {if !cycle(state,i32(index)) {return false}}; C.usleep(13000000)
  if !snapshot(observer,after) {return false}
  mut good := before.rows == after.rows && before.large == after.large
  for index in 0 .. int(before.rows) {if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] {good = false}; C.printf(c'LINUX CLONEPARENT SLAB: ordinary=%d init=%d size=%lu live=%lu/%lu cycles=200\n',i32(ordinary),i32(namespace),before.sizes[index],before.live[index],after.live[index])}
  C.printf(c'LINUX CLONEPARENT STORAGE: ordinary=%d init=%d cycles=200 big_pages=%lu/%lu %s\n',i32(ordinary),i32(namespace),before.large,after.large,if good {&char(c'PASS')} else {&char(c'FAIL')}); C.fflush(nil); return good
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

fn global_init() bool {
 unsafe {
  if C.getpid() != 1 || C.getuid() != 0 {fatal(25)}
  header := &CapHeader(C.alloca(usize(sizeof(CapHeader)))); *header = CapHeader{version:0x20080522}
  data := &CapData(C.alloca(usize(2*sizeof(CapData)))); C.memset(data,0,usize(2*sizeof(CapData)))
  if C.syscall(C.SYS_capget,header,data) != 0 {fatal(26)}
  first := data[0].effective; second := data[1].effective
  if first & (u32(1)<<21) == 0 {fatal(27)}
  data[0].effective &= ~(u32(1)<<21)
  if C.syscall(C.SYS_capset,header,data) != 0 || C.syscall(C.SYS_capget,header,data) != 0 || data[0].effective & (u32(1)<<21) != 0 {fatal(28)}
  args := &Args(C.alloca(usize(sizeof(Args)))); *args = Args{}
  mut failures := 0
  for index in 0 .. 24 {
   choice := index/2; *args = Args{flags:u64(0x20008000)|[u64(0),0x40000,0x800000]![choice/4]}
   mut code := C.__errno_location(); *code = 0
   result := if index%2 == 0 {C.syscall(C.SYS_clone3,args,[u64(64),72,80,88]![choice%4])} else {C.syscall(C.SYS_clone,args.flags|17|[u64(0),u64(1)<<32,~u64(0xffffffff)]![choice%3],u64(0),u64(0),u64(0),u64(0))}
   error := *code
   if result == 0 {C._exit(37)}
   if result > 0 {mut status := i32(-1); if C.waitpid(i32(result),&status,0) != result || status != 37<<8 {fatal(29)}}
   if result != -1 || error != C.EINVAL {failures++}
  }
  data[0].effective = first; data[1].effective = second
  if C.syscall(C.SYS_capset,header,data) != 0 || C.syscall(C.SYS_capget,header,data) != 0 || data[0].effective != first || data[1].effective != second {fatal(30)}
  C.printf(c'LINUX CLONEPARENT GLOBAL: self=1 uid=0 calls=24 failures=%d sysadmin_during=0 restored=1\n',failures); C.fflush(nil)
  return failures == 0
 }
}

fn cohort(report i32,reap i32,ack i32,ordinary bool,is_init bool,reference bool) {
 unsafe {
  counts := &Counts(C.alloca(usize(sizeof(Counts)))); *counts = Counts{}
  passed := qualify(counts,ordinary,is_init,reference,reap,ack)
  sent := C.write(report,counts,sizeof(Counts)) == isize(sizeof(Counts))
  C.close(report); C.close(reap); C.close(ack)
  C._exit(if passed && sent {0} else {1})
 }
}

fn collect(cohort_pid i32,reap i32,ack i32,ordinary bool,is_init bool) bool {
 unsafe {
  mut reaped := 0; mut good := true
  for {
   mut request := u8(0); received := C.read(reap,&request,1)
   if received == 0 {break}
   if received != 1 || request != 1 {fatal(31)}
   mut status := i32(-1); pid := C.waitpid(-1,&status,0)
   valid := pid > 0 && pid != cohort_pid && status == 37<<8
   if !valid {good = false}
   mut reply := i32(if valid {0} else {1})
   if C.write(ack,&reply,sizeof(i32)) != isize(sizeof(i32)) {fatal(32)}
   reaped++
  }
  C.close(reap); C.close(ack)
  mut status := i32(-1); finished := C.waitpid(cohort_pid,&status,0) == cohort_pid
  C.printf(c'LINUX CLONEPARENT REAPER: ordinary=%d init=%d reaped=%d status=%d\n',i32(ordinary),i32(is_init),reaped,status); C.fflush(nil)
  return good && finished && status == 0
 }
}

fn launch_cohort(report i32,ordinary bool,is_init bool,reference bool) {
 unsafe {
  mut reap := [i32(-1),i32(-1)]!; mut ack := [i32(-1),i32(-1)]!
  if C.pipe2(&reap[0],0) != 0 || C.pipe2(&ack[0],0) != 0 {fatal(33)}
  if C.unshare(C.CLONE_NEWPID) != 0 {fatal(17)}
  init := C.fork(); if init < 0 {fatal(18)}
  if init > 0 {
   C.close(report); C.close(reap[1]); C.close(ack[0])
   if is_init {C._exit(if collect(init,reap[0],ack[1],ordinary,is_init) {0} else {1})}
   C.close(reap[0]); C.close(ack[1])
   mut status := i32(-1); C._exit(if C.waitpid(init,&status,0) == init && status == 0 {0} else {1})
  }
  if C.getpid() != 1 {fatal(19)}
  if is_init {
   C.close(reap[0]); C.close(ack[1]); cohort(report,reap[1],ack[0],ordinary,is_init,reference)
  }
  child := C.fork(); if child < 0 {fatal(20)}
  if child == 0 {
   C.close(reap[0]); C.close(ack[1]); cohort(report,reap[1],ack[0],ordinary,is_init,reference)
  }
  C.close(report); C.close(reap[1]); C.close(ack[0])
  C._exit(if collect(child,reap[0],ack[1],ordinary,is_init) {0} else {1})
 }
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
 unsafe {
  if sizeof(Counts) != 112 {fatal(14)}
  reference := argc == 2 && C.strcmp(argv[1],c'--reference') == 0
  mut good := global_init()
  for is_init in [false,true]! {for ordinary in [false,true]! {
   mut pipe := [i32(-1),i32(-1)]!; if C.pipe2(&pipe[0],0) != 0 {fatal(15)}
   outer := C.fork(); if outer < 0 {fatal(16)}
   if outer == 0 {C.close(pipe[0]); launch_cohort(pipe[1],ordinary,is_init,reference); C._exit(90)}
   C.close(pipe[1]); counts := &Counts(C.alloca(usize(sizeof(Counts)))); *counts = Counts{}
   received := C.read(pipe[0],counts,sizeof(Counts)) == isize(sizeof(Counts)); C.close(pipe[0])
   mut status := i32(-1); completed := C.waitpid(outer,&status,0) == outer && status == 0
   if !received || !completed {good = false}
   if received {for kind in 0 .. 6 {
    C.printf(c'LINUX CLONEPARENT FINAL: ordinary=%d init=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),i32(is_init),kind,counts.calls[kind],counts.failures[kind])
    if counts.failures[kind] != 0 {good = false}
   }; C.printf(c'LINUX CLONEPARENT CHILDRENFINAL: ordinary=%d init=%d valid=%lu unexpected=%lu\n',i32(ordinary),i32(is_init),counts.forks[0],counts.forks[1])}; C.fflush(nil)
  }}
  if !good {C.puts(c'LINUX CLONEPARENT FAIL: init sibling rejection, ordinary parent reuse, import precedence, child lifecycle or retained storage'); C.fflush(nil); return 1}
  C.puts(if reference {c'LINUX CLONEPARENT REFERENCE: PASS'} else {c'LINUX CLONEPARENT: PASS'}); C.fflush(nil); for {C.pause()}
 }; return 0
}
