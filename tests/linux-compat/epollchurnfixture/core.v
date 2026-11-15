// SPDX-License-Identifier: GPL-2.0-or-later
module epollchurnfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/ioctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct Totals { mut: checks int failures int }
struct Targets {}
fn C.alloca(usize) voidptr
fn C.syscall(isize,...) isize
fn C.__errno_location() &i32
fn C.open(&char,i32,...) i32
fn C.close(i32) i32
fn C.fcntl(i32,i32,...) i32
fn C.pipe2(&i32,i32) i32
fn C.pipe(&i32) i32
fn C.dup2(i32,i32) i32
fn C.write(i32,voidptr,usize) isize
fn C.read(i32,voidptr,usize) isize
fn C.pread(i32,voidptr,usize,i64) isize
fn C.ioctl(i32,u64,...) i32
fn C.memcmp(voidptr,voidptr,usize) i32
fn C.memset(voidptr,i32,usize) voidptr
fn C.memcpy(voidptr,voidptr,usize) voidptr
fn C.sscanf(&char,&char,...) i32
fn C.snprintf(&char,usize,&char,...) i32
fn C.printf(&char,...) i32
fn C.strcmp(&char,&char) i32
fn C.chmod(&char,u32) i32
fn C.fflush(voidptr) i32
fn C.fork() i32
fn C.waitpid(i32,&i32,i32) i32
fn C._exit(i32)
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.getuid() u32
fn C.getgid() u32
fn C.alarm(u32) u32
fn C.pause() i32
fn C.usleep(u32) i32
fn C.epoll_create1(i32) i32
fn C.epoll_ctl(i32,i32,i32,voidptr) i32
fn C.epoll_wait(i32,voidptr,i32,i32) i32

