module main

import crypto.sha256
import json2
import os
import strconv
import strings
import time

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>
#define wine_retain_build_waitpid waitpid
#define wine_retain_build_read read
#define wine_retain_build_write write
#define wine_retain_build_getpid getpid

fn C.wine_retain_build_waitpid(i32, &i32, i32) i32
fn C.wine_retain_build_read(i32, voidptr, usize) isize
fn C.wine_retain_build_write(i32, voidptr, usize) isize
fn C.getpgid(i32) i32
fn C.setpgid(i32, i32) i32
fn C.wine_retain_build_getpid() i32

const base = '/Users/alex/Library/Caches/vinix-codex/section14'
const directory = base + '/wine-source-archive-retention-tools-07'
const compiler = '/Users/alex/code/v/v'
const clang = '/opt/homebrew/opt/llvm/bin/clang'

fn hash(path string) !string {
	if (os.lstat(path)!).get_filetype() != .regular {
		return error('requires ordinary input: ' + path)
	}
	return sha256.sum(os.read_bytes(path)!).hex()
}

struct Build {
	format               int
	source               string
	source_sha256        string
	binary               string
	binary_sha256        string
	selected_inputs      map[string]string
	argv                 []string
	transport_argv       []string
	environment          map[string]string
	clang_literal_target string
	clang_canonical      string
	scope                string
}

fn group_empty(group i32) bool {
	return C.kill(-group, 0) < 0 && C.errno == C.ESRCH
}

fn await_empty(group i32) bool {
	started := time.sys_mono_now()
	for time.sys_mono_now() - started < u64(2 * time.second) {
		if group_empty(group) { return true }
		time.sleep(time.millisecond)
	}
	return group_empty(group)
}

fn nonblocking(fd i32) ! {
	flags := C.fcntl(fd, C.F_GETFL, 0)
	if flags < 0 || C.fcntl(fd, C.F_SETFL, flags | C.O_NONBLOCK) < 0
		|| C.fcntl(fd, C.F_GETFL, 0) & C.O_NONBLOCK == 0 {
		return error('compiler pipe nonblocking setup failed')
	}
}

// Keep the target behind a ready/GO barrier until its live PGID is confirmed.
fn group_wrapper() ! {
	if os.args.len < 3 || os.args[2] != compiler {
		return error('build wrapper requires the pinned compiler')
	}
	pid := C.wine_retain_build_getpid()
	if C.setpgid(0, 0) != 0 || C.getpgid(pid) != pid {
		return error('compiler wrapper group setup failed')
	}
	mut token := u8(`R`)
	for {
		n := C.wine_retain_build_write(1, &token, 1)
		if n == 1 { break }
		if n < 0 && C.errno == C.EINTR { continue }
		return error('compiler wrapper readiness write failed')
	}
	for {
		n := C.wine_retain_build_read(0, &token, 1)
		if n < 0 && C.errno == C.EINTR { continue }
		if n != 1 || token != `G` { return error('compiler wrapper GO refused') }
		break
	}
	os.execvp(os.args[2], os.args[3..])!
}

fn await_ready(pid i32, fd i32) ! {
	nonblocking(fd)!
	deadline := time.sys_mono_now() + u64(2 * time.second)
	mut token := u8(0)
	for time.sys_mono_now() < deadline {
		n := C.wine_retain_build_read(fd, &token, 1)
		if n == 1 {
			if token != `R` || C.getpgid(pid) != pid {
				return error('live compiler wrapper group not confirmed')
			}
			return
		}
		if n == 0 || (n < 0 && C.errno !in [C.EINTR, C.EAGAIN]) {
			return error('compiler wrapper readiness refused')
		}
		time.sleep(time.millisecond)
	}
	return error('compiler wrapper readiness deadline exceeded')
}

fn release_ready(fd i32) ! {
	if C.fcntl(fd, C.F_SETNOSIGPIPE, 1) != 0 {
		return error('compiler GO pipe signal setup failed')
	}
	nonblocking(fd)!
	deadline := time.sys_mono_now() + u64(time.second)
	token := u8(`G`)
	for time.sys_mono_now() < deadline {
		n := C.wine_retain_build_write(fd, &token, 1)
		if n == 1 { return }
		if n < 0 && C.errno !in [C.EINTR, C.EAGAIN] {
			return error('compiler wrapper GO write failed')
		}
		time.sleep(time.millisecond)
	}
	return error('compiler wrapper GO deadline exceeded')
}

