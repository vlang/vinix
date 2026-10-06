// SPDX-License-Identifier: GPL-2.0-or-later
// Independent cached-procfs mount-cycle and namespace lifetime regression.
@[translated; has_globals]
module mountfixture

#include <mount-native-abi.h>

@[typedef] struct C.FILE {}
@[typedef] struct C.vpm_long {}
@[c_extern] __global C.stdout &C.FILE
@[c_extern] __global C.errno i32
__global pm_content [131072]char
__global pm_before_mounts [131072]char

fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.setvbuf(&C.FILE, &char, i32, usize) i32
fn C.fflush(&C.FILE) i32
fn C.open(&char, i32, ...) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.readlink(&char, &char, usize) isize
fn C.strchr(&char, i32) &char
fn C.strcmp(&char, &char) i32
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.sscanf(&char, &char, ...) i32
fn C.snprintf(&char, usize, &char, ...) i32
fn C.mount(&char, &char, &char, u64, voidptr) i32
fn C.umount(&char) i32
fn C.mkdir(&char, u32) i32
fn C.rmdir(&char) i32
fn C.unshare(i32) i32
fn C.getpid() i32
fn C.fork() i32
fn C._exit(i32)
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) bool
fn C.WEXITSTATUS(i32) i32
fn C.pipe(&i32) i32
fn C.dup2(i32, i32) i32
fn C.sync()
fn C.reboot(i32) i32

fn require(condition bool, line i32) bool {
	unsafe {
		if !condition { C.printf(c'PROC MOUNT FAIL: line=%d errno=%d\n', line, C.errno) }
		return condition
	}
}

fn long_value(value C.vpm_long) i64 {
	unsafe { result := i64(0); C.memcpy(&result, &value, 8); return result }
}

fn native_long(value i64) C.vpm_long {
	unsafe { result := C.vpm_long{}; C.memcpy(&result, &value, 8); return result }
}

fn read_file(path &char, buffer &char, capacity usize) isize {
	unsafe {
		fd := C.open(path, C.O_RDONLY)
		if fd < 0 { return -1 }
		length := usize(0)
		for length < capacity - 1 {
			count := C.read(fd, buffer + length, capacity - 1 - length)
			if count < 0 && C.errno == C.EINTR { continue }
			if count < 0 { C.close(fd); return -1 }
			if count == 0 { break }
			length += usize(count)
		}
		if C.close(fd) != 0 || length == capacity - 1 { return -1 }
		buffer[length] = 0
		return isize(length)
	}
}

fn slab_kib() i64 {
	unsafe {
		if read_file(c'/proc/meminfo', &pm_content[0], sizeof(pm_content)) < 0 { return -1 }
		line := &pm_content[0]
		for {
			value := C.vpm_long{}
			if C.sscanf(line, c'Slab: %ld kB', &value) == 1 { return long_value(value) }
			line = C.strchr(line, `\n`)
			if line == nil { break }
			line++
			if *line == 0 { break }
		}
		return -1
	}
}

fn deny_mount(target &char, kind &char) i32 {
	unsafe {
		C.errno = 0
		result := C.mount(c'proc', target, kind, 0, c'')
		if result == -1 && C.errno == C.EBUSY { return 0 }
		C.printf(c'PROC MOUNT UNEXPECTED: target=%s type=%s result=%d errno=%d\n', target, kind, result, C.errno)
		C.errno = 0
		length := read_file(c'/proc/self/mountinfo', &pm_content[0], sizeof(pm_content))
		C.printf(c'PROC MOUNT GRAPH: mountinfo_result=%zd errno=%d\n', length, C.errno)
		path := [128]char{}
		C.snprintf(&path[0], sizeof(path), c'%s/meminfo', target)
		C.errno = 0
		length = read_file(&path[0], &pm_content[0], sizeof(pm_content))
		C.printf(c'PROC MOUNT GRAPH: target_meminfo_result=%zd errno=%d\n', length, C.errno)
		return -1
	}
}

