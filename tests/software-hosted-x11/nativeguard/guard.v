@[has_globals]
module nativeguard

// Host-only, source-bound inherited-group supervision. No daemon tracking.
import os
import time
import strconv
import json2
import recoveryguard

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.fork() int
fn C.getpgid(pid i32) i32
fn C.setpgid(pid i32, pgid i32) i32
fn C.pipe(fds &i32) i32

pub struct KillObservation {
pub:
	target int
	result int
	saved_errno int
}

fn kill_owned(pid int) KillObservation {
	result := C.kill(pid, C.SIGKILL)
	saved_errno := int(C.errno)
	return KillObservation{pid, int(result), if result == 0 { 0 } else { saved_errno }}
}

__global interrupted = i32(0)

fn interrupt(signal os.Signal) { interrupted = i32(signal) }

pub fn watch_interrupts() ! {
	interrupted = 0
	for signal in [os.Signal.int, .term, .hup] { os.signal_opt(signal, interrupt)! }
}

pub struct Cleanup {
pub:
	pid int
	reaped bool
	group_empty bool
	final_wait int
	final_errno int
	exit_code int
	kill_attempts int
	kills []KillObservation
}

pub struct Child {
pub:
	pid int
	group_observed bool
pub mut:
	output int = -1
	output_eof bool
	output_would_block bool
	reaped bool
	exit_code int = -1
}

fn close_fd(fd int) int {
	if fd >= 0 { C.close(fd) }
	return -1
}

// All argv/environment allocations precede fork. Before exec the child only
// makes syscalls, and cannot start a descendant before the parent releases it.
pub fn launch(args []string, cwd string, lifecycle string) !Child {
	if args.len == 0 || !args[0].starts_with('/') { return error('requires absolute executable') }
	if interrupted != 0 { return error('cancelled before child creation') }
	mut argv := []&char{cap: args.len + 1}
	for arg in args { argv << &char(arg.str) }
	argv << &char(unsafe { nil })
	mut environment := []string{}
	for name, value in os.environ() { environment << name + '=' + value }
	mut envp := []&char{cap: environment.len + 1}
	for value in environment { envp << &char(value.str) }
	envp << &char(unsafe { nil })
	mut output := [i32(-1), i32(-1)]!
	mut ready := [i32(-1), i32(-1)]!
	mut release := [i32(-1), i32(-1)]!
	defer { for pair in [output, ready, release] { for fd in pair { if fd >= 0 { C.close(fd) } } } }
	if C.pipe(&output[0]) != 0 || C.pipe(&ready[0]) != 0 || C.pipe(&release[0]) != 0 {
		return error('supervisor pipe creation failed')
	}
	for fd in [output[0], ready[0]] {
		if C.fcntl(fd, C.F_SETFL, C.O_NONBLOCK) < 0 { return error('nonblocking pipe setup failed') }
	}
	if C.fcntl(release[1], C.F_SETNOSIGPIPE, 1) < 0 { return error('release pipe SIGPIPE protection failed') }
	pid := C.fork()
	if pid < 0 { return error('supervisor fork failed') }
	if pid == 0 {
		C.close(output[0]); C.close(ready[0]); C.close(release[1])
		if C.setpgid(0, 0) != 0 || C.chdir(&char(cwd.str)) != 0 { C._exit(120) }
		if C.dup2(output[1], 1) < 0 || C.dup2(output[1], 2) < 0 { C._exit(121) }
		C.close(output[1])
		null_fd := C.open(c'/dev/null', C.O_RDONLY)
		if null_fd < 0 || C.dup2(null_fd, 0) < 0 { C._exit(122) }
		if null_fd > 2 { C.close(null_fd) }
		mut token := u8(71)
		if C.write(ready[1], &token, 1) != 1 { C._exit(123) }
		C.close(ready[1])
		for {
			n := C.read(release[0], &token, 1)
			if n == -1 && C.errno == C.EINTR { continue }
			if n != 1 || token != 82 { C._exit(124) }
			break
		}
		C.close(release[0])
		C.execve(&char(args[0].str), argv.data, envp.data)
		C._exit(125)
	}
	output[1] = i32(close_fd(output[1])); ready[1] = i32(close_fd(ready[1])); release[0] = i32(close_fd(release[0]))
	mut child := Child{pid: pid, output: int(output[0])}
	output[0] = -1
	mut released := false
	defer {
		if !released {
			mut cleanup_error := ''
			final := cleanup(mut child, 5000) or { cleanup_error = err.msg(); Cleanup{} }
			os.write_file(lifecycle + '.barrier-cleanup.json', json2.encode({'cleanup': json2.encode(final), 'error': cleanup_error})) or { eprintln(err) }
			child.output = close_fd(child.output)
		}
	}
	start := time.sys_mono_now()
	mut token := u8(0)
	for {
		n := C.read(ready[0], &token, 1)
		if n == 1 {
			if token != 71 || C.getpgid(i32(pid)) != i32(pid) { return error('group barrier identity differs') }
			break
		}
		if n == 0 || (n < 0 && C.errno !in [C.EAGAIN, C.EWOULDBLOCK, C.EINTR]) {
			return error('child failed before group barrier')
		}
		if interrupted != 0 || recoveryguard.deadline_expired(start, 2000) { return error('group barrier interrupted or timed out') }
		time.sleep(time.millisecond)
	}
	if interrupted != 0 { return error('cancelled before child release') }
	os.write_file(lifecycle + '.barrier.json', json2.encode({'pid': pid, 'observed_pgid': int(C.getpgid(i32(pid))),
		'parent_uid': int(C.getuid()), 'parent_euid': int(C.geteuid())}))!
	token = 82
	if C.write(release[1], &token, 1) != 1 { return error('group release failed') }
	released = true
	return Child{pid: pid, group_observed: true, output: child.output}
}

