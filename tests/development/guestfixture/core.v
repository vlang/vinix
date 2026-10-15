// SPDX-License-Identifier: GPL-2.0-or-later
// Public CLI fixture. The job payload is this same V executable, dispatched
// only by an explicitly selected environment variable.
@[has_globals]
module guestfixture

#include <native-abi.h>
@[typedef]
struct C.FILE {}

struct C.utsname {
	sysname [65]char
}

struct C.stat {
	st_uid  u32
	st_mode u32
	st_size i64
	st_ino  u64
}

@[c_extern]
__global C.stdout &C.FILE

fn C.getuid() u32
fn C.geteuid() u32
fn C.getgid() u32
fn C.getegid() u32
fn C.setgroups(usize, voidptr) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.chmod(&char, u32) i32
fn C.chown(&char, u32, u32) i32
fn C.chdir(&char) i32
fn C.open(&char, i32, ...) i32
fn C.read(i32, voidptr, usize) isize
fn C.fstat(i32, &C.stat) i32
fn C.stat(&char, &C.stat) i32
fn C.uname(&C.utsname) i32
fn C.write(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.dup2(i32, i32) i32
fn C.fork() i32
fn C.execv(&char, &&char) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) i32
fn C.WEXITSTATUS(i32) i32
fn C.getenv(&char) &char
fn C.setenv(&char, &char, i32) i32
fn C.strcmp(&char, &char) i32
fn C.strstr(&char, &char) &char
fn C.symlink(&char, &char) i32
fn C.unlink(&char) i32
fn C.puts(&char) i32
fn C.printf(&char, ...) i32
fn C.snprintf(&char, usize, &char, ...) i32
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.readlink(&char, voidptr, usize) isize
fn C.lseek(i32, i64, i32) i64
fn C.setvbuf(&C.FILE, &char, i32, usize) i32
fn C.__errno_location() &i32
fn C._exit(i32)
fn C.pause() i32

fn check(ok bool, line int) {
	if !ok {
		unsafe { C.printf(c'DEVELOPMENT GUEST FAIL line=%d errno=%d\n', line, *C.__errno_location()) }
		C._exit(1)
	}
}

fn require_vinix() {
	mut kernel := C.utsname{}
	check(C.uname(unsafe { &kernel }) == 0
		&& C.strcmp(unsafe { &kernel.sysname[0] }, c'Vinix') == 0, 153)
}

fn write_text(path &char, value &char, length usize) {
	unsafe {
		fd := C.open(path, C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600))
		check(fd >= 0 && C.write(fd, value, length) == isize(length) && C.close(fd) == 0, 62)
	}
}

fn job_payload() i32 {
	unsafe {
		token := C.getenv(c'TEST_TOKEN')
		check(C.getuid() == 1000 && C.geteuid() == 1000 && C.getgid() == 1000 && C.getegid() == 1000, 69)
		check(token != nil && C.strcmp(token, c'vinix-native-fixture-secret') == 0, 70)
		check(C.getenv(c'UNSELECTED_PARENT_SECRET') == nil, 71)
		write_text(c'/home/developer/payload.done', c'completed', 9)
		// Both streams must be discarded by the scheduler, not saved in logs.
		C.puts(c'vinix-native-fixture-secret')
		C.write(2, c'vinix-native-fixture-secret\n', 28)
		return 0
	}
}

fn build_payload() i32 {
	unsafe {
		check(C.getuid() == 1000 && C.geteuid() == 1000, 190)
		check(C.strcmp(C.getenv(c'SOURCE_DATE_EPOCH'), c'1700000000') == 0, 191)
		check(C.getenv(c'UNSELECTED_PARENT_SECRET') == nil, 192)
		for name in [&char(c'HOME'), &char(c'TMPDIR')]! {
			path := C.getenv(name)
			mut st := C.stat{}
			check(path != nil && C.stat(path, &st) == 0 && st.st_uid == 1000 && st.st_mode & 0o777 == 0o700, 197)
		}
		mut data := [64]char{}
		fd := C.open(c'internal-link', C.O_RDONLY)
		check(fd >= 0 && C.read(fd, &data[0], 63) == 20 && C.close(fd) == 0, 195)
		check(C.memcmp(&data[0], c'build-fixture-input\n', 20) == 0, 196)
		write_text(c'artifact.txt', &data[0], 20)
		return 0
	}
}