fn refuse_self_mounts(where &char, count i32) i32 {
	unsafe {
		held := C.open(c'/proc/meminfo', C.O_RDONLY)
		if !require(held >= 0, 67) { return 1 }
		for i := i32(0); i < 20; i++ {
			if !require(deny_mount(c'/proc', if i % 2 != 0 { c'procfs' } else { c'proc' }) == 0, 69) { return 1 }
		}
		if !require(read_file(c'/proc/self/mountinfo', &pm_before_mounts[0], sizeof(pm_before_mounts)) > 0, 71) { return 1 }
		if !require(deny_mount(c'/proc/sys', c'proc') == 0, 72) { return 1 }
		if !require(deny_mount(c'/proc/sys', c'procfs') == 0, 73) { return 1 }
		before := slab_kib()
		if !require(before >= 0, 75) { return 1 }
		for i := i32(0); i < count; i++ {
			if !require(deny_mount(c'/proc', if i % 2 != 0 { c'procfs' } else { c'proc' }) == 0, 77) { return 1 }
		}
		after := slab_kib()
		if !require(after >= 0 && after <= before + 16, 80) { return 1 }
		if !require(read_file(c'/proc/self/mountinfo', &pm_content[0], sizeof(pm_content)) > 0, 81) { return 1 }
		if !require(C.strcmp(&pm_content[0], &pm_before_mounts[0]) == 0, 82) { return 1 }
		if !require(C.read(held, &pm_content[0], sizeof(pm_content) - 1) > 0 && C.close(held) == 0, 83) { return 1 }
		if !require(read_file(c'/proc/meminfo', &pm_content[0], sizeof(pm_content)) > 0, 84) { return 1 }
		if !require(read_file(c'/proc/self/stat', &pm_content[0], sizeof(pm_content)) > 0, 85) { return 1 }
		C.printf(c'PROC MOUNT RETAINED: %s denials=%d slab_kib=%ld -> %ld\n', where, count, native_long(before), native_long(after))
		return 0
	}
}

fn namespace_init() i32 {
	unsafe {
		if !require(C.getpid() == 1, 91) { return 1 }
		if !require(C.mount(c'proc', c'/proc', c'proc', 0, c'') == 0, 94) { return 1 }
		link := [32]char{}
		length := C.readlink(c'/proc/self', &link[0], sizeof(link))
		if !require(length == 7 && C.memcmp(&link[0], c'/proc/1', 7) == 0, 97) { return 1 }
		if !require(refuse_self_mounts(c'pid-namespace', 1000) == 0, 98) { return 1 }
		return 0
	}
}

fn namespace_parent() i32 {
	unsafe {
		if !require(C.unshare(C.CLONE_NEWNS) == 0, 103) { return 1 }
		if !require(C.unshare(C.CLONE_NEWPID) == 0, 104) { return 1 }
		child := C.fork()
		if !require(child >= 0, 106) { return 1 }
		if child == 0 { C._exit(namespace_init()) }
		status := i32(0)
		for C.waitpid(child, &status, 0) < 0 { if !require(C.errno == C.EINTR, 109) { return 1 } }
		if !require(C.WIFEXITED(status) && C.WEXITSTATUS(status) == 0, 110) { return 1 }
		return 0
	}
}

fn reaped(child i32) i32 {
	unsafe {
		status := i32(0)
		for C.waitpid(child, &status, 0) < 0 { if !require(C.errno == C.EINTR, 116) { return 1 } }
		if !require(C.WIFEXITED(status) && C.WEXITSTATUS(status) == 0, 117) { return 1 }
		return 0
	}
}

