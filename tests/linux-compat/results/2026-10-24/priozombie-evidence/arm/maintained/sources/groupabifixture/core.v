// SPDX-License-Identifier: GPL-2.0-or-later
module groupabifixture

#include <alloca.h>
#include <errno.h>
#include <grp.h>
#include <signal.h>
#include <stdio.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

@[typedef]
struct C.siginfo_t {}
struct Counts { mut: calls [4]u64 failures [4]u64 }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows i32 large u64 }
struct Result { ret isize code i32 }
struct Child { pid i32 door i32 }
struct State { self i32 a Child b Child outsider i32 outsider_group i32 outsider_session i32 dead i32 }

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
	C.printf(c'LINUX GROUPABI FAIL: setup stage=%d errno=%d\n',stage,unsafe{*C.__errno_location()})
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
				C.printf(c'LINUX GROUPABI DETAIL: ordinary=%d kind=%d pid=%d group=%d pform=%d gform=%d actual=%ld/%d expected=%ld/%d\n',
					i32(ordinary),kind,pid,group,pform,gform,actual.ret,actual.code,expected,code)
				C.fflush(nil)
			}
		}
	}
}

fn launch() Child {
	unsafe {
		mut pipe := [i32(-1),i32(-1)]!
		if C.pipe2(&pipe[0],0) != 0 { fatal(1) }
		child := C.fork(); if child < 0 { fatal(2) }
		if child == 0 {
			C.close(pipe[1]); mut token := u8(0)
			good := C.read(pipe[0],&token,1) == 1 && token == `X`
			C.close(pipe[0]); C._exit(if good { 0 } else { 1 })
		}
		C.close(pipe[0]); return Child{child,pipe[1]}
	}
}

fn finish(child Child) {
	unsafe {
		if C.write(child.door,c'X',1) != 1 || C.close(child.door) != 0 { fatal(3) }
		mut status := i32(-1)
		if C.waitpid(child.pid,&status,0) != child.pid || status != 0 { fatal(4) }
	}
}

fn intact(state &State, group i32) bool {
	return C.getpgid(0) == state.self && C.getsid(0) == state.self
		&& C.getpgid(state.a.pid) == state.a.pid && C.getsid(state.a.pid) == state.self
		&& C.getpgid(state.b.pid) == group && C.getsid(state.b.pid) == state.self
		&& C.getpgid(state.outsider) == state.outsider_group && C.getsid(state.outsider) == state.outsider_session
}

