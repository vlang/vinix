// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module jobcore

import devcore
import json2
import os
import os.filelock
import sourcecommand
import sync.stdatomic
import time

#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>

fn C.open(&char, int, ...int) int
fn C.fstat(int, &C.stat) int
fn C.fsync(int) int
fn C.read(int, voidptr, usize) isize
fn C.close(int) int
fn C.execv(&char, &&char) int

__global interrupted = u64(0)

pub fn signal_stop(signal os.Signal) { stdatomic.store_u64(&interrupted, u64(128 + int(signal))) }

pub struct Job {
pub:
	id               string
	executable       devcore.Pin
	arguments        []string
	directory        string
	interval_seconds int
	timeout_seconds  int = 300
	environment      map[string]string
	credential_files map[string]string
}

pub struct Plan {
pub:
	schema int = 1
	uid    int
	jobs   []Job
}

pub struct JobState {
pub mut:
	in_flight bool
	next_due  i64
	started   i64
	finished  i64
	exit_code int
	detail    string
	runs      u64
}

pub struct State {
pub:
	schema      int = 1
	uid         int
	plan_sha256 string
pub mut:
	jobs map[string]JobState
}

fn environment_name(name string) bool {
	return name.len > 0 && (name[0].is_letter() || name[0] == `_`)
		&& name.bytes().all(it.is_alnum() || it == `_`)
}

fn validate(plan Plan) ! {
	if plan.schema != 1 || plan.uid != os.getuid() || plan.jobs.len == 0 {
		return error('schedule must belong to the calling account')
	}
	mut names := map[string]bool{}
	for job in plan.jobs {
		if job.id == '' || job.id.len > 64 || !job.id.bytes().all(it.is_alnum() || it in [
			`-`,
			`_`,
		])
			|| names[job.id] || !job.directory.starts_with('/') || !os.is_dir(job.directory)
			|| job.interval_seconds < 1 || job.interval_seconds > 31 * 86400
			|| job.timeout_seconds < 1 || job.timeout_seconds > 86400
			|| job.arguments.any(it.contains('\x00')) {
			return error('invalid job: ${job.id}')
		}
		names[job.id] = true
		if !job.executable.path.starts_with('/') || !os.is_executable(job.executable.path) {
			return error('job requires an absolute executable: ${job.id}')
		}
		for name, value in job.environment {
			if !environment_name(name) || value.contains('\x00') {
				return error('invalid environment name/value')
			}
		}
		for name, path in job.credential_files {
			if !environment_name(name) || name in job.environment || !path.starts_with('/') || path.contains('\x00') {
				return error('invalid credential reference')
			}
		}
	}
}

// Check the opened descriptor, not a pathname followed by a separate open.
// Secret rotation cannot race the ownership/mode check into reading a link.
pub fn private_file(path string, limit int) !string {
	fd := unsafe { C.open(path.str, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW) }
	if fd < 0 { return error('cannot open private file: ${path}') }
	defer { C.close(fd) }
	mut st := C.stat{}
	if C.fstat(fd, &st) != 0 || u32(st.st_uid) != u32(os.getuid())
		|| u32(st.st_mode) & u32(C.S_IFMT) != u32(C.S_IFREG) || u32(st.st_mode) & 0o077 != 0 {
		return error('private file must be regular, owned by this account and mode 0600: ${path}')
	}
	mut data := []u8{len: limit + 1}
	mut used := 0
	for used < data.len {
		count := unsafe { C.read(fd, &data[used], usize(data.len - used)) }
		if count < 0 {
			if C.errno == C.EINTR { continue }
			return error('cannot read private file: ${path}')
		}
		if count == 0 { break }
		used += int(count)
	}
	if used > limit || data[..used].contains(0) {
		return error('invalid or oversized private file: ${path}')
	}
	return data[..used].bytestr()
}

fn write_atomic(path string, text string) ! {
	mut file := os.create(path + '.new')!
	defer { file.close() }
	file.write_string(text)!
	file.flush()
	if C.fsync(file.fd) != 0 {
		file.close()
		return os.error_posix()
	}
	file.close()
	os.chmod(path + '.new', 0o600)!
	os.rename(path + '.new', path)!
	directory := unsafe { C.open(os.dir(path).str, C.O_RDONLY | C.O_CLOEXEC | C.O_DIRECTORY) }
	if directory < 0 { return os.error_posix() }
	defer { C.close(directory) }
	if C.fsync(directory) != 0 { return os.error_posix() }
}

