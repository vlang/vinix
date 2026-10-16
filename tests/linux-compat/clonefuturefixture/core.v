// SPDX-License-Identifier: GPL-2.0-or-later
module clonefuturefixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/prctl.h>
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
struct State {self i32 page u64 input u64 wrongfd i32 context Context}
struct Context {same i32 future i32 keeper i32 stop i32}
struct Worker {mut: pid i32 tid i32 uid u32 ran i32 address u64}
struct ThreadResult {code i32 ran i32 joined bool valid bool}
@[typedef]
struct C.pthread_t {}
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
fn C.prctl(i32,...) i32
fn C.close(i32) i32
fn C.fcntl(i32,i32,...) i32
fn C.read(i32,voidptr,usize) isize
fn C.write(i32,voidptr,usize) isize
fn C.pread(i32,voidptr,usize,i64) isize
fn C.sscanf(&char,&char,...) i32
fn C.pipe2(&i32,i32) i32
fn C.setns(i32,i32) i32
fn C.readlink(&char,voidptr,usize) isize
fn C.pthread_create(&C.pthread_t,voidptr,fn (voidptr) voidptr,voidptr) i32
fn C.pthread_join(C.pthread_t,voidptr) i32
fn C.fork() i32
fn C.unshare(i32) i32
fn C.waitpid(i32,&i32,i32) i32
fn C._exit(i32)

fn fatal(stage i32) {C.printf(c'LINUX CLONEFUTURE FAIL: setup stage=%d errno=%d\n',stage,unsafe{*C.__errno_location()}); C.fflush(unsafe{nil}); C._exit(90)}
fn count(class i32) i32 {return unsafe {[i32(96),96,108,60,72,36]![class]}}

fn namespace_capability(enabled bool) {unsafe {
 header := &CapHeader(C.alloca(usize(sizeof(CapHeader)))); *header = CapHeader{version:0x20080522}
 data := &CapData(C.alloca(usize(2*sizeof(CapData)))); C.memset(data,0,usize(2*sizeof(CapData)))
 if C.syscall(C.SYS_capget,header,data) != 0 {fatal(23)}
 if data[0].permitted & (u32(1)<<21) == 0 {fatal(27)}
 if enabled {data[0].effective |= u32(1)<<21} else {data[0].effective &= ~(u32(1)<<21)}
 if C.syscall(C.SYS_capset,header,data) != 0 || C.syscall(C.SYS_capget,header,data) != 0 || (data[0].effective & (u32(1)<<21) != 0) != enabled {fatal(24)}
}}

fn thread_flags(choice i32) u64 {
 return unsafe {[u64(0x10900),0x10f00,0x810f00,0x210f00,0x1010f00,0x110f00,0x90f00,0x18f00]![choice]}
}