fn command(program &char, action &char, argument &char, extra &char) i32 {
	return command_output(program, action, argument, extra, unsafe { nil })
}

fn command_output(program &char, action &char, argument &char, extra &char, output &char) i32 {
	unsafe {
		mut argv := [5]&char{}
		argv[0] = program
		argv[1] = action
		argv[2] = argument
		argv[3] = extra
		pid := C.fork()
		check(pid >= 0, 91)
		if pid == 0 {
			if output != nil {
				fd := C.open(output, C.O_WRONLY | C.O_CREAT | C.O_TRUNC, u32(0o600))
				if fd < 0 || C.dup2(fd, 1) != 1 || C.dup2(fd, 2) != 2 { C._exit(125) }
				if fd > 2 { C.close(fd) }
			}
			C.execv(program, &argv[0])
			C._exit(127)
		}
		mut status := i32(0)
		check(C.waitpid(pid, &status, 0) == pid && C.WIFEXITED(status) != 0, 97)
		return C.WEXITSTATUS(status)
	}
}

fn private_receipt(path &char, expected &char) {
	emit_receipt(path, expected, true)
}

fn emit_receipt(path &char, expected &char, owner_only_file bool) {
	unsafe {
		mut text := [32768]char{}
		fd := C.open(path, C.O_RDONLY)
		check(fd >= 0, 106)
		count := C.read(fd, &text[0], text.len - 1)
		mut st := C.stat{}
		check(C.fstat(fd, &st) == 0 && st.st_uid == 1000
			&& (!owner_only_file || st.st_mode & 0o077 == 0), 107)
		check(count > 0 && count < text.len - 1 && C.close(fd) == 0, 108)
		check(C.strstr(&text[0], c'vinix-native-fixture-secret') == nil, 109)
		check(C.strstr(&text[0], expected) != nil, 110)
		// JSON encoders escape newlines within strings. Remove formatting
		// line breaks so the full native receipt remains one serial record.
		mut used := 0
		for i := 0; i < count; i++ {
			if text[i] == char(10) || text[i] == char(13) { continue }
			text[used] = text[i]
			used++
		}
		text[used] = 0
		C.printf(c'DEVELOPMENT RECEIPT %s %s\n', path, &text[0])
	}
}

fn emit_command_log(path &char) {
	unsafe {
		fd := C.open(path, C.O_RDONLY)
		if fd < 0 { return }
		mut text := [8192]char{}
		count := C.read(fd, &text[0], text.len - 1)
		check(count >= 0, 255)
		check(C.strstr(&text[0], c'vinix-native-fixture-secret') == nil, 256)
		C.printf(c'DEVELOPMENT COMMAND LOG %s\n%s\n', path, &text[0])
		mut st := C.stat{}
		check(C.fstat(fd, &st) == 0, 309)
		if st.st_size > text.len - 1 {
			check(C.lseek(fd, -i64(text.len - 1), C.SEEK_END) >= 0, 310)
			text = [8192]char{}
			tail := C.read(fd, &text[0], text.len - 1)
			check(tail >= 0 && C.strstr(&text[0], c'vinix-native-fixture-secret') == nil, 311)
			C.printf(c'DEVELOPMENT COMMAND LOG TAIL %s\n%s\n', path, &text[0])
		}
		check(C.close(fd) == 0, 312)
	}
}

fn command_log_checks() {
	unsafe {
		mut text := [16384]char{}
		head := &char(c'DEVELOPMENT LOG HEAD SENTINEL')
		tail := &char(c'DEVELOPMENT LOG TAIL SENTINEL')
		for i in 0 .. 29 { text[i] = head[i] }
		for i in 0 .. 29 { text[8193 + i] = tail[i] }
		write_text(c'/home/developer/log-fixture.log', &text[0], usize(text.len))
		emit_command_log(c'/home/developer/log-fixture.log')
	}
}

