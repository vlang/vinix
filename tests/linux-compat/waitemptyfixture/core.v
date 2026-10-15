// SPDX-License-Identifier: GPL-2.0-or-later
module waitemptyfixture

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
struct State { self i32 child Child page u64 base u64 readonly u64 inaccessible u64 }

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
	C.printf(c'LINUX WAITEMPTY FAIL: setup stage=%d errno=%d\n',stage,unsafe{*C.__errno_location()})
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
fn C.memset(voidptr,i32,usize) voidptr
fn wait_id(which i32,pid i32,options i32,tform i32,iform i32,oform i32,info voidptr,usage voidptr) Result {
 unsafe {
  slot := C.__errno_location(); *slot = 0
  ret := if tform == 7 && iform == 7 && oform == 7 && usage == nil {isize(C.waitid(which,u32(pid),&C.siginfo_t(info),options))}
   else {C.syscall(isize(C.SYS_waitid),word(which,tform),word(pid,iform),info,word(options,oform),usage)}
  return Result{ret,*slot}
 }
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
#include <sys/mman.h>
fn C.mmap(voidptr,usize,i32,i32,i32,i64) voidptr
fn C.mprotect(voidptr,usize,i32) i32
fn C.munmap(voidptr,usize) i32
fn C.sysconf(i32) isize

struct Query { which i32 pid i32 options i32 code i32 }
fn query(state &State,index i32) Query {
 unsafe {
  options := i32(C.WEXITED|C.WNOWAIT|C.WNOHANG)
  if index == 0 {return Query{i32(C.P_ALL),-1,options,0}}
  if index == 1 {return Query{i32(C.P_PID),state.child.pid,options,0}}
  if index == 2 {return Query{i32(C.P_PGID),state.child.pid,options,0}}
  if index == 3 {return Query{i32(C.P_PGID),0,options,i32(C.ECHILD)}}
  if index == 4 {return Query{i32(C.P_PID),2147483647,options,i32(C.ECHILD)}}
  if index == 5 {return Query{i32(C.P_PID),0,options,i32(C.EINVAL)}}
  if index == 6 {return Query{i32(C.P_PID),-1,options,i32(C.EINVAL)}}
  if index == 7 {return Query{i32(C.P_PGID),-1,options,i32(C.EINVAL)}}
  if index == 8 {return Query{-1,state.child.pid,options,i32(C.EINVAL)}}
  if index == 9 {return Query{i32(C.P_PID),state.child.pid,i32(C.WNOHANG),i32(C.EINVAL)}}
  if index == 10 {return Query{i32(C.P_PID),state.child.pid,options|0x10,i32(C.EINVAL)}}
  return Query{-1,-1,0,i32(C.EINVAL)}
 }
}
fn invoke(q Query,form i32,info voidptr,usage voidptr) Result {return wait_id(q.which,q.pid,q.options,form,form,form,info,usage)}
fn record(counts &Counts,kind i32,good bool,index i32,form i32,position i32,usage i32,actual Result,code i32,bad i32) {
 unsafe {
  counts.calls[kind]++
  if !good {counts.failures[kind]++; if counts.failures[kind] <= 6 {
   C.printf(c'LINUX WAITEMPTY DETAIL: kind=%d query=%d form=%d position=%d usage=%d actual=%ld/%d expected_errno=%d bad_byte=%d\n',kind,index,form,position,usage,actual.ret,actual.code,code,bad); C.fflush(nil)
  }}
 }
}
fn intact(state &State) bool {unsafe {return C.getpgid(state.child.pid) == state.child.pid && C.getsid(state.child.pid) == state.self}}
fn usage_pointer(data voidptr,kind i32) voidptr {return if kind == 0 {unsafe{nil}} else if kind == 1 {data} else {voidptr(usize(0xffffffffffffffff))}}
fn unchanged(data voidptr,length int) bool {unsafe {for i in 0 .. length {if (&u8(data))[i] != 0xa5 {return false}}; return true}}
// Linux's six 32-bit stores touch offsets 0/4/8/16/20/24; a faulting split
// field has no committed prefix in these stable guard-page controls.
fn empty_difference(data voidptr,total int,start int,available int) i32 {
 unsafe {
  for i in 0 .. total {
   local := i-start; mut zero := false
   if local >= 0 && local < available {
    if local < 12 {zero = (local/4)*4+4 <= available}
    else if local >= 16 && local < 28 {zero = (local/4)*4+4 <= available}
   }
   wanted := if zero {u8(0)} else {u8(0xa5)}
   if (&u8(data))[i] != wanted {return i32(i)}
  }; return -1
 }
}
fn mapped(counts &Counts,state &State) {
 unsafe {
  for index in 0 .. 12 {q := query(state,i32(index)); kind := if q.code == 0 {i32(1)} else {i32(0)}
   for offset in [0,1,3,7]! {for form in 0 .. 8 {for use in 0 .. 3 {
    mut data := [160]u8{}; mut usage := [144]u8{}; C.memset(&data[0],0xa5,160); C.memset(&usage[0],0xa5,144)
    start := 16+offset
    actual := invoke(q,i32(form),&data[start],usage_pointer(&usage[0],i32(use)))
    bad := empty_difference(&data[0],160,start,128)
    good := actual.ret == if q.code == 0 {isize(0)} else {isize(-1)} && actual.code == q.code && bad == -1 && unchanged(&usage[0],144) && intact(state)
    record(counts,kind,good,i32(index),i32(form),i32(offset),i32(use),actual,q.code,bad)
   }}}
  }
 }
}
fn invalid(counts &Counts,state &State) {
 unsafe {
  for index in 0 .. 12 {q := query(state,i32(index)); for pointer in 0 .. 4 {for form in 0 .. 8 {for use in 0 .. 3 {
   address := if pointer == 0 {~u64(0)} else if pointer == 1 {u64(1)} else if pointer == 2 {state.readonly} else {state.inaccessible}
   mut usage := [144]u8{}; C.memset(&usage[0],0xa5,144)
   actual := invoke(q,i32(form),voidptr(address),usage_pointer(&usage[0],i32(use)))
   good := actual.ret == -1 && actual.code == C.EFAULT && unchanged(&usage[0],144) && unchanged(voidptr(state.readonly),128) && intact(state)
   record(counts,2,good,i32(index),i32(form),i32(pointer),i32(use),actual,C.EFAULT,-1)
  }}}}
 }
}
fn cut_value(index int) int {return if index < 33 {index} else if index == 33 {64} else if index == 34 {127} else {128}}
fn guard_call(state &State,q Query,form i32,cut int,use i32) (Result,i32) {
 unsafe {
  boundary := state.base+state.page; start := boundary-u64(cut); beginning := voidptr(start-16)
  C.memset(beginning,0xa5,usize(16+cut))
  actual := invoke(q,form,voidptr(start),if use == 0 {nil} else {voidptr(usize(0xffffffffffffffff))})
  return actual,empty_difference(beginning,16+cut,16,cut)
 }
}
fn guards(counts &Counts,state &State) {
 unsafe {
  for index in 0 .. 12 {q := query(state,i32(index)); for point in 0 .. 36 {cut := cut_value(point); code := if cut < 28 {i32(C.EFAULT)} else {q.code}
   for form in 0 .. 8 {for use in [i32(0),i32(2)]! {
    actual,bad := guard_call(state,q,i32(form),cut,use)
    good := actual.ret == if code == 0 {isize(0)} else {isize(-1)} && actual.code == code && bad == -1 && intact(state)
    record(counts,3,good,i32(index),i32(form),i32(cut),use,actual,code,bad)
   }}
  }}
 }
}
fn null_info(counts &Counts,state &State) {
 unsafe {for index in 0 .. 12 {q := query(state,i32(index)); for form in 0 .. 8 {for use in 0 .. 3 {
  mut usage := [144]u8{}; C.memset(&usage[0],0xa5,144)
  actual := invoke(q,i32(form),nil,usage_pointer(&usage[0],i32(use)))
  good := actual.ret == if q.code == 0 {isize(0)} else {isize(-1)} && actual.code == q.code && unchanged(&usage[0],144) && intact(state)
  record(counts,4,good,i32(index),i32(form),0,i32(use),actual,q.code,-1)
 }}}}
}
fn events(counts &Counts,state &State,reaped bool) {
 unsafe {for index in 0 .. 3 {q := query(state,i32(index)); for form in 0 .. 8 {for use in 0 .. 2 {
  mut data := [160]u8{}; mut usage := [144]u8{}; C.memset(&data[0],0xa5,160); C.memset(&usage[0],0xa5,144)
  actual := invoke(q,i32(form),&data[16],usage_pointer(&usage[0],i32(use)))
  info := &C.siginfo_t(&data[16]); code := if reaped {i32(C.ECHILD)} else {i32(0)}
  bad := if reaped {empty_difference(&data[0],160,16,128)} else {i32(-1)}
  contents := if reaped {bad == -1 && unchanged(&usage[0],144)} else {info.si_signo == C.SIGCHLD && info.si_errno == 0 && info.si_code == C.CLD_EXITED && info.si_pid == state.child.pid && info.si_status == 37}
  good := actual.ret == if code == 0 {isize(0)} else {isize(-1)} && actual.code == code && contents
  record(counts,5,good,i32(index),i32(form),i32(reaped),i32(use),actual,code,bad)
 }}}}
}
fn cycle(state &State,index i32) bool {
 unsafe {
  form := if index % 2 == 0 {i32(3)} else {i32(7)}
  for selector in 0 .. 12 {
   q := query(state,i32(selector)); mut data := [160]u8{}; C.memset(&data[0],0xa5,160)
   actual := invoke(q,form,&data[17],nil)
   if actual.ret != if q.code == 0 {isize(0)} else {isize(-1)} || actual.code != q.code || empty_difference(&data[0],160,17,128) != -1 {return false}
  }
  q := query(state,5); guard,bad := guard_call(state,q,form,28,2)
  refused := invoke(q,form,voidptr(state.readonly),nil)
  return guard.ret == -1 && guard.code == C.EINVAL && bad == -1 && refused.ret == -1 && refused.code == C.EFAULT && intact(state)
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
   C.printf(c'LINUX WAITEMPTY SLAB: ordinary=%d namespace=%d size=%lu live=%lu/%lu cycles=200\n',i32(ordinary),i32(namespace),before.sizes[index],before.live[index],after.live[index])
  }
  C.printf(c'LINUX WAITEMPTY STORAGE: ordinary=%d namespace=%d cycles=200 big_pages=%lu/%lu %s\n',i32(ordinary),i32(namespace),before.large,after.large,if good {&char(c'PASS')} else {&char(c'FAIL')}); C.fflush(nil); return good
 }
}
fn qualify(counts &Counts,ordinary bool,namespace bool,reference bool) bool {
 unsafe {
  C.alarm(1400); uid := if ordinary {u32(1000)} else {u32(0)}
  if ordinary && (C.setgroups(0,nil) != 0 || C.setgid(uid) != 0 || C.setuid(uid) != 0) {fatal(9)}
  if C.getuid() != uid || C.geteuid() != uid || C.getgid() != uid || C.getegid() != uid {fatal(10)}
  self := C.getpid(); if self <= 1 || C.setsid() != self {fatal(11)}
  page := u64(C.sysconf(C._SC_PAGESIZE)); if page != 4096 && page != 16384 {fatal(12)}
  flags := i32(C.MAP_PRIVATE|C.MAP_ANONYMOUS)
  base := C.mmap(nil,usize(2*page),C.PROT_READ|C.PROT_WRITE,flags,-1,0)
  readonly := C.mmap(nil,usize(page),C.PROT_READ|C.PROT_WRITE,flags,-1,0)
  inaccessible := C.mmap(nil,usize(page),C.PROT_NONE,flags,-1,0)
  if u64(base) == ~u64(0) || u64(readonly) == ~u64(0) || u64(inaccessible) == ~u64(0) {fatal(13)}
  C.memset(readonly,0xa5,usize(page))
  if C.mprotect(voidptr(u64(base)+page),usize(page),C.PROT_NONE) != 0 || C.mprotect(readonly,usize(page),C.PROT_READ) != 0 {fatal(14)}
  state := &State(C.alloca(usize(sizeof(State)))); *state = State{self,launch(0),page,u64(base),u64(readonly),u64(inaccessible)}
  if !intact(state) {fatal(15)}
  C.printf(c'LINUX WAITEMPTY TOPOLOGY: ordinary=%d namespace=%d uid=%u self=%d pid=%d group=%d session=%d page=%lu\n',i32(ordinary),i32(namespace),uid,self,state.child.pid,state.child.pid,self,page); C.fflush(nil)
  mapped(counts,state); invalid(counts,state); guards(counts,state); null_info(counts,state)
  mut good := true; for kind in 0 .. 6 {if counts.failures[kind] != 0 {good = false}}
  if good && !reference && !storage(state,ordinary,namespace) {good = false}
  release(state.child); mut info := C.siginfo_t{}
  if C.waitid(C.P_PID,u32(state.child.pid),&info,C.WEXITED|C.WNOWAIT) != 0 || info.si_pid != state.child.pid || info.si_status != 37 || info.si_code != C.CLD_EXITED {fatal(16)}
  C.printf(c'LINUX WAITEMPTY EXIT: ordinary=%d namespace=%d pid=%d wait=CLD_EXITED status=37\n',i32(ordinary),i32(namespace),state.child.pid); C.fflush(nil)
  events(counts,state,false); reap(state.child,0)
  C.printf(c'LINUX WAITEMPTY REAP: ordinary=%d namespace=%d pid=%d status=37\n',i32(ordinary),i32(namespace),state.child.pid)
  events(counts,state,true)
  if C.munmap(base,usize(2*page)) != 0 || C.munmap(readonly,usize(page)) != 0 || C.munmap(inaccessible,usize(page)) != 0 {fatal(17)}
  for kind in 0 .. 6 {C.printf(c'LINUX WAITEMPTY CASES: ordinary=%d namespace=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),i32(namespace),kind,counts.calls[kind],counts.failures[kind]); if counts.failures[kind] != 0 {good = false}}
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
    C.printf(c'LINUX WAITEMPTY FINAL: ordinary=%d namespace=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),i32(namespace),kind,counts.calls[kind],counts.failures[kind])
    if counts.failures[kind] != 0 { good = false }
   } }; C.fflush(nil)
  } }
  if !good { C.puts(c'LINUX WAITEMPTY FAIL: waitid empty/error fields, padding, pointer faults or event controls'); C.fflush(nil); return 1 }
  C.puts(if reference {c'LINUX WAITEMPTY REFERENCE: PASS'} else {c'LINUX WAITEMPTY: PASS'}); C.fflush(nil); for { C.pause() }
 }; return 0
}