pub fn poll(mut child Child) !bool {
	if child.reaped { return false }
	mut status := 0
	result := C.waitpid(child.pid, &status, C.WNOHANG)
	saved_errno := int(C.errno)
	if result == child.pid {
		child.reaped = true
		child.exit_code = if status & 127 == 0 { (status >> 8) & 255 } else { 128 + (status & 127) }
		return false
	}
	if result == 0 || (result == -1 && saved_errno == C.EINTR) { return true }
	return error('unexpected waitpid result=' + result.str() + ' errno=' + saved_errno.str())
}

// Never signal a positive PID after reaping it. Negative PGID probes are trusted
// host numeric observations, not protection against hostile group-ID reuse.
pub fn cleanup(mut child Child, timeout_ms int) !Cleanup {
	if child.pid <= 1 || child.pid == C.getpgid(0) { return error('unsafe cleanup identity') }
	start := time.sys_mono_now()
	mut attempts := 0
	mut kills := []KillObservation{}
	for {
		present := recoveryguard.group_present(child.pid)!
		// A signal error is an observation, never proof of cleanup. Continue
		// bounded polling: only actual ECHILD plus group ESRCH can accept.
		if present {
			observation := kill_owned(-child.pid)
			attempts++
			if kills.len < 64 { kills << observation }
		}
		if !child.reaped {
			observation := kill_owned(child.pid)
			attempts++
			if kills.len < 64 { kills << observation }
		}
		poll(mut child)!
		empty := !recoveryguard.group_present(child.pid)!
		if child.reaped && empty {
			mut status := 0
			waited := C.waitpid(child.pid, &status, C.WNOHANG)
			saved_errno := int(C.errno)
			if waited != -1 || saved_errno != C.ECHILD { return error('leader reaping proof differs') }
			return Cleanup{pid: child.pid, reaped: true, group_empty: true, final_wait: waited,
				final_errno: saved_errno, exit_code: child.exit_code, kill_attempts: attempts, kills: kills}
		}
		if recoveryguard.deadline_expired(start, timeout_ms) { return error('bounded group cleanup failed: reaped=' + child.reaped.str() +
			' group_empty=' + empty.str() + ' attempts=' + attempts.str() + ' first64=' + json2.encode(kills)) }
		time.sleep(10 * time.millisecond)
	}
}

pub fn drain(mut child Child, mut log os.File) !int {
	child.output_would_block = false
	mut buffer := [32768]u8{}
	mut total := 0
	for _ in 0 .. 16 {
		n := C.read(child.output, &buffer[0], buffer.len)
		if n > 0 {
			mut written := 0
			for written < n {
				part := C.write(log.fd, &buffer[written], usize(n - written))
				if part < 0 && C.errno == C.EINTR { continue }
				if part <= 0 { return error('raw output log write failed') }
				written += int(part)
			}
			total += int(n)
			continue
		}
		if n == 0 { child.output_eof = true; break }
		if C.errno in [C.EAGAIN, C.EWOULDBLOCK] { child.output_would_block = true; break }
		if C.errno == C.EINTR { continue }
		return error('nonblocking child output read failed')
	}
	// Raw descriptor writes above never leave stdio-buffered output pending.
	return total
}

