module androidhost

import os

#include "@DIR/probe_spawn_abi.h"
#include <sys/wait.h>
#include <dirent.h>

fn C.posix_spawn(&i32, &char, voidptr, voidptr, &&char, &&char) i32
fn C.posix_spawnp(&i32, &char, voidptr, voidptr, &&char, &&char) i32
fn C.posix_spawn_file_actions_init(voidptr) i32
fn C.posix_spawn_file_actions_destroy(voidptr) i32
fn C.posix_spawn_file_actions_addclose(voidptr, i32) i32
fn C.posix_spawn_file_actions_adddup2(voidptr, i32, i32) i32
fn C.getdtablesize() i32
fn C.posix_spawnattr_init(voidptr) i32
fn C.posix_spawnattr_destroy(voidptr) i32
fn C.posix_spawnattr_setsigdefault(voidptr, voidptr) i32
fn C.posix_spawnattr_setflags(voidptr, i16) i32
fn C.posix_spawnattr_setbinpref_np(voidptr, usize, &i32, &usize) i32

@[typedef]
struct C.posix_spawnattr_t {}

@[typedef]
struct C.posix_spawn_file_actions_t {}

fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) i32
fn C.WEXITSTATUS(i32) i32
fn C.WTERMSIG(i32) i32
fn C.openat(i32, &char, i32, ...int) i32
fn C.fstatat(i32, &char, &C.stat, i32) i32
fn C.unlinkat(i32, &char, i32) i32
fn C.fdopendir(i32) &C.DIR

pub struct ProbeExit {
	message string
}

pub fn (e ProbeExit) msg() string { return e.message }

pub fn (e ProbeExit) code() int { return 0 }

pub struct ProbeCommandError {
	arguments []string
	status    int
}

pub struct ProbeFilesystemError {
	message string
}

pub fn (e ProbeFilesystemError) msg() string { return e.message }

pub fn (e ProbeFilesystemError) code() int { return 0 }

pub fn (e ProbeCommandError) msg() string { return 'Compiler command failed' }

pub fn (e ProbeCommandError) code() int { return e.status }

const probe_r8_sha = '900dfbc649519969fc5a4c7520d6b7355338e565fa1249874e0190b8d61b1199'
const probe_core_sha = 'f47736d9d410766a20ae1f60d679607d8e85241e8cdeb5a0c040ab260ba68f42'

fn probe_command(arguments []string) ! {
	probe_command_output(arguments, false)!
}

fn probe_command_output(arguments []string, capture bool) !string {
	return probe_command_output_preferred(arguments, capture, '')!
}