fn build_checks() {
	unsafe {
		check(C.symlink(c'input.txt', c'/home/developer/source/internal-link') == 0, 209)
		check(command_output(c'/usr/bin/vinix-build', c'hash', c'/home/developer/source', nil, c'/home/developer/source.sha') == 0, 210)
		mut hash := [66]char{}
		fd := C.open(c'/home/developer/source.sha', C.O_RDONLY)
		check(fd >= 0 && C.read(fd, &hash[0], 65) == 65 && C.close(fd) == 0 && hash[64] == char(10), 213)
		for i in 0 .. 64 {
			check((hash[i] >= char(`0`) && hash[i] <= char(`9`)) || (hash[i] >= char(`a`) && hash[i] <= char(`f`)), 214)
		}
		hash[64] = 0
		mut template := [4096]char{}
		input := C.open(c'/home/developer/build-template.json', C.O_RDONLY)
		length := C.read(input, &template[0], 4095)
		check(input >= 0 && length > 0 && length < 4095 && C.close(input) == 0, 219)
		mut plan := [4096]char{}
		written := C.snprintf(&plan[0], plan.len, &template[0], &hash[0])
		check(written > 0 && written < plan.len, 222)
		write_text(c'/home/developer/build.json', &plan[0], usize(written))
		for output in [&char(c'/home/developer/build-a'), &char(c'/home/developer/build-b')]! {
			check(command(c'/usr/bin/vinix-build', c'build', c'/home/developer/build.json', output) == 0, 225)
			mut st := C.stat{}
			check(C.stat(output, &st) == 0 && st.st_uid == 1000 && st.st_mode & 0o777 == 0o700, 226)
		}
		emit_receipt(c'/home/developer/build-a/receipt.json', c'"complete": true', false)
		emit_receipt(c'/home/developer/build-b/receipt.json', c'"complete": true', false)
		mut link := [32]char{}
		check(C.readlink(c'/home/developer/build-a/work/internal-link', &link[0], 31) == 9 && C.strcmp(&link[0], c'input.txt') == 0, 230)
		mut first := [21]char{}
		mut second := [21]char{}
		a := C.open(c'/home/developer/build-a/work/artifact.txt', C.O_RDONLY)
		b := C.open(c'/home/developer/build-b/work/artifact.txt', C.O_RDONLY)
		check(a >= 0 && b >= 0 && C.read(a, &first[0], 20) == 20 && C.read(b, &second[0], 20) == 20, 235)
		check(C.close(a) == 0 && C.close(b) == 0 && C.memcmp(&first[0], &second[0], 20) == 0, 236)
		check(C.memcmp(&first[0], c'build-fixture-input\n', 20) == 0, 237)
		write_text(c'/home/developer/source/input.txt', c'changed\n', 8)
		check(command(c'/usr/bin/vinix-build', c'build', c'/home/developer/build.json', c'/home/developer/refused') == 1, 239)
		check(C.open(c'/home/developer/refused/work/artifact.txt', C.O_RDONLY) == -1, 240)
		C.puts(c'DEVELOPMENT BUILD PASS: UID 1000, pinned closure, preserved link, epoch, two matching artifacts, changed-input refusal')
	}
}

fn cpu_output_checks(path &char) {
	unsafe {
		mut text := [8192]char{}
		log := C.open(path, C.O_RDONLY)
		count := C.read(log, &text[0], text.len - 1)
		check(log >= 0 && count > 0 && count < text.len - 1 && C.close(log) == 0, 270)
		C.printf(c'DEVELOPMENT CPU OUTPUT %s\n%s\n', path, &text[0])
		$if arm64 {
			check(C.strstr(&text[0], c'Architecture:     aarch64\n') != nil
				&& C.strstr(&text[0], c'Flags:            Unknown') == nil, 272)
		} $else {
			check(C.strstr(&text[0], c'Architecture:     x86_64\n') != nil, 273)
		}
		// Independently count processor records from the guest's procfs.
		mut cpuinfo := [16384]char{}
		fd := C.open(c'/proc/cpuinfo', C.O_RDONLY)
		bytes := C.read(fd, &cpuinfo[0], cpuinfo.len - 1)
		check(fd >= 0 && bytes > 0 && bytes < cpuinfo.len - 1 && C.close(fd) == 0, 274)
		mut processors := 0
		mut cursor := &cpuinfo[0]
		for {
			found := C.strstr(cursor, c'processor\t: ')
			if found == nil { break }
			processors++
			cursor = found + 1
		}
		mut expected := [128]char{}
		C.snprintf(&expected[0], expected.len, c'CPU Count:        %d\n', processors)
		check(processors > 0 && C.strstr(&text[0], &expected[0]) != nil, 275)
	}
}

