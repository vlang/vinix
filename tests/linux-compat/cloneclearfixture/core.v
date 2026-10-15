// SPDX-License-Identifier: GPL-2.0-or-later
module cloneclearfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <sched.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct Counts {mut: calls [6]u64 failures [6]u64}
struct Slabs {mut: sizes [32]u64 live [32]u64 rows i32 large u64}
struct Args {mut: flags u64 pidfd u64 child_tid u64 parent_tid u64 exit_signal u64 stack u64 stack_size u64 tls u64 set_tid u64 set_tid_size u64 cgroup u64}
struct Action {mut: handler u64 flags u64 restorer u64 mask u64}
struct State {self i32 page u64 input u64}
struct Child {pid i32 tid i32 parent i32 uid u32 actions bool blocked bool}
struct Outcome {result i64 code i32 guarded bool identity bool actions bool blocked bool delivered bool}

fn C.alloca(usize) voidptr
fn C.syscall(isize,...) isize
fn C.__errno_location() &i32
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

fn fatal(stage i32) {C.printf(c'LINUX CLONECLEAR FAIL: setup stage=%d errno=%d\n',stage,unsafe{*C.__errno_location()}); C.fflush(unsafe{nil}); C._exit(90)}
fn count(class i32) i32 {return if class == 4 {36} else if class == 5 {12} else {24}}
fn caught(_ i32) {C._exit(42)}

fn action(signum i32,value &Action,previous &Action) bool {return unsafe{C.syscall(C.SYS_rt_sigaction,signum,value,previous,u64(8)) == 0}}
fn query_mask() u64 {mut mask := u64(0); if C.syscall(C.SYS_rt_sigprocmask,i32(2),unsafe{nil},&mask,u64(8)) != 0 {fatal(1)}; return mask}

