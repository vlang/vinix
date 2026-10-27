// SPDX-License-Identifier: GPL-2.0-or-later
// A sampled host build guard. No shell, unbounded capture, or per-PID RSS check.
module main

import json2
import os
import strconv
import time

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <unistd.h>

fn C.getpgid(int) int
fn C.fsync(int) int

struct Limits {
mut:
	rss u64 = u64(2) * 1024 * 1024 * 1024
	wall_ms i64 = 300_000
	reserve u64 = 1024 * 1024 * 1024
	growth u64 = 512 * 1024 * 1024
	output u64 = 4 * 1024 * 1024
}

struct Receipt {
	argv []string
	generated_root string
	log string
	limits Limits
mut:
	pid int
	exit_code int = 125
	child_exit_code int = -1
	reason string
	cleanup_complete bool
	elapsed_ms i64
	peak_sampled_rss_bytes u64
	rss_samples int
	initial_free_bytes u64
	minimum_free_bytes u64
	maximum_observed_disk_growth_bytes u64
	output_bytes u64
	supervised_groups []int
}

fn monotonic_ms() i64 { return time.sys_mono_now() / time.millisecond }

fn fresh_file(path string) !int {
	fd := C.open(&char(path.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_CLOEXEC, 0o600)
	if fd < 0 { return error('cannot create fresh file: ' + path) }
	return fd
}

fn write_all(fd int, data []u8) ! {
	mut written := 0
	for written < data.len {
		n := C.write(fd, unsafe { &u8(data.data) + written }, usize(data.len - written))
		if n < 0 && C.errno == C.EINTR { continue }
		if n <= 0 { return error('file write failed') }
		written += int(n)
	}
}

fn number(s string) !u64 {
	if s == '' || !s.bytes().all(it >= `0` && it <= `9`) { return error('invalid unsigned integer') }
	return strconv.parse_uint(s, 10, 64)
}

fn group_present(pid int) !bool {
	if pid <= 1 || pid == C.getpgid(0) { return error('unsafe process group') }
	if C.kill(-pid, 0) == 0 { return true }
	saved_errno := int(C.errno)
	if saved_errno == C.ESRCH { return false }
	if saved_errno == C.EPERM {
		table := probe(['/bin/ps', '-axo', 'pid=,ppid=,pgid=,rss='])!
		for line in table.split_into_lines() {
			fields := line.fields()
			if fields.len != 4 { return error('invalid group probe row') }
			if number(fields[2])! == u64(pid) { return true }
		}
		return false
	}
	return error('process group probe failed errno=' + saved_errno.str())
}

fn cleanup(mut p os.Process) ! { cleanup_group(mut p, true)! }

fn cleanup_group(mut p os.Process, scan_members bool) ! {
	if p.pid <= 1 { return }
	start := monotonic_ms()
	for {
		if !scan_members {
			// Fixed system monitor tools spawn no children. Avoid recursively
			// starting a monitor to clean up another monitor.
			if !p.is_alive() { return }
			if C.getpgid(p.pid) == p.pid { C.kill(i32(p.pid), C.SIGKILL) }
			if monotonic_ms() - start >= 2000 { return error('monitor cleanup timed out') }
			time.sleep(10 * time.millisecond)
			continue
		}
		present := group_present(p.pid)!
		if present {
			killed := C.kill(-p.pid, C.SIGKILL)
			saved_errno := int(C.errno)
			if killed != 0 && saved_errno == C.EPERM {
				// Some host policies reject negative-PGID signals. Enumerate only
				// this group and verify membership again immediately before kill.
				table := probe(['/bin/ps', '-axo', 'pid=,ppid=,pgid=,rss='])!
				for line in table.split_into_lines() {
					fields := line.fields()
					if fields.len != 4 { return error('invalid cleanup ps row') }
					pid := number(fields[0])!; group := number(fields[2])!
					if pid > 0x7fffffff { return error('cleanup pid overflow') }
					if group == u64(p.pid) && pid > 1 && C.getpgid(int(pid)) == p.pid {
						result := C.kill(i32(pid), C.SIGKILL)
						code := int(C.errno)
						if result != 0 && code != C.ESRCH { return error('cannot stop group member') }
					}
				}
			} else if killed != 0 && saved_errno != C.ESRCH { return error('cannot kill process group errno=' + saved_errno.str()) }
		}
		alive := p.is_alive()
		if !alive && !group_present(p.pid)! { return }
		if monotonic_ms() - start >= 2000 { return error('process group cleanup timed out') }
		time.sleep(10 * time.millisecond)
	}
}

fn start_command(args []string) !&os.Process {
	mut p := os.new_process(args[0])
	p.set_args(args[1..])
	p.set_redirect_stdio_merged()
	p.set_stdin_path('/dev/null')
	p.use_pgroup = true
	p.run()
	if p.pid <= 1 { p.close(); return error('cannot spawn command') }
	C.close(p.stdio_fd[0]); p.stdio_fd[0] = -1
	flags := C.fcntl(p.stdio_fd[1], C.F_GETFL, 0)
	if flags < 0 || C.fcntl(p.stdio_fd[1], C.F_SETFL, flags | C.O_NONBLOCK) < 0 {
		cleanup(mut p) or {}; p.close(); return error('cannot make output nonblocking')
	}
	// The child establishes its group before exec; wait out the fork race.
	start := monotonic_ms()
	for C.getpgid(p.pid) != p.pid {
		if !p.is_alive() { return p }
		if monotonic_ms() - start >= 1000 {
			// This PID is still our unreaped live child; never signal a reused PID.
			C.kill(p.pid, C.SIGKILL)
			p.wait(); p.close(); return error('command did not establish its process group')
		}
		time.sleep(time.millisecond)
	}
	return p
}

// One bounded read, including explicit EOF. The caller must keep draining while
// monitoring so a compiler can never block the supervisor on a full pipe.
fn read_block(mut p os.Process, mut buf []u8) !(int, bool) {
	n := C.read(p.stdio_fd[1], buf.data, usize(buf.len))
	saved_errno := int(C.errno)
	if n > 0 { return int(n), false }
	if n == 0 { return 0, true }
	if saved_errno in [C.EINTR, C.EAGAIN] { return 0, false }
	return error('output pipe read failed')
}

// ps and df are themselves bounded, including their pipe output and descendants.
fn probe(args []string) !string {
	mut p := start_command(args)!
	defer { cleanup_group(mut p, false) or {}; p.close() }
	start := monotonic_ms()
	mut result := []u8{cap: 8192}
	mut buf := []u8{len: 8192}
	for {
		n, eof := read_block(mut p, mut buf)!
		if result.len + n > 1024 * 1024 { return error('monitor output exceeds 1 MiB') }
		result << buf[..n]
		alive := p.is_alive()
		if !alive && eof {
			if p.code != 0 { return error('monitor command failed') }
			return result.bytestr()
		}
		if monotonic_ms() - start >= 1000 { return error('monitor command exceeded one second') }
		if n == 0 { time.sleep(time.millisecond) }
	}
	return error('unreachable probe state')
}

struct ProcessRow { pid int; parent int; group int; rss u64 }

fn process_rows(table string) ![]ProcessRow {
	mut rows := []ProcessRow{}
	for line in table.split_into_lines() {
		fields := line.fields()
		if fields.len == 0 { continue }
		if fields.len != 4 { return error('invalid ps row') }
		pid := number(fields[0])!; parent := number(fields[1])!; group := number(fields[2])!
		rss := number(fields[3])!
		if pid > 0x7fffffff || parent > 0x7fffffff || group > 0x7fffffff || rss > ~u64(0) / 1024 {
			return error('ps integer overflow')
		}
		rows << ProcessRow{int(pid), int(parent), int(group), rss * 1024}
	}
	return rows
}

struct Supervision {
	guard_group int
mut:
	groups map[int]bool
	unowned map[int]bool
	retired map[int]bool
	history []int
}

fn supervision(before []ProcessRow, leader int) Supervision {
	mut result := Supervision{guard_group: C.getpgid(0)}
	for row in before { result.unowned[row.group] = true }
	result.groups[leader] = true
	result.history << leader
	return result
}

// A nested group is owned only when its leader is an observed descendant and
// the group did not exist before spawn. Keep it after reparenting, until empty.
fn supervised_rss(rows []ProcessRow, mut state Supervision) !u64 {
	mut present := map[int]bool{}
	for row in rows { present[row.group] = true }
	for group in state.groups.keys() {
		if !present[group] { state.groups.delete(group); state.retired[group] = true }
	}
	mut selected := map[int]bool{}
	for row in rows { if state.groups[row.group] { selected[row.pid] = true } }
	for _ in 0 .. rows.len {
		mut changed := false
		for row in rows {
			if !selected[row.pid] && (selected[row.parent] || state.groups[row.group]) {
				selected[row.pid] = true; changed = true
			}
			if selected[row.pid] && row.pid == row.group && !state.groups[row.group] &&
				row.group > 1 && row.group != state.guard_group && !state.unowned[row.group] && !state.retired[row.group] {
				state.groups[row.group] = true
				state.history << row.group
				changed = true
			}
		}
		if !changed { break }
	}
	mut total := u64(0)
	mut refusal := false
	for row in rows {
		if selected[row.pid] {
			if !state.groups[row.group] { refusal = true }
			if row.rss > ~u64(0) - total { return error('RSS aggregate overflow') }
			total += row.rss
		}
	}
	if refusal { return error('descendant joined an unowned process group') }
	return total
}

fn cleanup_supervised(mut p os.Process, mut state Supervision) ! {
	start := monotonic_ms()
	mut problem := ''
	for {
		rows := process_rows(probe(['/bin/ps', '-axo', 'pid=,ppid=,pgid=,rss='])!)!
		// Discover groups made since the last sample before stopping their parents.
		supervised_rss(rows, mut state) or { problem = err.msg() }
		for group, _ in state.groups {
			if group <= 1 || group == state.guard_group || state.unowned[group] {
				return error('unsafe supervised cleanup group')
			}
			if C.kill(-group, C.SIGKILL) != 0 {
				code := int(C.errno)
				if code != C.EPERM && code != C.ESRCH { return error('cannot kill supervised group') }
				if code == C.EPERM {
					for row in rows {
						if row.group == group && row.pid > 1 && C.getpgid(row.pid) == group {
							if C.kill(row.pid, C.SIGKILL) != 0 && C.errno != C.ESRCH {
								return error('cannot stop supervised group member')
							}
						}
					}
				}
			}
		}
		alive := p.is_alive()
		if !alive && state.groups.len == 0 {
			if problem != '' { return error(problem + '; unowned descendants not claimed as cleaned') }
			return
		}
		if monotonic_ms() - start >= 2000 { return error('supervised process group cleanup timed out') }
		time.sleep(10 * time.millisecond)
	}
}

fn free_bytes(path string) !u64 {
	text := probe(['/bin/df', '-Pk', path])!
	lines := text.trim_space().split_into_lines()
	if lines.len != 2 { return error('unexpected df output') }
	fields := lines[1].fields()
	if fields.len < 6 { return error('invalid df row') }
	available := number(fields[3])!
	if available > ~u64(0) / 1024 { return error('df integer overflow') }
	return available * 1024
}

fn outside(path string, root string) bool { return path != root && !path.starts_with(root + os.path_separator) }

// Subtraction after the reserve check avoids overflow for large explicit reserves.
fn disk_budget_backed(available u64, reserve u64, growth u64) bool {
	return available >= reserve && available - reserve >= growth
}

fn run(args []string) !int {
	separator := args.index('--')
	if separator < 0 || separator + 1 >= args.len { return error('missing -- COMMAND [ARGS]') }
	mut root := ''; mut log := ''; mut receipt_path := ''; mut limits := Limits{}
	for item in args[..separator] {
		key, value := item.split_once('=') or { return error('expected key=value') }
		match key {
			'root' { root = value }
			'log' { log = value }
			'receipt' { receipt_path = value }
			'rss' { limits.rss = number(value)! }
			'wall_ms' { n := number(value)!; if n > 300_000 { return error('wall limit exceeds 300 seconds') }; limits.wall_ms = i64(n) }
			'reserve' { limits.reserve = number(value)! }
			'growth' { limits.growth = number(value)! }
			'output' { limits.output = number(value)! }
			else { return error('unknown option: ' + key) }
		}
	}
	if limits.rss == 0 || limits.rss > 2 * u64(1024 * 1024 * 1024) || limits.wall_ms <= 0 || limits.output == 0 || limits.output > 4 * u64(1024 * 1024) || limits.reserve < 1024 * u64(1024 * 1024) || limits.growth > 8 * u64(1024 * 1024 * 1024) {
		return error('invalid resource limit')
	}
	if root == '' || log == '' || receipt_path == '' { return error('root, log and receipt paths required') }
	// Producers normally demand an absent output directory. Resolve its existing
	// parent without creating the directory or changing that contract.
	if !os.is_dir(os.dir(root)) { return error('generated root parent must exist') }
	root = os.join_path(os.real_path(os.dir(root)), os.base(root))
	if os.exists(root) {
		if !os.is_dir(root) || os.is_link(root) { return error('generated root must be a directory, not a link') }
		root = os.real_path(root)
	}
	disk_path := if os.is_dir(root) { root } else { os.dir(root) }
	log = os.join_path(os.real_path(os.dir(log)), os.base(log))
	receipt_path = os.join_path(os.real_path(os.dir(receipt_path)), os.base(receipt_path))
	if !outside(log, root) || !outside(receipt_path, root) || log == receipt_path {
		return error('log and receipt must be outside generated root')
	}
	receipt_fd := fresh_file(receipt_path)!
	defer { C.close(receipt_fd) }
	mut report := Receipt{argv: args[separator + 1..].clone(), generated_root: root, log: log, limits: limits}
	start := monotonic_ms()
	defer {
		report.elapsed_ms = monotonic_ms() - start
		write_all(receipt_fd, (json2.encode(report, prettify: true) + '\n').bytes()) or { eprintln('receipt write failed: ${err}'); exit(125) }
		C.fsync(receipt_fd)
	}
	output_fd := fresh_file(log) or { report.reason = 'cannot create fresh log'; return 125 }
	defer { C.close(output_fd) }
	initial := free_bytes(disk_path) or { report.reason = 'initial disk probe failed: ' + err.msg(); return 125 }
	report.initial_free_bytes = initial; report.minimum_free_bytes = initial
	if initial < limits.reserve { report.reason = 'disk reserve'; return 125 }
	if !disk_budget_backed(initial, limits.reserve, limits.growth) {
		report.reason = 'disk growth budget'; return 125
	}
	before := process_rows(probe(['/bin/ps', '-axo', 'pid=,ppid=,pgid=,rss='])!)!
	mut p := start_command(report.argv) or { report.reason = err.msg(); return 125 }
	report.pid = p.pid
	mut state := supervision(before, p.pid)
	defer { report.supervised_groups = state.history.clone() }
	defer { p.close() }
	mut buf := []u8{len: 8192}
	mut next_sample := i64(0)
	for {
		if monotonic_ms() - start >= limits.wall_ms { report.reason = 'wall time'; break }
		// At most 64 KiB per turn so a noisy child cannot starve monitoring.
		mut eof := false
		for _ in 0 .. 8 {
			n, done := read_block(mut p, mut buf) or { report.reason = err.msg(); break }
			eof = done
			if n == 0 { break }
			remaining := limits.output - report.output_bytes
			keep := if u64(n) > remaining { int(remaining) } else { n }
			write_all(output_fd, buf[..keep]) or { report.reason = 'log write failed'; break }
			report.output_bytes += u64(keep)
			if u64(n) > remaining { report.reason = 'output limit'; break }
		}
		if report.reason != '' { break }
		alive := p.is_alive()
		if !alive && eof { report.child_exit_code = p.code; report.exit_code = p.code; break }
		if monotonic_ms() >= next_sample {
			table := probe(['/bin/ps', '-axo', 'pid=,ppid=,pgid=,rss=']) or { report.reason = 'RSS probe failed: ' + err.msg(); break }
			rows := process_rows(table) or { report.reason = err.msg(); break }
			rss := supervised_rss(rows, mut state) or { report.reason = err.msg(); break }
			report.rss_samples++
			if rss > report.peak_sampled_rss_bytes { report.peak_sampled_rss_bytes = rss }
			if rss > limits.rss { report.reason = 'aggregate RSS'; break }
			available := free_bytes(disk_path) or { report.reason = 'disk probe failed: ' + err.msg(); break }
			if available < report.minimum_free_bytes { report.minimum_free_bytes = available }
			growth := if initial > available { initial - available } else { u64(0) }
			if growth > report.maximum_observed_disk_growth_bytes { report.maximum_observed_disk_growth_bytes = growth }
			if available < limits.reserve { report.reason = 'disk reserve'; break }
			if growth > limits.growth { report.reason = 'observed disk growth'; break }
			next_sample = monotonic_ms() + 100
		}
		time.sleep(2 * time.millisecond)
	}
	cleanup_supervised(mut p, mut state) or { report.reason += '; ' + err.msg(); report.exit_code = 125; return 125 }
	report.cleanup_complete = true
	report.child_exit_code = p.code
	// Also enforce disk bounds for commands that finish between samples.
	available := free_bytes(disk_path) or { report.reason += '; final disk probe failed'; report.exit_code = 125; return 125 }
	if available < report.minimum_free_bytes { report.minimum_free_bytes = available }
	growth := if initial > available { initial - available } else { u64(0) }
	if growth > report.maximum_observed_disk_growth_bytes { report.maximum_observed_disk_growth_bytes = growth }
	if available < limits.reserve { report.reason = 'disk reserve' }
	if growth > limits.growth { report.reason = 'observed disk growth' }
	if report.reason != '' { report.exit_code = 125 }
	return report.exit_code
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' {
		assert disk_budget_backed(0, 0, 0)
		assert disk_budget_backed(9, 1, 8)
		assert !disk_budget_backed(8, 1, 8)
		assert !disk_budget_backed(0, ~u64(0), 1)
		assert !disk_budget_backed(~u64(0), ~u64(0), 1)
		assert disk_budget_backed(~u64(0), ~u64(0), 0)
		mut state := supervision([ProcessRow{99, 1, 99, 1}], 31)
		first := supervised_rss([ProcessRow{34, 1, 32, 5}, ProcessRow{31, 1, 31, 10}, ProcessRow{32, 31, 32, 20}], mut state) or { panic(err) }
		assert first == 35
		assert state.groups[32]
		orphan := supervised_rss([ProcessRow{33, 1, 32, 40}], mut state) or { panic(err) }
		assert orphan == 40
		assert !state.groups[31] && state.retired[31]
		empty := supervised_rss([]ProcessRow{}, mut state) or { panic(err) }
		assert empty == 0
		assert state.groups.len == 0 && state.retired[32]
		for rejected in [99, C.getpgid(0)] {
			mut refusal := supervision([ProcessRow{99, 1, 99, 1}], 31)
			mut refused := false
			supervised_rss([ProcessRow{31, 1, 31, 10}, ProcessRow{rejected, 31, rejected, 20}], mut refusal) or {
				refused = true
			}
			assert refused && !refusal.groups[rejected]
		}
		println('BOUNDED-COMMAND-SELF-PASS backed-disk-budget overflow-refusal nested-ownership retired-groups unowned-refusal')
		return
	}
	code := run(os.args[1..]) or {
		eprintln('bounded-command: ${err}\nusage: bounded-command root=GENERATED_DIR log=FRESH_LOG receipt=FRESH_JSON -- COMMAND [ARGS]')
		exit(125)
	}
	exit(code)
}