fn probe_command_output_preferred(arguments []string, capture bool, host_arch string) !string {
	mut pipes := [2]i32{}
	mut read_open := false
	mut write_open := false
	defer {
		if read_open { C.close(pipes[0]) }
		if write_open { C.close(pipes[1]) }
	}
	if capture {
		if C.pipe(&pipes[0]) != 0 { return file_error('') }
		read_open = true
		write_open = true

		for index in 0 .. 2 {
			if pipes[index] < 3 {
				moved := C.fcntl(pipes[index], C.F_DUPFD_CLOEXEC, 3)
				if moved < 0 { return file_error('') }
				C.close(pipes[index])
				pipes[index] = moved
			}
			if C.fcntl(pipes[index], C.F_SETFD, C.FD_CLOEXEC) != 0 { return file_error('') }
		}
	}
	if arguments.any(it.contains('\x00')) { return error('ValueError: embedded null byte') }
	mut argv := []&char{cap: arguments.len + 1}
	for item in arguments { argv << &char(item.str) }
	argv << &char(unsafe { nil })
	mut environment := []string{}
	for name, value in os.environ() { environment << name + '=' + value }
	mut envp := []&char{cap: environment.len + 1}
	for item in environment { envp << &char(item.str) }
	envp << &char(unsafe { nil })
	// SDK-owned storage binds the system primitive. Popen closes inherited
	// descriptors other than stdin/out/err.
	mut actions := C.posix_spawn_file_actions_t{}
	initialized := C.posix_spawn_file_actions_init(&actions)
	if initialized != 0 {
		return FileError{ message: os.get_error_msg(initialized), number: initialized }
	}
	defer { C.posix_spawn_file_actions_destroy(&actions) }
	if capture {
		duplicated := C.posix_spawn_file_actions_adddup2(&actions, pipes[1], 1)
		if duplicated != 0 {
			return FileError{ message: os.get_error_msg(duplicated), number: duplicated }
		}
	}
	directory := $if darwin { '/dev/fd' } $else { '/proc/self/fd' }
	mut descriptors := []int{}
	if names := os.ls(directory) {
		for name in names {
			if name.len > 0 && name.bytes().all(it >= `0` && it <= `9`) {
				descriptors << name.int()
			}
		}
	} else {
		for fd in 3 .. int(C.getdtablesize()) { descriptors << fd }
	}
	for fd in descriptors {
		if fd < 3 || C.fcntl(i32(fd), C.F_GETFD) < 0 { continue }
		closed := C.posix_spawn_file_actions_addclose(&actions, i32(fd))
		if closed != 0 { return FileError{ message: os.get_error_msg(closed), number: closed } }
	}
	mut attributes := C.posix_spawnattr_t{}
	attribute_status := C.posix_spawnattr_init(&attributes)
	if attribute_status != 0 {
		return FileError{ message: os.get_error_msg(attribute_status), number: attribute_status }
	}
	defer { C.posix_spawnattr_destroy(&attributes) }
	// CPython restores the signals it ignores in the interpreter before exec.
	$if darwin {
		mut defaults := u32(0)
		C.sigemptyset(&defaults)
		C.sigaddset(&defaults, C.SIGPIPE)
		if C.VINIX_PROBE_SIGXFZ != 0 { C.sigaddset(&defaults, C.VINIX_PROBE_SIGXFZ) }
		if C.VINIX_PROBE_SIGXFSZ != 0 { C.sigaddset(&defaults, C.VINIX_PROBE_SIGXFSZ) }
		status := C.posix_spawnattr_setsigdefault(&attributes, &defaults)
		if status != 0 { return FileError{ message: os.get_error_msg(status), number: status } }
	} $else {
		mut defaults := C.sigset_t{}
		C.sigemptyset(&defaults)
		C.sigaddset(&defaults, C.SIGPIPE)
		if C.VINIX_PROBE_SIGXFZ != 0 { C.sigaddset(&defaults, C.VINIX_PROBE_SIGXFZ) }
		if C.VINIX_PROBE_SIGXFSZ != 0 { C.sigaddset(&defaults, C.VINIX_PROBE_SIGXFSZ) }
		status := C.posix_spawnattr_setsigdefault(&attributes, &defaults)
		if status != 0 { return FileError{ message: os.get_error_msg(status), number: status } }
	}
	flags_status := C.posix_spawnattr_setflags(&attributes, i16(C.POSIX_SPAWN_SETSIGDEF))
	if flags_status != 0 {
		return FileError{ message: os.get_error_msg(flags_status), number: flags_status }
	}
	$if darwin {
		cpu := match host_arch.to_lower() {
			'arm64', 'aarch64' { i32(C.CPU_TYPE_ARM64) }
			'x86_64', 'amd64' { i32(C.CPU_TYPE_X86_64) }
			else { i32(0) }
		}
		if cpu != 0 {
			preferences := [cpu, i32(C.CPU_TYPE_ANY)]!
			mut copied := usize(0)
			preferred := C.posix_spawnattr_setbinpref_np(&attributes, 2, &preferences[0], &copied)
			if preferred != 0 {
				return FileError{ message: os.get_error_msg(preferred), number: preferred }
			}
			if copied != 2 { return error('Incomplete SDK binary preference') }
		}
	}
	mut pid := i32(0)
	status := if arguments[0].contains('/') {
		C.posix_spawn(&pid, &char(arguments[0].str), &actions, &attributes, argv.data, envp.data)
	} else {
		C.posix_spawnp(&pid, &char(arguments[0].str), &actions, &attributes, argv.data, envp.data)
	}
	if status != 0 {
		return FileError{ message: os.get_error_msg(status), number: status, filename: arguments[0] }
	}
	mut reaped := false
	defer {
		if !reaped {
			C.kill(pid, C.SIGKILL)
			mut retired := i32(0)
			for C.waitpid(pid, &retired, 0) < 0 {
				if C.errno != C.EINTR { break }
			}
		}
	}
	mut output := []u8{}
	if capture {
		C.close(pipes[1])
		write_open = false
		mut buffer := [8192]u8{}
		for {
			count := C.read(pipes[0], &buffer[0], usize(buffer.len))
			if count < 0 {
				if C.errno == C.EINTR { continue }
				return file_error('')
			}
			if count == 0 { break }
			if u64(output.len) + u64(count) >= 0x7fffffff { return error('MemoryError') }
			output << buffer[..int(count)]
		}
		C.close(pipes[0])
		read_open = false
	}
	mut result := i32(0)
	for C.waitpid(pid, &result, 0) < 0 {
		if C.errno != C.EINTR { return file_error('') }
	}
	reaped = true
	code := if C.WIFEXITED(result) != 0 {
		int(C.WEXITSTATUS(result))
	} else {
		-int(C.WTERMSIG(result))
	}
	captured := if capture {
		advanced_decode(output)!.replace('\r\n', '\n').replace('\r', '\n')
	} else {
		''
	}
	if code != 0 {
		if capture { return ProbeCaptureError{arguments.clone(), code, captured} }
		return ProbeCommandError{arguments.clone(), code}
	}
	return captured
}

