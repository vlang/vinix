// SPDX-License-Identifier: GPL-2.0-or-later
module groupzombiefixture

#include <alloca.h>
#include <errno.h>
#include <grp.h>
#include <poll.h>
#include <signal.h>
#include <sched.h>
#include <stdio.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

@[typedef]
struct C.siginfo_t { si_pid i32 si_status i32 si_code i32 }
struct C.pollfd { mut: fd i32 events i16 revents i16 }
struct Counts { mut: calls [6]u64 failures [6]u64 }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows i32 large u64 }
struct Result { ret isize code i32 }
struct Reply { pid i32 parent i32 group i32 session i32 executed i32 }
struct Child { pid i32 door i32 group i32 session i32 }
struct State { self i32 mut: children [5]Child }

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
	C.printf(c'LINUX GROUPZOMBIE FAIL: setup stage=%d errno=%d\n',stage,unsafe{*C.__errno_location()})
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
				C.printf(c'LINUX GROUPZOMBIE DETAIL: ordinary=%d kind=%d pid=%d group=%d pform=%d gform=%d actual=%ld/%d expected=%ld/%d\n',
					i32(ordinary),kind,pid,group,pform,gform,actual.ret,actual.code,expected,code)
				C.fflush(nil)
			}
		}
	}
}

