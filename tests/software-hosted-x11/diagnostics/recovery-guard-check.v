module main

// Compile with this diagnostics directory in V's module path. Results belong
// in a new external directory; this control never reclaims evidence.
import crypto.sha256
import json2
import os
import recoveryguard
import time

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.alarm(seconds u32) u32
fn C.fork() int
fn C.getpgid(pid i32) i32

struct Descendant {
	pid int
	pgid int
}

struct ChildExit {
	exit_code int
}

struct PassedControl {
	name string
	detail string
}

fn sha(path string) !string {
	mut f := os.open(path)!
	defer { f.close() }
	mut h := sha256.new()
	defer { unsafe { h.free() } }
	mut buffer := []u8{len: 64 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		n := f.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		h.write(buffer[..n])!
	}
	return h.sum([]u8{}).hex()
}

fn failure_payload() string {
	marker := 'RAW-CHILD-FAILURE-only:'
	return marker + 'x'.repeat(1024 * 1024 - marker.len)
}

fn large_failure_child() {
	C.alarm(15)
	text := failure_payload()
	mut sent := 0
	for sent < text.len {
		n := C.write(1, unsafe { text.str + sent }, usize(text.len - sent))
		if n < 0 && C.errno == C.EINTR { continue }
		if n <= 0 { C._exit(71) }
		sent += int(n)
	}
	C._exit(37)
}

fn exited_leader_child(out string) ! {
	C.alarm(15)
	leader := os.getpid()
	if C.getpgid(0) != leader { return error('fixture requires its own process group') }
	child := C.fork()
	if child < 0 { return os.error_posix() }
	if child == 0 {
		C.alarm(15)
		os.write_file(out + '/descendant.json', json2.encode(Descendant{os.getpid(), C.getpgid(0)})) or {
			C._exit(72)
		}
		// Inherit stdout without writing. Its observer must see a live pipe
		// writer even after this process's leader has been reaped.
		for { time.sleep(time.second) }
	}
	expected := json2.encode(Descendant{child, leader})
	start := time.sys_mono_now()
	for {
		if (os.read_file(out + '/descendant.json') or { '' }) == expected { C._exit(0) }
		if time.sys_mono_now() - start >= 5 * time.second {
			C.kill(child, C.SIGKILL)
			return error('descendant did not publish its exact identity')
		}
		time.sleep(10 * time.millisecond)
	}
}

fn absent_group(pid int) bool {
	result := C.kill(-pid, 0)
	saved_errno := int(C.errno)
	return result == -1 && saved_errno == C.ESRCH
}

fn large_failure_control(out string) !PassedControl {
	log := out + '/large-failure.log'
	args := [os.executable(), '--child-large-failure']
	mut message := ''
	recoveryguard.invoke(args, log) or { message = err.msg() }
	if message == '' || message.len > 2048 || !message.contains(log) ||
		message.contains('RAW-CHILD-FAILURE-only:') {
		return error('large-failure refusal is missing, unbounded, or embeds child output')
	}
	actual := os.read_file(log)!
	if actual.len != 1024 * 1024 || actual != failure_payload() {
		return error('full raw child failure output differs')
	}
	if json2.decode[ChildExit](os.read_file(log + '.exit.json')!)!.exit_code != 37 ||
		json2.decode[[]string](os.read_file(log + '.argv.json')!)! != args {
		return error('child failure status or literal argv receipt differs')
	}
	os.write_file(out + '/large-failure-error.txt', message)!
	return PassedControl{'one-mebibyte-child-failure', 'exact raw output retained; exit37 and argv checked; returned error bounded and payload-free'}
}