fn matrix(counts &Counts, state &State, ordinary bool) {
	unsafe {
		for session in [false,true]! {
			for pid in [i32(0),state.self,state.a.pid,state.b.pid,state.outsider,state.dead,i32(0x7fffffff),i32(-1),i32(-2),i32(-2147483648)]! {
				for form in 0 .. 8 {
					wanted := if pid < 0 || pid == state.dead || pid == 0x7fffffff { isize(-1) }
						else if pid == state.outsider { isize(if session { state.outsider_session } else { state.outsider_group }) }
						else if !session && pid == state.a.pid { isize(state.a.pid) } else { isize(state.self) }
					code := if wanted == -1 { C.ESRCH } else { 0 }
					actual := query(session,pid,i32(form))
					record(counts,0,actual.ret == wanted && actual.code == code && intact(state,state.self),ordinary,pid,i32(session),i32(form),0,actual,wanted,code)
				}
			}
		}
		for group in [state.self,state.a.pid,i32(0)]! { for pform in 0 .. 8 { for gform in 0 .. 8 {
			actual := set(state.b.pid,group,i32(pform),i32(gform))
			wanted := if group == 0 { state.b.pid } else { group }
			record(counts,1,actual.ret == 0 && actual.code == 0 && intact(state,wanted),ordinary,state.b.pid,group,i32(pform),i32(gform),actual,0,0)
		} } }
		if C.setpgid(state.b.pid,state.self) != 0 || !intact(state,state.self) { fatal(5) }
		for pid in [i32(0),state.self,state.outsider,state.dead,i32(0x7fffffff),i32(-1),i32(-2),i32(-2147483648),state.b.pid]! {
			for group in [i32(-1),i32(-2),i32(-2147483648),i32(0x7fffffff)]! {
				code := if group < 0 { C.EINVAL }
					else if pid == 0 || pid == state.self || pid == state.b.pid { C.EPERM } else { C.ESRCH }
				for pform in 0 .. 8 { for gform in 0 .. 8 {
					actual := set(pid,group,i32(pform),i32(gform))
					record(counts,2,actual.ret == -1 && actual.code == code && intact(state,state.self),ordinary,pid,group,i32(pform),i32(gform),actual,-1,code)
				} }
			}
		}
		for pid in [i32(-1),i32(-2),i32(-2147483648)]! { for pform in 0 .. 8 { for gform in 0 .. 8 {
			actual := set(pid,0,i32(pform),i32(gform))
			record(counts,2,actual.ret == -1 && actual.code == C.EINVAL && intact(state,state.self),ordinary,pid,0,i32(pform),i32(gform),actual,-1,C.EINVAL)
		} } }
		zombie := C.fork(); if zombie < 0 { fatal(6) }; if zombie == 0 { C._exit(0) }
		mut info := C.siginfo_t{}
		if C.waitid(C.P_PID,u32(zombie),&info,C.WEXITED | C.WNOWAIT) != 0 { fatal(7) }
		for removed in [false,true]! {
			if removed { mut status := i32(-1); if C.waitpid(zombie,&status,0) != zombie || status != 0 { fatal(8) } }
			for session in [false,true]! { for form in 0 .. 8 {
				wanted := if removed { isize(-1) } else { isize(state.self) }; code := if removed { C.ESRCH } else { 0 }
				actual := query(session,zombie,i32(form))
				record(counts,3,actual.ret == wanted && actual.code == code && intact(state,state.self),ordinary,zombie,i32(session),i32(form),i32(removed),actual,wanted,code)
			} }
		}
	}
}

fn cycle(state &State) bool {
	unsafe {
		for form in 0 .. 8 {
			bad_group := query(false,-1,i32(form)); bad_session := query(true,-2,i32(form))
			bad_set := set(-1,state.self,i32(form),i32(7-form))
			if bad_group.ret != -1 || bad_group.code != C.ESRCH || bad_session.ret != -1 || bad_session.code != C.ESRCH
				|| bad_set.ret != -1 || bad_set.code != C.ESRCH { return false }
			group := if form % 2 == 0 { state.a.pid } else { state.self }
			changed := set(state.b.pid,group,i32(form),i32(7-form))
			if changed.ret != 0 || changed.code != 0 || !intact(state,group) { return false }
		}
		return intact(state,state.self)
	}
}

fn storage(state &State, ordinary bool) bool {
	unsafe {
		observer := C.open(c'/proc/slabinfo',0)
		if observer < 0 { return false }; defer { C.close(observer) }
		for _ in 0 .. 32 { if !cycle(state) { return false } }
		C.usleep(13000000)
		before := &Slabs(C.alloca(usize(sizeof(Slabs)))); after := &Slabs(C.alloca(usize(sizeof(Slabs))))
		if !snapshot(observer,before) { return false }
		for _ in 0 .. 200 { if !cycle(state) { return false } }
		C.usleep(13000000)
		if !snapshot(observer,after) { return false }
		mut good := before.rows == after.rows && before.large == after.large
		for index in 0 .. int(before.rows) {
			if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] { good = false }
			C.printf(c'LINUX GROUPABI SLAB: ordinary=%d size=%lu live=%lu/%lu cycles=200\n',i32(ordinary),before.sizes[index],before.live[index],after.live[index])
		}
		C.printf(c'LINUX GROUPABI STORAGE: ordinary=%d cycles=200 big_pages=%lu/%lu %s\n',i32(ordinary),before.large,after.large,if good { &char(c'PASS') } else { &char(c'FAIL') })
		C.fflush(nil); return good
	}
}