pub fn initialise(plan_text string, path string) ! {
	plan := json2.decode[Plan](plan_text, strict: true)!
	validate(plan)!
	for job in plan.jobs { devcore.verify(job.executable)! }
	devcore.fresh_directory(path)!
	write_atomic(path + '/plan.json', plan_text)!
	os.write_file(path + '/run.lock', '')!
	state := State{ uid: plan.uid, plan_sha256: devcore.file_hash(path + '/plan.json')!, jobs: map[string]JobState{} }
	write_atomic(path + '/state.json', json2.encode(state) + '\n')!
}

fn load(path string) !(Plan, State) {
	devcore.private_directory(path)!
	plan_text := private_file(path + '/plan.json', 1024 * 1024)!
	plan := json2.decode[Plan](plan_text, strict: true)!
	state := json2.decode[State](private_file(path + '/state.json', 1024 * 1024)!, strict: true)!
	validate(plan)!
	if state.schema != 1 || state.uid != os.getuid()
		|| state.plan_sha256 != devcore.file_hash(path + '/plan.json')! {
		return error('schedule identity or plan changed')
	}
	return plan, state
}

struct Clock {
	deadline u64
}

fn wait_job(pid int, raw voidptr) ! {
	clock := unsafe { &Clock(raw) }
	for !sourcecommand.child_exited(pid)! {
		if stdatomic.load_u64(&interrupted) != 0 { return error('job interrupted') }
		if time.sys_mono_now() >= clock.deadline { return error('job deadline expired') }
		time.sleep(10 * time.millisecond)
	}
}

fn execute(job Job) !int {
	devcore.verify(job.executable)!
	mut env := devcore.environment(0)
	for name, value in job.environment { env[name] = value }
	for name, path in job.credential_files { env[name] = private_file(path, 65536)! }
	clock := Clock{time.sys_mono_now() + u64(job.timeout_seconds) * u64(time.second)}
	// Receipts contain only status/times. Child output and credential values
	// never enter a scheduler log. The job can explicitly write its own files.
	result := sourcecommand.run_logged_owned([job.executable.path, ...job.arguments], env,
		unsafe { nil }, '/dev/null', false, job.directory, wait_job, unsafe { &clock }, 1)!
	return result.status
}

pub fn run_due(path string, now i64) !State {
	devcore.private_directory(path)!
	mut guard := filelock.new_file(path + '/run.lock', mode: .exclusive)
	if !guard.try_acquire() { return error('schedule already has an active runner') }
	defer { guard.release() }
	plan, mut state := load(path)!
	for job in plan.jobs {
		mut current := state.jobs[job.id] or { JobState{} }
		if current.in_flight || current.next_due > now { continue }
		if stdatomic.load_u64(&interrupted) != 0 { break }
		current.in_flight = true
		current.started = now
		current.detail = 'running'
		state.jobs[job.id] = current
		write_atomic(path + '/state.json', json2.encode(state) + '\n')!
		mut detail := 'finished'
		status := execute(job) or {
			detail = err.msg()
			-1
		}
		current.in_flight = false
		current.finished = time.now().unix()
		current.next_due = current.finished + job.interval_seconds
		current.exit_code = status
		current.detail = detail
		current.runs++
		state.jobs[job.id] = current
		write_atomic(path + '/state.json', json2.encode(state) + '\n')!
		println('${job.id}: ${status}')
	}
	return state
}

pub fn inspect(path string) !State {
	_, state := load(path)!
	return state
}

pub fn acknowledge(path string, name string) ! {
	devcore.private_directory(path)!
	mut guard := filelock.new_file(path + '/run.lock', mode: .exclusive)
	if !guard.try_acquire() { return error('schedule already has an active runner') }
	defer { guard.release() }
	_, mut state := load(path)!
	mut job := state.jobs[name] or { return error('unknown job') }
	if !job.in_flight { return error('job has no interrupted run to acknowledge') }
	job.in_flight = false
	job.next_due = time.now().unix()
	job.detail = 'interrupted run acknowledged by owner'
	state.jobs[name] = job
	write_atomic(path + '/state.json', json2.encode(state) + '\n')!
}

// Replace the polling process at each tick. On Vinix's gc-none runtime this
// releases the tick's V allocations instead of retaining them forever.
pub fn watch(path string) ! {
	run_due(path, time.now().unix())!
	if stdatomic.load_u64(&interrupted) != 0 { return }
	time.sleep(time.second)
	if stdatomic.load_u64(&interrupted) != 0 { return }
	argv := [os.executable(), 'watch', os.abs_path(path)]
	mut pointers := argv.map(unsafe { &char(it.str) })
	pointers << &char(unsafe { nil })
	unsafe { C.execv(argv[0].str, pointers.data) }
	return os.error_posix()
}