fn attempt(state &State,class i32,index i32) Outcome {
 unsafe {
  placement:=index%3;choice:=index/3
  mut size:=u64(88)
  if class==0 || class==1 {size=[u64(88),96,128,256]![choice%4]}
  if class==4 {
   if choice in [i32(3),4,5,9,10,11]! {size=[u64(64),72,80]![choice%3]}
   if choice>=12 && choice<20 {size=[u64(89),96,128,256]![(choice-12)%4]}
   if choice>=20 {size=[u64(88),96,128,256]![choice-20]}
  }
  if class==5 && choice<8 {size=[u64(64),72,80,88]![choice%4]}
  mut offset:=if placement==0 {u64(128)} else if placement==1 {u64(129)} else {state.page-size}
  if class==4 && choice>=16 && choice<20 {offset=state.page-88}
  source:=state.input+offset
  if C.mprotect(voidptr(state.input),usize(2*state.page),C.PROT_READ|C.PROT_WRITE)!=0 {fatal(1)}
  C.memset(voidptr(state.input),0xa5,usize(2*state.page))
  args:=&Args(C.alloca(usize(sizeof(Args))));*args=Args{flags:u64(0x200010f00),cgroup:0x7fffffff}
  mut pointer:=source;mut wanted:=i32(C.EINVAL);mut legacy:=false;mut upper:=u64(0)
  if class==0 || class==1 {
   args.flags=u64(0x200000000)|thread_flags(choice/4)
   if class==1 {args.cgroup=u64(state.wrongfd)}
  }
  if class==2 {
   legacy=true;args.flags=[u64(0x10900),0x10b00,0x10d00,0x10f00]![choice/9]
   upper=[u64(0),u64(1)<<32,~u64(0xffffffff)]![(choice/3)%3]
  }
  if class==3 {
   match choice {
    0 {pointer=0;size=0}
    1 {pointer=0;size=63}
    2 {pointer=0;size=64;wanted=C.EFAULT}
    3 {pointer=1;wanted=C.EFAULT}
    4 {pointer=state.input+state.page-48;wanted=C.EFAULT}
    5 {pointer=state.input+state.page;wanted=C.EFAULT}
    6 {pointer=~u64(0)-31;wanted=C.EFAULT}
    7 {pointer=0;size=state.page+1;wanted=C.E2BIG}
    8 {pointer=state.input+state.page-87;wanted=C.EFAULT}
    9 {args.set_tid=1;args.set_tid_size=1;wanted=C.EFAULT}
    10 {args.set_tid=1}
    11 {args.set_tid=source;args.set_tid_size=33}
    12 {args.exit_signal=65}
    13 {args.flags|=u64(0x8000);args.exit_signal=17}
    14 {args.flags|=u64(0x400000)}
    15 {args.flags|=u64(1)<<63}
    16 {args.flags|=u64(0x100000800)}
    17 {args.stack=source}
    18 {args.stack_size=1}
    else {args.stack=~u64(0)-15;args.stack_size=32}
   }
  }
  if class==4 {
   if choice<3 || (choice>=6 && choice<9) {args.cgroup=[u64(1)<<31,u64(1)<<32,~u64(0)]![choice%3]}
   if choice>=6 && choice<9 {args.set_tid=1;args.set_tid_size=1}
   if choice>=9 && choice<12 {args.flags|=u64(1)<<63}
   if choice>=12 && choice<16 {wanted=C.E2BIG}
   if choice>=16 && choice<20 {wanted=C.EFAULT}
   if choice>=20 {args.flags=u64(0x200000000)|[u64(0x10900),0x10b00,0x10d00,0x10f00]![choice-20];wanted=C.EBADF}
  }
  if class==5 {
   wanted=0;args.flags=0;args.exit_signal=17;args.cgroup=[u64(0),0x7fffffff,~u64(0)]![placement]
   if choice<8 {args.flags=if choice<4 {u64(0)} else {u64(0x800000)}}
   else {legacy=true;upper=[u64(0),u64(1)<<32,u64(0xffffffff00000000),u64(1)<<63]![choice-8]}
  }
  C.memcpy(voidptr(source),args,88)
  if size>88 && size<=256 {C.memset(voidptr(source+88),0,usize(size-88))}
  if class==4 && choice>=12 && choice<16 {*(&u8(voidptr(source+size-1)))=1}
  if class==3 && pointer>=state.input+state.page-88 && pointer<state.input+state.page {C.memcpy(voidptr(pointer),args,88)}
  expected := &u8(C.alloca(usize(2*state.page))); C.memcpy(expected,voidptr(state.input),usize(2*state.page))
  if C.mprotect(voidptr(state.input),usize(state.page),C.PROT_READ) != 0 || C.mprotect(voidptr(state.input+state.page),usize(state.page),C.PROT_NONE) != 0 {fatal(2)}
  mut pipe := [i32(-1),i32(-1)]!; if C.pipe2(&pipe[0],0) != 0 {fatal(3)}
  mut code := C.__errno_location(); *code = 0
  result := if legacy {C.syscall(C.SYS_clone,args.flags|upper|if class == 5 {u64(17)} else {u64(0)},u64(0),u64(0),u64(0),u64(0))} else {C.syscall(C.SYS_clone3,voidptr(pointer),size)}; error := *code
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
   mut status := i32(-1); reaped := C.waitpid(i32(result),&status,0) == i32(result) && status == 37<<8
   child_ok = received && reaped && reply.pid == result && reply.tid == result && reply.parent == state.self && reply.uid == C.getuid()
  } else if result != -1 {fatal(5)}
  if C.close(pipe[0]) != 0 || C.mprotect(voidptr(state.input),usize(2*state.page),C.PROT_READ|C.PROT_WRITE) != 0 {fatal(6)}
  guarded := C.memcmp(expected,voidptr(state.input),usize(2*state.page)) == 0
  // Rejected calls cannot leave a child behind, even if an errno happened
  // to match after partially creating one. The cohort has no other children.
  mut status := i32(-1); *code = 0
  empty := C.waitpid(-1,&status,C.WNOHANG); no_children := empty == 0 && *code == 0
  return Outcome{result:i64(result),code:error,expected:wanted,guarded:guarded&&no_children&&C.fcntl(state.wrongfd,C.F_GETFD)==0,child:child_ok}
 }
}
fn run_case(counts &Counts,state &State,class i32,index i32,ordinary bool,namespace bool) bool {
 outcome := attempt(state,class,index)
 good := outcome.guarded && if outcome.expected == 0 {outcome.result > 1 && outcome.code == 0 && outcome.child} else {outcome.result == -1 && outcome.code == outcome.expected && !outcome.child}
 if counts != unsafe{nil} {unsafe {
  mut output := &Counts(counts); output.calls[class]++
  if outcome.result > 0 && outcome.child {output.forks[if outcome.expected == 0 {0} else {1}]++}
  if !good {output.failures[class]++; if output.failures[class] <= 3 {C.printf(c'LINUX CLONEFUTURE DETAIL: ordinary=%d route=%d kind=%d index=%d result=%ld errno=%d expected=%d guarded=%d child=%d\n',i32(ordinary),i32(namespace),class,index,outcome.result,outcome.code,outcome.expected,i32(outcome.guarded),i32(outcome.child))}}
 }}
 return good
}
fn namespace_links(same bool) {unsafe {
 mut active:=[128]char{};mut future:=[128]char{}
 n:=C.readlink(c'/proc/self/ns/pid',&active[0],128)
 m:=C.readlink(c'/proc/self/ns/pid_for_children',&future[0],128)
 if n<=0 || m<=0 || n>=128 || m>=128 {fatal(30)}
 equal:=n==m && C.memcmp(&active[0],&future[0],usize(n))==0
 if equal!=same {fatal(31)}
}}