fn attempt(state &State,class i32,index i32) Outcome {
 unsafe {
  placement := index%3; size := [u64(64),72,80,88]![(index/3)%4]; variant := index/12
  clear := class != 3 && !(class == 4 && variant == 1)
  offset := if placement == 0 {u64(128)} else if placement == 1 {u64(129)} else {state.page-size}
  source := state.input+offset
  if C.mprotect(voidptr(state.input),usize(2*state.page),C.PROT_READ|C.PROT_WRITE) != 0 {fatal(2)}
  C.memset(voidptr(state.input),0xa5,usize(2*state.page))
  args := &Args(C.alloca(usize(sizeof(Args)))); *args = Args{flags:if clear {u64(0x100000000)} else {u64(0)},exit_signal:17}
  if class == 5 {args.flags |= 0x900}
  C.memcpy(voidptr(source),args,usize(size))
  expected := &u8(C.alloca(usize(2*state.page))); C.memcpy(expected,voidptr(state.input),usize(2*state.page))
  if C.mprotect(voidptr(state.input),usize(state.page),C.PROT_READ) != 0 || C.mprotect(voidptr(state.input+state.page),usize(state.page),C.PROT_NONE) != 0 {fatal(3)}
  saved := &Action(C.alloca(usize(65*sizeof(Action)))); installed := &Action(C.alloca(usize(65*sizeof(Action))))
  observed := &Action(C.alloca(usize(sizeof(Action)))); C.memset(saved,0,usize(65*sizeof(Action))); C.memset(installed,0,usize(65*sizeof(Action)))
  for signum in 1 .. 65 {
   if signum == 9 || signum == 19 {continue}
   mode := if signum == 17 {2} else if class == 3 {(signum+variant)%3} else if class == 4 {if variant == 2 {1} else {0}} else {int(class)%3}
   installed[signum] = Action{handler:if mode == 0 {u64(voidptr(caught))} else if mode == 1 {u64(1)} else {u64(0)}, flags:if variant == 0 {u64(0x14000000)} else {u64(0x9c000004)}, restorer:0x12345678,mask:(u64(0x5a5aa5a5f0f00f0f) ^ (u64(signum)<<32)) & ~((u64(1)<<8)|(u64(1)<<18))}
   // Keep SIGCHLD waitable in the parent in every mode.
   if !action(i32(signum),&installed[signum],&saved[signum]) {fatal(4)}
   if !action(i32(signum),nil,observed) || C.memcmp(observed,&installed[signum],sizeof(Action)) != 0 {fatal(5)}
  }
  parent_mask := query_mask()
  mut pipe := [i32(-1),i32(-1)]!; if C.pipe2(&pipe[0],0) != 0 {fatal(6)}
  mut code := C.__errno_location(); *code = 0
  result := C.syscall(C.SYS_clone3,voidptr(source),size); error := *code
  if result == 0 {
   C.close(pipe[0]); mut good := true
   for signum in 1 .. 65 {
    if signum == 9 || signum == 19 {continue}
    mut wanted := installed[signum]
    if clear {wanted = Action{handler:if wanted.handler == 1 {u64(1)} else {u64(0)}}}
    if !action(i32(signum),nil,observed) || C.memcmp(observed,&wanted,sizeof(Action)) != 0 {good = false}
   }
   reply := Child{pid:C.getpid(),tid:i32(C.syscall(C.SYS_gettid)),parent:C.getppid(),uid:C.getuid(),actions:good,blocked:query_mask()==parent_mask}
   if C.write(pipe[1],&reply,sizeof(Child)) != isize(sizeof(Child)) {C._exit(91)}
   C.close(pipe[1])
   if class == 4 {
    unblocked := parent_mask & ~(u64(1)<<9)
    if C.syscall(C.SYS_rt_sigprocmask,i32(2),&unblocked,nil,u64(8)) != 0 {C._exit(92)}
    if C.syscall(C.SYS_kill,C.getpid(),i32(10)) != 0 {C._exit(93)}
   }
   C._exit(37)
  }
  if C.close(pipe[1]) != 0 {fatal(7)}
  mut identity := false; mut actions := false; mut blocked := false; mut delivered := false
  if result > 0 {
   reply := &Child(C.alloca(usize(sizeof(Child)))); *reply = Child{}
   received := C.read(pipe[0],reply,sizeof(Child)) == isize(sizeof(Child))
   mut status := i32(-1); reaped := C.waitpid(i32(result),&status,0) == i32(result)
   identity = received && reaped && reply.pid == result && reply.tid == result && reply.parent == state.self && reply.uid == C.getuid()
   actions = reply.actions; blocked = reply.blocked
   wanted := if class != 4 || variant == 2 {i32(37<<8)} else if clear {i32(10)} else {i32(42<<8)}
   delivered = status == wanted
  } else if result != -1 {fatal(8)}
  mut parent_unchanged := query_mask() == parent_mask
  for signum in 1 .. 65 {
   if signum == 9 || signum == 19 {continue}
   if !action(i32(signum),nil,observed) || C.memcmp(observed,&installed[signum],sizeof(Action)) != 0 {parent_unchanged = false}
   if !action(i32(signum),&saved[signum],nil) {fatal(9)}
  }
  if C.close(pipe[0]) != 0 || C.mprotect(voidptr(state.input),usize(2*state.page),C.PROT_READ|C.PROT_WRITE) != 0 {fatal(10)}
  guarded := C.memcmp(expected,voidptr(state.input),usize(2*state.page)) == 0
  mut status := i32(-1); *code = 0
  empty := C.waitpid(-1,&status,C.WNOHANG); no_children := empty == -1 && *code == C.ECHILD
  return Outcome{result:i64(result),code:error,guarded:guarded&&parent_unchanged&&no_children,identity:identity,actions:actions,blocked:blocked,delivered:delivered}
 }
}
fn run_case(counts &Counts,state &State,class i32,index i32,ordinary bool,namespace bool) bool {
 outcome := attempt(state,class,index)
 good := outcome.guarded && if class == 5 {outcome.result == -1 && outcome.code == C.EINVAL && !outcome.identity} else {outcome.result > 1 && outcome.code == 0 && outcome.identity && outcome.actions && outcome.blocked && outcome.delivered}
 if counts != unsafe{nil} {unsafe {
  mut output := &Counts(counts); output.calls[class]++
  if !good {output.failures[class]++; if output.failures[class] <= 3 {C.printf(c'LINUX CLONECLEAR DETAIL: ordinary=%d namespace=%d kind=%d index=%d result=%ld errno=%d guarded=%d identity=%d actions=%d blocked=%d delivered=%d\n',i32(ordinary),i32(namespace),class,index,outcome.result,outcome.code,i32(outcome.guarded),i32(outcome.identity),i32(outcome.actions),i32(outcome.blocked),i32(outcome.delivered))}}
 }}
 return good
}
fn cycle(state &State,index i32) bool {
 // Identical real forks on both kernels; strict semantics are counted above.
 // This cleanup measurement accepts the original table only in this path.
 outcome := attempt(state,i32(index%4),i32(index%24))
 if !outcome.guarded || outcome.result <= 1 || outcome.code != 0 || !outcome.identity || !outcome.blocked || !outcome.delivered {return false}
 return run_case(unsafe{nil},state,5,i32(index%12),false,false)
}