fn compile(source string, binary string, environment map[string]string) !Build {
	mut pins := map[string]string{}
	for path in [@FILE, os.executable(), source, compiler, compiler + 'lib/os/os.v',
		compiler + 'lib/os/os.c.v', compiler + 'lib/os/process_nix.c.v', os.real_path(clang)] {
		pins[path] = hash(path)!
	}
	alias := os.readlink(clang)!
	canonical := os.real_path(clang)
	argv := [compiler, '-cc', clang, '-prod', '-o', binary, source]
	mut transport := [os.executable(), '--private-group-wrapper']
	transport << argv
	os.write_file(directory + '/argv.json', json2.encode(argv))!
	os.write_file(directory + '/transport-argv.json', json2.encode(transport))!
	os.write_file(directory + '/environment.json', json2.encode(environment))!
	os.write_file(directory + '/inputs-before.json', json2.encode(pins))!
	mut child := os.new_process(transport[0])
	defer { child.close() }
	child.set_args(transport[1..])
	child.set_environment(environment)
	child.set_redirect_stdio_merged()
	child.use_pgroup = true
	child.run()
	if child.pid <= 0 || child.status != .running { return error('compiler spawn failed') }
	mut reaped := false
	mut confirmed_group := false
	defer {
		if confirmed_group && !group_empty(i32(child.pid)) { C.kill(-i32(child.pid), C.SIGKILL) }
		if !reaped {
			C.kill(i32(child.pid), C.SIGKILL)
			mut status := i32(0)
			for {
				result := C.wine_retain_build_waitpid(i32(child.pid), &status, 0)
				if result >= 0 || C.errno != C.EINTR { break }
			}
			child.status = .exited
		}
		if confirmed_group && !await_empty(i32(child.pid)) {
			eprintln('REFUSED: compiler group not empty after bounded cleanup')
		}
	}
	await_ready(i32(child.pid), i32(child.stdio_fd[1]))!
	confirmed_group = true
	release_ready(i32(child.stdio_fd[0]))!
	C.close(i32(child.stdio_fd[0]))
	child.stdio_fd[0] = -1
	fd := i32(child.stdio_fd[1])
	nonblocking(fd)!
	mut bytes := []u8{len: 65536}
	mut log := strings.new_builder(4096)
	mut eof := false
	mut status := i32(0)
	start := time.sys_mono_now()
	for !reaped || !eof {
		if time.sys_mono_now() - start > u64(120 * time.second) {
			return error('compiler deadline exceeded')
		}
		if !eof {
			n := C.wine_retain_build_read(fd, bytes.data, usize(bytes.len))
			if n == 0 { eof = true }
			if n < 0 && C.errno !in [C.EINTR, C.EAGAIN] {
				return error('compiler pipe read failed')
			}
			if n > 0 {
				if log.len + int(n) > 1024 * 1024 { return error('compiler output bound exceeded') }
				log.write(unsafe { bytes[..int(n)] })!
			}
		}
		if !reaped {
			result := C.wine_retain_build_waitpid(i32(child.pid), &status, C.WNOHANG)
			if result == i32(child.pid) {
				reaped = true
				child.status = .exited
			} else if result < 0 && C.errno != C.EINTR {
				return error('compiler wait failed')
			}
		}
		if !reaped || !eof { time.sleep(time.millisecond) }
	}
	os.write_file(directory + '/compile.log', log.str())!
	os.write_file(directory + '/exit.json', json2.encode({
		'raw_wait_status': status
	}))!
	for path, expected in pins {
		if hash(path)! != expected { return error('selected build input changed: ' + path) }
	}
	os.write_file(directory + '/inputs-after.json', json2.encode(pins))!
	if os.readlink(clang)! != alias || os.real_path(clang) != canonical {
		return error('Clang alias changed')
	}
	if status != 0 { return error('compiler failed; see preserved compile.log') }
	if !await_empty(i32(child.pid)) {
		return error('compiler group not empty after successful leader exit')
	}
	return Build{1, source, pins[source], binary, hash(binary)!, pins, argv, transport, environment, alias, canonical, 'Selected compiler/source/Clang and adjacent os ABI implementation binding with exact environment and ready/GO process-group transport. Default-GC bounded host helper; no full imported/header/sysroot/linker closure, hermetic build, or retained-memory claim.'}
}

fn build() ! {
	if os.exists(directory) || os.is_link(directory) {
		return error('requires fresh build directory')
	}
	// Literal completed df is used instead of the affected macOS disk_usage API.
	disk := os.exec(['/bin/df', '-k', base])
	lines := disk.output.trim_space().split_into_lines()
	if disk.exit_code != 0 || lines.len != 2 { return error('completed df required') }
	fields := lines[1].fields()
	if fields.len < 6 || !fields[3].bytes().all(it >= `0` && it <= `9`)
		|| strconv.parse_uint(fields[3], 10, 64)! < 550 * 1024 {
		return error('requires actual completed df at least550MiB free')
	}
	os.mkdir(directory)!
	os.mkdir(directory + '/tmp')!
	os.write_file(directory + '/df-before.txt', disk.output)!
	environment := {
		'PATH':                                  '/usr/bin:/bin'
		'HOME':                                  '/Users/alex'
		'LC_ALL':                                'C'
		'LANG':                                  'C'
		'TMPDIR':                                directory + '/tmp'
		'VEXE':                                  compiler
		'V':                                     compiler
		'V_MACOS_V3_CALLER_VEXE':                compiler
		'V_MACOS_V3_CALLER_VEXE_PRESENT':        '1'
		'V_MACOS_V3_CALLER_VCHILD_PRESENT':      '0'
		'V_MACOS_V3_NO_FALLBACK':                '1'
		'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT': '1'
		'V_MACOS_V3_CALLER_NO_FALLBACK':         '1'
		'V_C_ERROR_BUG_REPORT_DISABLED':         '1'
	}
	receipt := compile(os.dir(@FILE) + '/wine-source-archive-retain.v', directory + '/wine-source-archive-retain', environment)!
	os.write_file(directory + '/build.json', json2.encode(receipt))!
	println('PASS retained helper build ' + hash(directory + '/build.json')!)
}

fn main() {
	if os.args.len >= 2 && os.args[1] == '--private-group-wrapper' {
		group_wrapper() or {
			eprintln(err)
			exit(1)
		}
		return
	}
	build() or {
		eprintln(err)
		exit(1)
	}
}