fn stale_namespace_init(phase i32, ready i32, gate i32) i32 {
	unsafe {
		if !require(C.getpid() == 1, 122) { return 1 }
		link := [32]char{}
		if phase == 0 {
			if !require(C.mount(c'proc', c'/tmp/proc-stale', c'proc', 0, c'') == 0, 125) { return 1 }
			if !require(C.readlink(c'/tmp/proc-stale/self', &link[0], sizeof(link)) == 7 && C.memcmp(&link[0], c'/proc/1', 7) == 0, 127) { return 1 }
			return 0
		}
		if phase == 2 {
			if !require(C.mount(c'proc', c'/tmp/proc-fresh', c'procfs', 0, c'') == 0, 131) { return 1 }
			if !require(C.readlink(c'/tmp/proc-fresh/self', &link[0], sizeof(link)) == 7 && C.memcmp(&link[0], c'/proc/1', 7) == 0, 133) { return 1 }
			if !require(C.readlink(c'/tmp/proc-stale/self', &link[0], sizeof(link)) == 7 && C.memcmp(&link[0], c'/proc/1', 7) == 0, 137) { return 1 }
			return 0
		}
		if !require(C.write(ready, c'r', 1) == 1, 140) { return 1 }
		if !require(C.read(gate, &link[0], 1) == 1, 141) { return 1 }
		C.errno = 0
		if !require(C.readlink(c'/tmp/proc-stale/self', &link[0], sizeof(link)) == -1 && C.errno == C.ENOENT, 143) { return 1 }
		if !require(read_file(c'/proc/self/mountinfo', &pm_before_mounts[0], sizeof(pm_before_mounts)) > 0, 144) { return 1 }
		for i := i32(0); i < 128; i++ {
			if !require(deny_mount(c'/tmp/proc-stale', if i % 2 != 0 { c'procfs' } else { c'proc' }) == 0, 146) { return 1 }
			if !require(deny_mount(c'/tmp/proc-stale/sys', if i % 2 != 0 { c'procfs' } else { c'proc' }) == 0, 147) { return 1 }
		}
		C.errno = 0
		if !require(C.readlink(c'/tmp/proc-stale/self', &link[0], sizeof(link)) == -1 && C.errno == C.ENOENT, 150) { return 1 }
		if !require(read_file(c'/tmp/proc-stale/meminfo', &pm_content[0], sizeof(pm_content)) > 0, 151) { return 1 }
		if !require(read_file(c'/tmp/proc-stale/sys/kernel/ostype', &pm_content[0], sizeof(pm_content)) > 0, 152) { return 1 }
		if !require(read_file(c'/proc/self/mountinfo', &pm_content[0], sizeof(pm_content)) > 0 && C.strcmp(&pm_content[0], &pm_before_mounts[0]) == 0, 154) { return 1 }
		return 0
	}
}

fn spawn_stale_namespace(phase i32, ready i32, gate i32) i32 {
	unsafe {
		helper := C.fork()
		if helper != 0 { return helper }
		if C.unshare(C.CLONE_NEWPID) != 0 { C._exit(1) }
		init := C.fork()
		if init < 0 { C._exit(2) }
		if init == 0 { C._exit(stale_namespace_init(phase, ready, gate)) }
		C._exit(reaped(init))
		return 0
	}
}

fn stale_view_test() i32 {
	unsafe {
		if !require(C.mkdir(c'/tmp/proc-stale', 0o755) == 0, 171) { return 1 }
		if !require(C.mkdir(c'/tmp/proc-fresh', 0o755) == 0, 172) { return 1 }
		first := spawn_stale_namespace(0, -1, -1)
		if !require(first > 0 && reaped(first) == 0, 174) { return 1 }
		ready := [2]i32{}; gate := [2]i32{}
		if !require(C.pipe(&ready[0]) == 0 && C.pipe(&gate[0]) == 0, 176) { return 1 }
		peers := [4]i32{}
		for i := i32(0); i < 4; i++ {
			peers[i] = spawn_stale_namespace(1, ready[1], gate[0])
			if !require(peers[i] > 0, 180) { return 1 }
		}
		byte := char(0)
		for i := i32(0); i < 4; i++ { if !require(C.read(ready[0], &byte, 1) == 1, 183) { return 1 } }
		if !require(C.write(gate[1], c'gggg', 4) == 4, 184) { return 1 }
		for i := i32(0); i < 4; i++ { if !require(reaped(peers[i]) == 0, 185) { return 1 } }
		if !require(C.close(ready[0]) == 0 && C.close(ready[1]) == 0, 186) { return 1 }
		if !require(C.close(gate[0]) == 0 && C.close(gate[1]) == 0, 187) { return 1 }
		allowed := spawn_stale_namespace(2, -1, -1)
		if !require(allowed > 0 && reaped(allowed) == 0, 189) { return 1 }
		if !require(C.umount(c'/tmp/proc-fresh') == 0 && C.umount(c'/tmp/proc-stale') == 0, 190) { return 1 }
		if !require(C.rmdir(c'/tmp/proc-fresh') == 0 && C.rmdir(c'/tmp/proc-stale') == 0, 191) { return 1 }
		C.puts(c'PROC MOUNT PASS: inactive view reuse rejects self edges before retarget, concurrently')
		return 0
	}
}