fn collect_probe_classes(root string, class string, mut paths []string) {
	for name in os.ls(root) or { return } {
		path := path_join(root, name)
		if name.starts_with(class) && name.ends_with('.class') { paths << path }
		if os.is_dir(path) && !os.is_link(path) { collect_probe_classes(path, class, mut paths) }
	}
}

fn probe_class_paths(root string, class string) []string {
	mut paths := []string{}
	collect_probe_classes(root, class, mut paths)
	paths.sort()
	return paths
}

fn remove_probe_tree_at(parent i32, name string, path string, device u64, inode u64) ! {
	fd := C.openat(parent, &char(name.str), C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW)
	if fd < 0 { return file_error(path) }
	mut actual := C.stat{}
	if C.fstat(fd, &actual) != 0 {
		failure := file_error(path)
		C.close(fd)
		return failure
	}
	if u64(actual.st_dev) != device || u64(actual.st_ino) != inode {
		C.close(fd)
		return ProbeFilesystemError{'Cannot call rmtree on a symbolic link'}
	}
	directory := C.fdopendir(fd)
	if isnil(directory) {
		failure := file_error(path)
		C.close(fd)
		return failure
	}
	mut closed := false
	defer { if !closed { C.closedir(directory) } }
	for {
		C.errno = 0
		entry := C.readdir(directory)
		if isnil(entry) {
			if C.errno != 0 { return file_error(path) }
			break
		}
		child := unsafe { tos_clone(&u8(&entry.d_name[0])) }
		if child in ['', '.', '..'] { continue }
		child_path := path_join(path, child)
		mut state := C.stat{}
		if C.fstatat(fd, &char(child.str), &state, C.AT_SYMLINK_NOFOLLOW) != 0 {
			return file_error(child_path)
		}
		if u32(state.st_mode) & u32(C.S_IFMT) == u32(C.S_IFDIR) {
			remove_probe_tree_at(fd, child, child_path, u64(state.st_dev), u64(state.st_ino))!
		} else if C.unlinkat(fd, &char(child.str), 0) != 0 {
			return file_error(child_path)
		}
	}
	closed = true
	if C.closedir(directory) != 0 { return file_error(path) }
	if C.unlinkat(parent, &char(name.str), C.AT_REMOVEDIR) != 0 { return file_error(path) }
}

