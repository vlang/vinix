// SPDX-License-Identifier: GPL-2.0-or-later
// Independent concurrent procfs map/snapshot and retained-buffer regression.
@[translated; has_globals]
module mapfixture

#include <map-native-abi.h>

@[typedef] struct C.FILE {}
@[typedef] struct C.DIR {}
@[typedef] struct C.pthread_t {}
@[typedef] struct C.pthread_mutex_t {}
@[typedef] struct C.vml_long {}
@[typedef] struct C.vml_ulong {}
struct C.dirent { mut: d_name [256]char }
struct C.timespec { mut: tv_sec i64 tv_nsec i64 }
type Inspector = fn (voidptr) voidptr
@[c_extern] __global C.stdout &C.FILE
@[c_extern] __global C.errno i32
@[cinit] __global pm_lock C.pthread_mutex_t = C.pthread_mutex_t{}
__global pm_children [12]i32
__global pm_owner i32
__global pm_observed u32
__global pm_listed u32
__global pm_epoch u32
__global pm_active i32
__global pm_stopped i32
__global pm_failures i32
__global pm_lookups usize
__global pm_listings usize

struct Heap { mut: size [32]i64 live [32]i64 pages [32]i64 large i64 uaf i64 count i32 }

fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.setbuf(&C.FILE, &char)
fn C.open(&char, i32, ...) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.readlink(&char, &char, usize) isize
fn C.snprintf(&char, usize, &char, ...) i32
fn C.sscanf(&char, &char, ...) i32
fn C.strcmp(&char, &char) i32
fn C.strstr(&char, &char) &char
fn C.memchr(voidptr, i32, usize) voidptr
fn C.memset(voidptr, i32, usize) voidptr
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.opendir(&char) &C.DIR
fn C.readdir(&C.DIR) &C.dirent
fn C.closedir(&C.DIR) i32
fn C.fopen(&char, &char) &C.FILE
fn C.fgets(&char, i32, &C.FILE) &char
fn C.fclose(&C.FILE) i32
fn C.pthread_mutex_lock(&C.pthread_mutex_t) i32
fn C.pthread_mutex_unlock(&C.pthread_mutex_t) i32
fn C.pthread_create(&C.pthread_t, voidptr, Inspector, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.vml_inspector(voidptr) voidptr
fn C.__atomic_add_fetch(voidptr, i32, i32) i32
fn C.__atomic_load_n(voidptr, i32) i32
fn C.__atomic_store_n(voidptr, i32, i32)
fn C.nanosleep(&C.timespec, &C.timespec) i32
fn C.getpid() i32
fn C.alarm(u32) u32
fn C.pipe(&i32) i32
fn C.fork() i32
fn C._exit(i32)
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) bool
fn C.WEXITSTATUS(i32) i32
fn C.sync()
fn C.reboot(i32) i32
fn C.pause() i32

fn value(word C.vml_long) i64 { unsafe { result := i64(0); C.memcpy(&result, &word, 8); return result } }
fn native_long(word i64) C.vml_long { unsafe { result := C.vml_long{}; C.memcpy(&result, &word, 8); return result } }
fn native_ulong(word usize) C.vml_ulong { unsafe { result := C.vml_ulong{}; C.memcpy(&result, &word, 8); return result } }

fn fail(what &char) {
	unsafe {
		C.printf(c'FAIL: proc map lookup: %s errno=%d\n', what, C.errno)
		C.__atomic_add_fetch(&pm_failures, 1, C.__ATOMIC_RELAXED)
	}
}
fn failed() bool { unsafe { return C.__atomic_load_n(&pm_failures, C.__ATOMIC_RELAXED) != 0 } }

fn read_process(pid i32, required bool) bool {
	unsafe {
		names := [&char(c'stat'), &char(c'status'), &char(c'comm')]!
		path := [96]char{}; text := [2048]char{}
		for i := u32(0); i < 3; i++ {
			C.snprintf(&path[0], sizeof(path), c'/proc/%d/%s', pid, names[i])
			fd := C.open(&path[0], C.O_RDONLY)
			if fd < 0 {
				if required || (C.errno != C.ENOENT && C.errno != C.ESRCH) { fail(c'open process entry') }
				return false
			}
			count := C.read(fd, &text[0], sizeof(text) - 1)
			error := C.errno
			if C.close(fd) != 0 { fail(c'close process entry') }
			if count <= 0 {
				C.errno = error
				if required { fail(c'read stable process entry') }
				return false
			}
			text[count] = 0
			if C.strcmp(names[i], c'status') == 0 && C.strstr(&text[0], c'State:\t') == nil { fail(c'status keeps its state field') }
		}
		C.__atomic_add_fetch(&pm_lookups, 1, C.__ATOMIC_RELAXED)
		return true
	}
}

