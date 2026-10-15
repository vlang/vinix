// SPDX-License-Identifier: GPL-2.0-or-later
module robustwakefixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <poll.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

@[typedef]
struct C.pthread_t {}
@[typedef]
struct C.pthread_mutex_t {}
@[typedef]
struct C.pthread_mutexattr_t {}
@[typedef]
struct C.sigset_t {}
struct C.pollfd { mut: fd i32 events i16 revents i16 }
struct Counts { mut: calls [6]u64 failures [6]u64 }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows i32 large u64 }
struct State { self i32 page u64 shared u64 }
struct Spec { class i32 flags i32 layout i32 negative bool pi bool owner i32 }
struct Reply { mut: pid i32 tid i32 parent i32 uid u32 head u64 length u64 }
struct Wait { park u64 private bool mut: result isize code i32 }
struct MutexTask { mut: mutex C.pthread_mutex_t result i32 payload u64 }

fn C.alloca(usize) voidptr
fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.pthread_create(&C.pthread_t,voidptr,fn(voidptr) voidptr,voidptr) i32
fn C.pthread_join(C.pthread_t,voidptr) i32
fn C.pthread_mutexattr_init(&C.pthread_mutexattr_t) i32
fn C.pthread_mutexattr_setrobust(&C.pthread_mutexattr_t,i32) i32
fn C.pthread_mutexattr_destroy(&C.pthread_mutexattr_t) i32
fn C.pthread_mutex_init(&C.pthread_mutex_t,&C.pthread_mutexattr_t) i32
fn C.pthread_mutex_lock(&C.pthread_mutex_t) i32
fn C.pthread_mutex_consistent(&C.pthread_mutex_t) i32
fn C.pthread_mutex_unlock(&C.pthread_mutex_t) i32
fn C.pthread_mutex_destroy(&C.pthread_mutex_t) i32
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
fn C.poll(&C.pollfd,usize,i32) i32
fn C._exit(i32)