fn qualify(counts &Counts, ordinary bool, reference bool) bool {
	unsafe {
		C.alarm(800)
		uid := if ordinary { u32(1000) } else { u32(0) }
		if ordinary && (C.setgroups(0,nil) != 0 || C.setgid(uid) != 0 || C.setuid(uid) != 0) { fatal(9) }
		if C.getuid() != uid || C.geteuid() != uid || C.getgid() != uid || C.getegid() != uid { fatal(10) }
		self := C.getpid()
		if self <= 1 || C.setsid() != self || C.getpgid(0) != self || C.getsid(0) != self { fatal(11) }
		a := launch(); b := launch()
		if C.setpgid(a.pid,a.pid) != 0 { fatal(12) }
		dead := C.fork(); if dead < 0 { fatal(13) }; if dead == 0 { C._exit(0) }
		mut status := i32(-1)
		if C.waitpid(dead,&status,0) != dead || status != 0 { fatal(14) }
		outsider := C.getppid(); outsider_group := C.getpgid(outsider); outsider_session := C.getsid(outsider)
		if outsider <= 0 || outsider_group < 0 || outsider_session < 0 || outsider_session == self { fatal(15) }
		mut state := State{self,a,b,outsider,outsider_group,outsider_session,dead}
		if !intact(&state,self) { fatal(16) }
		C.printf(c'LINUX GROUPABI TOPOLOGY: ordinary=%d uid=%u self=%d sid=%d leader=%d member=%d outsider=%d dead=%d outsider_group=%d outsider_session=%d\n',i32(ordinary),uid,self,self,a.pid,b.pid,outsider,dead,outsider_group,outsider_session)
		matrix(counts,&state,ordinary)
		mut good := counts.failures[0] == 0 && counts.failures[1] == 0 && counts.failures[2] == 0 && counts.failures[3] == 0
		if good && !reference && !storage(&state,ordinary) { good = false }
		finish(b); finish(a)
		for kind in 0 .. 4 {
			C.printf(c'LINUX GROUPABI CASES: ordinary=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),kind,counts.calls[kind],counts.failures[kind])
			if counts.failures[kind] != 0 { good = false }
		}
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
		if sizeof(Counts) != 64 { fatal(9) }
		reference := argc == 2 && C.strcmp(argv[1], c'--reference') == 0
		mut good := true
		for ordinary in [false, true]! {
			mut pipe := [i32(-1), i32(-1)]!
			if C.pipe2(&pipe[0], 0) != 0 { fatal(10) }
			child := C.fork()
			if child < 0 { fatal(11) }
			if child == 0 {
				C.close(pipe[0])
				counts := &Counts(C.alloca(usize(sizeof(Counts))))
				*counts = Counts{}
				passed := qualify(counts, ordinary, reference)
				sent := C.write(pipe[1], counts, sizeof(Counts)) == isize(sizeof(Counts))
				C.close(pipe[1])
				C._exit(if passed && sent { 0 } else { 1 })
			}
			C.close(pipe[1])
			counts := &Counts(C.alloca(usize(sizeof(Counts))))
			*counts = Counts{}
			received := C.read(pipe[0], counts, sizeof(Counts)) == isize(sizeof(Counts))
			C.close(pipe[0])
			mut status := i32(-1)
			completed := C.waitpid(child, &status, 0) == child && status == 0
			if !received || !completed { good = false }
			if received {
				for kind in 0 .. 4 {
					C.printf(c'LINUX GROUPABI FINAL: ordinary=%d kind=%d calls=%lu failures=%lu\n', i32(ordinary), kind, counts.calls[kind], counts.failures[kind])
					if counts.failures[kind] != 0 { good = false }
				}
			}
			C.fflush(nil)
		}
		if !good {
			C.puts(c'LINUX GROUPABI FAIL: group/session IDs, signed argument words, errors or retained state')
			C.fflush(nil)
			return 1
		}
		C.puts(if reference {
			c'LINUX GROUPABI REFERENCE: PASS'
		} else {
			c'LINUX GROUPABI: PASS'
		})
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}