fn listing(pid i32, suffix &char, required bool, process_dir bool) bool {
	unsafe {
		path := [96]char{}
		if pid != 0 { C.snprintf(&path[0], sizeof(path), c'/proc/%d%s', pid, suffix) }
		else { C.snprintf(&path[0], sizeof(path), c'/proc%s', suffix) }
		directory := C.opendir(&path[0])
		if directory == nil {
			if required || (C.errno != C.ENOENT && C.errno != C.ESRCH) { fail(c'open directory snapshot') }
			return false
		}
		dot := i32(0); dotdot := i32(0); status := i32(0); stat := i32(0)
		C.errno = 0
		for {
			entry := C.readdir(directory)
			if entry == nil { break }
			if C.memchr(&entry.d_name[0], 0, sizeof(entry.d_name)) == nil { fail(c'terminated directory name') }
			dot |= i32(C.strcmp(&entry.d_name[0], c'.') == 0)
			dotdot |= i32(C.strcmp(&entry.d_name[0], c'..') == 0)
			status |= i32(C.strcmp(&entry.d_name[0], c'status') == 0)
			stat |= i32(C.strcmp(&entry.d_name[0], c'stat') == 0)
		}
		error := C.errno
		if C.closedir(directory) != 0 { fail(c'close directory snapshot') }
		if error != 0 { C.errno = error; fail(c'read directory snapshot') }
		if dot == 0 || dotdot == 0 || (process_dir && (status == 0 || stat == 0)) { fail(c'snapshot contains required entries') }
		C.__atomic_add_fetch(&pm_listings, 1, C.__ATOMIC_RELAXED)
		return error == 0
	}
}

fn stable_operation() bool {
	unsafe {
		if !read_process(pm_owner, true) || !listing(0, c'', true, false) || !listing(pm_owner, c'', true, true)
			|| !listing(pm_owner, c'/task', true, false) || !listing(pm_owner, c'/fd', true, false) { return false }
		links := [&char(c'exe'), &char(c'cwd'), &char(c'root')]!
		path := [96]char{}; target := [256]char{}
		for i := u32(0); i < 3; i++ {
			C.snprintf(&path[0], sizeof(path), c'/proc/%d/%s', pm_owner, links[i])
			if C.readlink(&path[0], &target[0], sizeof(target)) <= 0 { fail(c'refresh process magic link') }
		}
		return !failed()
	}
}

@[export: 'vml_inspector']
pub fn inspector(argument voidptr) voidptr {
	unsafe {
		kind := usize(argument)
		slot := u32(0)
		for C.__atomic_load_n(&pm_stopped, C.__ATOMIC_ACQUIRE) == 0 && !failed() {
			if kind == 2 {
				listing(0, c'', true, false); listing(pm_owner, c'', true, true)
				listing(pm_owner, c'/task', true, false); listing(pm_owner, c'/fd', true, false)
			} else { read_process(pm_owner, true) }
			C.pthread_mutex_lock(&pm_lock)
			saved_epoch := pm_epoch
			child := if pm_active != 0 { pm_children[slot % u32(pm_active)] } else { i32(0) }
			saved_slot := if pm_active != 0 { slot % u32(pm_active) } else { u32(0) }
			C.pthread_mutex_unlock(&pm_lock)
			if child != 0 {
				saw := if kind == 2 { listing(child, c'', false, true) } else { read_process(child, false) }
				if saw {
					C.pthread_mutex_lock(&pm_lock)
					if pm_epoch == saved_epoch && saved_slot < u32(pm_active) && pm_children[saved_slot] == child {
						if kind == 2 { pm_listed |= u32(1) << saved_slot }
						else { pm_observed |= u32(1) << saved_slot }
					}
					C.pthread_mutex_unlock(&pm_lock)
				}
			}
			slot++
			pause := C.timespec{tv_nsec: 1000000}
			C.nanosleep(&pause, nil)
		}
		return nil
	}
}

fn snapshot(heap &Heap) bool {
	unsafe {
		C.memset(heap, 0, sizeof(Heap))
		file := C.fopen(c'/proc/slabinfo', c'r')
		if file == nil { fail(c'open allocation snapshot'); return false }
		line := [256]char{}; large := i32(0); uaf := i32(0)
		for C.fgets(&line[0], i32(sizeof(line)), file) != nil {
			label := C.vml_long{}; size := C.vml_long{}; live := C.vml_long{}; pages := C.vml_long{}
			if C.sscanf(&line[0], c'size-%ld %ld %ld %ld', &label, &size, &live, &pages) == 4 && value(label) == value(size) {
				if heap.count == 32 { fail(c'allocation class capacity'); break }
				i := heap.count++; heap.size[i] = value(size); heap.live[i] = value(live); heap.pages[i] = value(pages)
			} else if C.sscanf(&line[0], c'large - - %ld', &pages) == 1 { heap.large = value(pages); large = 1 }
			else if C.sscanf(&line[0], c'# written after free %ld', &live) == 1 { heap.uaf = value(live); uaf = 1 }
		}
		if C.fclose(file) != 0 { fail(c'close allocation snapshot') }
		$if arm64 { if heap.count != 18 || large == 0 || uaf == 0 { fail(c'complete ARM allocation snapshot') } }
		$else { if heap.count != 14 || large == 0 || uaf == 0 { fail(c'complete x86 allocation snapshot') } }
		return !failed()
	}
}