fn run_tests() i32 {
	unsafe {
		$if proc_mount_reuse_only ? { return stale_view_test() }
		if !require(refuse_self_mounts(c'initial', 3000) == 0, 200) { return 1 }
		C.puts(c'PROC MOUNT PASS: self mounts fail without damaging proc paths or mountinfo')
		if !require(C.mkdir(c'/tmp/proc-alias', 0o755) == 0, 202) { return 1 }
		if !require(C.mount(c'proc', c'/tmp/proc-alias', c'proc', 0, c'') == 0, 203) { return 1 }
		if !require(read_file(c'/tmp/proc-alias/meminfo', &pm_content[0], sizeof(pm_content)) > 0, 204) { return 1 }
		C.errno = 0
		if !require(C.mount(c'proc', c'/tmp/proc-alias', c'proc', 0, c'') == -1 && C.errno == C.EBUSY, 206) { return 1 }
		if !require(C.mount(c'none', c'/tmp/proc-alias', nil, C.MS_REMOUNT | C.MS_RDONLY, c'') == 0, 207) { return 1 }
		if !require(read_file(c'/proc/meminfo', &pm_content[0], sizeof(pm_content)) > 0, 208) { return 1 }
		if !require(C.umount(c'/tmp/proc-alias') == 0 && C.rmdir(c'/tmp/proc-alias') == 0, 209) { return 1 }
		if !require(C.mkdir(c'/tmp/proc-bind', 0o755) == 0, 210) { return 1 }
		if !require(C.mount(c'/proc', c'/tmp/proc-bind', nil, C.MS_BIND, nil) == 0, 211) { return 1 }
		if !require(read_file(c'/tmp/proc-bind/meminfo', &pm_content[0], sizeof(pm_content)) > 0, 212) { return 1 }
		if !require(C.umount(c'/tmp/proc-bind') == 0 && C.rmdir(c'/tmp/proc-bind') == 0, 213) { return 1 }
		C.puts(c'PROC MOUNT PASS: independent aliases and remounts remain usable')
		if !require(stale_view_test() == 0, 215) { return 1 }
		C.fflush(C.stdout)
		child := C.fork()
		if !require(child >= 0, 218) { return 1 }
		if child == 0 { C._exit(namespace_parent()) }
		status := i32(0)
		for C.waitpid(child, &status, 0) < 0 { if !require(C.errno == C.EINTR, 221) { return 1 } }
		if !require(C.WIFEXITED(status) && C.WEXITSTATUS(status) == 0, 222) { return 1 }
		if !require(read_file(c'/proc/meminfo', &pm_content[0], sizeof(pm_content)) > 0, 223) { return 1 }
		C.puts(c'PROC MOUNT PASS: fresh PID namespace views remain mountable and reject cycles')
		C.puts(c'PROC MOUNT PASS: cached roots cannot cover their own descendants')
		return 0
	}
}

@[export: 'main']
pub fn entry() i32 {
	unsafe {
		$if amd64 {
			serial := C.open(c'/dev/com1', C.O_WRONLY | C.O_NOCTTY)
			if serial < 0 || C.dup2(serial, 1) < 0 || C.dup2(serial, 2) < 0 { return 1 }
			if serial > 2 { C.close(serial) }
		}
		C.setvbuf(C.stdout, nil, C._IONBF, 0)
		C.puts(c'PROC MOUNT START')
		result := run_tests()
		C.puts(if result != 0 { c'PROC MOUNT GUEST: FAIL' } else { c'PROC MOUNT GUEST: PASS' })
		C.sync()
		C.reboot(C.RB_POWER_OFF)
		return result
	}
}