fn package_checks(output &char) {
	unsafe {
		mut path := [512]char{}
		C.snprintf(&path[0], path.len, c'%s/work/package-bin', output)
		mut st := C.stat{}
		check(C.stat(&path[0], &st) == 0 && st.st_uid == 1000 && st.st_mode & 0o111 != 0, 280)
		for name in [&char(c'help-v'), &char(c'help-package')]! {
			C.snprintf(&path[0], path.len, c'%s/%s.log', output, name)
			mut help := [8192]char{}
			fd := C.open(&path[0], C.O_RDONLY)
			length := C.read(fd, &help[0], help.len - 1)
			expected := if C.strcmp(name, c'help-v') == 0 { &char(c'V is a tool for managing V source code.') } else { &char(c'usage: vinix-package') }
			check(fd >= 0 && length > 0 && length < help.len - 1 && C.close(fd) == 0
				&& C.strstr(&help[0], expected) != nil, 281)
		}
		C.snprintf(&path[0], path.len, c'%s/work/release/index.json', output)
		emit_receipt(&path[0], c'org.vinix.native-lscpu', false)
		C.snprintf(&path[0], path.len, c'%s/work/release/index.sig', output)
		mut signature := [130]char{}
		fd_sig := C.open(&path[0], C.O_RDONLY)
		check(fd_sig >= 0 && C.fstat(fd_sig, &st) == 0 && st.st_uid == 1000
			&& C.read(fd_sig, &signature[0], 130) == 129 && C.close(fd_sig) == 0
			&& signature[128] == char(10), 282)
		for i in 0 .. 128 {
			check((signature[i] >= char(`0`) && signature[i] <= char(`9`))
				|| (signature[i] >= char(`a`) && signature[i] <= char(`f`)), 283)
		}
		signature[128] = 0
		mut executable := [512]char{}
		mut log := [512]char{}
		C.snprintf(&executable[0], executable.len, c'%s/work/lscpu-bin', output)
		C.snprintf(&log[0], log.len, c'%s/lscpu.sha', output)
		check(command_output(c'/usr/bin/vinix-build', c'hash', &executable[0], nil, &log[0]) == 0, 284)
		mut hash := [66]char{}
		fd_hash := C.open(&log[0], C.O_RDONLY)
		check(fd_hash >= 0 && C.read(fd_hash, &hash[0], hash.len) == 65
			&& C.close(fd_hash) == 0 && hash[64] == char(10), 285)
		hash[64] = 0
		C.snprintf(&executable[0], executable.len, c'%s/work/release/objects/%s', output, &hash[0])
		check(C.stat(&executable[0], &st) == 0 && st.st_uid == 1000 && st.st_mode & 0o777 == 0o644, 286)
		bytes := u64(st.st_size)
		check(command_output(c'/usr/bin/vinix-build', c'hash', &executable[0], nil, &log[0]) == 0, 287)
		mut object_hash := [66]char{}
		fd_object := C.open(&log[0], C.O_RDONLY)
		check(fd_object >= 0 && C.read(fd_object, &object_hash[0], object_hash.len) == 65
			&& C.close(fd_object) == 0 && object_hash[64] == char(10), 288)
		object_hash[64] = 0
		check(C.strcmp(&hash[0], &object_hash[0]) == 0, 289)
		C.printf(c'DEVELOPMENT RECEIPT %s {"signature":"%s","object_sha256":"%s","object_bytes":%zu}\n',
			&path[0], &signature[0], &object_hash[0], usize(bytes))
		C.snprintf(&path[0], path.len, c'%s/work/release/publisher.seed', output)
		check(C.open(&path[0], C.O_RDONLY) == -1, 290)
		C.snprintf(&path[0], path.len, c'%s/work/release/.publisher', output)
		check(C.open(&path[0], C.O_RDONLY) == -1, 291)
	}
}

fn assertion_checks(output &char) {
	unsafe {
		mut executable := [512]char{}
		mut log := [512]char{}
		C.snprintf(&executable[0], executable.len, c'%s/work/assert-bin', output)
		C.snprintf(&log[0], log.len, c'%s/assert-failure.log', output)
		mut st := C.stat{}
		check(C.stat(&executable[0], &st) == 0 && st.st_uid == 1000 && st.st_mode & 0o111 != 0, 301)
		check(command_output(&executable[0], nil, nil, nil, &log[0]) == 1, 302)
		mut text := [2048]char{}
		fd := C.open(&log[0], C.O_RDONLY)
		count := C.read(fd, &text[0], text.len - 1)
		check(fd >= 0 && count > 0 && count < text.len - 1 && C.close(fd) == 0
			&& C.strstr(&text[0], c'assert-failure.v:2: FAIL: fn main.main: assert 1 == 2') != nil
			&& C.strstr(&text[0], c'V panic: Assertion failed...') != nil
			&& C.strstr(&text[0], c'/home/developer/') == nil, 303)
		emit_command_log(&log[0])
	}
}