fn fatal(stage int) {
 C.printf(c'LINUX EPOLLCHURN FAIL: setup=%d errno=%d\n',stage,unsafe { *C.__errno_location() })
 C.fflush(unsafe { nil }); C._exit(90)
}
fn check(mut sum Totals,good bool) { sum.checks++; if !good { sum.failures++ } }
fn ctl(api int,epfd int,op int,fd int,tag u64) isize { unsafe {
 bytes := &u8(C.alloca(16)); C.memset(bytes,0,16)
 mut offset := 8
 $if amd64 { offset = 4 }
 mask := &u32(C.alloca(4)); *mask = 1
 value := &u64(C.alloca(8)); *value = tag
 C.memcpy(bytes,mask,4); C.memcpy(bytes+offset,value,8)
 if api == 0 { return C.syscall(isize(C.SYS_epoll_ctl),epfd,op,fd,if op == 2 { voidptr(nil) } else { voidptr(bytes) }) }
 return C.epoll_ctl(epfd,op,fd,if op == 2 { voidptr(nil) } else { voidptr(bytes) })
} }
// Preserve guards, unused records and ABI fields; ARM's internal padding is
// deliberately unasserted. Tags are unique and output order is immaterial.
fn wait_probe(mut sum Totals,epfd int,tags int) { unsafe {
 out := &u8(C.alloca(64)); C.memset(out,0xa7,64)
 mut size := 16; mut offset := 8
 $if amd64 { size = 12; offset = 4 }
 slot := C.__errno_location(); *slot = 0
 ret := C.epoll_wait(epfd,voidptr(out+8),2,0)
 code := *slot
 count := int(tags&1 != 0)+int(tags&2 != 0)+int(tags&4 != 0)
 check(mut sum,ret == count)
 check(mut sum,code == 0)
 mut seen := 0
 mut good := ret >= 0 && ret <= 2
 if ret >= 0 && ret <= 2 {
  for i in 0 .. int(ret) {
   mask := &u32(C.alloca(4)); tag := &u64(C.alloca(8))
   C.memcpy(mask,out+8+i*size,4); C.memcpy(tag,out+8+i*size+offset,8)
   bit := if *tag == 0x1122334455667788 { 1 } else if *tag == 0x8877665544332211 { 2 } else if *tag == 0x246813579abcdef0 { 4 } else { 0 }
   if *mask != 1 || bit == 0 || seen&bit != 0 { good = false }
   seen |= bit
  }
  for i in 0 .. 64 {
   if i < 8 || i >= 8+int(ret)*size { if out[i] != 0xa7 { good = false } }
  }
 }
 check(mut sum,good && seen == tags)
} }
// mode 0: new pipe description at a reused fd; mode 1: the original open
// description restored to that fd; mode 2: a different fd of the original
// description; mode 3: reopened description of the same pipe inode.
fn probe(api int,mode int,op int,state int,layout int) Totals { unsafe {
 a := &i32(C.alloca(8)); b := &i32(C.alloca(8))
 if C.pipe2(a,C.O_NONBLOCK) != 0 || C.pipe2(b,C.O_NONBLOCK) != 0 { fatal(1) }
 byte := &u8(C.alloca(1)); *byte = 0x59
 aq,bq := state&1 != 0,state&2 != 0
 if aq && C.write(a[1],byte,1) != 1 { fatal(2) }
 if bq && C.write(b[1],byte,1) != 1 { fatal(3) }
 target := C.fcntl(a[0],C.F_DUPFD_CLOEXEC,if layout == 0 { 70 } else { 134 })
 epfd := C.epoll_create1(C.EPOLL_CLOEXEC)
 if target < 70 || epfd < 0 || ctl(api,epfd,1,target,0x1122334455667788) != 0 { fatal(4) }
 mut candidate := target
 mut reopened := i32(-1)
 if mode == 2 {
  candidate = C.fcntl(a[0],C.F_DUPFD_CLOEXEC,200)
  if candidate < 200 { fatal(5) }
 } else {
  if C.close(target) != 0 { fatal(6) }
  if mode == 3 {
   path := &char(C.alloca(64))
   if C.snprintf(path,64,c'/proc/self/fd/%d',a[0]) <= 0 { fatal(7) }
   reopened = C.open(path,C.O_RDONLY|C.O_NONBLOCK)
   if reopened < 0 { fatal(8) }
  }
  source := if mode == 0 { b[0] } else if mode == 3 { reopened } else { a[0] }
  if C.dup2(source,target) != target { fatal(9) }
 }
 slot := C.__errno_location(); *slot = 0
 result := ctl(api,epfd,op,candidate,0x8877665544332211)
 code := *slot
 same := mode == 1
 accepted := if same { op != 1 } else { op == 1 }
 mut sum := Totals{}
 check(mut sum,result == if accepted { 0 } else { -1 })
 check(mut sum,code == if accepted { 0 } else if same { C.EEXIST } else { C.ENOENT })
 cq := if mode == 0 { bq } else { aq }
 mut tags := if aq { 1 } else { 0 }
 if same { tags = if op == 2 || !aq { 0 } else if op == 3 { 2 } else { 1 } }
 else if op == 1 && cq { tags |= 2 }
 wait_probe(mut sum,epfd,tags)
 wait_probe(mut sum,epfd,tags)
 // If two descriptions share the number, MOD/DEL must skip the older entry
 // even though it occurs first. A different-number duplicate is also valid.
 if !same && op == 1 {
  *slot = 0
  changed := ctl(api,epfd,3,candidate,0x246813579abcdef0)
  changed_errno := *slot
  check(mut sum,changed == 0 && changed_errno == 0)
  wait_probe(mut sum,epfd,(if aq { 1 } else { 0 }) | (if cq { 4 } else { 0 }))
  *slot = 0
  removed := ctl(api,epfd,2,candidate,0)
  removed_errno := *slot
  check(mut sum,removed == 0 && removed_errno == 0)
  wait_probe(mut sum,epfd,if aq { 1 } else { 0 })
 }
 qa := &i32(C.alloca(4)); qb := &i32(C.alloca(4))
 check(mut sum,C.ioctl(a[0],u64(C.FIONREAD),qa) == 0 && *qa == int(aq)
  && C.ioctl(b[0],u64(C.FIONREAD),qb) == 0 && *qb == int(bq))
 check(mut sum,C.fcntl(candidate,C.F_GETFL)&(C.O_ACCMODE|C.O_NONBLOCK) == C.O_NONBLOCK)
 if C.close(candidate) != 0 { fatal(10) }
 if mode == 2 && C.close(target) != 0 { fatal(11) }
 if reopened >= 0 && C.close(reopened) != 0 { fatal(12) }
 if C.close(a[0]) != 0 { fatal(13) }
 // Closing the final original description removes its old watch. B remains
 // open, but the explicit deletion above leaves no new watch to deliver.
 wait_probe(mut sum,epfd,0)
 if C.close(epfd) != 0 || C.close(a[1]) != 0 || C.close(b[0]) != 0 || C.close(b[1]) != 0 { fatal(14) }
 return sum
} }
fn qualify() Totals {
 mut total := Totals{}
 for api in 0 .. 2 { for mode in 0 .. 4 { for op in 1 .. 4 {
 mut sum := Totals{}
 for state in 0 .. 4 { for layout in 0 .. 2 {
  got := probe(api,mode,op,state,layout)
  sum.checks += got.checks; sum.failures += got.failures
 } }
 C.printf(c'LINUX EPOLLCHURN CASE: uid=%u gid=%u api=%d mode=%d op=%d checks=%d failures=%d\n',C.getuid(),C.getgid(),api,mode,op,sum.checks,sum.failures)
 total.checks += sum.checks; total.failures += sum.failures
 } } }
 return total
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		C.alarm(600)
		if C.chmod(c'/tmp',0o1777) != 0 { fatal(20) }
		reference := argc == 2 && C.strcmp(argv[1],c'--reference') == 0
		apis := 2
		mut total := Totals{}
		mut storage_good := true
		for ordinary in [false,true]! {
			mut channel := [2]i32{}
			if C.pipe(&channel[0]) != 0 { fatal(8) }
			C.fflush(nil); pid := C.fork()
			if pid < 0 { fatal(9) }
			if pid == 0 {
				C.close(channel[0])
				if ordinary && (C.setgid(2000) != 0 || C.setuid(1000) != 0) { fatal(10) }
				t := &Targets(C.alloca(usize(sizeof(Targets))))
				*t = Targets{}
				sum := qualify()
				good := if reference { C.printf(c'LINUX EPOLLCHURN STORAGE: uid=%u SKIP reference\n',C.getuid()); true } else { storage(t,apis) }
				mut answer := [3]int{}
				answer[0] = sum.checks; answer[1] = sum.failures; answer[2] = if good { 0 } else { 1 }
				if C.write(channel[1],&answer[0],sizeof(answer)) != isize(sizeof(answer)) { fatal(11) }
				C.fflush(nil); C._exit(0)
			}
			C.close(channel[1]); mut answer := [3]int{}
			if C.read(channel[0],&answer[0],sizeof(answer)) != isize(sizeof(answer)) { fatal(12) }
			C.close(channel[0]); mut status := i32(0)
			if C.waitpid(pid,&status,0) != pid || status != 0 { fatal(13) }
			total.checks += answer[0]; total.failures += answer[1]
			if answer[2] != 0 { storage_good = false }
		}
		C.printf(c'LINUX EPOLLCHURN SUMMARY: checks=%d failures=%d\n',total.checks,total.failures)
		C.printf(c'LINUX EPOLLCHURN: %s\n',if total.failures == 0 && storage_good { &char(c'PASS') } else { &char(c'FAIL') })
		C.fflush(nil); C.alarm(0)
		for { C.pause() }
	}
	return 0
}
