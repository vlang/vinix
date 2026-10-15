// SPDX-License-Identifier: GPL-2.0-or-later
module waitabifixture

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
struct C.siginfo_t { mut: si_signo i32 si_errno i32 si_code i32 si_pid i32 si_uid u32 si_status i32 }
struct C.pollfd { mut: fd i32 events i16 revents i16 }
struct Counts { mut: calls [6]u64 failures [6]u64 }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows i32 large u64 }
struct Result { ret isize code i32 }
struct Reply { pid i32 parent i32 group i32 session i32 executed i32 }
struct Child { pid i32 door i32 group i32 session i32 }
struct State { self i32 mut: children [2]Child }

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
	C.printf(c'LINUX WAITABI FAIL: setup stage=%d errno=%d\n',stage,unsafe{*C.__errno_location()})
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

fn C.unshare(i32) i32
fn C.poll(&C.pollfd,usize,i32) i32
fn C.wait4(i32,&i32,i32,voidptr) i32
fn C.memset(voidptr,i32,usize) voidptr

fn record(counts &Counts,kind i32,good bool,pid i32,tform i32,iform i32,oform i32,actual Result,code i32) {
 unsafe {
  counts.calls[kind]++
  if !good {counts.failures[kind]++; if counts.failures[kind] <= 6 {C.printf(c'LINUX WAITABI DETAIL: kind=%d pid=%d tform=%d iform=%d oform=%d actual=%ld/%d expected_errno=%d\n',kind,pid,tform,iform,oform,actual.ret,actual.code,code); C.fflush(nil)}}
 }
}
fn wait_four(pid i32,options i32,pform i32,oform i32,status voidptr,usage voidptr) Result {
 unsafe {
  slot := C.__errno_location(); *slot = 0
  ret := if pform == 7 && oform == 7 {isize(C.wait4(pid,&i32(status),options,usage))} else {C.syscall(isize(C.SYS_wait4),word(pid,pform),status,word(options,oform),usage)}
  return Result{ret,*slot}
 }
}
fn wait_id(which i32,pid i32,options i32,tform i32,iform i32,oform i32,info voidptr,usage voidptr) Result {
 unsafe {
  slot := C.__errno_location(); *slot = 0
  ret := if tform == 7 && iform == 7 && oform == 7 && usage == nil {isize(C.waitid(which,u32(pid),&C.siginfo_t(info),options))}
   else {C.syscall(isize(C.SYS_waitid),word(which,tform),word(pid,iform),info,word(options,oform),usage)}
  return Result{ret,*slot}
 }
}
fn untouched(data voidptr,size usize) bool {
 unsafe {for index in 0 .. int(size) {if (&u8(data))[index] != 0xa5 {return false}}; return true}
}
fn launch(kind i32) Child {
 unsafe {
  mut info := [i32(-1),i32(-1)]!; mut door := [i32(-1),i32(-1)]!
  if C.pipe2(&info[0],0) != 0 || C.pipe2(&door[0],0) != 0 {fatal(1)}
  pid := C.fork(); if pid < 0 {fatal(2)}
  if pid == 0 {
   C.close(info[0]); C.close(door[1]); if kind == 0 && C.setpgid(0,0) != 0 {fatal(3)}
   mut reply := Reply{C.getpid(),C.getppid(),C.getpgid(0),C.getsid(0),0}
   if C.write(info[1],&reply,sizeof(Reply)) != isize(sizeof(Reply)) || C.close(info[1]) != 0 {fatal(4)}
   mut token := u8(0); good := C.read(door[0],&token,1) == 1 && token == `X` && C.close(door[0]) == 0; C._exit(if good {37+kind} else {1})
  }
  C.close(info[1]); C.close(door[0]); mut reply := Reply{}
  if C.read(info[0],&reply,sizeof(Reply)) != isize(sizeof(Reply)) || C.close(info[0]) != 0 {fatal(5)}
  group := if kind == 0 {pid} else {C.getpid()}
  if reply.pid != pid || reply.parent != C.getpid() || reply.group != group || reply.session != C.getsid(0) {fatal(6)}
  return Child{pid,door[1],group,reply.session}
 }
}
fn release(child Child) {unsafe {sent := C.write(child.door,c'X',1) == 1; closed := C.close(child.door) == 0; if !sent || !closed {fatal(7)}}}
fn reap(child Child,kind i32) {unsafe {mut status := i32(-1); if C.waitpid(child.pid,&status,0) != child.pid || status != (37+kind)<<8 {fatal(8)}}}
fn visible(state &State) bool {
 unsafe {return C.getpgid(state.children[0].pid) == state.children[0].pid && C.getpgid(state.children[1].pid) == state.self && C.getsid(state.children[0].pid) == state.self && C.getsid(state.children[1].pid) == state.self}
}
fn ready(state &State) bool {
 unsafe {mut info := C.siginfo_t{}; return C.waitid(C.P_PID,u32(state.children[0].pid),&info,C.WEXITED|C.WNOWAIT|C.WNOHANG) == 0 && info.si_pid == state.children[0].pid && info.si_status == 37 && info.si_code == C.CLD_EXITED}
}
fn four_matrix(counts &Counts,state &State,invalid bool) {
 unsafe {
  selectors := [i32(0),i32(-1),-state.self,-state.children[0].pid,state.children[0].pid,state.children[1].pid,i32(0x7fffffff),i32(-2147483647),i32(-2147483648)]!
  for pid in selectors {for pform in 0 .. 8 {for oform in 0 .. 8 {for variant in 0 .. if invalid {1} else {2} {
   options := if invalid {i32(C.WNOHANG|0x10)} else if variant == 0 {i32(C.WNOHANG)} else {i32(C.WNOHANG|C.WUNTRACED|C.WCONTINUED)}
   code := if invalid {i32(C.EINVAL)} else if pid == -2147483648 {i32(C.ESRCH)} else if pid == 2147483647 || pid == -2147483647 {i32(C.ECHILD)} else {i32(0)}
   mut status := i32(0xa5a5a5a5); mut usage := [144]u8{}; C.memset(&usage[0],0xa5,144)
   actual := wait_four(pid,options,i32(pform),i32(oform),&status,&usage[0])
   good := actual.ret == if code == 0 {isize(0)} else {isize(-1)} && actual.code == code && status == i32(0xa5a5a5a5) && untouched(&usage[0],144) && visible(state)
   record(counts,if invalid {1} else {0},good,pid,0,i32(pform),i32(oform),actual,code)
  }}}}
 }
}
fn id_case(state &State,index i32) (i32,i32) {
 unsafe {
  if index < 4 {return i32(C.P_ALL),[i32(0),state.children[0].pid,i32(-1),i32(-2147483648)]![index]}
  if index < 10 {return i32(C.P_PID),[i32(0),state.children[0].pid,state.children[1].pid,i32(2147483647),i32(-1),i32(-2147483648)]![index-4]}
  if index < 16 {return i32(C.P_PGID),[i32(0),state.self,state.children[0].pid,i32(2147483647),i32(-1),i32(-2147483648)]![index-10]}
  return i32(-1),state.children[0].pid
 }
}
fn id_matrix(counts &Counts,state &State,zombie bool,invalid bool) {
 unsafe {
  for index in 0 .. 17 {
   which,pid := id_case(state,i32(index)); kind := if invalid {3} else if zombie {4} else {2}
   code := if invalid || which < 0 || (which == C.P_PID && pid <= 0) || (which == C.P_PGID && pid < 0) {i32(C.EINVAL)}
    else if which != C.P_ALL && pid == 2147483647 {i32(C.ECHILD)} else {i32(0)}
   selected := zombie && code == 0 && (which == C.P_ALL || (which == C.P_PID && pid == state.children[0].pid) || (which == C.P_PGID && pid == state.children[0].pid))
   for tform in 0 .. 8 {for iform in 0 .. 8 {for oform in 0 .. 8 {
    mut info := C.siginfo_t{}; C.memset(&info,0xa5,sizeof(C.siginfo_t)); mut usage := [144]u8{}; C.memset(&usage[0],0xa5,144)
    options := i32(C.WEXITED|C.WNOWAIT|C.WNOHANG|if invalid {0x10} else {0})
    // The genuine musl waitid path has four arguments; raw controls also check
    // the fifth Linux rusage argument, whose bytes stay untouched without an event.
    usage_ptr := if tform == 7 && iform == 7 && oform == 7 {voidptr(nil)} else {voidptr(&usage[0])}
    actual := wait_id(which,pid,options,i32(tform),i32(iform),i32(oform),&info,usage_ptr)
    mut output := if code != 0 {untouched(&info,sizeof(C.siginfo_t))} else if selected {
     info.si_signo == C.SIGCHLD && info.si_errno == 0 && info.si_code == C.CLD_EXITED && info.si_pid == state.children[0].pid && info.si_status == 37
    } else {info.si_signo == 0 && info.si_errno == 0 && info.si_code == 0 && info.si_pid == 0 && info.si_uid == 0 && info.si_status == 0}
    if !selected && !untouched(&usage[0],144) {output = false}
    record(counts,kind,actual.ret == if code == 0 {isize(0)} else {isize(-1)} && actual.code == code && output && visible(state),pid,i32(tform),i32(iform),i32(oform),actual,code)
   }}}
  }
 }
}
fn faults(counts &Counts,state &State) {
 unsafe {
  bad := voidptr(usize(0xffffffffffffffff))
  for pform in 0 .. 8 {for oform in 0 .. 8 {for target in 0 .. 2 {
   mut status := i32(-1)
   actual := wait_four(state.children[0].pid,C.WNOHANG,i32(pform),i32(oform),if target == 0 {bad} else {voidptr(&status)},if target == 1 {bad} else {voidptr(nil)})
   good := actual.ret == -1 && actual.code == C.EFAULT && ready(state) && (target == 0 || status == 37<<8)
   record(counts,5,good,state.children[0].pid,i32(target),i32(pform),i32(oform),actual,C.EFAULT)
  }}}
  for tform in 0 .. 8 {for iform in 0 .. 8 {for oform in 0 .. 8 {for target in 0 .. 2 {
   mut info := C.siginfo_t{}
   actual := wait_id(C.P_PID,state.children[0].pid,C.WEXITED|C.WNOWAIT|C.WNOHANG,i32(tform),i32(iform),i32(oform),if target == 0 {bad} else {voidptr(&info)},if target == 1 {bad} else {voidptr(nil)})
   record(counts,5,actual.ret == -1 && actual.code == C.EFAULT && ready(state),state.children[0].pid,i32(tform),i32(iform),i32(oform),actual,C.EFAULT)
  }}}}
 }
}
fn gone(counts &Counts,state &State) {
 unsafe {
  for pform in 0 .. 8 {for oform in 0 .. 8 {
   actual := wait_four(state.children[0].pid,C.WNOHANG,i32(pform),i32(oform),nil,nil)
   record(counts,5,actual.ret == -1 && actual.code == C.ECHILD,state.children[0].pid,0,i32(pform),i32(oform),actual,C.ECHILD)
  }}
  for tform in 0 .. 8 {for iform in 0 .. 8 {for oform in 0 .. 8 {
   mut info := C.siginfo_t{}; C.memset(&info,0xa5,sizeof(C.siginfo_t))
   actual := wait_id(C.P_PID,state.children[0].pid,C.WEXITED|C.WNOHANG,i32(tform),i32(iform),i32(oform),&info,nil)
   record(counts,5,actual.ret == -1 && actual.code == C.ECHILD && untouched(&info,sizeof(C.siginfo_t)),state.children[0].pid,i32(tform),i32(iform),i32(oform),actual,C.ECHILD)
  }}}
 }
}
fn cycle(state &State,index i32) bool {
 unsafe {
  form := if index % 2 == 0 {i32(3)} else {i32(7)}
  mut status := i32(-1); a := wait_four(state.children[1].pid,C.WNOHANG,form,form,&status,nil)
  mut info := C.siginfo_t{}; b := wait_id(C.P_PGID,state.children[0].pid,C.WEXITED|C.WNOWAIT|C.WNOHANG,form,form,form,&info,nil)
  c := wait_four(-2147483648,C.WNOHANG,form,form,nil,nil)
  return a.ret == 0 && a.code == 0 && status == -1 && b.ret == 0 && b.code == 0 && info.si_pid == state.children[0].pid && info.si_status == 37 && c.ret == -1 && c.code == C.ESRCH && ready(state) && visible(state)
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
   C.printf(c'LINUX WAITABI SLAB: ordinary=%d namespace=%d size=%lu live=%lu/%lu cycles=200\n',i32(ordinary),i32(namespace),before.sizes[index],before.live[index],after.live[index])
  }
  C.printf(c'LINUX WAITABI STORAGE: ordinary=%d namespace=%d cycles=200 big_pages=%lu/%lu %s\n',i32(ordinary),i32(namespace),before.large,after.large,if good {&char(c'PASS')} else {&char(c'FAIL')}); C.fflush(nil); return good
 }
}
fn qualify(counts &Counts,ordinary bool,namespace bool,reference bool) bool {
 unsafe {
  C.alarm(1400); uid := if ordinary {u32(1000)} else {u32(0)}
  if ordinary && (C.setgroups(0,nil) != 0 || C.setgid(uid) != 0 || C.setuid(uid) != 0) {fatal(9)}
  if C.getuid() != uid || C.geteuid() != uid || C.getgid() != uid || C.getegid() != uid {fatal(10)}
  self := C.getpid(); if self <= 1 || C.setsid() != self {fatal(11)}
  state := &State(C.alloca(usize(sizeof(State)))); *state = State{self:self}
  for kind in 0 .. 2 {state.children[kind] = launch(i32(kind)); child := state.children[kind]
   C.printf(c'LINUX WAITABI TOPOLOGY: ordinary=%d namespace=%d uid=%u self=%d kind=%d pid=%d group=%d session=%d\n',i32(ordinary),i32(namespace),uid,self,kind,child.pid,child.group,child.session)
  }; C.fflush(nil)
  four_matrix(counts,state,false); four_matrix(counts,state,true); id_matrix(counts,state,false,false); id_matrix(counts,state,false,true)
  release(state.children[0]); mut info := C.siginfo_t{}
  if C.waitid(C.P_PID,u32(state.children[0].pid),&info,C.WEXITED|C.WNOWAIT) != 0 || !ready(state) {fatal(12)}
  C.printf(c'LINUX WAITABI EXIT: ordinary=%d namespace=%d pid=%d wait=CLD_EXITED status=37\n',i32(ordinary),i32(namespace),state.children[0].pid); C.fflush(nil)
  id_matrix(counts,state,true,false); faults(counts,state)
  mut good := true; for kind in 0 .. 6 {if counts.failures[kind] != 0 {good = false}}
  if good && !reference && !storage(state,ordinary,namespace) {good = false}
  reap(state.children[0],0); C.printf(c'LINUX WAITABI REAP: ordinary=%d namespace=%d pid=%d status=37\n',i32(ordinary),i32(namespace),state.children[0].pid)
  gone(counts,state); release(state.children[1]); reap(state.children[1],1)
  for kind in 0 .. 6 {C.printf(c'LINUX WAITABI CASES: ordinary=%d namespace=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),i32(namespace),kind,counts.calls[kind],counts.failures[kind]); if counts.failures[kind] != 0 {good = false}}
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
    C.printf(c'LINUX WAITABI FINAL: ordinary=%d namespace=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),i32(namespace),kind,counts.calls[kind],counts.failures[kind])
    if counts.failures[kind] != 0 { good = false }
   } }; C.fflush(nil)
  } }
  if !good { C.puts(c'LINUX WAITABI FAIL: wait argument imports, selection, errors, copyout or retained zombies'); C.fflush(nil); return 1 }
  C.puts(if reference {c'LINUX WAITABI REFERENCE: PASS'} else {c'LINUX WAITABI: PASS'}); C.fflush(nil); for { C.pause() }
 }; return 0
}
