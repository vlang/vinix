// Private Linux reference runner. All guest and controller inputs are pinned.
import crypto.sha256
import json2
import os
import time

const previous = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'

struct Receipt {
	architecture string
	context string = 'Unmodified Linux reference; unchanged native semaphore probe; semantics only'
	command []string
	inputs map[string]string
	serial_sha256 string
	passed bool
	verdict_seen bool
	termination string
	qemu_status int
	started string
	finished string
}

fn digest(path string) string {
	return sha256.sum(os.read_bytes(path) or { panic(err) }).hex()
}

fn entry(mut archive []u8, name string, mode u32, inode u32, data []u8, major u32, minor u32) {
	mut header := '070701'
	for value in [inode, mode, u32(0), 0, 1, 0, u32(data.len), 0, 0, major, minor, u32(name.len + 1), 0]! {
		header += '${value:08x}'
	}
	archive << header.bytes()
	archive << name.bytes()
	archive << u8(0)
	for archive.len % 4 != 0 { archive << u8(0) }
	archive << data
	for archive.len % 4 != 0 { archive << u8(0) }
}

fn valid(text string) bool {
	if !text.contains('Linux version ') || !text.contains('LINUX SEMABI REFERENCE: PASS') {
		return false
	}
	for bad in ['LINUX SEMABI FAIL', 'LINUX SEMABI: FAIL', 'LINUX SEMABI MISMATCH', 'REFERENCE FAIL', 'Kernel panic', 'BUG:'] {
		if text.contains(bad) { return false }
	}
	mut summaries := 0
	for line in text.split_into_lines() {
		if !line.starts_with('LINUX SEMABI SUMMARY: checks=') { continue }
		parts := line.trim_space().fields()
		if parts.len != 5 || parts[3].all_after('checks=').int() <= 0 || parts[4] != 'failures=0' {
			return false
		}
		summaries++
	}
	return summaries == 1
}

fn run() ! {
	assert os.args.len == 5, 'Usage: reference arm|x86 PROBE_ELF LAUNCHER_ELF FRESH_STATE'
	suffix := os.args[1]
	assert suffix in ['arm', 'x86']
	arch := if suffix == 'arm' { 'aarch64' } else { 'x86_64' }
	probe := os.real_path(os.args[2])
	launcher := os.real_path(os.args[3])
	state := os.args[4]
	assert !os.exists(state), 'Refusing to overwrite a reference attempt'
	for path in [probe, launcher] {
		bytes := os.read_bytes(path)!
		assert bytes.len >= 20 && bytes[..6] == [u8(127), `E`, `L`, `F`, 2, 1]
		assert int(bytes[18]) + (int(bytes[19]) << 8) == if suffix == 'arm' { 183 } else { 62 }
	}
	os.mkdir_all(state)!
	work := os.real_path(state)
	linux := previous + '/states/final2-reference-' + suffix + '/linux'
	mut inputs := {
		probe: digest(probe)
		launcher: digest(launcher)
		linux: digest(linux)
		@FILE: digest(@FILE)
		os.executable(): digest(os.executable())
	}
	for name, path in {'probe': probe, 'init': launcher, 'linux': linux} {
		os.write_file_array(work + '/' + name, os.read_bytes(path)!)!
		assert digest(work + '/' + name) == inputs[path]!
	}
	mut archive := []u8{}
	for index, directory in ['.', 'dev', 'tmp', 'sbin', 'proc'] {
		entry(mut archive, directory, 0o040755, u32(index + 1), []u8{}, 0, 0)
	}
	entry(mut archive, 'dev/console', 0o020600, 10, []u8{}, 5, 1)
	entry(mut archive, 'dev/null', 0o020666, 11, []u8{}, 1, 3)
	entry(mut archive, 'sbin/probe', 0o100755, 12, os.read_bytes(work + '/probe')!, 0, 0)
	entry(mut archive, 'init', 0o100755, 13, os.read_bytes(work + '/init')!, 0, 0)
	entry(mut archive, 'TRAILER!!!', 0, 14, []u8{}, 0, 0)
	os.write_file_array(work + '/initramfs.cpio', archive)!
	inputs[work + '/initramfs.cpio'] = digest(work + '/initramfs.cpio')
	mut command := if suffix == 'arm' {
		[os.find_abs_path_of_executable('qemu-system-aarch64')!, '-machine', 'virt', '-accel', 'hvf', '-cpu', 'host']
	} else {
		[os.find_abs_path_of_executable('qemu-system-x86_64')!, '-machine', 'q35', '-accel', 'tcg', '-cpu', 'max']
	}
	inputs[command[0]] = digest(command[0])
	serial := work + '/serial.log'
	command << ['-m', '512', '-smp', '2', '-kernel', work + '/linux', '-initrd', work + '/initramfs.cpio',
		'-append', if suffix == 'arm' { 'console=ttyAMA0 rdinit=/init panic=-1' } else { 'console=ttyS0 rdinit=/init panic=-1' },
		'-display', 'none', '-monitor', 'none', '-serial', 'file:' + serial, '-no-reboot']
	os.write_file(work + '/inputs.json', json2.encode(inputs, prettify: true) + '\n')!
	os.write_file(work + '/command.json', json2.encode(command, prettify: true) + '\n')!
	started := time.utc().str()
	mut process := os.new_process(command[0])
	process.set_args(command[1..])
	process.set_redirect_stdio()
	process.run()
	deadline := time.now().unix_milli() + 600000
	mut verdict_seen := false
	mut reason := 'deadline reached'
	for process.is_alive() {
		text := os.read_file(serial) or { '' }
		if text.contains('LINUX SEMABI REFERENCE: PASS') || text.contains('LINUX SEMABI: FAIL') || text.contains('LINUX SEMABI FAIL') || text.contains('Kernel panic') || text.contains('REFERENCE FAIL') {
			verdict_seen = true
			reason = 'Controller terminated paused guest after serial verdict'
			break
		}
		if time.now().unix_milli() >= deadline { break }
		time.sleep(100 * time.millisecond)
	}
	if process.is_alive() { process.signal_term() }
	process.wait()
	qemu_output := process.stdout_slurp() + process.stderr_slurp()
	status := process.code
	process.close()
	os.write_file(work + '/qemu.log', qemu_output)!
	text := os.read_file(serial) or { '' }
	mut passed := verdict_seen && valid(text)
	for path, expected in inputs {
		if digest(path) != expected { passed = false }
	}
	os.write_file(work + '/receipt.json', json2.encode(Receipt{
		architecture: arch
		command: command
		inputs: inputs
		serial_sha256: digest(serial)
		passed: passed
		verdict_seen: verdict_seen
		termination: reason
		qemu_status: status
		started: started
		finished: time.utc().str()
	}, prettify: true) + '\n')!
	os.write_file(work + '/status', if passed { '0\n' } else { '1\n' })!
	assert passed, 'Linux reference failed; inspect ' + work
	println('Linux semaphore reference: PASS ' + arch)
}

fn main() {
	run() or { eprintln(err.msg()); exit(1) }
}