fn selfhost_checks(output &char) {
	unsafe {
		mut path := [512]char{}
		C.snprintf(&path[0], path.len, c'%s/work/compiler/v', output)
		mut st := C.stat{}
		check(C.stat(&path[0], &st) == 0 && st.st_uid == 1000 && st.st_mode & 0o111 != 0, 304)
		C.snprintf(&path[0], path.len, c'%s/version-selfhost-v.log', output)
		mut version := [128]char{}
		fd := C.open(&path[0], C.O_RDONLY)
		count := C.read(fd, &version[0], version.len - 1)
		check(fd >= 0 && count > 0 && count < version.len - 1 && C.close(fd) == 0
			&& C.strstr(&version[0], c'V 0.') != nil, 305)
		mut revision := [66]char{}
		fd_revision := C.open(c'/usr/lib/vlang/VERSION', C.O_RDONLY)
		bytes := C.read(fd_revision, &revision[0], revision.len)
		check(fd_revision >= 0 && bytes in [isize(41), isize(65)]!
			&& C.close(fd_revision) == 0 && revision[bytes - 1] == char(10), 306)
		revision[7] = 0
		check(C.strstr(&version[0], &revision[0]) != nil, 307)
		emit_command_log(&path[0])
	}
}

fn native_userland_checks() {
	unsafe {
		marker := C.open(c'/home/developer/selfhost-v', C.O_RDONLY)
		selfhost := marker >= 0
		if selfhost { check(C.close(marker) == 0, 308) }
		private_receipt(c'/home/developer/native-build.json', c'/home/developer/native-source')
		for output in [&char(c'/home/developer/native-a'), &char(c'/home/developer/native-b')]! {
			status := command(c'/usr/bin/vinix-build', c'build', c'/home/developer/native-build.json', output)
			mut path := [256]char{}
			check(C.snprintf(&path[0], path.len, c'%s/receipt.json', output) > 0, 261)
			if status != 0 {
				emit_command_log(c'/proc/meminfo')
				emit_command_log(c'/proc/self/limits')
				emit_command_log(c'/proc/kernel-resources')
				check(command(c'/bin/busybox', c'ls', c'-la', c'/opt/native/lib') == 0, 268)
				check(command_output(c'/usr/bin/vinix-build', c'hash', c'/opt/native', nil, c'/home/developer/sdk-pin.sha') == 0, 269)
				emit_command_log(c'/home/developer/sdk-pin.sha')
				for step in [&char(c'translate-selfhost-v'), &char(c'compile-selfhost-v'), &char(c'version-selfhost-v'), &char(c'help-v'), &char(c'compile-assertion'), &char(c'compile-fetch'), &char(c'compile-mount'), &char(c'compile-chsh'), &char(c'compile-lscpu'), &char(c'compile-init'), &char(c'inspect-lscpu'),
					&char(c'compile-package'), &char(c'help-package'), &char(c'pack-package'), &char(c'publish-package')]! {
					C.snprintf(&path[0], path.len, c'%s/%s.log', output, step)
					emit_command_log(&path[0])
				}
				C.snprintf(&path[0], path.len, c'%s/receipt.json', output)
				emit_receipt(&path[0], c'Vinix', false)
			}
			check(status == 0, 262)
			C.snprintf(&path[0], path.len, c'%s/receipt.json', output)
			emit_receipt(&path[0], c'Vinix', false)
			for directory in [&char(c'.'), &char(c'home'), &char(c'tmp')]! {
				C.snprintf(&path[0], path.len, c'%s/%s', output, directory)
				mut st := C.stat{}
				check(C.stat(&path[0], &st) == 0 && st.st_uid == 1000 && st.st_mode & 0o777 == 0o700, 263)
			}
			for name in [&char(c'fetch'), &char(c'mount'), &char(c'chsh'), &char(c'lscpu'), &char(c'init')]! {
				C.snprintf(&path[0], path.len, c'%s/work/%s-bin', output, name)
				fd := C.open(&path[0], C.O_RDONLY)
				mut elf := [20]u8{}
				mut st := C.stat{}
				check(fd >= 0 && C.fstat(fd, &st) == 0 && st.st_uid == 1000 && st.st_mode & 0o111 != 0, 264)
				check(C.read(fd, &elf[0], elf.len) == elf.len && C.close(fd) == 0
					&& elf[0] == 0x7f && elf[1] == `E` && elf[2] == `L` && elf[3] == `F`
					&& elf[4] == 2 && elf[5] == 1, 265)
				C.snprintf(&path[0], path.len, c'%s/run-%s.log', output, name)
				log := C.open(&path[0], C.O_RDONLY)
				mut text := [128]char{}
				mut expected := [128]char{}
				if C.strcmp(name, c'init') == 0 {
					C.snprintf(&expected[0], expected.len, c'init from Vinix\n')
				} else {
					C.snprintf(&expected[0], expected.len, c'%s from util-vinix\n', name)
				}
				count := C.read(log, &text[0], text.len - 1)
				check(log >= 0 && count > 0 && count < text.len - 1 && C.close(log) == 0
					&& C.strcmp(&text[0], &expected[0]) == 0, 266)
			}
			C.snprintf(&path[0], path.len, c'%s/inspect-lscpu.log', output)
			cpu_output_checks(&path[0])
			assertion_checks(output)
			package_checks(output)
			if selfhost { selfhost_checks(output) }
		}
		C.puts(c'DEVELOPMENT USERLAND PASS: UID 1000, pinned SDK/V/runtime, two fresh workspaces, fetch/mount/chsh/lscpu/init compiled and executed, procfs CPU count matched')
		C.puts(c'DEVELOPMENT PACKAGES PASS: UID 1000, native package CLI, compiled lscpu payload, signed releases in two workspaces, verified copied objects')
		if selfhost {
			C.puts(c'DEVELOPMENT SELFHOST PASS: UID 1000, V compiler rebuilt twice, matching version, rebuilt compiler used for userland and signed packages')
		}
	}
}

