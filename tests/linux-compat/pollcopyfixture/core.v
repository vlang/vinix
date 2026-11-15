// SPDX-License-Identifier: GPL-2.0-or-later
module pollcopyfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.timespec { mut: tv_sec i64 tv_nsec i64 }
struct C.pollfd {}
@[typedef]
struct C.sigset_t {}
struct Poll { mut: fd i32 events i16 revents i16 }
struct Totals { mut: checks int failures int }
struct Targets { source i32 peer i32 file i32 path i32 closed i32 page voidptr page_size usize }

fn C.alloca(usize) voidptr
fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.dup(i32) i32
fn C.unlink(&char) i32
fn C.chmod(&char, u32) i32
fn C.socketpair(i32, i32, i32, &i32) i32
fn C.write(i32, voidptr, usize) isize
fn C.read(i32, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.recv(i32, voidptr, usize, i32) isize
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memset(voidptr, i32, usize) voidptr
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.mprotect(voidptr, usize, i32) i32
fn C.sysconf(i32) isize
fn C.strcmp(&char, &char) i32
fn C.sscanf(&char, &char, ...) i32
fn C.printf(&char, ...) i32
fn C.fflush(voidptr) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.getuid() u32
fn C.getgid() u32
fn C.alarm(u32) u32
fn C.pause() i32
fn C.usleep(u32) i32
fn C.pipe(&i32) i32
fn C.fcntl(i32, i32, ...) i32
fn C.ppoll(&C.pollfd, u64, &C.timespec, &C.sigset_t) i32
fn C.poll(&C.pollfd, u64, i32) i32

fn fatal(stage int) {
 C.printf(c'LINUX POLLCOPY FAIL: setup=%d errno=%d\n',stage,unsafe { *C.__errno_location() })
 C.fflush(unsafe { nil }); C._exit(90)
}
fn check(mut t Totals, good bool) { t.checks++; if !good { t.failures++ } }
fn targets() Targets {
 unsafe {
 if sizeof(Poll) != 8 { fatal(1) }
 mut pair := [2]i32{}
 if C.socketpair(C.AF_UNIX,C.SOCK_STREAM|C.SOCK_NONBLOCK,0,&pair[0]) != 0 || C.write(pair[1],c'Q',1) != 1 { fatal(2) }
 file := C.open(c'/tmp/pollcopy-file',C.O_CREAT|C.O_EXCL|C.O_RDWR,0o600)
 if file < 0 || C.unlink(c'/tmp/pollcopy-file') != 0 || C.write(file,c'F',1) != 1 { fatal(3) }
 path := C.open(c'/proc/version',C.O_PATH)
 closed := C.fcntl(file,C.F_DUPFD_CLOEXEC,123)
 if path < 0 || closed < 0 || C.close(closed) != 0 { fatal(4) }
 length := usize(C.sysconf(C._SC_PAGESIZE))
 page := C.mmap(nil,2*length,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0)
 if page == voidptr(-1) { fatal(5) }
 return Targets{pair[0],pair[1],file,path,closed,page,length}
 }
}
fn call(api int, fds &Poll, count int) isize {
 unsafe {
 duration := &C.timespec(C.alloca(usize(sizeof(C.timespec))))
 *duration = C.timespec{}
 match api {
  0 { return C.syscall(isize(C.SYS_ppoll),fds,u64(count),duration,nil,u64(8)) }
  1 { return C.ppoll(&C.pollfd(fds),u64(count),duration,nil) }
  2 { return C.poll(&C.pollfd(fds),u64(count),0) }
  else {
   $if amd64 { return C.syscall(isize(C.SYS_poll),fds,u64(count),u64(0)) }
   $else { fatal(6); return -1 }
  }
 }
 }
}
fn probe(t &Targets, api int, layout int, kind int, mask int) Totals {
 unsafe {
 // Layouts avoid a revents field spanning pages: that scalar's partial-store
 // behavior is architecture-specific and is outside this qualification.
 count := if layout == 6 { 0 } else if layout in [3,4] { 2 } else if layout == 5 { 3 } else { 1 }
 offset := if layout in [1,2,4] { 6 } else if layout == 3 { 14 } else if layout in [5,7] { 16 } else { 32 }
 if C.mprotect(t.page,2*t.page_size,C.PROT_READ|C.PROT_WRITE) != 0 { fatal(7) }
 fds := &Poll(&u8(t.page)+t.page_size-usize(offset))
 start := &u8(fds)-8
 C.memset(start,0xa5,64)
 descriptor := match kind { 0 { t.file } 1 { t.peer } 2 { i32(-1) } 3 { t.closed } 4 { t.path } else { t.source } }
 // The user array may be unaligned. Construct an aligned value, then copy
 // bytes; only the syscall/libc boundary receives the unaligned Poll pointer.
 item := &Poll(C.alloca(usize(sizeof(Poll))))
 *item = Poll{fd:descriptor,events:i16(mask),revents:0x1234}
 for i in 0 .. count { C.memcpy(&u8(fds)+i*int(sizeof(Poll)),item,sizeof(Poll)) }
 desired := C.alloca(64)
 C.memcpy(desired,start,64)
 output := &Poll(&u8(desired)+8)
 normal := if kind in [3,4] { i16(32) } else if kind == 2 { i16(0) } else { i16(mask & if kind == 1 { 4 } else { 5 }) }
 // First output refusal stops the ordered stores. Earlier entries remain
 // published; failed and subsequent entries preserve their sentinels.
 written := if layout in [2,7] { 0 } else if layout == 3 { 1 } else if layout == 5 { 2 } else { count }
 for i in 0 .. written { output[i].revents = normal }
 if layout in [1,4,6] && C.mprotect(t.page,t.page_size,C.PROT_READ) != 0 { fatal(8) }
 if layout in [2,3,5,6] && C.mprotect(&u8(t.page)+t.page_size,t.page_size,C.PROT_READ) != 0 { fatal(9) }
 if layout == 7 && C.mprotect(t.page,t.page_size,C.PROT_NONE) != 0 { fatal(10) }
 wanted_errno := if layout in [2,3,5,7] { C.EFAULT } else { 0 }
 wanted := if wanted_errno != 0 { isize(-1) } else if normal == 0 { isize(0) } else { isize(count) }
 errno_slot := C.__errno_location()
 *errno_slot = 0
 result := call(api,fds,count)
 code := *C.__errno_location()
 if C.mprotect(t.page,2*t.page_size,C.PROT_READ|C.PROT_WRITE) != 0 { fatal(11) }
 mut sum := Totals{}
 check(mut sum,result == wanted)
 check(mut sum,code == wanted_errno)
 check(mut sum,C.memcmp(start,desired,64) == 0)
 check(mut sum,C.fcntl(t.file,C.F_GETFL) & C.O_ACCMODE == C.O_RDWR && C.fcntl(t.path,C.F_GETFL) & C.O_PATH != 0)
 mut byte := u8(0)
 check(mut sum,C.recv(t.source,&byte,1,C.MSG_PEEK|C.MSG_DONTWAIT) == 1 && byte == `Q`)
 check(mut sum,C.syscall(isize(C.SYS_lseek),t.file,i64(0),1) == 1 && C.pread(t.file,&byte,1,0) == 1 && byte == `F`)
 return sum
 }
}
fn qualify(t &Targets, apis int) Totals {
 mut total := Totals{}
 for api in 0 .. apis { for layout in 0 .. 8 {
 mut group := Totals{}
 for kind in 0 .. 6 { for choice in 0 .. 6 {
 mask := match choice { 0 { 0 } 1 { 1 } 2 { 2 } 3 { 4 } 4 { 5 } else { 7 } }
 result := probe(t,api,layout,kind,mask); group.checks += result.checks; group.failures += result.failures
 } }
 C.printf(c'LINUX POLLCOPY CASE: uid=%u gid=%u api=%d layout=%d checks=%d failures=%d\n',C.getuid(),C.getgid(),api,layout,group.checks,group.failures)
 total.checks += group.checks; total.failures += group.failures
 } }
 return total
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		C.alarm(600)
		if C.chmod(c'/tmp',0o1777) != 0 { fatal(20) }
		reference := argc == 2 && C.strcmp(argv[1],c'--reference') == 0
		mut apis := 3
		$if amd64 { apis = 4 }
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
				t := targets()
				sum := qualify(&t,apis)
				good := if reference { C.printf(c'LINUX POLLCOPY STORAGE: uid=%u SKIP reference\n',C.getuid()); true } else { storage(&t,apis) }
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
		C.printf(c'LINUX POLLCOPY SUMMARY: checks=%d failures=%d\n',total.checks,total.failures)
		C.printf(c'LINUX POLLCOPY: %s\n',if total.failures == 0 && storage_good { &char(c'PASS') } else { &char(c'FAIL') })
		C.fflush(nil); C.alarm(0)
		for { C.pause() }
	}
	return 0
}