fn start_context(via_setns bool) Context {unsafe {
 same:=C.open(c'/proc/self/ns/pid',0);if same<0 {fatal(32)}
 namespace_links(true)
 mut ready:=[i32(-1),i32(-1)]!;mut stop:=[i32(-1),i32(-1)]!
 if C.pipe2(&ready[0],0)!=0 || C.pipe2(&stop[0],0)!=0 || C.unshare(C.CLONE_NEWPID)!=0 {fatal(33)}
 keeper:=C.fork();if keeper<0 {fatal(34)}
 if keeper==0 {
  C.close(ready[0]);C.close(stop[1]);reply:=Child{pid:C.getpid(),tid:i32(C.syscall(C.SYS_gettid)),parent:C.getppid(),uid:C.getuid()}
  if C.write(ready[1],&reply,sizeof(Child))!=isize(sizeof(Child)) {C._exit(91)}
  C.close(ready[1]);mut byte:=u8(0)
  C._exit(if C.read(stop[0],&byte,1)==1 && byte==1 {38} else {92})
 }
 C.close(ready[1]);C.close(stop[0]);reply:=&Child(C.alloca(usize(sizeof(Child))));*reply=Child{}
 if C.read(ready[0],reply,sizeof(Child))!=isize(sizeof(Child)) || reply.pid!=1 || reply.tid!=1 || reply.parent!=0 || reply.uid!=C.getuid() {fatal(35)}
 C.close(ready[0]);future:=C.open(c'/proc/self/ns/pid_for_children',0)
 if future<0 || future==same {fatal(36)}
 namespace_links(false)
 if via_setns {
  if C.setns(same,C.CLONE_NEWPID)!=0 {fatal(37)}
  namespace_links(true)
 }
 return Context{same:same,future:future,keeper:keeper,stop:stop[1]}
}}