pub fn close_output(mut child Child) { child.output = close_fd(child.output) }

pub fn parse_df(text string) !u64 {
	lines := text.trim_space().split_into_lines()
	if lines.len != 2 || !lines[0].contains('1024-blocks') { return error('actual df format differs') }
	fields := lines[1].fields()
	if fields.len != 9 || fields[0] != '/dev/disk3s5' || fields[8] != '/System/Volumes/Data' { return error('actual df volume or columns differ') }
	kib := strconv.parse_uint(fields[3], 10, 64)!
	if kib > ~u64(0) / 1024 { return error('actual df overflow') }
	return kib * 1024
}

pub struct DfObservation {
pub:
	available u64
	text string
	cleanup Cleanup
}

// Separately owned helper group: cleanup precedes return, also on cancellation
// or parse failure. It is never hidden inside the native runner's group.
pub fn actual_df(root string, log_path string) !DfObservation {
	mut child := launch(['/bin/df', '-k', root], os.getwd(), log_path)!
	defer { close_output(mut child) }
	mut cleaned := false
	defer {
		if !cleaned {
			mut cleanup_error := ''
			final := cleanup(mut child, 5000) or { cleanup_error = err.msg(); Cleanup{} }
			os.write_file(log_path + '.cleanup.json', json2.encode({'cleanup': json2.encode(final), 'error': cleanup_error})) or { eprintln(err) }
		}
	}
	mut log := os.create(log_path)!
	defer { log.close() }
	start := time.sys_mono_now()
	mut reason := ''
	mut drained := 0
	for {
		drained += drain(mut child, mut log) or { reason = err.msg(); break }
		if drained > 65536 { reason = 'actual df output exceeds64KiB'; break }
		if !poll(mut child)! { break }
		if interrupted != 0 || recoveryguard.deadline_expired(start, 5000) { reason = 'actual df interrupted or timed out'; break }
		time.sleep(time.millisecond)
	}
	remaining := recoveryguard.group_present(child.pid)!
	final := cleanup(mut child, 5000)!
	os.write_file(log_path + '.cleanup.json', json2.encode({'cleanup': json2.encode(final), 'error': ''}))!
	cleaned = true
	drained += drain(mut child, mut log)!
	if drained > 65536 { reason = 'actual df output exceeds64KiB' }
	log.close()
	text := os.read_file(log_path)!
	if reason != '' || remaining || final.exit_code != 0 { return error('actual df refused: ' + reason) }
	return DfObservation{parse_df(text)!, text, final}
}

struct Counter {
mut:
	entries int
}

fn allocated_one(path string, device u64, start i64, mut counter Counter) !u64 {
	counter.entries++
	if counter.entries > 200000 || recoveryguard.deadline_expired(start, 5000) || interrupted != 0 { return error('allocation inventory interrupted or exceeds bounded scope') }
	mut stat := C.stat{}
	if unsafe { C.lstat(&char(path.str), &stat) } != 0 {
		if C.errno == C.ENOENT { return 0 }
		return error('allocation lstat failed: ' + path)
	}
	if u64(stat.st_dev) != device || stat.st_blocks < 0 { return error('allocation device or blocks differ') }
	mut bytes := u64(stat.st_blocks) * 512
	if stat.st_mode & C.S_IFMT == C.S_IFDIR {
		names := os.ls(path) or {
			if !os.exists(path) { return bytes }
			return err
		}
		for name in names {
			part := allocated_one(path + '/' + name, device, start, mut counter)!
			if part > ~u64(0) - bytes { return error('allocation sum overflow') }
			bytes += part
		}
	}
	return bytes
}

// No link traversal; hardlinks/shared APFS blocks may be counted twice. This
// bounds a namespace's allocation and does not measure exclusive physical use.
pub fn allocated(paths []string, device u64) !u64 {
	mut counter := Counter{}
	mut total := u64(0)
	start := time.sys_mono_now()
	for path in paths {
		part := allocated_one(path, device, start, mut counter)!
		if part > ~u64(0) - total { return error('allocation total overflow') }
		total += part
	}
	return total
}