fn qualify(counts &Counts,ordinary bool,namespace bool,reference bool) bool {
 unsafe {
  C.alarm(1100)
  if ordinary && (C.setgroups(0,nil) != 0 || C.setgid(1000) != 0 || C.setresuid(1000,1000,1000) != 0) {fatal(11)}
  uid := if ordinary {u32(1000)} else {u32(0)}
  if C.getuid() != uid || C.geteuid() != uid || C.setsid() != C.getpid() {fatal(12)}
  blocked := ~u64(0) & ~((u64(1)<<8)|(u64(1)<<18)); mut previous := u64(0)
  if C.syscall(C.SYS_rt_sigprocmask,i32(2),&blocked,&previous,u64(8)) != 0 || query_mask() != blocked {fatal(13)}
  page := u64(C.sysconf(C._SC_PAGESIZE)); if page != 4096 && page != 16384 {fatal(14)}
  input := C.mmap(nil,usize(2*page),C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0)
  if u64(input) == ~u64(0) {fatal(15)}
  state := &State(C.alloca(usize(sizeof(State)))); *state = State{self:C.getpid(),page:page,input:u64(input)}
  mut good := true
  for class in 0 .. 6 {for index in 0 .. count(i32(class)) {if !run_case(counts,state,i32(class),i32(index),ordinary,namespace) {good = false}}}
  C.printf(c'LINUX CLONECLEAR COHORT: ordinary=%d namespace=%d self=%d uid=%u page=%lu raw=144 classes=6 layouts=3\n',i32(ordinary),i32(namespace),state.self,uid,page); C.fflush(nil)
  if !reference && !storage(state,ordinary,namespace) {good = false}
  if C.munmap(input,usize(2*page)) != 0 {fatal(16)}
  if C.syscall(C.SYS_rt_sigprocmask,i32(2),&previous,nil,u64(8)) != 0 {fatal(17)}
  for class in 0 .. 6 {C.printf(c'LINUX CLONECLEAR CASES: ordinary=%d namespace=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),i32(namespace),class,counts.calls[class],counts.failures[class])}
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
  for index in 0 .. int(before.rows) {if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] {good = false}; C.printf(c'LINUX CLONECLEAR SLAB: ordinary=%d namespace=%d size=%lu live=%lu/%lu cycles=200\n',i32(ordinary),i32(namespace),before.sizes[index],before.live[index],after.live[index])}
  C.printf(c'LINUX CLONECLEAR STORAGE: ordinary=%d namespace=%d cycles=200 big_pages=%lu/%lu %s\n',i32(ordinary),i32(namespace),before.large,after.large,if good {&char(c'PASS')} else {&char(c'FAIL')}); C.fflush(nil); return good
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
    C.printf(c'LINUX CLONECLEAR FINAL: ordinary=%d namespace=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),i32(namespace),kind,counts.calls[kind],counts.failures[kind])
    if counts.failures[kind] != 0 { good = false }
   } }; C.fflush(nil)
  } }
  if !good { C.puts(c'LINUX CLONECLEAR FAIL: clone3 cleared dispositions, inherited actions, parent isolation, blocked mask, signal delivery, rejection or retained storage'); C.fflush(nil); return 1 }
  C.puts(if reference {c'LINUX CLONECLEAR REFERENCE: PASS'} else {c'LINUX CLONECLEAR: PASS'}); C.fflush(nil); for { C.pause() }
 }; return 0
}