fn probe_class_valid(kind string, name string, class string) bool {
	prefix := (if kind == 'lifecycle' { 'android/app/' } else { 'org/vinix/tests/' }) + class
	if kind in ['lifecycle', 'cookie'] { return name.starts_with(prefix) }
	if !name.starts_with(prefix) || !name.ends_with('.class') { return false }
	suffix := name[prefix.len..name.len - 6]
	if suffix == '' { return true }
	if !suffix.starts_with('$') { return false }
	return suffix[1..].split('$').all(it.len > 0 && it.bytes().all(it in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_'.bytes()))
}

fn probe_quote(value string) string {
	// Python json.dumps uses ASCII escaping, preserving non-BMP surrogate pairs.
	mut output := '"'
	for ch in value.runes() {
		output += match ch {
			`"` { '\\"' }
			`\\` { '\\\\' }
			`\b` { '\\b' }
			`\f` { '\\f' }
			`\n` { '\\n' }
			`\r` { '\\r' }
			`\t` { '\\t' }
			else {
				if ch < 32 || ch >= 127 {
					if ch > 0xffff {
						point := u32(ch) - 0x10000
						'\\u${(0xd800 + (point >> 10)):04x}\\u${(0xdc00 + (point & 0x3ff)):04x}'
					} else {
						'\\u${u32(ch):04x}'
					}
				} else {
					ch.str()
				}
			}
		}
	}
	return output + '"'
}

// Production calls always use the committed pins. The separate parameters
// let independent host controls exercise the exact pipeline on frozen inputs.
fn build_probe_with_pins(row map[string]Value, r8_pin string, core_pin string) ! {
	kind := text(row, 'kind')!
	if kind !in ['lifecycle', 'cookie', 'autofill', 'location'] {
		return error('Unknown Android probe kind')
	}
	class := match kind {
		'lifecycle' { 'AndroidActivityLifecycleProbe' }
		'cookie' { 'AndroidCookieProbe' }
		'autofill' { 'AndroidAutofillProbe' }
		else { 'AndroidLocationProbe' }
	}
	r8 := text(row, 'r8')!
	core := text(row, 'core_classes')!
	for path, checksum in {
		r8:   r8_pin
		core: core_pin
	} {
		if digest(path)! != checksum { return ProbeExit{'pinned compiler input mismatch: ' + path} }
	}
	output := text(row, 'output')!
	mkdir_parents(output)!
	classes := path_join(output, 'classes')
	if os.exists(classes) {
		if os.is_link(classes) {
			return ProbeFilesystemError{'Cannot call rmtree on a symbolic link'}
		}
		if !os.is_dir(classes) {
			return FileError{ message: os.get_error_msg(C.ENOTDIR), number: int(C.ENOTDIR), filename: classes, filename_is_path: true }
		}
		state := os.lstat(classes) or { return file_error(classes) }
		remove_probe_tree_at(C.AT_FDCWD, classes, classes, state.dev, state.inode)!
	}
	if C.mkdir(&char(classes.str), 0o777) != 0 { return file_error(classes) }
	framework := text(row, 'framework_classes')!
	source := text(row, 'source')!
	probe_command([text(row, 'javac')!, '-source', '8', '-target', '8', '-bootclasspath', core,
		'-cp', framework, '-d', classes, source])!
	jar := path_join(output, kind + '-fixture-classes.jar')
	class_probe_zip(jar, classes, class)!
	dex_file := path_join(output, 'android-' + kind + '-probe.jar')
	probe_command([text(row, 'java')!, '-cp', r8, 'com.android.tools.r8.D8', '--min-api', '26',
		'--lib', core, '--lib', framework, '--output', dex_file, jar])!
	class_archive := read_probe_zip(jar)!
	if class_archive.entries.len == 0 || class_archive.entries.any(!probe_class_valid(kind, it.name, class)) {
		return ProbeExit{'fixture contains unexpected provider classes'}
	}
	apk := path_join(output, 'android-' + kind + '-probe.apk')
	framework_res := text(row, 'framework_res')!
	manifest := text(row, 'manifest')!
	probe_command([text(row, 'aapt2')!, 'link', '--manifest', manifest, '-I', framework_res, '-o',
		apk])!
	dex := read_probe_zip(dex_file)!
	merge_probe_dex(dex, apk)!
	final_apk := read_probe_zip(apk)!
	names := final_apk.entries.map(it.name)
	if 'AndroidManifest.xml' !in names || 'classes.dex' !in names || names.any(it !in [
		'AndroidManifest.xml',
		'resources.arsc',
		'classes.dex',
	]) {
		return ProbeExit{'fixture APK contains unexpected payloads'}
	}
	mut receipt := []string{}
	for key, path in {
		'source_sha256':            source
		'framework_classes_sha256': framework
		'core_classes_sha256':      core
		'r8_sha256':                r8
		'fixture_sha256':           dex_file
		'framework_res_sha256':     framework_res
		'manifest_sha256':          manifest
		'fixture_apk_sha256':       apk
	} {
		receipt << '  ' + probe_quote(key) + ': ' + probe_quote(digest(path)!)
	}
	marker := if kind == 'lifecycle' { 'ACTIVITY-LIFECYCLE' } else { kind.to_upper() }
	receipt << '  "expected_marker": "ANDROID-' + marker + '-PASS"'
	receipt << '  "' + if kind == 'lifecycle' {
		'fixture_uses_framework_loader'
	} else {
		'fixture_uses_public_api'
	} + '": true'
	if kind == 'cookie' {
		receipt << '  "persistence_activity": "org.vinix.tests.AndroidCookieProbe$PersistenceActivity"'
		receipt << '  "expected_reload_marker": "ANDROID-COOKIE-RELOAD-PASS"'
	}
	if kind in ['autofill', 'location'] {
		receipt << '  "activity": "org.vinix.tests.' + class + '$BootstrapActivity"'
		receipt << '  "helper_sha256": ' + probe_quote(digest(text(row, 'helper')!)!)
	}
	receipt << '  "runtime_tested": false'
	receipt_path := path_join(output, kind + '-probe-build.json')
	os.write_file(receipt_path, '{\n' + receipt.join(',\n') + '\n}\n') or { return file_error(receipt_path) }
	println(apk)
}

pub fn build_probe(row map[string]Value) ! {
	build_probe_with_pins(row, probe_r8_sha, probe_core_sha)!
}
