// SPDX-License-Identifier: GPL-2.0-or-later
// Host lifecycle for one audited, credential-free diagnostic guest.
module main

import crypto.sha256
import json2
import os
import strconv
import time

#include <signal.h>

fn C.kill(int, int) int

const repo = '/Users/alex/code/vinix'
const qemu = repo + '/build/qemu-horizontal/bin/qemu-system-aarch64'
const firmware = '/opt/homebrew/share/qemu/edk2-aarch64-code.fd'
const source = $embed_file(@FILE).to_string()

struct Ownership {
	pid     int
	command string
	started string
}

struct Stage {
	format                int
	staged_boot_sha256    string
	staged_efivars_sha256 string
}

struct Execution {
	argv   []string
	code   int
	stdout string
	stderr string
}

fn hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := sha256.new()
	mut bytes := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut bytes) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		digest.write(bytes[..n])!
	}
	return digest.sum([]u8{}).hex()
}

fn execute(argv []string) !Execution {
	mut process := os.new_process(argv[0])
	process.set_args(argv[1..])
	process.set_stdin_path('/dev/null')
	process.set_redirect_stdio()
	process.run()
	defer { process.close() }
	mut stdout := ''
	mut stderr := ''
	deadline := time.sys_mono_now() + 15 * time.second
	for {
		stdout += process.stdout_read()
		stderr += process.stderr_read()
		if stdout.len + stderr.len > 1024 * 1024 || time.sys_mono_now() >= deadline {
			process.signal_kill()
			process.wait()
			return error('command output/deadline limit')
		}
		if !process.is_alive() { break }
		time.sleep(10 * time.millisecond)
	}
	process.wait()
	for {
		out := process.stdout_read()
		err := process.stderr_read()
		stdout += out
		stderr += err
		if stdout.len + stderr.len > 1024 * 1024 {
			return error('command output limit')
		}
		if out == '' && err == '' { break }
	}
	return Execution{argv, process.code, stdout, stderr}
}

fn checked(argv []string) !string {
	result := execute(argv)!
	if result.code != 0 { return error('command failed: ' + argv[0] + ': ' + result.stderr) }
	return result.stdout.trim_space()
}

fn canonical_root(path string) !string {
	absolute := os.abs_path(path)
	if !os.is_dir(absolute) || os.real_path(absolute) != absolute || absolute.contains_any(' \t\r\n,\x00') {
		return error('canonical directory without whitespace/comma required')
	}
	if absolute == repo || absolute.starts_with(repo + '/') {
		return error('external staged directory required')
	}
	if !os.is_file(absolute + '/stage.json') { return error('browser stage receipt required') }
	return absolute
}

fn qmp_check(root string) ! {
	if (root + '/qmp.sock').len >= 104 {
		return error('QMP Unix socket path must be shorter than 104 bytes')
	}
}

fn identity(pid int) !Ownership {
	if pid <= 1 { return error('invalid process ID') }
	return Ownership{pid, checked(['/bin/ps', '-ww', '-p', pid.str(), '-o', 'command='])!, checked([
		'/bin/ps',
		'-p',
		pid.str(),
		'-o',
		'lstart=',
	])!}
}

fn owned(root string) !Ownership {
	recorded := json2.decode[Ownership](os.read_file(root + '/ownership.json')!)!
	if strconv.atoi(os.read_file(root + '/qemu.pid')!.trim_space())! != recorded.pid {
		return error('PID receipt differs')
	}
	current := identity(recorded.pid)!
	if current != recorded || !current.command.starts_with(qemu + ' ')
		|| !current.command.contains('unix:' + root + '/qmp.sock,server=on,wait=off')
		|| !current.command.ends_with('-pidfile ' + root + '/qemu.pid') {
		return error('live process ownership differs; refusing signal')
	}
	return current
}

fn write_json(path string, value json2.Any) ! {
	mut file := os.open_file(path, 'wx', 0o600)!
	defer { file.close() }
	file.write_string(json2.encode(value, prettify: true) + '\n')!
}

fn start(root string) ! {
	qmp_check(root)!
	for name in ['launch.json', 'launch-result.json', 'ownership.json', 'qemu.pid', 'qmp.sock',
		'serial.log', 'network.pcap', 'stop.json', 'gone.json', 'run-source.v', 'runner'] {
		if os.exists(root + '/' + name) || os.is_link(root + '/' + name) {
			return error('guest can be launched once only: ' + name)
		}
	}
	for line in checked(['/bin/ps', '-axo', 'pid=,command='])!.split_into_lines() {
		if line.contains('qemu-system-aarch64 ') && line.contains(' -machine ') {
			return error('another aarch64 QEMU guest is live')
		}
	}
	stage := json2.decode[Stage](os.read_file(root + '/stage.json')!)!
	if stage.format != 1 || hash(root + '/boot.img')! != stage.staged_boot_sha256
		|| hash(root + '/efivars.fd')! != stage.staged_efivars_sha256 {
		return error('staged media changed')
	}
	args := ['-qmp', 'unix:' + root + '/qmp.sock,server=on,wait=off', '-machine', 'virt,gic-version=3',
		'-accel', 'hvf', '-cpu', 'host', '-m', '12288', '-smp', '4', '-object',
		'rng-random,filename=/dev/urandom,id=vinix-rng', '-device', 'virtio-rng-device', '-drive',
		'if=pflash,format=raw,readonly=on,file=' + firmware, '-drive',
		'if=pflash,format=raw,file=' + root + '/efivars.fd', '-drive',
		'format=raw,file=' + root + '/boot.img', '-device', 'virtio-keyboard-device', '-device',
		'virtio-tablet-device', '-device', 'ramfb', '-netdev', 'user,id=net0', '-device',
		'virtio-net-device,netdev=net0', '-object',
		'filter-dump,id=capture,netdev=net0,file=' + root + '/network.pcap', '-display', 'none',
		'-monitor', 'none', '-serial', 'file:' + root + '/serial.log', '-daemonize', '-pidfile',
		root + '/qemu.pid']
	mut argv := [qemu]
	argv << args
	os.write_file(root + '/run-source.v', source)!
	os.cp(os.executable(), root + '/runner')!
	write_json(root + '/launch.json', json2.decode[json2.Any](json2.encode({
		'argv':                 json2.Any(argv)
		'started_utc':          json2.Any(time.utc().str())
		'stage_sha256':         json2.Any(hash(root + '/stage.json')!)
		'qemu_sha256':          json2.Any(hash(qemu)!)
		'firmware_sha256':      json2.Any(hash(firmware)!)
		'runner_sha256':        json2.Any(hash(os.executable())!)
		'runner_source_sha256': json2.Any(sha256.sum(source.bytes()).hex())
		'scope':                json2.Any('Separate credential-free real-engine diagnostic; no Google authentication proof.')
	}))!)!
	result := execute(argv)!
	write_json(root + '/launch-result.json', json2.decode[json2.Any](json2.encode(result))!)!
	if result.code != 0 { return error('QEMU launch failed: ' + result.stderr) }
	pid := strconv.atoi(os.read_file(root + '/qemu.pid')!.trim_space())!
	write_json(root + '/ownership.json', json2.decode[json2.Any](json2.encode(identity(pid)!))!)!
	println('BROWSER-RUN STARTED pid=' + owned(root)!.pid.str() + ' state=' + root)
}