fn select_namespace(state &State,different bool) {
 namespace_capability(true)
 if C.setns(if different {state.context.future} else {state.context.same},C.CLONE_NEWPID)!=0 {fatal(38)}
 namespace_capability(false)
 if C.getpid()!=state.self {fatal(39)}
}

fn thread_worker(argument voidptr) voidptr {unsafe {
 mut value:=&Worker(argument)
 value.pid=C.getpid();value.tid=i32(C.syscall(C.SYS_gettid));value.uid=C.getuid()
 mut code:=C.__errno_location();value.address=u64(code);*code=91;value.ran=1
 return argument
}}

fn pthread_attempt(state &State) ThreadResult {unsafe {
 worker:=&Worker(C.alloca(usize(sizeof(Worker))));*worker=Worker{}
 handle:=&C.pthread_t(C.alloca(usize(sizeof(C.pthread_t))))
 reply:=&voidptr(C.alloca(usize(sizeof(voidptr))));*reply=nil
 code:=C.pthread_create(handle,nil,thread_worker,worker)
 mut joined:=false;mut valid:=code==C.EAGAIN && worker.ran==0
 if code==0 {
  joined=C.pthread_join(*handle,reply)==0
  valid=joined && *reply==voidptr(worker) && worker.ran==1 && worker.pid==state.self && worker.tid>1 && worker.tid!=state.self && worker.uid==C.getuid() && worker.address!=0 && worker.address!=u64(C.__errno_location())
 }
 return ThreadResult{code:code,ran:worker.ran,joined:joined,valid:valid}
}}

fn pthread_case(state &State,different bool,ordinary bool,namespace bool) bool {
 if !different || namespace {select_namespace(state,different)}
 namespace_links(!different)
 result:=pthread_attempt(state)
 good:=result.valid && if different {result.code==C.EAGAIN && result.ran==0 && !result.joined} else {result.code==0 && result.ran==1 && result.joined}
 C.printf(c'LINUX CLONEFUTURE PTHREAD: ordinary=%d route=%d different=%d result=%d ran=%d joined=%d valid=%d\n',i32(ordinary),i32(namespace),i32(different),result.code,result.ran,i32(result.joined),i32(result.valid))
 return good
}

fn cycle(state &State,index i32) bool {unsafe {
 select_namespace(state,true)
 for class in [i32(0),2]! {
  outcome:=attempt(state,class,i32(index%if class==0 {96} else {81}))
  old:=if class==0 {C.EBADF} else {C.ENOTSUP}
  if !outcome.guarded || outcome.result!=-1 || outcome.child || (outcome.code!=old && outcome.code!=C.EINVAL) {return false}
 }
 // The original creates and joins this thread; the fixed kernel refuses it.
 mismatch:=pthread_attempt(state)
 if !mismatch.valid || mismatch.code !in [i32(0),C.EAGAIN]! {return false}
 select_namespace(state,false)
 same:=pthread_attempt(state)
 return same.valid && same.code==0 && run_case(unsafe{nil},state,4,i32(60+index%12),false,false) && run_case(unsafe{nil},state,5,i32(index%36),false,false)
}}