@[export: 'main']
pub fn entry() i32 {
	unsafe {
		C.setbuf(C.stdout, nil); C.alarm(600); pm_owner = C.getpid()
		threads := [3]C.pthread_t{}; started := i32(0)
		for started < 3 {
			error := C.pthread_create(&threads[started], nil, C.vml_inspector, voidptr(usize(started)))
			if error != 0 { C.errno = error; fail(c'start concurrent inspector'); break }
			started++
		}
		for round := i32(0); round < 4 && !failed(); round++ {
			gate := [2]i32{}
			if C.pipe(&gate[0]) != 0 { fail(c'create child lifetime gate'); break }
			cohort := [12]i32{}; count := i32(0)
			for count < 12 {
				pid := C.fork()
				if pid == 0 {
					C.close(gate[1]); byte := char(0); got := C.read(gate[0], &byte, 1)
					C._exit(if got == 1 { 0 } else { 1 })
				}
				if pid < 0 { fail(c'fork map-growth child'); break }
				cohort[count] = pid; count++
			}
			C.close(gate[0]); C.pthread_mutex_lock(&pm_lock)
			pm_epoch++; pm_observed = 0; pm_listed = 0; pm_active = count
			C.memcpy(&pm_children[0], &cohort[0], usize(count) * sizeof(i32))
			C.pthread_mutex_unlock(&pm_lock)
			all := (u32(1) << u32(count)) - u32(1)
			for !failed() {
				C.pthread_mutex_lock(&pm_lock)
				complete := pm_observed == all && pm_listed == all
				C.pthread_mutex_unlock(&pm_lock)
				if complete { break }
				pause := C.timespec{tv_nsec: 1000000}; C.nanosleep(&pause, nil)
			}
			C.pthread_mutex_lock(&pm_lock); pm_active = 0; pm_epoch++; C.pthread_mutex_unlock(&pm_lock)
			release := [12]char{}; C.memset(&release[0], `X`, sizeof(release))
			if C.write(gate[1], &release[0], usize(count)) != count { fail(c'release map-growth children') }
			C.close(gate[1])
			for i := i32(0); i < count; i++ {
				status := i32(0)
				if C.waitpid(cohort[i], &status, 0) != cohort[i] || !C.WIFEXITED(status) || C.WEXITSTATUS(status) != 0 { fail(c'reap map-growth child') }
			}
			C.printf(c'proc map lookup: completed growth cohort %d children=%d\n', round + 1, count)
		}
		C.__atomic_store_n(&pm_stopped, 1, C.__ATOMIC_RELEASE)
		for i := i32(0); i < started; i++ { if C.pthread_join(threads[i], nil) != 0 { fail(c'join inspector') } }
		if pm_lookups < 100 || pm_listings < 100 { fail(c'concurrent lookup and snapshot progress') }
		for i := i32(0); i < 20 && !failed(); i++ { stable_operation() }
		grace := C.timespec{tv_sec: 7}; C.nanosleep(&grace, nil)
		before := Heap{}; after := Heap{}
		if !failed() && snapshot(&before) {
			for i := i32(0); i < 200 && !failed(); i++ { stable_operation() }
			if snapshot(&after) {
				if before.count != after.count { fail(c'allocation class count remains stable') }
				for i := i32(0); i < before.count && i < after.count; i++ {
					C.printf(c'PROC-MAP-RETENTION class=%ld live=%ld pages=%ld\n', native_long(before.size[i]), native_long(after.live[i] - before.live[i]), native_long(after.pages[i] - before.pages[i]))
					if before.size[i] != after.size[i] || before.live[i] != after.live[i] || before.pages[i] != after.pages[i] { fail(c'snapshot and lookup buffers remain flat') }
				}
				C.printf(c'PROC-MAP-RETENTION large=%ld uaf=%ld\n', native_long(after.large - before.large), native_long(after.uaf - before.uaf))
				if before.large != after.large || before.uaf != after.uaf { fail(c'large allocations and UAF remain flat') }
			}
		}
		C.printf(c'proc map lookup: %lu lookups, %lu directory snapshots\n', native_ulong(pm_lookups), native_ulong(pm_listings))
		if !failed() { C.puts(c'VINIX PROC MAP LOOKUP: PASS') }
		if pm_owner != 1 { return if failed() { 1 } else { 0 } }
		C.sync(); C.reboot(C.RB_POWER_OFF); for { C.pause() }
		return 0
	}
}