fn group_controls(out string) ![]PassedControl {
	mut p := os.new_process(os.executable())
	mut cleanup_complete := false
	p.set_args(['--child-exited-leader', out])
	p.set_redirect_stdio_merged()
	p.use_pgroup = true
	p.run()
	defer {
		// Shared cleanup probes the group and skips positive-PID kills after
		// the leader is reaped, when its PID could already have been reused.
		if !cleanup_complete && p.pid > 1 && p.pid != C.getpgid(0) {
			recoveryguard.terminate_group(mut p, 1000) or {
				eprintln(recoveryguard.bounded_message('control cleanup refused: ' + err.msg()))
			}
		}
		p.close()
	}
	if p.pid <= 1 || p.pid == C.getpgid(0) { return error('fixture process group is unsafe') }
	C.close(p.stdio_fd[0]); p.stdio_fd[0] = -1
	start := time.sys_mono_now()
	for {
		if !p.is_alive() { break }
		if time.sys_mono_now() - start >= 5 * time.second { return error('fixture leader exit timed out') }
		time.sleep(10 * time.millisecond)
	}
	if p.status != .exited || p.code != 0 { return error('fixture leader did not exit normally') }
	mut status := 0
	leader_wait := C.waitpid(p.pid, &status, C.WNOHANG)
	leader_errno := int(C.errno)
	if leader_wait != -1 || leader_errno != C.ECHILD {
		return error('is_alive did not actually reap the fixture leader')
	}
	descendant := json2.decode[Descendant](os.read_file(out + '/descendant.json')!)!
	if descendant.pid <= 1 || descendant.pgid != p.pid || C.getpgid(descendant.pid) != p.pid ||
		C.kill(descendant.pid, 0) != 0 || absent_group(p.pid) {
		return error('exited leader did not leave the intended live group descendant')
	}
	flags := C.fcntl(p.stdio_fd[1], C.F_GETFL)
	if flags < 0 || C.fcntl(p.stdio_fd[1], C.F_SETFL, flags | C.O_NONBLOCK) < 0 {
		return error('could not probe held stdout pipe without blocking')
	}
	mut probe_byte := u8(0)
	read_result := C.read(p.stdio_fd[1], &probe_byte, 1)
	read_errno := int(C.errno)
	if C.fcntl(p.stdio_fd[1], C.F_SETFL, flags) < 0 { return error('could not restore stdout pipe flags') }
	if read_result != -1 || read_errno !in [C.EAGAIN, C.EWOULDBLOCK] {
		return error('live descendant did not retain the otherwise empty stdout pipe')
	}
	cleanup_start := time.sys_mono_now()
	recoveryguard.terminate_group(mut p, 5000)!
	cleanup_ns := time.sys_mono_now() - cleanup_start
	if cleanup_ns > 6 * time.second || !absent_group(p.pid) {
		return error('exited-leader cleanup did not establish bounded group absence')
	}
	child_probe := C.kill(descendant.pid, 0)
	child_errno := int(C.errno)
	if child_probe != -1 || child_errno != C.ESRCH { return error('fixture descendant remains after cleanup') }
	// Group absence, rather than a kill attempt, makes this EOF read safe.
	text := p.stdout_slurp()
	if text != '' { return error('silent held-pipe fixture emitted unexpected output') }
	os.write_file(out + '/exited-leader.log', text)!
	repeat_start := time.sys_mono_now()
	recoveryguard.terminate_group(mut p, 1000)!
	repeat_ns := time.sys_mono_now() - repeat_start
	if repeat_ns > 1500 * time.millisecond || !absent_group(p.pid) {
		return error('already-empty group was not a bounded safe no-op')
	}
	cleanup_complete = true
	os.write_file(out + '/group-observations.json', json2.encode({
		'leader_pid': p.pid.str(), 'leader_status_before_cleanup': 'exited',
		'leader_wait_result': leader_wait.str(), 'leader_wait_errno': leader_errno.str(),
		'descendant_pid': descendant.pid.str(), 'descendant_group': descendant.pgid.str(),
		'held_pipe_read': read_result.str(), 'held_pipe_errno': read_errno.str(),
		'cleanup_ns': cleanup_ns.str(), 'repeat_cleanup_ns': repeat_ns.str(),
		'group_absent': 'true', 'descendant_absent': 'true'
	}))!
	return [
		PassedControl{'exited-leader-live-descendant', 'leader reaped by is_alive; live descendant held stdout; group cleanup established ESRCH within bound'},
		PassedControl{'already-empty-group', 'second cleanup succeeded within bound and group remained ESRCH'},
	]
}

fn run() ! {
	if os.args.len != 2 || !os.args[1].starts_with('--out=') { return error('usage: recovery-guard-check --out=ABS_NEW_DIRECTORY') }
	out := os.args[1].all_after('--out=')
	if out == '' || out != os.abs_path(out) || os.exists(out) || os.is_link(out) {
		return error('control output must be a new absolute directory')
	}
	os.mkdir(out)!
	os.write_file(out + '/invocation.json', json2.encode(os.args))!
	mut pins := map[string]string{}
	for path in [@FILE, os.dir(@FILE) + '/recoveryguard/recoveryguard.v', os.executable()] { pins[path] = sha(path)! }
	os.write_file(out + '/pins-before.json', json2.encode(pins))!
	mut passed := []PassedControl{}
	for text in ['', 'small λ error', 'x'.repeat(2048)] {
		if recoveryguard.bounded_message(text) != text { return error('bounded_message changed an in-range message') }
		passed << PassedControl{'bounded-message-' + text.len.str(), 'in-range message retained byte for byte'}
	}
	if recoveryguard.bounded_message('x'.repeat(4096)).len > 2048 { return error('bounded_message exceeds2048 bytes') }
	passed << PassedControl{'bounded-message-over-limit', '4096-byte message capped at2048 bytes'}
	now := time.sys_mono_now()
	if recoveryguard.deadline_expired(now, 1000) { return error('future deadline was expired') }
	passed << PassedControl{'deadline-before', 'future deadline stays active'}
	if !recoveryguard.deadline_expired(time.sys_mono_now() - 2 * time.millisecond, 1) {
		return error('past deadline was not expired')
	}
	passed << PassedControl{'deadline-after', 'elapsed deadline expires'}
	passed << large_failure_control(out)!
	passed << group_controls(out)!
	for path, wanted in pins { if sha(path)! != wanted { return error('control source or executable changed during execution') } }
	if passed.len != 9 { return error('focused recovery control count differs') }
	os.write_file(out + '/results.json', json2.encode({
		'passed': 'true', 'control_count': passed.len.str(), 'controls': json2.encode(passed),
		'pins_before_and_after': json2.encode(pins),
		'scope': 'Host recovery guard controls only. No archive creation, expanded evidence removal, guest execution, or native acceptance.'
	}))!
	println('PASS9 focused recovery guard controls')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--child-large-failure' { large_failure_child(); return }
	if os.args.len == 3 && os.args[1] == '--child-exited-leader' {
		exited_leader_child(os.args[2]) or { eprintln(err); exit(1) }
		return
	}
	// A final external bound also catches a faulty guard that blocks. The
	// descendant independently expires if this observer is terminated.
	C.alarm(45)
	run() or { eprintln(recoveryguard.bounded_message(err.msg())); exit(1) }
}