pub struct Limits {
pub:
	start_bytes u64
	floor_bytes u64
	cap_bytes u64
	wall_ms int
	sample_ms int = 1000
}

pub fn refusal(available u64, allocation u64, elapsed_ms i64, limits Limits) string {
	if available < limits.floor_bytes { return 'actual df below shared floor' }
	if allocation > limits.cap_bytes { return 'namespace allocation cap exceeded' }
	if elapsed_ms >= limits.wall_ms { return 'outer wall deadline exceeded' }
	return ''
}

pub struct Sample {
pub:
	mono_ns i64
	allocated_bytes u64
	df DfObservation
}

pub struct Result {
pub:
	reason string
	group_observed bool
	held_pipe_after_leader_exit bool
	cleanup Cleanup
	samples []Sample
}

pub fn supervise(args []string, cwd string, df_root string, paths []string,
	log_path string, df_log string, limits Limits) !Result {
	if limits.wall_ms <= 0 || limits.sample_ms <= 0 || limits.sample_ms > 5000 || limits.cap_bytes == 0 || limits.start_bytes < limits.floor_bytes {
		return error('invalid supervisor limits')
	}
	initial_df := actual_df(df_root, df_log + '.0')!
	if initial_df.available < limits.start_bytes { return error('fresh actual df below start admission') }
	device := os.lstat(df_root)!.dev
	initial_allocation := allocated(paths, device)!
	if initial_allocation > limits.cap_bytes { return error('initial namespace exceeds cap') }
	mut samples := [Sample{time.sys_mono_now(), initial_allocation, initial_df}]
	mut log := os.create(log_path)!
	defer { log.close() }
	mut child := launch(args, cwd, log_path)!
	mut cleaned := false
	defer {
		if !cleaned {
			mut cleanup_error := ''
			final := cleanup(mut child, 5000) or { cleanup_error = err.msg(); Cleanup{} }
			os.write_file(log_path + '.cleanup.json', json2.encode({'cleanup': json2.encode(final), 'error': cleanup_error})) or { eprintln(err) }
		}
		close_output(mut child)
	}
	started := time.sys_mono_now()
	mut last_sample := started
	mut reason := ''
	mut held_pipe := false
	for {
		drain(mut child, mut log) or { reason = err.msg(); break }
		if interrupted != 0 { reason = 'outer interruption signal=' + interrupted.str(); break }
		if recoveryguard.deadline_expired(started, limits.wall_ms) { reason = 'outer wall deadline exceeded'; break }
		if !poll(mut child)! {
			if recoveryguard.group_present(child.pid)! {
				reason = 'leader exited with remaining inherited-group members'
				drain(mut child, mut log)!
				held_pipe = child.output_would_block && !child.output_eof
			}
			break
		}
		if recoveryguard.deadline_expired(last_sample, limits.sample_ms) {
			observation := actual_df(df_root, df_log + '.' + samples.len.str()) or { reason = err.msg(); break }
			allocation := allocated(paths, device) or { reason = err.msg(); break }
			now := time.sys_mono_now()
			samples << Sample{now, allocation, observation}
			reason = refusal(observation.available, allocation, (now - started) / 1_000_000, limits)
			if reason != '' { break }
			last_sample = now
		}
		time.sleep(10 * time.millisecond)
	}
	final := cleanup(mut child, 5000)!
	os.write_file(log_path + '.cleanup.json', json2.encode({'cleanup': json2.encode(final), 'error': ''}))!
	cleaned = true
	// Absence is proved before final nonblocking drain: no inherited writer can
	// hold this pipe indefinitely. Bounded drain work also limits flooding.
	for _ in 0 .. 16 { drain(mut child, mut log)! }
	log.close()
	// Cancellation remains sticky. Do not release another helper after a
	// cancellation request; its absence is explicit in the retained samples.
	if interrupted == 0 {
		observation := actual_df(df_root, df_log + '.final')!
		allocation := allocated(paths, device)!
		now := time.sys_mono_now()
		samples << Sample{now, allocation, observation}
		last_reason := refusal(observation.available, allocation, (now - started) / 1_000_000, limits)
		if reason == '' { reason = last_reason }
	}
	return Result{reason, child.group_observed, held_pipe, final, samples}
}