fn qualify(counts &Counts,ordinary bool,namespace bool,reference bool) bool {unsafe {
 C.alarm(1100)
 context:=start_context(namespace)
 if C.prctl(C.PR_SET_KEEPCAPS,1,u64(0),u64(0),u64(0))!=0 {fatal(28)}
 if ordinary && (C.setgroups(0,nil)!=0 || C.setgid(1000)!=0 || C.setresuid(1000,1000,1000)!=0) {fatal(7)}
 uid:=if ordinary {u32(1000)} else {u32(0)}
 if C.getuid()!=uid || C.geteuid()!=uid || C.setsid()!=C.getpid() {fatal(8)}
 namespace_capability(false)
 C.printf(c'LINUX CLONEFUTURE CAPS: ordinary=%d route=%d sysadmin=0 permitted_sysadmin=1 keepcaps=1\n',i32(ordinary),i32(namespace))
 mut blocked:=C.sigset_t{};mut previous:=C.sigset_t{}
 if C.sigemptyset(&blocked)!=0 || C.sigaddset(&blocked,C.SIGCHLD)!=0 || C.pthread_sigmask(C.SIG_BLOCK,&blocked,&previous)!=0 {fatal(9)}
 page:=u64(C.sysconf(C._SC_PAGESIZE));if page!=4096 && page!=16384 {fatal(10)}
 input:=C.mmap(nil,usize(2*page),C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0);if u64(input)==~u64(0) {fatal(11)}
 wrongfd:=C.open(c'/dev/null',0);if wrongfd<0 || C.fcntl(wrongfd,C.F_GETFD)!=0 {fatal(25)}
 C.printf(c'LINUX CLONEFUTURE FD: ordinary=%d route=%d wrong=%d\n',i32(ordinary),i32(namespace),wrongfd)
 state:=&State(C.alloca(usize(sizeof(State))));*state=State{self:C.getpid(),page:page,input:u64(input),wrongfd:wrongfd,context:context}
 mut good:=pthread_case(state,true,ordinary,namespace)
 for class in 0 .. 6 {
  if class!=0 || namespace {select_namespace(state,class<4)}
  namespace_links(class>=4)
  for index in 0 .. count(i32(class)) {if !run_case(counts,state,i32(class),i32(index),ordinary,namespace) {good=false}}
 }
 if !pthread_case(state,false,ordinary,namespace) {good=false}
 C.printf(c'LINUX CLONEFUTURE COHORT: ordinary=%d route=%d self=%d uid=%u page=%lu raw=468 classes=6 layouts=3\n',i32(ordinary),i32(namespace),state.self,uid,page);C.fflush(nil)
 if !reference && !storage(state,ordinary,namespace) {good=false}
 select_namespace(state,false);namespace_links(true)
 mut byte:=u8(1);mut status:=i32(-1)
 if C.write(context.stop,&byte,1)!=1 || C.close(context.stop)!=0 || C.waitpid(context.keeper,&status,0)!=context.keeper || status!=38<<8 {fatal(40)}
 C.printf(c'LINUX CLONEFUTURE KEEPER: ordinary=%d route=%d outer=%d inner=1 parent=0 reaped=1\n',i32(ordinary),i32(namespace),context.keeper)
 if C.close(context.future)!=0 || C.close(context.same)!=0 || C.munmap(input,usize(2*page))!=0 || C.close(wrongfd)!=0 {fatal(41)}
 mut code:=C.__errno_location();*code=0
 if C.waitpid(-1,&status,C.WNOHANG)!=-1 || *code!=C.ECHILD {fatal(42)}
 namespace_capability(false)
 C.printf(c'LINUX CLONEFUTURE CAPSRESTORED: ordinary=%d route=%d sysadmin=0\n',i32(ordinary),i32(namespace))
 if C.pthread_sigmask(C.SIG_SETMASK,&previous,nil)!=0 {fatal(13)}
 for class in 0 .. 6 {C.printf(c'LINUX CLONEFUTURE CASES: ordinary=%d route=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),i32(namespace),class,counts.calls[class],counts.failures[class])}
 C.printf(c'LINUX CLONEFUTURE CHILDREN: ordinary=%d route=%d valid=%lu unexpected=%lu\n',i32(ordinary),i32(namespace),counts.forks[0],counts.forks[1])
 C.alarm(0);C.fflush(nil);return good
}}


fn storage(state &State,ordinary bool,namespace bool) bool {
 unsafe {
  observer := C.open(c'/proc/slabinfo',0); if observer < 0 {return false}; defer {C.close(observer)}
  for index in 0 .. 64 {if !cycle(state,i32(index)) {return false}}; C.usleep(13000000)
  before := &Slabs(C.alloca(usize(sizeof(Slabs)))); after := &Slabs(C.alloca(usize(sizeof(Slabs))))
  if !snapshot(observer,before) {return false}
  for index in 0 .. 200 {if !cycle(state,i32(index)) {return false}}; C.usleep(13000000)
  if !snapshot(observer,after) {return false}
  mut good := before.rows == after.rows && before.large == after.large
  for index in 0 .. int(before.rows) {if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] {good = false}; C.printf(c'LINUX CLONEFUTURE SLAB: ordinary=%d route=%d size=%lu live=%lu/%lu cycles=200\n',i32(ordinary),i32(namespace),before.sizes[index],before.live[index],after.live[index])}
  C.printf(c'LINUX CLONEFUTURE STORAGE: ordinary=%d route=%d cycles=200 big_pages=%lu/%lu %s\n',i32(ordinary),i32(namespace),before.large,after.large,if good {&char(c'PASS')} else {&char(c'FAIL')}); C.fflush(nil); return good
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
  if sizeof(Counts) != 112 { fatal(14) }
  reference := argc == 2 && C.strcmp(argv[1],c'--reference') == 0; mut good := true
  for namespace in [false,true]! { for ordinary in [false,true]! {
   mut pipe := [i32(-1),i32(-1)]!; if C.pipe2(&pipe[0],0) != 0 { fatal(15) }
   outer := C.fork(); if outer < 0 { fatal(16) }
   if outer == 0 {
    C.close(pipe[0])
    counts := &Counts(C.alloca(usize(sizeof(Counts)))); *counts = Counts{}
    passed := qualify(counts,ordinary,namespace,reference)
    sent := C.write(pipe[1],counts,sizeof(Counts)) == isize(sizeof(Counts)); C.close(pipe[1]); C._exit(if passed && sent {0} else {1})
   }
   C.close(pipe[1]); counts := &Counts(C.alloca(usize(sizeof(Counts)))); *counts = Counts{}
   received := C.read(pipe[0],counts,sizeof(Counts)) == isize(sizeof(Counts)); C.close(pipe[0])
   mut status := i32(-1); completed := C.waitpid(outer,&status,0) == outer && status == 0
   if !received || !completed { good = false }
   if received { for kind in 0 .. 6 {
    C.printf(c'LINUX CLONEFUTURE FINAL: ordinary=%d route=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),i32(namespace),kind,counts.calls[kind],counts.failures[kind])
    if counts.failures[kind] != 0 { good = false }
   }; C.printf(c'LINUX CLONEFUTURE CHILDRENFINAL: ordinary=%d route=%d valid=%lu unexpected=%lu\n',i32(ordinary),i32(namespace),counts.forks[0],counts.forks[1]) }; C.fflush(nil)
  } }
  if !good { C.puts(c'LINUX CLONEFUTURE FAIL: clone thread future PID namespace admission, import precedence, admission, fork/reap or retained storage'); C.fflush(nil); return 1 }
  C.puts(if reference {c'LINUX CLONEFUTURE REFERENCE: PASS'} else {c'LINUX CLONEFUTURE: PASS'}); C.fflush(nil); for { C.pause() }
 }; return 0
}