fn stopped(root string) !bool {
	recorded := json2.decode[Ownership](os.read_file(root + '/ownership.json')!)!
	result := execute(['/bin/ps', '-ww', '-p', recorded.pid.str(), '-o', 'command='])!
	if result.code == 1 && result.stdout.trim_space() == '' { return true }
	if result.code != 0 { return error('could not inspect guest process') }
	owned(root)!
	return false
}

fn stop(root string) ! {
	if os.exists(root + '/stop.json') || os.is_link(root + '/stop.json') {
		return error('stop already requested')
	}
	owner := owned(root)!
	if C.kill(owner.pid, C.SIGTERM) != 0 { return error('could not signal owned guest') }
	write_json(root + '/stop.json', json2.decode[json2.Any](json2.encode({
		'pid':           json2.Any(owner.pid)
		'signal':        json2.Any('SIGTERM')
		'requested_utc': json2.Any(time.utc().str())
	}))!)!
	deadline := time.sys_mono_now() + 5 * time.second
	for {
		if stopped(root)! {
			write_json(root + '/gone.json', json2.decode[json2.Any](json2.encode({
				'pid':         json2.Any(owner.pid)
				'checked_utc': json2.Any(time.utc().str())
				'check':       json2.Any('ps returned exit1 and empty command for recorded owned PID')
			}))!)!
			println('BROWSER-RUN STOPPED pid=' + owner.pid.str())
			return
		}
		if time.sys_mono_now() >= deadline {
			return error('owned guest remains after SIGTERM; no further signal sent')
		}
		time.sleep(100 * time.millisecond)
	}
}

fn self_test() ! {
	qmp_check('/tmp/browser-probe')!
	if _ := qmp_check('/' + 'x'.repeat(103)) { return error('oversized QMP path accepted') }
	if _ := canonical_root(repo) { return error('repository output accepted') }
	if _ := identity(1) { return error('unsafe PID accepted') }
	result := execute(['/bin/ps', '-p', os.getpid().str(), '-o', 'pid='])!
	assert result.code == 0 && result.stdout.trim_space() == os.getpid().str()
	output := execute([os.executable(), '--self-test-output'])!
	assert output.code == 0 && output.stdout == 'o'.repeat(65536) + '\n'
	assert output.stderr == 'e'.repeat(65536) + '\n'
	root := os.join_path(os.temp_dir(), 'vinix-browser-run-selftest-' + os.getpid().str())
	if os.exists(root) || os.is_link(root) { return error('selftest output exists') }
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	os.write_file(root + '/qemu.pid', os.getpid().str())!
	write_json(root + '/ownership.json', json2.decode[json2.Any](json2.encode(identity(os.getpid())!))!)!
	if _ := owned(root) { return error('non-QEMU process accepted as owned guest') }
	println('BROWSER-RUN SELF-TEST PASS qmp-length external-directory unsafe-pid bounded-command complete-output foreign-owner')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test-output' {
		println('o'.repeat(65536))
		eprintln('e'.repeat(65536))
		return
	}
	if os.args.len == 2 && os.args[1] == '--self-test' {
		self_test() or {
			eprintln(err.msg())
			exit(1)
		}
		return
	}
	if os.args.len != 3 || os.args[1] !in ['start', 'status', 'stop'] {
		eprintln('usage: run start|status|stop STAGED_EXTERNAL_DIRECTORY')
		exit(2)
	}
	root := canonical_root(os.args[2]) or {
		eprintln(err.msg())
		exit(1)
	}
	match os.args[1] {
		'start' {
			start(root) or {
				eprintln(err.msg())
				exit(1)
			}
		}
		'stop' {
			stop(root) or {
				eprintln(err.msg())
				exit(1)
			}
		}
		'status' {
			gone := stopped(root) or {
				eprintln(err.msg())
				exit(1)
			}
			println(if gone {
				'BROWSER-RUN STOPPED'
			} else {
				'BROWSER-RUN LIVE pid=' + owned(root) or {
					eprintln(err.msg())
					exit(1)
				}.pid.str()
			})
		}
		else {}
	}
}