fn C.execl(&char,&char,...) i32
fn C.snprintf(&char,usize,&char,...) i32
fn C.unshare(i32) i32
fn C.poll(&C.pollfd,usize,i32) i32
fn detached(kind i32) bool {return kind == 2 || kind == 3}
fn executed(kind i32) bool {return kind == 1 || kind == 3}
fn hold(info i32,door i32,kind i32,after_exec bool) i32 {
 unsafe {
  if after_exec != executed(kind) {fatal(1)}
  self := C.getpid(); mut reply := Reply{self,C.getppid(),C.getpgid(0),C.getsid(0),i32(after_exec)}
  if after_exec {C.printf(c'LINUX GROUPZOMBIE EXEC: kind=%d pid=%d parent=%d group=%d session=%d uid=%u\n',kind,self,reply.parent,reply.group,reply.session,C.getuid()); C.fflush(nil)}
  if C.write(info,&reply,sizeof(Reply)) != isize(sizeof(Reply)) || C.close(info) != 0 {fatal(2)}
  mut token := u8(0); good := C.read(door,&token,1) == 1 && token == `X` && C.close(door) == 0
  return if good {0} else {1}
 }
}
fn launch(kind i32) Child {
 unsafe {
  mut info := [i32(-1),i32(-1)]!; mut door := [i32(-1),i32(-1)]!
  if C.pipe2(&info[0],0) != 0 || C.pipe2(&door[0],0) != 0 {fatal(3)}
  pid := C.fork(); if pid < 0 {fatal(4)}
  if pid == 0 {
   C.close(info[0]); C.close(door[1])
   if kind == 0 && C.setpgid(0,0) != 0 {fatal(5)}
   if detached(kind) && C.setsid() != C.getpid() {fatal(6)}
   if executed(kind) {
    mut report_text := [24]char{}; mut door_text := [24]char{}; mut kind_text := [8]char{}
    a := C.snprintf(&report_text[0],24,c'%d',info[1]); b := C.snprintf(&door_text[0],24,c'%d',door[0]); k := C.snprintf(&kind_text[0],8,c'%d',kind)
    if a <= 0 || a >= 24 || b <= 0 || b >= 24 || k != 1 {fatal(7)}
    C.execl(c'/proc/self/exe',c'init',c'--held',&report_text[0],&door_text[0],&kind_text[0],voidptr(nil)); fatal(8)
   }
   C._exit(hold(info[1],door[0],kind,false))
  }
  C.close(info[1]); C.close(door[0]); mut reply := Reply{}
  if C.read(info[0],&reply,sizeof(Reply)) != isize(sizeof(Reply)) || C.close(info[0]) != 0 {fatal(9)}
  group := if kind == 0 || detached(kind) {pid} else {C.getpid()}; session := if detached(kind) {pid} else {C.getpid()}
  if reply.pid != pid || reply.parent != C.getpid() || reply.executed != i32(executed(kind)) || reply.group != group || reply.session != session {fatal(10)}
  return Child{pid,door[1],group,session}
 }
}
fn zombie(child Child,ordinary bool,namespace bool,kind i32) {
 unsafe {
  sent := C.write(child.door,c'X',1) == 1; closed := C.close(child.door) == 0; if !sent || !closed {fatal(11)}
  mut info := C.siginfo_t{}
  if C.waitid(C.P_PID,u32(child.pid),&info,C.WEXITED|C.WNOWAIT) != 0 || info.si_pid != child.pid || info.si_code != C.CLD_EXITED || info.si_status != 0 {fatal(12)}
  fd := i32(C.syscall(C.SYS_pidfd_open,u64(u32(child.pid)),u64(0))); if fd < 0 {fatal(13)}
  mut poll := C.pollfd{fd:fd,events:i16(C.POLLIN)}
  ready := C.poll(&poll,1,2000) == 1 && poll.revents & C.POLLIN != 0 && poll.revents & C.POLLHUP == 0
  done := C.close(fd) == 0; if !ready || !done {fatal(14)}
  C.printf(c'LINUX GROUPZOMBIE EXIT: ordinary=%d namespace=%d kind=%d pid=%d wait=CLD_EXITED poll=POLLIN status=0\n',i32(ordinary),i32(namespace),kind,child.pid); C.fflush(nil)
 }
}
fn reap(child Child) {
 unsafe {mut status := i32(-1); if C.waitpid(child.pid,&status,0) != child.pid || status != 0 {fatal(15)}}
}
fn finish(child Child) {
 unsafe {sent := C.write(child.door,c'X',1) == 1; closed := C.close(child.door) == 0; reap(child); if !sent || !closed {fatal(16)}}
}
fn intact(state &State,first_group i32,live_group i32,reaped bool) bool {
 unsafe {
  if C.getpgid(0) != state.self || C.getsid(0) != state.self || C.getpgid(state.children[4].pid) != live_group || C.getsid(state.children[4].pid) != state.self {return false}
  if !reaped {for index in 0 .. 4 {child := state.children[index]; wanted := if index == 0 {first_group} else {child.group}; if C.getpgid(child.pid) != wanted || C.getsid(child.pid) != child.session {return false}}}
  return true
 }
}
fn selected(state &State,group i32) bool {
 unsafe {
  mut info := C.siginfo_t{}; slot := C.__errno_location(); *slot = 0
  actual := C.waitid(C.P_PGID,u32(state.children[0].pid),&info,C.WEXITED|C.WNOWAIT|C.WNOHANG); code := *slot
  if group != state.children[0].pid {return actual == -1 && code == C.ECHILD}
  return actual == 0 && code == 0 && info.si_pid == state.children[0].pid && info.si_code == C.CLD_EXITED && info.si_status == 0
 }
}
fn queries(counts &Counts,state &State,ordinary bool,reaped bool) {
 unsafe {for index in 0 .. 4 {child := state.children[index]; for session in [false,true]! {for form in 0 .. 8 {
  wanted := if reaped {isize(-1)} else {isize(if session {child.session} else {child.group})}; code := if reaped {C.ESRCH} else {0}; actual := query(session,child.pid,i32(form))
  record(counts,5,actual.ret == wanted && actual.code == code && intact(state,state.children[0].pid,state.self,reaped),ordinary,child.pid,i32(session),i32(form),i32(reaped),actual,wanted,code)
 }}}}
}
fn matrix(counts &Counts,state &State,ordinary bool) {
 unsafe {
  queries(counts,state,ordinary,false)
  for index in 0 .. 4 {child := state.children[index]
   for group in [i32(0),state.self,child.pid,state.children[2].pid,i32(0x7fffffff),i32(-1),i32(-2147483648)]! {
    code := if group < 0 {i32(C.EINVAL)} else if detached(i32(index)) {i32(C.EPERM)} else if executed(i32(index)) {i32(C.EACCES)}
     else if group == 0 || group == state.self || group == child.pid {i32(0)} else {i32(C.EPERM)}
    for pform in 0 .. 8 {for gform in 0 .. 8 {
     actual := set(child.pid,group,i32(pform),i32(gform)); wanted := if code == 0 {isize(0)} else {isize(-1)}
     first_group := if code == 0 && group == state.self {state.self} else {state.children[0].pid}
     good := actual.ret == wanted && actual.code == code && intact(state,first_group,state.self,false) && selected(state,first_group)
     record(counts,i32(index),good,ordinary,child.pid,group,i32(pform),i32(gform),actual,wanted,code)
     if actual.ret == 0 && (C.setpgid(state.children[0].pid,0) != 0 || !intact(state,state.children[0].pid,state.self,false) || !selected(state,state.children[0].pid)) {fatal(17)}
    }}
   }
  }
  queries(counts,state,ordinary,false)
 }
}
fn destinations(counts &Counts,state &State,ordinary bool,reaped bool) {
 unsafe {for group in [state.children[0].pid,state.children[2].pid,i32(0x7fffffff),i32(-1)]! {
  code := if group < 0 {i32(C.EINVAL)} else if !reaped && group == state.children[0].pid {i32(0)} else {i32(C.EPERM)}
  for pform in 0 .. 8 {for gform in 0 .. 8 {
   actual := set(state.children[4].pid,group,i32(pform),i32(gform)); wanted := if code == 0 {isize(0)} else {isize(-1)}; live_group := if code == 0 {group} else {state.self}
   record(counts,4,actual.ret == wanted && actual.code == code && intact(state,state.children[0].pid,live_group,reaped),ordinary,state.children[4].pid,group,i32(pform),i32(gform),actual,wanted,code)
   if actual.ret == 0 && (C.setpgid(state.children[4].pid,state.self) != 0 || !intact(state,state.children[0].pid,state.self,reaped)) {fatal(18)}
  }}
 }}
}
fn gone(counts &Counts,state &State,ordinary bool) {
 unsafe {
  queries(counts,state,ordinary,true)
  for index in 0 .. 4 {child := state.children[index]
   for group in [i32(0),state.self,child.pid,state.children[2].pid,i32(0x7fffffff),i32(-1),i32(-2147483648)]! {for pform in 0 .. 8 {for gform in 0 .. 8 {
    actual := set(child.pid,group,i32(pform),i32(gform)); code := if group < 0 {C.EINVAL} else {C.ESRCH}
    record(counts,5,actual.ret == -1 && actual.code == code && intact(state,state.children[0].pid,state.self,true),ordinary,child.pid,group,i32(pform),i32(gform),actual,-1,code)
   }}}
  }
 }
}
fn cycle(state &State,index i32) bool {
 unsafe {
  form := if index % 2 == 0 {i32(3)} else {i32(7)}
  a := set(state.children[0].pid,state.self,form,form); if a.ret != 0 || a.code != 0 || !selected(state,state.self) {return false}
  b := set(state.children[0].pid,0,form,form); if b.ret != 0 || b.code != 0 || !selected(state,state.children[0].pid) {return false}
  joined := set(state.children[4].pid,state.children[0].pid,form,form); if joined.ret != 0 || joined.code != 0 || !intact(state,state.children[0].pid,state.children[0].pid,false) {return false}
  left := set(state.children[4].pid,state.self,form,form); if left.ret != 0 || left.code != 0 {return false}
  for kind in [i32(1),i32(2),i32(3)]! {
   bad := set(state.children[kind].pid,0,form,form); code := if kind == 1 {C.EACCES} else {C.EPERM}; if bad.ret != -1 || bad.code != code {return false}
  }
  negative := set(state.children[0].pid,-1,form,form); if negative.ret != -1 || negative.code != C.EINVAL {return false}
  return intact(state,state.children[0].pid,state.self,false)
 }
}
fn storage(state &State,ordinary bool,namespace bool) bool {
 unsafe {
  observer := C.open(c'/proc/slabinfo',0); if observer < 0 {return false}; defer {C.close(observer)}
  for index in 0 .. 32 {if !cycle(state,i32(index)) {return false}}; C.usleep(13000000)
  before := &Slabs(C.alloca(usize(sizeof(Slabs)))); after := &Slabs(C.alloca(usize(sizeof(Slabs))))
  if !snapshot(observer,before) {return false}
  for index in 0 .. 200 {if !cycle(state,i32(index)) {return false}}; C.usleep(13000000)
  if !snapshot(observer,after) {return false}
  mut good := before.rows == after.rows && before.large == after.large
  for index in 0 .. int(before.rows) {
   if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] {good = false}
   C.printf(c'LINUX GROUPZOMBIE SLAB: ordinary=%d namespace=%d size=%lu live=%lu/%lu cycles=200\n',i32(ordinary),i32(namespace),before.sizes[index],before.live[index],after.live[index])
  }
  C.printf(c'LINUX GROUPZOMBIE STORAGE: ordinary=%d namespace=%d cycles=200 big_pages=%lu/%lu %s\n',i32(ordinary),i32(namespace),before.large,after.large,if good {&char(c'PASS')} else {&char(c'FAIL')}); C.fflush(nil); return good
 }
}
fn qualify(counts &Counts,ordinary bool,namespace bool,reference bool) bool {
 unsafe {
  C.alarm(1400); uid := if ordinary {u32(1000)} else {u32(0)}
  if ordinary && (C.setgroups(0,nil) != 0 || C.setgid(uid) != 0 || C.setuid(uid) != 0) {fatal(19)}
  if C.getuid() != uid || C.geteuid() != uid || C.getgid() != uid || C.getegid() != uid {fatal(20)}
  self := C.getpid(); if self <= 1 || C.setsid() != self {fatal(21)}
  state := &State(C.alloca(usize(sizeof(State)))); *state = State{self:self}
  for kind in 0 .. 5 {state.children[kind] = launch(i32(kind))}
  for kind in 0 .. 4 {zombie(state.children[kind],ordinary,namespace,i32(kind))}
  if !intact(state,state.children[0].pid,self,false) || !selected(state,state.children[0].pid) {fatal(22)}
  for kind in 0 .. 5 {child := state.children[kind]
   C.printf(c'LINUX GROUPZOMBIE TOPOLOGY: ordinary=%d namespace=%d uid=%u self=%d kind=%d pid=%d group=%d session=%d executed=%d zombie=%d\n',i32(ordinary),i32(namespace),uid,self,kind,child.pid,child.group,child.session,i32(executed(i32(kind))),i32(kind < 4))
  }; C.fflush(nil)
  matrix(counts,state,ordinary); destinations(counts,state,ordinary,false)
  mut good := true; for kind in 0 .. 6 {if counts.failures[kind] != 0 {good = false}}
  if good && !reference && !storage(state,ordinary,namespace) {good = false}
  for kind in 0 .. 4 {reap(state.children[kind]); C.printf(c'LINUX GROUPZOMBIE REAP: ordinary=%d namespace=%d kind=%d pid=%d status=0\n',i32(ordinary),i32(namespace),kind,state.children[kind].pid)}
  gone(counts,state,ordinary); destinations(counts,state,ordinary,true); finish(state.children[4])
  for kind in 0 .. 6 {C.printf(c'LINUX GROUPZOMBIE CASES: ordinary=%d namespace=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),i32(namespace),kind,counts.calls[kind],counts.failures[kind]); if counts.failures[kind] != 0 {good = false}}
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
  if argc == 5 && C.strcmp(argv[1],c'--held') == 0 {
   mut info := i32(-1); mut door := i32(-1); mut kind := i32(-1)
   if C.sscanf(argv[2],c'%d',&info) != 1 || C.sscanf(argv[3],c'%d',&door) != 1 || C.sscanf(argv[4],c'%d',&kind) != 1 || info < 0 || door < 0 || (kind != 1 && kind != 3) {fatal(18)}
   return hold(info,door,kind,true)
  }
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
    C.printf(c'LINUX GROUPZOMBIE FINAL: ordinary=%d namespace=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),i32(namespace),kind,counts.calls[kind],counts.failures[kind])
    if counts.failures[kind] != 0 { good = false }
   } }; C.fflush(nil)
  } }
  if !good { C.puts(c'LINUX GROUPZOMBIE FAIL: zombie target/destination semantics, wait selection or reaped identities'); C.fflush(nil); return 1 }
  C.puts(if reference {c'LINUX GROUPZOMBIE REFERENCE: PASS'} else {c'LINUX GROUPZOMBIE: PASS'}); C.fflush(nil); for { C.pause() }
 }; return 0
}
