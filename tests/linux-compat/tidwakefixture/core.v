// SPDX-License-Identifier: GPL-2.0-or-later
module tidwakefixture

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
struct C.pthread_t {}
@[typedef]
struct C.sigset_t {}
struct Counts {mut: calls [6]u64 failures [6]u64}
struct Slabs {mut: sizes [32]u64 live [32]u64 rows i32 large u64}
struct State {self i32 page u64 shared u64 alias u64}
struct Reply {mut: pid i32 tid i32 parent i32 uid u32 count i32 returned [3]i64}
struct Owner {target u64 abandoned u64 alias u64 class i32 ready i32 door i32}
struct Wait {park u64 private bool mut: result isize code i32}
struct Joined {mut: value u64}

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
fn C.getuid() u32
fn C.geteuid() u32
fn C.setsid() i32
fn C.setgroups(usize,voidptr) i32
fn C.setgid(u32) i32
fn C.setresuid(u32,u32,u32) i32
fn C.sysconf(i32) isize
fn C.mmap(voidptr,usize,i32,i32,i32,isize) voidptr
fn C.munmap(voidptr,usize) i32
fn C.ftruncate(i32,i64) i32
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

fn fatal(stage i32) {C.printf(c'LINUX TIDWAKE FAIL: setup stage=%d errno=%d\n',stage,unsafe{*C.__errno_location()}); C.fflush(unsafe{nil}); C._exit(90)}
fn futex(address u64,operation i32,count i32,move i32,other u64) isize {return C.syscall(C.SYS_futex,voidptr(address),isize(operation),isize(count),isize(move),voidptr(other),isize(0))}
fn waiter(argument voidptr) voidptr {
 unsafe {
  mut request := &Wait(argument); mut code := C.__errno_location(); *code = 0
  request.result = C.syscall(C.SYS_futex,voidptr(request.park),isize(if request.private {128} else {0}),isize(0),voidptr(nil),isize(0),isize(0)); request.code = *code; return nil
 }
}
// Positive requeue counts prove queue admission before the owner is released.
fn queue(park u64,target u64,count i32,private bool) {
 mut moved := i32(0)
 for _ in 0 .. 20000 {
  n := futex(park,if private {132} else {4},0,count-moved,target)
  if n < 0 || n > count-moved {fatal(1)}
  moved += i32(n); if moved == count {return}; C.usleep(1000)
 }; fatal(2)
}
fn record(counts &Counts,class i32,good bool,ordinary bool,namespace bool,index i32,actual isize,expected isize,changed bool) {
 if counts == unsafe{nil} {return}
 unsafe {
  mut output := &Counts(counts); output.calls[class]++
  if !good {output.failures[class]++; if output.failures[class] <= 3 {C.printf(c'LINUX TIDWAKE DETAIL: ordinary=%d namespace=%d kind=%d index=%d remaining=%ld expected=%ld changed=%d\n',i32(ordinary),i32(namespace),class,index,actual,expected,i32(changed))}}
 }
}
fn owner(argument voidptr) voidptr {
 unsafe {
  state := &Owner(argument); reply := &Reply(C.alloca(usize(sizeof(Reply)))); *reply = Reply{pid:C.getpid(),tid:i32(C.syscall(C.SYS_gettid)),parent:C.getppid(),uid:C.getuid()}
  if state.class in [1,2,4]! {reply.returned[reply.count] = C.syscall(C.SYS_set_tid_address,voidptr(state.abandoned)); reply.count++}
  if state.class == 4 {reply.returned[reply.count] = C.syscall(C.SYS_set_tid_address,voidptr(nil)); reply.count++}
  pointer := if state.class == 2 {u64(0)} else if state.class == 3 {state.alias} else {state.target}
  reply.returned[reply.count] = C.syscall(C.SYS_set_tid_address,voidptr(pointer)); reply.count++
  if C.write(state.ready,reply,sizeof(Reply)) != isize(sizeof(Reply)) {fatal(3)}
  mut release := u8(0); if C.read(state.door,&release,1) != 1 || release != `X` {fatal(4)}
  // Replacing musl's clear-tid registration deliberately bypasses libc exit
  // and join. The live leader keeps this map and stack until the parent has
  // observed worker ESRCH; the leader's later exit retires the entire image.
  C.syscall(C.SYS_exit,isize(37)); fatal(5); return nil
 }
}
fn trial(counts &Counts,state &State,ordinary bool,namespace bool,index i32,measure bool,announce bool) bool {
 unsafe {
  class := index/16; within := index%16; offset := if (within/4)%2 == 0 {u64(128)} else {state.page-4}
  address := state.shared+offset; abandoned := state.shared+state.page+256
  C.memset(voidptr(state.shared),0xa5,usize(2*state.page)); for at in [u64(32),36,40]! {*(&u32(state.shared+at)) = 0}
  mut ready := [i32(-1),i32(-1)]!; mut door := [i32(-1),i32(-1)]!; mut leader := [i32(-1),i32(-1)]!
  if C.pipe2(&ready[0],0) != 0 || C.pipe2(&door[0],0) != 0 || C.pipe2(&leader[0],0) != 0 {fatal(6)}
  child := C.fork(); if child < 0 {fatal(7)}
  if child == 0 {
   C.close(ready[0]); C.close(door[1]); C.close(leader[1])
   request := &Owner(C.alloca(usize(sizeof(Owner)))); *request = Owner{target:address,abandoned:abandoned,alias:state.alias+offset,class:class,ready:ready[1],door:door[0]}; mut handle := C.pthread_t{}
   if C.pthread_create(&handle,nil,owner,request) != 0 {fatal(8)}
   mut release := u8(0); if C.read(leader[0],&release,1) != 1 || release != `X` {fatal(9)}
   for fd in [ready[1],door[0],leader[0]]! {if C.close(fd) != 0 {fatal(10)}}
   C._exit(43)
  }
  C.close(ready[1]); C.close(door[0]); C.close(leader[0]); reply := &Reply(C.alloca(usize(sizeof(Reply)))); *reply = Reply{}
  if C.read(ready[0],reply,sizeof(Reply)) != isize(sizeof(Reply)) || C.close(ready[0]) != 0 {fatal(11)}
  if reply.pid != child || reply.tid <= 0 || reply.tid == child || reply.parent != state.self || reply.uid != if ordinary {u32(1000)} else {u32(0)} {fatal(12)}
  mut good := reply.count == if class == 4 {3} else if class in [1,2]! {2} else {1}
  for number in 0 .. int(reply.count) {good = good && reply.returned[number] == i64(reply.tid)}
  // Registration itself must leave the data untouched.
  for at in [offset,state.page+256]! {good = good && *(&u32(state.shared+at)) == u32(0xa5a5a5a5)}
  initial := match within%4 {0 {u32(0)} 1 {u32(0xffffffff)} 2 {u32(0xa5a55a5a)} else {u32(reply.tid)}}
  *(&u32(address)) = initial
  expected := &u8(C.alloca(usize(2*state.page))); C.memcpy(expected,voidptr(state.shared),usize(2*state.page))
  wanted := if class == 2 {initial} else {u32(0)}; C.memcpy(expected+offset,&wanted,4)
  sharing := if measure || within < 8 {1} else {3}; total := if measure {1} else {sharing+2}
  handles := &C.pthread_t(C.alloca(usize(5*sizeof(C.pthread_t)))); requests := &Wait(C.alloca(usize(5*sizeof(Wait))))
  for number in 0 .. total {
   requests[number] = Wait{park:state.shared+if number < sharing {u64(32)} else if number == sharing {u64(36)} else {u64(40)},private:number == sharing}
   if C.pthread_create(&handles[number],nil,waiter,&requests[number]) != 0 {fatal(13)}
  }
  queue(state.shared+32,address,i32(sharing),false)
  if !measure {queue(state.shared+36,address,1,true); queue(state.shared+40,abandoned,1,false)}
  if C.write(door[1],c'X',1) != 1 || C.close(door[1]) != 0 {fatal(14)}
  mut retired := false
  for _ in 0 .. 20000 {
   mut error_slot := C.__errno_location(); *error_slot = 0; result := C.syscall(C.SYS_tgkill,isize(child),isize(reply.tid),isize(0))
   if result == -1 && *C.__errno_location() == C.ESRCH {retired = true; break}
   if result != 0 {fatal(15)}; C.usleep(1000)
  }
  mut status := i32(-1)
  if !retired || C.syscall(C.SYS_tgkill,isize(child),isize(child),isize(0)) != 0 || C.waitpid(child,&status,C.WNOHANG) != 0 {fatal(16)}
  remaining := futex(address,1,8,0,0); expected_remaining := isize(sharing)-if class == 2 {isize(0)} else {isize(1)}
  good = good && remaining == expected_remaining
  if futex(state.shared+32,1,8,0,0) != 0 {fatal(17)}
  if !measure {good = futex(address,129,8,0,0) == 1 && good; good = futex(abandoned,1,8,0,0) == 1 && good; good = futex(state.shared+36,129,8,0,0) == 0 && good; good = futex(state.shared+40,1,8,0,0) == 0 && good}
  for number in 0 .. total {if C.pthread_join(handles[number],nil) != 0 || requests[number].result != 0 || requests[number].code != 0 {fatal(18)}}
  changed := C.memcmp(expected,voidptr(state.shared),usize(2*state.page)) != 0 || C.memcmp(expected,voidptr(state.alias),usize(2*state.page)) != 0
  good = good && !changed
  if C.write(leader[1],c'X',1) != 1 || C.close(leader[1]) != 0 || C.waitpid(child,&status,0) != child || status != 43<<8 {fatal(19)}
  if announce {C.printf(c'LINUX TIDWAKE TOPOLOGY: ordinary=%d namespace=%d self=%d child=%d worker=%d uid=%u alive_leader=1 observed_ESRCH=1 queued=3 private=1 abandoned=1\n',i32(ordinary),i32(namespace),state.self,child,reply.tid,reply.uid); C.fflush(nil)}
  record(counts,class,good,ordinary,namespace,index,remaining,expected_remaining,changed); return good
 }
}
fn joined(argument voidptr) voidptr {unsafe {mut state := &Joined(argument); state.value++; return voidptr(state.value)}}
fn libc_controls(counts &Counts,ordinary bool,namespace bool) {
 unsafe {
  state := &Joined(C.alloca(usize(sizeof(Joined)))); *state = Joined{}
  for index in 0 .. 16 {mut handle := C.pthread_t{}; mut returned := voidptr(nil)
   if C.pthread_create(&handle,nil,joined,state) != 0 || C.pthread_join(handle,&returned) != 0 {fatal(20)}
   record(counts,5,state.value == u64(index+1) && u64(returned) == u64(index+1),ordinary,namespace,i32(index),isize(u64(returned)),isize(index+1),false)
  }
 }
}
fn storage(state &State,ordinary bool,namespace bool) bool {
 unsafe {
  observer := C.open(c'/proc/slabinfo',0); if observer < 0 {return false}; defer {C.close(observer)}
  for index in 0 .. 80 {if !trial(nil,state,ordinary,namespace,i32(index),true,false) {return false}}; C.usleep(13000000)
  before := &Slabs(C.alloca(usize(sizeof(Slabs)))); after := &Slabs(C.alloca(usize(sizeof(Slabs))))
  if !snapshot(observer,before) {return false}
  for index in 0 .. 200 {if !trial(nil,state,ordinary,namespace,i32(index%80),true,false) {return false}}; C.usleep(13000000)
  if !snapshot(observer,after) {return false}
  mut good := before.rows == after.rows && before.large == after.large
  for index in 0 .. int(before.rows) {
   if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] {good = false}
   C.printf(c'LINUX TIDWAKE SLAB: ordinary=%d namespace=%d size=%lu live=%lu/%lu cycles=200\n',i32(ordinary),i32(namespace),before.sizes[index],before.live[index],after.live[index])
  }
  C.printf(c'LINUX TIDWAKE STORAGE: ordinary=%d namespace=%d cycles=200 big_pages=%lu/%lu %s\n',i32(ordinary),i32(namespace),before.large,after.large,if good {&char(c'PASS')} else {&char(c'FAIL')}); C.fflush(nil); return good
 }
}
fn qualify(counts &Counts,ordinary bool,namespace bool,reference bool) bool {
 unsafe {
  C.alarm(1400)
  if ordinary && (C.setgroups(0,nil) != 0 || C.setgid(1000) != 0 || C.setresuid(1000,1000,1000) != 0) {fatal(21)}
  uid := if ordinary {u32(1000)} else {u32(0)}
  if C.getuid() != uid || C.geteuid() != uid || C.setsid() != C.getpid() {fatal(22)}
  mut blocked := C.sigset_t{}; mut previous := C.sigset_t{}
  if C.sigemptyset(&blocked) != 0 || C.sigaddset(&blocked,C.SIGCHLD) != 0 || C.pthread_sigmask(C.SIG_BLOCK,&blocked,&previous) != 0 {fatal(23)}
  page := u64(C.sysconf(C._SC_PAGESIZE)); if page != 4096 && page != 16384 {fatal(24)}
  fd := i32(C.syscall(C.SYS_memfd_create,c'tidwake',isize(1))); if fd < 0 || C.ftruncate(fd,i64(2*page)) != 0 {fatal(25)}
  shared := C.mmap(nil,usize(2*page),C.PROT_READ|C.PROT_WRITE,C.MAP_SHARED,fd,0); alias := C.mmap(nil,usize(2*page),C.PROT_READ|C.PROT_WRITE,C.MAP_SHARED,fd,0)
  if u64(shared) == ~u64(0) || u64(alias) == ~u64(0) || shared == alias {fatal(26)}
  state := &State(C.alloca(usize(sizeof(State)))); *state = State{self:C.getpid(),page:page,shared:u64(shared),alias:u64(alias)}
  for index in 0 .. 80 {trial(counts,state,ordinary,namespace,i32(index),false,index == 15)}
  libc_controls(counts,ordinary,namespace)
  C.printf(c'LINUX TIDWAKE COHORT: ordinary=%d namespace=%d self=%d uid=%u page=%lu raw=80 libc=16 classes=5 leader_alive=1\n',i32(ordinary),i32(namespace),state.self,uid,page); C.fflush(nil)
  mut good := true; for kind in 0 .. 6 {if counts.failures[kind] != 0 {good = false}}
  if good && !reference && !storage(state,ordinary,namespace) {good = false}
  if C.munmap(shared,usize(2*page)) != 0 || C.munmap(alias,usize(2*page)) != 0 || C.close(fd) != 0 {fatal(27)}
  if C.pthread_sigmask(C.SIG_SETMASK,&previous,nil) != 0 {fatal(28)}
  for kind in 0 .. 6 {C.printf(c'LINUX TIDWAKE CASES: ordinary=%d namespace=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),i32(namespace),kind,counts.calls[kind],counts.failures[kind])}
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
    C.printf(c'LINUX TIDWAKE FINAL: ordinary=%d namespace=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),i32(namespace),kind,counts.calls[kind],counts.failures[kind])
    if counts.failures[kind] != 0 { good = false }
   } }; C.fflush(nil)
  } }
  if !good { C.puts(c'LINUX TIDWAKE FAIL: clear-child-tid wake count, registration replacement, alias keys or retained storage'); C.fflush(nil); return 1 }
  C.puts(if reference {c'LINUX TIDWAKE REFERENCE: PASS'} else {c'LINUX TIDWAKE: PASS'}); C.fflush(nil); for { C.pause() }
 }; return 0
}