fn fatal(stage i32) {
 C.printf(c'LINUX ROBUSTWAKE FAIL: setup stage=%d errno=%d\n',stage,unsafe{*C.__errno_location()}); C.fflush(unsafe{nil}); C._exit(90)
}
fn spec(index i32) Spec {
 if index < 16 {return Spec{class:0,flags:index%4,layout:1+(index/4)%2,negative:index/8 != 0}}
 if index < 40 {n := index-16; return Spec{class:1,flags:n%4,layout:(n/4)%3,negative:n/12 != 0,owner:1}}
 if index < 88 {n := index-40; return Spec{class:2,flags:n%4,layout:(n/4)%3,negative:(n/12)%2 != 0,pi:true,owner:n/24}}
 if index < 112 {n := index-88; return Spec{class:3,flags:n%4,layout:(n/4)%3,negative:n/12 != 0,owner:2}}
 n := index-112; return Spec{class:4,flags:n%4,negative:n/4 != 0}
}
fn flags(choice i32) u32 {return [u32(0),0x40000000,0x80000000,0xc0000000]![choice]}
fn futex(address u64,operation i32,count i32,move i32,other u64) isize {
 return C.syscall(C.SYS_futex,voidptr(address),isize(operation),isize(count),isize(move),voidptr(other),isize(0))
}
fn waiter(argument voidptr) voidptr {
 unsafe {
  mut request := &Wait(argument); mut code := C.__errno_location(); *code = 0
  request.result = C.syscall(C.SYS_futex,voidptr(request.park),isize(if request.private {128} else {0}),isize(0),voidptr(nil),isize(0),isize(0))
  request.code = *code; return nil
 }
}
// Positive CMP_REQUEUE return counts prove that these exact waiters are already
// queued. No sleep or ready flag is accepted as proof of queue admission.
fn queue(park u64,target u64,count i32,private bool) {
 mut moved := i32(0)
 for _ in 0 .. 20000 {
  n := futex(park,if private {132} else {4},0,count-moved,target)
  if n < 0 || n > count-moved {fatal(1)}
  moved += i32(n); if moved == count {return}; C.usleep(1000)
 }
 fatal(2)
}
fn record(counts &Counts,class i32,good bool,ordinary bool,namespace bool,index i32,actual isize,expected isize,changed bool) {
 if counts == unsafe{nil} {return}
 unsafe {
  mut output := &Counts(counts); output.calls[class]++
  if !good {
   output.failures[class]++
   if output.failures[class] <= 3 {C.printf(c'LINUX ROBUSTWAKE DETAIL: ordinary=%d namespace=%d kind=%d index=%d remaining=%ld expected=%ld changed=%d\n',i32(ordinary),i32(namespace),class,index,actual,expected,i32(changed))}
  }
 }
}
fn trial(counts &Counts,state &State,ordinary bool,namespace bool,index i32,measure bool,announce bool) bool {
 unsafe {
  selection := spec(index); word_offset := if selection.negative {120} else {136}
  address := state.shared+u64(word_offset); head := state.shared; entry := state.shared+128
  C.memset(voidptr(state.shared),0xa5,256)
  (&u64(head))[0] = if selection.layout == 1 {head} else {entry|u64(selection.pi)}
  (&i64(head))[1] = if selection.negative {i64(-8)} else {i64(8)}
  (&u64(head))[2] = if selection.layout == 0 {u64(0)} else {entry|u64(selection.pi)}
  *(&u64(entry)) = head
  for offset in [u64(32),36,40,64]! {*(&u32(state.shared+offset)) = 0}
  mut ready := [i32(-1),i32(-1)]!; mut door := [i32(-1),i32(-1)]!
  if C.pipe2(&ready[0],0) != 0 || C.pipe2(&door[0],0) != 0 {fatal(3)}
  child := C.fork(); if child < 0 {fatal(4)}
  if child == 0 {
   C.close(ready[0]); C.close(door[1])
   tid := i32(C.syscall(C.SYS_gettid)); owner := if selection.owner == 1 {u32(tid)} else if selection.owner == 2 {u32(C.getppid())} else {u32(0)}
   *(&u32(address)) = owner|flags(selection.flags)
   if C.syscall(C.SYS_set_robust_list,voidptr(head),u64(24)) != 0 {fatal(5)}
   reply := &Reply(C.alloca(usize(sizeof(Reply)))); *reply = Reply{pid:C.getpid(),tid:tid,parent:C.getppid(),uid:C.getuid()}
   if C.syscall(C.SYS_get_robust_list,isize(0),&reply.head,&reply.length) != 0 {fatal(6)}
   if C.write(ready[1],reply,sizeof(Reply)) != isize(sizeof(Reply)) {fatal(7)}
   mut release := u8(0); if C.read(door[0],&release,1) != 1 || release != `X` {fatal(8)}
   C._exit(37)
  }
  C.close(ready[1]); C.close(door[0]); reply := &Reply(C.alloca(usize(sizeof(Reply)))); *reply = Reply{}
  if C.read(ready[0],reply,sizeof(Reply)) != isize(sizeof(Reply)) || C.close(ready[0]) != 0 {fatal(9)}
  if reply.pid != child || reply.tid != child || reply.parent != state.self || reply.uid != if ordinary {u32(1000)} else {u32(0)} || reply.head != head || reply.length != 24 {fatal(10)}
  pidfd := i32(C.syscall(C.SYS_pidfd_open,isize(child),isize(0))); if pidfd < 0 {fatal(11)}
  mut expected := [256]u8{}; C.memcpy(&expected[0],voidptr(state.shared),256)
  initial := *(&u32(address)); wanted := if selection.owner == 1 {(flags(selection.flags)&0x80000000)|u32(0x40000000)} else {initial}
  C.memcpy(&expected[word_offset],unsafe{&wanted},4)
  sharing := if measure {1} else {3}; total := if measure {1} else {5}
  handles := &C.pthread_t(C.alloca(usize(5*sizeof(C.pthread_t)))); requests := &Wait(C.alloca(usize(5*sizeof(Wait))))
  for number in 0 .. total {
   requests[number] = Wait{park:state.shared+if number < sharing {u64(32)} else if number == sharing {u64(36)} else {u64(40)},private:number == sharing}
   if C.pthread_create(&handles[number],nil,waiter,&requests[number]) != 0 {fatal(12)}
  }
  queue(state.shared+32,address,i32(sharing),false)
  if !measure {queue(state.shared+36,address,1,true); queue(state.shared+40,state.shared+64,1,false)}
  if C.write(door[1],c'X',1) != 1 || C.close(door[1]) != 0 {fatal(13)}
  mut observed := C.pollfd{fd:pidfd,events:i16(C.POLLIN)}
  if C.poll(&observed,1,5000) != 1 || observed.revents&i16(C.POLLIN) == 0 || observed.revents&i16(C.POLLERR|C.POLLNVAL) != 0 {fatal(14)}
  mut status := i32(-1); if C.waitpid(child,&status,0) != child || status != 37<<8 {fatal(15)}
  // Wake removes queued nodes synchronously, so this exact remaining count
  // does not depend on which already-woken thread has reached userspace.
  wake := !selection.pi && ((selection.owner == 0 && selection.layout != 0) || (selection.owner == 1 && flags(selection.flags)&0x80000000 != 0))
  expected_remaining := isize(sharing)-isize(wake)
  remaining := futex(address,1,8,0,0); mut good := remaining == expected_remaining
  if futex(state.shared+32,1,8,0,0) != 0 {fatal(16)}
  if !measure {
   if futex(address,129,8,0,0) != 1 || futex(state.shared+64,1,8,0,0) != 1 || futex(state.shared+36,129,8,0,0) != 0 || futex(state.shared+40,1,8,0,0) != 0 {good = false}
  }
  for number in 0 .. total {if C.pthread_join(handles[number],nil) != 0 || requests[number].result != 0 || requests[number].code != 0 {fatal(17)}}
  if C.close(pidfd) != 0 {fatal(18)}
  changed := C.memcmp(&expected[0],voidptr(state.shared),256) != 0
  good = good && !changed
  if announce {C.printf(c'LINUX ROBUSTWAKE TOPOLOGY: ordinary=%d namespace=%d self=%d child=%d tid=%d uid=%u registered=24 queued=3 private=1 neighbor=1\n',i32(ordinary),i32(namespace),state.self,child,reply.tid,reply.uid)}
  record(counts,selection.class,good,ordinary,namespace,index,remaining,expected_remaining,changed); return good
 }
}
fn mutex_owner(argument voidptr) voidptr {
 unsafe {
  mut task := &MutexTask(argument); task.result = C.pthread_mutex_lock(&task.mutex)
  if task.result == 0 {task.payload++}; return nil
 }
}
fn libc_controls(counts &Counts,ordinary bool,namespace bool) {
 unsafe {
  task := &MutexTask(C.alloca(usize(sizeof(MutexTask)))); C.memset(task,0,usize(sizeof(MutexTask)))
  mut attributes := C.pthread_mutexattr_t{}
  if C.pthread_mutexattr_init(&attributes) != 0 || C.pthread_mutexattr_setrobust(&attributes,C.PTHREAD_MUTEX_ROBUST) != 0 || C.pthread_mutex_init(&task.mutex,&attributes) != 0 || C.pthread_mutexattr_destroy(&attributes) != 0 {fatal(19)}
  for index in 0 .. 32 {
   mut worker := C.pthread_t{}
   if C.pthread_create(&worker,nil,mutex_owner,task) != 0 || C.pthread_join(worker,nil) != 0 || task.result != 0 {fatal(20)}
   locked := C.pthread_mutex_lock(&task.mutex)
   good := locked == C.EOWNERDEAD && task.payload == u64(index+1)
   if locked == C.EOWNERDEAD && C.pthread_mutex_consistent(&task.mutex) != 0 {fatal(21)}
   if locked !in [i32(0),i32(C.EOWNERDEAD)]! || C.pthread_mutex_unlock(&task.mutex) != 0 {fatal(22)}
   record(counts,5,good,ordinary,namespace,i32(index),isize(locked),isize(C.EOWNERDEAD),false)
  }
  if C.pthread_mutex_destroy(&task.mutex) != 0 {fatal(23)}
 }
}
fn storage(state &State,ordinary bool,namespace bool) bool {
 unsafe {
  observer := C.open(c'/proc/slabinfo',0); if observer < 0 {return false}; defer {C.close(observer)}
  for index in 0 .. 32 {if !trial(nil,state,ordinary,namespace,i32(index),true,false) {return false}}; C.usleep(13000000)
  before := &Slabs(C.alloca(usize(sizeof(Slabs)))); after := &Slabs(C.alloca(usize(sizeof(Slabs))))
  if !snapshot(observer,before) {return false}
  for index in 0 .. 200 {if !trial(nil,state,ordinary,namespace,i32(index%120),true,false) {return false}}; C.usleep(13000000)
  if !snapshot(observer,after) {return false}
  mut good := before.rows == after.rows && before.large == after.large
  for index in 0 .. int(before.rows) {
   if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] {good = false}
   C.printf(c'LINUX ROBUSTWAKE SLAB: ordinary=%d namespace=%d size=%lu live=%lu/%lu cycles=200\n',i32(ordinary),i32(namespace),before.sizes[index],before.live[index],after.live[index])
  }
  C.printf(c'LINUX ROBUSTWAKE STORAGE: ordinary=%d namespace=%d cycles=200 big_pages=%lu/%lu %s\n',i32(ordinary),i32(namespace),before.large,after.large,if good {&char(c'PASS')} else {&char(c'FAIL')}); C.fflush(nil); return good
 }
}
fn qualify(counts &Counts,ordinary bool,namespace bool,reference bool) bool {
 unsafe {
  C.alarm(1400)
  if ordinary && (C.setgroups(0,nil) != 0 || C.setgid(1000) != 0 || C.setresuid(1000,1000,1000) != 0) {fatal(24)}
  uid := if ordinary {u32(1000)} else {u32(0)}
  if C.getuid() != uid || C.geteuid() != uid || C.setsid() != C.getpid() {fatal(25)}
  mut blocked := C.sigset_t{}; mut previous := C.sigset_t{}
  if C.sigemptyset(&blocked) != 0 || C.sigaddset(&blocked,C.SIGCHLD) != 0 || C.pthread_sigmask(C.SIG_BLOCK,&blocked,&previous) != 0 {fatal(29)}
  page := u64(C.sysconf(C._SC_PAGESIZE)); if page != 4096 && page != 16384 {fatal(26)}
  shared := C.mmap(nil,usize(page),C.PROT_READ|C.PROT_WRITE,C.MAP_SHARED|C.MAP_ANONYMOUS,-1,0)
  if u64(shared) == ~u64(0) {fatal(27)}
  state := &State(C.alloca(usize(sizeof(State)))); *state = State{self:C.getpid(),page:page,shared:u64(shared)}
  for index in 0 .. 120 {trial(counts,state,ordinary,namespace,i32(index),false,index == 0)}
  libc_controls(counts,ordinary,namespace)
  C.printf(c'LINUX ROBUSTWAKE COHORT: ordinary=%d namespace=%d self=%d uid=%u page=%lu raw=120 libc=32 queued=600 cleaned=600\n',i32(ordinary),i32(namespace),state.self,uid,page)
  mut good := true; for kind in 0 .. 6 {if counts.failures[kind] != 0 {good = false}}
  if good && !reference && !storage(state,ordinary,namespace) {good = false}
  if C.munmap(shared,usize(page)) != 0 {fatal(28)}
  if C.pthread_sigmask(C.SIG_SETMASK,&previous,nil) != 0 {fatal(30)}
  for kind in 0 .. 6 {C.printf(c'LINUX ROBUSTWAKE CASES: ordinary=%d namespace=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),i32(namespace),kind,counts.calls[kind],counts.failures[kind])}
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
    C.printf(c'LINUX ROBUSTWAKE FINAL: ordinary=%d namespace=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),i32(namespace),kind,counts.calls[kind],counts.failures[kind])
    if counts.failures[kind] != 0 { good = false }
   } }; C.fflush(nil)
  } }
  if !good { C.puts(c'LINUX ROBUSTWAKE FAIL: robust-futex pending unlock, wake counts, PI tags or retained storage'); C.fflush(nil); return 1 }
  C.puts(if reference {c'LINUX ROBUSTWAKE REFERENCE: PASS'} else {c'LINUX ROBUSTWAKE: PASS'}); C.fflush(nil); for { C.pause() }
 }; return 0
}