fn account_checks() {
	unsafe {
		check(C.setgroups(0, nil) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0, 116)
		check(C.chdir(c'/home/developer') == 0, 117)
		command_log_checks()
		signal_identity_checks()
		check(C.setenv(c'UNSELECTED_PARENT_SECRET', c'parent-must-not-reach-job', 1) == 0, 118)
		for program in [&char(c'/usr/bin/vinix-build'), &char(c'/usr/bin/vinix-qualify'),
			&char(c'/usr/bin/vinix-vm'), &char(c'/usr/bin/vinix-jobs')]! {
			check(command(program, c'--help', nil, nil) == 0, 120)
		}
		v_smoke := C.open(c'/usr/bin/v-smoke', C.O_RDONLY)
		if v_smoke >= 0 {
			check(C.close(v_smoke) == 0, 293)
			check(command_output(c'/usr/bin/v-smoke', c'--help', nil, nil, c'/home/developer/v-help.log') == 0
				&& command_output(c'/usr/bin/v-smoke', c'--version', nil, nil, c'/home/developer/v-version.log') == 0, 294)
			mut help := [8192]char{}
			fd_help := C.open(c'/home/developer/v-help.log', C.O_RDONLY)
			length := C.read(fd_help, &help[0], help.len - 1)
			check(fd_help >= 0 && length > 0 && length < help.len - 1 && C.close(fd_help) == 0
				&& C.strstr(&help[0], c'V is a tool for managing V source code.') != nil, 295)
			mut version := [128]char{}
			fd_version := C.open(c'/home/developer/v-version.log', C.O_RDONLY)
			bytes := C.read(fd_version, &version[0], version.len - 1)
			check(fd_version >= 0 && bytes > 0 && bytes < version.len - 1 && C.close(fd_version) == 0
				&& C.strstr(&version[0], c'V 0.') != nil, 296)
			mut revision := [66]char{}
			fd_revision := C.open(c'/usr/lib/vlang/VERSION', C.O_RDONLY)
			count := C.read(fd_revision, &revision[0], revision.len)
			check(fd_revision >= 0 && count in [isize(41), isize(65)]!
				&& C.close(fd_revision) == 0 && revision[count - 1] == char(10), 297)
			for i in 0 .. count - 1 {
				check((revision[i] >= char(`0`) && revision[i] <= char(`9`))
					|| (revision[i] >= char(`a`) && revision[i] <= char(`f`)), 298)
			}
			revision[7] = 0
			check(C.strstr(&version[0], &revision[0]) != nil, 299)
			emit_command_log(c'/home/developer/v-version.log')
			C.puts(c'DEVELOPMENT V SMOKE PASS: UID 1000, prepared compiler, matching version revision and help assets')
		}
		cpu := C.open(c'/usr/bin/lscpu-smoke', C.O_RDONLY)
		if cpu >= 0 {
			check(C.close(cpu) == 0, 276)
			check(command_output(c'/usr/bin/lscpu-smoke', nil, nil, nil, c'/home/developer/lscpu-smoke.log') == 0, 277)
			cpu_output_checks(c'/home/developer/lscpu-smoke.log')
			C.puts(c'DEVELOPMENT CPU PASS: UID 1000, prepared lscpu ELF, procfs CPU count matched')
		}
		check(command(c'/usr/bin/vinix-jobs', c'init', c'/home/developer/jobs.json', c'/home/developer/good') == 0, 123)
		check(command(c'/usr/bin/vinix-jobs', c'run-due', c'/home/developer/good', nil) == 0, 124)
		private_receipt(c'/home/developer/good/state.json', c'"runs":1')
		private_receipt(c'/home/developer/good/plan.json', c'TEST_TOKEN')
		check(command(c'/usr/bin/vinix-jobs', c'run-due', c'/home/developer/good', nil) == 0, 127)
		private_receipt(c'/home/developer/good/state.json', c'"runs":1')
		mut proof := [10]char{}
		fd := C.open(c'/home/developer/payload.done', C.O_RDONLY)
		check(fd >= 0 && C.read(fd, &proof[0], 9) == 9 && C.close(fd) == 0 && C.strcmp(&proof[0], c'completed') == 0, 131)
		check(C.unlink(c'/home/developer/payload.done') == 0, 132)
		check(C.chmod(c'/home/developer/token', 0o644) == 0, 133)
		check(command(c'/usr/bin/vinix-jobs', c'init', c'/home/developer/jobs.json', c'/home/developer/public-token') == 0, 134)
		check(command(c'/usr/bin/vinix-jobs', c'run-due', c'/home/developer/public-token', nil) == 1, 135)
		private_receipt(c'/home/developer/public-token/state.json', c'private file must be regular')
		check(C.open(c'/home/developer/payload.done', C.O_RDONLY) == -1, 137)
		check(C.chmod(c'/home/developer/token', 0o600) == 0, 138)
		check(C.symlink(c'token', c'/home/developer/token-link') == 0, 139)
		check(command(c'/usr/bin/vinix-jobs', c'init', c'/home/developer/link-jobs.json', c'/home/developer/link-token') == 0, 140)
		check(command(c'/usr/bin/vinix-jobs', c'run-due', c'/home/developer/link-token', nil) == 1, 141)
		private_receipt(c'/home/developer/link-token/state.json', c'cannot open private file')
		check(C.open(c'/home/developer/payload.done', C.O_RDONLY) == -1, 143)
		C.puts(c'DEVELOPMENT ACCOUNT PASS: UID 1000 jobs, credentials, environment, receipts, interval, unsafe-file refusal')
		private_file_checks()
		service_export_checks()
		job_lifecycle_checks()
		build_checks()
		reference_checks()
		sdk := C.open(c'/home/developer/qualify-sdk', C.O_RDONLY)
		if sdk >= 0 {
			mut profiles := [64]char{}
			count := C.read(sdk, &profiles[0], profiles.len - 1)
			check(count > 0 && count < profiles.len - 1 && C.close(sdk) == 0, 257)
			check(C.setenv(c'PATH', c'/usr/bin:/bin:/opt/native/bin', 1) == 0, 251)
			C.puts(c'DEVELOPMENT COMPILER VERSIONS:')
			check(C.setenv(c'VINIX_QUALIFY_TIMEOUT_SECONDS', c'600', 1) == 0, 300)
			check(command(c'/usr/bin/cc', c'--version', nil, nil) == 0, 253)
			check(command(c'/usr/bin/c++', c'--version', nil, nil) == 0, 254)
			if C.strstr(&profiles[0], c',v') != nil {
				check(command(c'/usr/bin/v', c'version', nil, nil) == 0, 258)
			}
			status := command(c'/usr/bin/vinix-qualify', c'--require-vinix', c'/home/developer/qualification', &profiles[0])
			emit_receipt(c'/home/developer/qualification/report.json', c'vinix-native', false)
			if status != 0 {
				for path in [&char(c'/home/developer/qualification/c/command-0.log'),
					&char(c'/home/developer/qualification/c/command-1.log'),
					&char(c'/home/developer/qualification/cpp/command-0.log'),
					&char(c'/home/developer/qualification/cpp/command-1.log'),
					&char(c'/home/developer/qualification/v/command-0.log'),
					&char(c'/home/developer/qualification/v/command-1.log')]! { emit_command_log(path) }
			}
			check(status == 0, 252)
			C.printf(c'DEVELOPMENT TOOLCHAINS PASS: UID 1000, profiles %s, compilation and executed artifacts\n', &profiles[0])
			if C.strstr(&profiles[0], c',v') != nil { native_userland_checks() }
		}
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		C.setvbuf(C.stdout, nil, C._IONBF, 0)
		mode := C.getenv(c'VINIX_DEVELOPMENT_PAYLOAD')
		if mode != nil {
			if C.strcmp(mode, c'build') == 0 { return build_payload() }
			if C.strcmp(mode, c'ci-check') == 0 { return ci_payload() }
			if C.strcmp(mode, c'linger') == 0 || C.strcmp(mode, c'tick') == 0 || C.strcmp(mode, c'recover') == 0 {
				return lifecycle_payload(mode)
			}
			return job_payload()
		}
		require_vinix()
		ci_prepare()
		jit_approved := reference_jit_prepare()
		check(C.chown(c'/home/developer', 1000, 1000) == 0 && C.chmod(c'/home/developer', 0o700) == 0, 154)
		for path in [&char(c'/home/developer/token'), &char(c'/home/developer/jobs.json'),
			&char(c'/home/developer/link-jobs.json'), &char(c'/home/developer/fifo-jobs.json'), &char(c'/home/developer/build-template.json')]! {
			check(C.chown(path, 1000, 1000) == 0 && C.chmod(path, 0o600) == 0, 156)
		}
		for name in [&char(c'deadline'), &char(c'term'), &char(c'int'), &char(c'watch'), &char(c'interrupted')]! {
			mut path := [256]char{}
			C.snprintf(&path[0], path.len, c'/home/developer/%s-jobs.json', name)
			check(C.chown(&path[0], 1000, 1000) == 0 && C.chmod(&path[0], 0o600) == 0, 361)
		}
		reference_plan := C.open(c'/home/developer/reference-build.json', C.O_RDONLY)
		if reference_plan >= 0 {
			check(C.close(reference_plan) == 0 && C.chown(c'/home/developer/reference-build.json', 1000, 1000) == 0
				&& C.chmod(c'/home/developer/reference-build.json', 0o600) == 0, 382)
		}
		check(C.chown(c'/home/developer/source', 1000, 1000) == 0 && C.chmod(c'/home/developer/source', 0o755) == 0, 177)
		check(C.chown(c'/home/developer/source/input.txt', 1000, 1000) == 0 && C.chmod(c'/home/developer/source/input.txt', 0o644) == 0, 178)
		native_plan := C.open(c'/home/developer/native-build.json', C.O_RDONLY)
		if native_plan >= 0 {
			check(C.close(native_plan) == 0 && C.chown(c'/home/developer/native-build.json', 1000, 1000) == 0
				&& C.chmod(c'/home/developer/native-build.json', 0o600) == 0, 267)
			check(C.chown(c'/home/developer/publisher.seed', 1000, 1000) == 0
				&& C.chmod(c'/home/developer/publisher.seed', 0o600) == 0, 292)
		}
		// Even root must not silently run a schedule labelled as another account.
		check(command(c'/usr/bin/vinix-jobs', c'init', c'/home/developer/jobs.json', c'/root/wrong-owner') == 1, 159)
		pid := C.fork()
		check(pid >= 0, 161)
		if pid == 0 {
			account_checks()
			C._exit(0)
		}
		mut status := i32(0)
		// The fixture is PID 1: reap descendants orphaned by group retirement
		// while the account checks continue, so their PID probes can settle.
		for {
			reaped := C.waitpid(-1, &status, C.WNOHANG)
			check(reaped >= 0 || *C.__errno_location() == C.EINTR, 362)
			if reaped == pid { check(status == 0, 164); break }
			if reaped <= 0 { C.usleep(10000) }
		}
		reference_jit_revoke(jit_approved)
		C.puts(c'DEVELOPMENT GUEST PASS')
		for { C.pause() }
		return 0
	}
}
