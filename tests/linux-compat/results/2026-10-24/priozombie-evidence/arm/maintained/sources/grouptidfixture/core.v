// SPDX-License-Identifier: GPL-2.0-or-later
module grouptidfixture

#include <alloca.h>
#include <errno.h>
#include <grp.h>
#include <signal.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

@[typedef]
struct C.siginfo_t {}
struct Counts { mut: calls [6]u64 failures [6]u64 }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows i32 large u64 }
struct Result { ret isize code i32 }
@[typedef]
struct C.pthread_t {}
struct Worker { mut: tid i32 release i32 command i32 done i32 counts &Counts = unsafe { nil } ordinary bool }
struct Child { pid i32 tid i32 door i32 }
struct State { self i32 child Child first i32 second i32 }

fn C.alloca(usize) voidptr
fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.getpid() i32
fn C.getppid() i32
fn C.getpgid(i32) i32
fn C.getsid(i32) i32
fn C.setpgid(i32,i32) i32
fn C.setsid() i32
fn C.getuid() u32
fn C.geteuid() u32
fn C.getgid() u32
fn C.getegid() u32
fn C.setgroups(usize,voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.pipe2(&i32,i32) i32
fn C.read(i32,voidptr,usize) isize
fn C.write(i32,voidptr,usize) isize
fn C.pread(i32,voidptr,usize,i64) isize
fn C.open(&char,i32,...) i32
fn C.close(i32) i32
fn C.fork() i32
fn C.waitpid(i32,&i32,i32) i32
fn C.waitid(i32,u32,&C.siginfo_t,i32) i32
fn C._exit(i32)
fn C.alarm(u32) u32
fn C.usleep(u32) i32
fn C.pause() i32
fn C.strcmp(&char,&char) i32
fn C.sscanf(&char,&char,...) i32
fn C.printf(&char,...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32

fn fatal(stage i32) {
	C.printf(c'LINUX GROUPTID FAIL: setup stage=%d errno=%d\n',stage,unsafe{*C.__errno_location()})
	C.fflush(unsafe{nil}); C._exit(1)
}

fn word(value i32, form i32) u64 {
	if form == 0 { return u64(u32(value)) }
	if form == 1 || form == 7 { return u64(i64(value)) }
	if form == 2 { return u64(u32(value)) | 0x0000000100000000 }
	if form == 3 { return u64(u32(value)) | 0x1234567800000000 }
	if form == 4 { return u64(u32(value)) | 0x8000000000000000 }
	if form == 5 { return u64(u32(value)) | 0x7fffffff00000000 }
	return u64(u32(value)) | 0xffffffff00000000
}

fn query(session bool, pid i32, form i32) Result {
	unsafe {
		slot := C.__errno_location(); *slot = 0
		ret := if form == 7 { isize(if session { C.getsid(pid) } else { C.getpgid(pid) }) }
			else { C.syscall(isize(if session { C.SYS_getsid } else { C.SYS_getpgid }),word(pid,form)) }
		return Result{ret,*slot}
	}
}

fn set(pid i32, group i32, pform i32, gform i32) Result {
	unsafe {
		slot := C.__errno_location(); *slot = 0
		ret := if pform == 7 && gform == 7 { isize(C.setpgid(pid,group)) }
			else { C.syscall(isize(C.SYS_setpgid),word(pid,pform),word(group,gform)) }
		return Result{ret,*slot}
	}
}

fn record(counts &Counts, kind i32, good bool, ordinary bool, pid i32, group i32, pform i32, gform i32, actual Result, expected isize, code i32) {
	unsafe {
		counts.calls[kind]++
		if !good {
			counts.failures[kind]++
			if counts.failures[kind] <= 6 {
				C.printf(c'LINUX GROUPTID DETAIL: ordinary=%d kind=%d pid=%d group=%d pform=%d gform=%d actual=%ld/%d expected=%ld/%d\n',
					i32(ordinary),kind,pid,group,pform,gform,actual.ret,actual.code,expected,code)
				C.fflush(nil)
			}
		}
	}
}

fn C.pthread_create(&C.pthread_t,voidptr,fn (voidptr) voidptr,voidptr) i32
fn C.pthread_join(C.pthread_t,voidptr) i32
fn C.__atomic_store_n(&i32,i32,i32)
fn C.__atomic_load_n(&i32,i32) i32
fn C.sched_yield() i32
fn C.unshare(i32) i32

fn worker(argument voidptr) voidptr {
 unsafe {
  mut value := &Worker(argument)
  C.__atomic_store_n(&value.tid,i32(C.syscall(C.SYS_gettid)),3)
  for C.__atomic_load_n(&value.release,2) == 0 {
   if C.__atomic_load_n(&value.command,2) == 1 {
    for form in 0 .. 8 {
     for session in [false,true]! { for id in [i32(0),value.tid]! {
      actual := query(session,id,i32(form)); wanted := isize(C.getpid())
      record(value.counts,5,actual.ret == wanted && actual.code == 0,value.ordinary,id,i32(session),i32(form),0,actual,wanted,0)
     } }
     for id in [i32(0),value.tid]! {
      code := if id == 0 { C.EPERM } else { C.EINVAL }
      actual := set(id,0,i32(form),i32(7-form))
      record(value.counts,5,actual.ret == -1 && actual.code == code,value.ordinary,id,0,i32(form),i32(7-form),actual,-1,code)
     }
    }
    C.__atomic_store_n(&value.command,0,3); C.__atomic_store_n(&value.done,1,3)
   }
   C.sched_yield()
  }
 }
 return unsafe { nil }
}
fn signal_zero(tid i32, removed bool) bool {
 unsafe { for attempt in 0 .. 1000 {
  slot := C.__errno_location(); *slot = 0
  actual := C.syscall(C.SYS_tgkill,C.getpid(),tid,0); code := *slot
  if !removed { return actual == 0 && code == 0 }
  if actual == -1 && code == C.ESRCH { return true }
  if actual != 0 || code != 0 || (attempt < 999 && C.usleep(1000) != 0) { return false }
 }; return false }
}
fn launch_worker(token &C.pthread_t, state &Worker) {
 unsafe {
  mut value := &Worker(state); *value = Worker{}
  if C.pthread_create(token,nil,worker,value) != 0 { fatal(1) }
  for C.__atomic_load_n(&value.tid,2) == 0 { C.sched_yield() }
  if value.tid <= 0 || value.tid == C.getpid() || !signal_zero(value.tid,false) { fatal(2) }
 }
}
fn finish_worker(token C.pthread_t, state &Worker) {
 unsafe { mut value := &Worker(state); C.__atomic_store_n(&value.release,1,3)
  if C.pthread_join(token,nil) != 0 || !signal_zero(value.tid,true) { fatal(3) }
 }
}
fn launch_child() Child {
 unsafe {
  mut info := [i32(-1),i32(-1)]!; mut door := [i32(-1),i32(-1)]!
  if C.pipe2(&info[0],0) != 0 || C.pipe2(&door[0],0) != 0 { fatal(4) }
  pid := C.fork(); if pid < 0 { fatal(5) }
  if pid == 0 {
   C.close(info[0]); C.close(door[1]); mut token := C.pthread_t{}; mut state := Worker{}
   launch_worker(&token,&state)
   if C.write(info[1],&state.tid,4) != 4 || C.close(info[1]) != 0 { fatal(6) }
   mut byte := u8(0); good := C.read(door[0],&byte,1) == 1 && byte == `X` && C.close(door[0]) == 0
   finish_worker(token,&state); C._exit(if good {0} else {1})
  }
  C.close(info[1]); C.close(door[0]); mut tid := i32(0)
  if C.read(info[0],&tid,4) != 4 || C.close(info[0]) != 0 || tid <= 0 || tid == pid { fatal(7) }
  return Child{pid,tid,door[1]}
 }
}
fn finish_child(child Child) {
 unsafe { mut status := i32(-1)
  if C.write(child.door,c'X',1) != 1 || C.close(child.door) != 0 || C.waitpid(child.pid,&status,0) != child.pid || status != 0 { fatal(8) }
 }
}
fn intact(state &State, group i32) bool {
 return C.getpgid(0) == state.self && C.getsid(0) == state.self
  && C.getpgid(state.child.pid) == group && C.getsid(state.child.pid) == state.self
}
fn queries(counts &Counts,state &State,ordinary bool) {
 unsafe { for session in [false,true]! {
  for pid in [i32(0),state.self,state.first,state.second,state.child.pid,state.child.tid]! { for form in 0 .. 8 {
   actual := query(session,pid,i32(form)); wanted := isize(state.self)
   record(counts,0,actual.ret == wanted && actual.code == 0 && intact(state,state.self),ordinary,pid,i32(session),i32(form),0,actual,wanted,0)
  } }
 } }
}
fn setters(counts &Counts,state &State,ordinary bool) {
 unsafe {
  for pid in [state.first,state.second,state.child.tid]! {
   for group in [i32(0),state.self,state.child.pid,i32(0x7fffffff),i32(-1)]! { for pform in 0 .. 8 { for gform in 0 .. 8 {
    actual := set(pid,group,i32(pform),i32(gform))
    record(counts,1,actual.ret == -1 && actual.code == C.EINVAL && intact(state,state.self),ordinary,pid,group,i32(pform),i32(gform),actual,-1,C.EINVAL)
   } } }
  }
  for group in [i32(0),state.self]! { for pform in 0 .. 8 { for gform in 0 .. 8 {
   actual := set(state.child.pid,group,i32(pform),i32(gform)); wanted := if group == 0 { state.child.pid } else { state.self }
   record(counts,2,actual.ret == 0 && actual.code == 0 && intact(state,wanted),ordinary,state.child.pid,group,i32(pform),i32(gform),actual,0,0)
   for session in [false,true]! { for form in 0 .. 8 {
    got := query(session,state.child.tid,i32(form)); expected := isize(if session { state.self } else { wanted })
    record(counts,3,got.ret == expected && got.code == 0 && intact(state,wanted),ordinary,state.child.tid,i32(session),i32(form),0,got,expected,0)
   } }
  } } }
  if !intact(state,state.self) { fatal(9) }
 }
}
fn retired(counts &Counts,state &State,ordinary bool) {
 unsafe {
  for session in [false,true]! { for form in 0 .. 8 {
   actual := query(session,state.first,i32(form))
   record(counts,4,actual.ret == -1 && actual.code == C.ESRCH && intact(state,state.self),ordinary,state.first,i32(session),i32(form),0,actual,-1,C.ESRCH)
  } }
  for group in [i32(0),state.self,state.child.pid,i32(0x7fffffff),i32(-1)]! { for pform in 0 .. 8 { for gform in 0 .. 8 {
   actual := set(state.first,group,i32(pform),i32(gform)); code := if group < 0 { C.EINVAL } else { C.ESRCH }
   record(counts,4,actual.ret == -1 && actual.code == code && intact(state,state.self),ordinary,state.first,group,i32(pform),i32(gform),actual,-1,code)
  } } }
 }
}
fn cycle(state &State) bool {
 for form in 0 .. 8 {
  live := query(false,state.second,i32(form)); session := query(true,state.child.tid,i32(form))
  gone := query(false,state.first,i32(form)); bad := set(state.second,0,i32(form),i32(7-form))
  if live.ret != state.self || live.code != 0 || session.ret != state.self || session.code != 0
   || gone.ret != -1 || gone.code != C.ESRCH || bad.ret != -1 || bad.code != C.EINVAL { return false }
 }
 return intact(state,state.self)
}
fn storage(state &State, ordinary bool, namespace bool) bool {
 unsafe {
  observer := C.open(c'/proc/slabinfo',0); if observer < 0 { return false }; defer { C.close(observer) }
  for _ in 0 .. 32 { if !cycle(state) { return false } }; C.usleep(13000000)
  before := &Slabs(C.alloca(usize(sizeof(Slabs)))); after := &Slabs(C.alloca(usize(sizeof(Slabs))))
  if !snapshot(observer,before) { return false }
  for _ in 0 .. 200 { if !cycle(state) { return false } }; C.usleep(13000000)
  if !snapshot(observer,after) { return false }
  mut good := before.rows == after.rows && before.large == after.large
  for index in 0 .. int(before.rows) {
   if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] { good = false }
   C.printf(c'LINUX GROUPTID SLAB: ordinary=%d namespace=%d size=%lu live=%lu/%lu cycles=200\n',i32(ordinary),i32(namespace),before.sizes[index],before.live[index],after.live[index])
  }
  C.printf(c'LINUX GROUPTID STORAGE: ordinary=%d namespace=%d cycles=200 big_pages=%lu/%lu %s\n',i32(ordinary),i32(namespace),before.large,after.large,if good { &char(c'PASS') } else { &char(c'FAIL') })
  C.fflush(nil); return good
 }
}
fn qualify(counts &Counts, ordinary bool, namespace bool, reference bool) bool {
 unsafe {
  C.alarm(800); uid := if ordinary {u32(1000)} else {u32(0)}
  if ordinary && (C.setgroups(0,nil) != 0 || C.setgid(uid) != 0 || C.setuid(uid) != 0) { fatal(10) }
  if C.getuid() != uid || C.geteuid() != uid || C.getgid() != uid || C.getegid() != uid { fatal(11) }
  self := C.getpid(); if self <= 1 || C.setsid() != self { fatal(12) }
  // Fork before starting caller threads. Each worker has an independent live gate.
  child := launch_child(); mut first := Worker{}; mut second := Worker{}; mut t1 := C.pthread_t{}; mut t2 := C.pthread_t{}
  launch_worker(&t1,&first); launch_worker(&t2,&second)
  mut state := State{self,child,first.tid,second.tid}
  if !intact(&state,self) { fatal(13) }
  C.printf(c'LINUX GROUPTID TOPOLOGY: ordinary=%d namespace=%d uid=%u self=%d first=%d second=%d child=%d child_tid=%d\n',i32(ordinary),i32(namespace),uid,self,first.tid,second.tid,child.pid,child.tid); C.fflush(nil)
  queries(counts,&state,ordinary); setters(counts,&state,ordinary)
  // The leader is idle while the worker writes its disjoint kind-5 counters.
  second.counts = counts; second.ordinary = ordinary; C.__atomic_store_n(&second.command,1,3)
  for C.__atomic_load_n(&second.done,2) == 0 { C.sched_yield() }
  finish_worker(t1,&first); retired(counts,&state,ordinary)
  mut good := true; for kind in 0 .. 6 { if counts.failures[kind] != 0 { good = false } }
  if good && !reference && !storage(&state,ordinary,namespace) { good = false }
  finish_worker(t2,&second); finish_child(child)
  for kind in 0 .. 6 { C.printf(c'LINUX GROUPTID CASES: ordinary=%d namespace=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),i32(namespace),kind,counts.calls[kind],counts.failures[kind]) }
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
    C.printf(c'LINUX GROUPTID FINAL: ordinary=%d namespace=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),i32(namespace),kind,counts.calls[kind],counts.failures[kind])
    if counts.failures[kind] != 0 { good = false }
   } }; C.fflush(nil)
  } }
  if !good { C.puts(c'LINUX GROUPTID FAIL: live/retired task group/session lookup, setter refusals or retained state'); C.fflush(nil); return 1 }
  C.puts(if reference {c'LINUX GROUPTID REFERENCE: PASS'} else {c'LINUX GROUPTID: PASS'}); C.fflush(nil); for { C.pause() }
 }; return 0
}
