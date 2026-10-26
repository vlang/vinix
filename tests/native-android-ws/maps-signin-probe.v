// SPDX-License-Identifier: GPL-2.0-or-later
// Fresh diagnostic guest using unchanged Maps372 media; never overwrites evidence.
module main

import crypto.sha256
import json2
import os
import strconv
import time

#include <sys/clonefile.h>
#include <signal.h>

fn C.clonefile(&char, &char, int) int
fn C.kill(int, int) int

const repo = '/Users/alex/code/vinix'
const baseline = repo + '/build/android-maps/maps372/vm'
const qemu = repo + '/build/qemu-horizontal/bin/qemu-system-aarch64'
const firmware = '/opt/homebrew/share/qemu/edk2-aarch64-code.fd'
const source = repo + '/tests/native-android-ws/maps-signin-probe.v'
const scope = 'Unchanged Maps372 image baseline: anonymous operation previously qualified; Google account sign-in is unverified. No credentials supplied.'

struct Ownership {
	pid     int
	command string
	started string
}

fn checked(args []string) !string {
	r := os.exec(args)
	if r.exit_code != 0 { return error(args[0] + ' failed: ' + r.output) }
	return r.output.trim_space()
}

fn hash(path string) !string {
	if os.is_link(path) || os.lstat(path)!.get_filetype() != .regular {
		return error('regular input required: ' + path)
	}
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := sha256.new()
	mut bytes := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut bytes) or {
			if err.code() == 0 { break }
			return err
		}
		if n == 0 { break }
		digest.write(bytes[..n])!
	}
	return digest.sum([]u8{}).hex()
}

fn write_json[T](path string, data T) ! {
	os.write_file(path, json2.encode(data, prettify: true) + '\n')!
}

fn identity(pid int) !Ownership {
	if pid <= 1 { return error('invalid process ID') }
	return Ownership{
		pid:     pid
		command: checked(['/bin/ps', '-ww', '-p', pid.str(), '-o', 'command='])!
		started: checked(['/bin/ps', '-p', pid.str(), '-o', 'lstart='])!
	}
}

fn ownership(root string) !Ownership {
	if os.is_link(root) || os.real_path(root) != root {
		return error('canonical state directory required')
	}
	path := root + '/ownership.json'
	if os.is_link(path) { return error('linked ownership receipt rejected') }
	recorded := json2.decode[Ownership](os.read_file(path)!)!
	pid := strconv.atoi(os.read_file(root + '/qemu.pid')!.trim_space())!
	if recorded.pid != pid { return error('PID file differs from ownership receipt') }
	current := identity(pid)!
	if current != recorded || !current.command.starts_with(qemu + ' ')
		|| !current.command.contains('unix:' + root + '/qmp.sock,server=on,wait=off')
		|| !current.command.ends_with('-pidfile ' + root + '/qemu.pid') {
		return error('process ownership differs; refusing to signal')
	}
	return current
}

fn start(root string) ! {
	if root.contains(' ') || root.contains('\n') || root.contains('\t') {
		return error('state path must not contain whitespace')
	}
	if os.exists(root) || os.is_link(root) { return error('fresh state directory required') }
	listing := checked(['/bin/ps', '-axo', 'pid=,command='])!
	for line in listing.split_into_lines() {
		if line.contains(qemu + ' ') && (line.contains('/maps372/') || line.contains('/maps-signin-')) {
			return error('an existing Maps guest must be stopped by its owner first')
		}
	}
	os.mkdir_all(root)!
	mut inputs := map[string]string{}
	for path in [baseline + '/boot.img', baseline + '/efivars.fd', qemu, firmware, source] {
		inputs[path] = hash(path)!
	}
	for name in ['boot.img', 'efivars.fd'] {
		from := baseline + '/' + name
		to := root + '/' + name
		if C.clonefile(from.str, to.str, 0) != 0 { return error('APFS clone failed: ' + name) }
		if hash(to)! != inputs[from] { return error('clone hash differs: ' + name) }
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
	write_json(root + '/launch-before.json', {
		'scope':           json2.Any(scope)
		'source_revision': json2.Any(checked(['/usr/bin/git', '-C', repo, 'rev-parse', 'HEAD'])!)
		'input_sha256':    json2.decode[json2.Any](json2.encode(inputs))!
		'argv':            json2.Any([qemu, ...args])
		'started_utc':     json2.Any(time.utc().str())
	})!
	r := os.exec([qemu, ...args])
	write_json(root + '/launch-result.json', {
		'exit_code':     json2.Any(r.exit_code)
		'output':        json2.Any(r.output)
		'completed_utc': json2.Any(time.utc().str())
	})!
	if r.exit_code != 0 { return error('QEMU launch failed: ' + r.output) }
	pid := strconv.atoi(os.read_file(root + '/qemu.pid')!.trim_space())!
	write_json(root + '/ownership.json', identity(pid)!)!
	ownership(root)!
	println('MAPS-SIGNIN-PROBE-STARTED pid=' + pid.str() + ' state=' + root)
	println(scope)
}

fn stop(root string) ! {
	owned := ownership(root)!
	if C.kill(owned.pid, C.SIGTERM) != 0 { return error('could not signal owned QEMU') }
	write_json(root + '/stop.json', {
		'pid':           json2.Any(owned.pid)
		'signal':        json2.Any('SIGTERM')
		'requested_utc': json2.Any(time.utc().str())
	})!
	println('MAPS-SIGNIN-PROBE-STOP-SENT pid=' + owned.pid.str())
}

fn self_test(root string) ! {
	if os.exists(root) || os.is_link(root) { return error('fresh test directory required') }
	os.mkdir_all(root)!
	mut sleeper := os.new_process('/bin/sleep')
	sleeper.set_args(['30'])
	sleeper.run()
	defer {
		if sleeper.is_alive() { sleeper.signal_term() }
		sleeper.wait()
		sleeper.close()
	}
	if sleeper.pid <= 1 { return error('test process failed to start') }
	write_json(root + '/ownership.json', identity(sleeper.pid)!)!
	os.write_file(root + '/qemu.pid', sleeper.pid.str() + '\n')!
	mut rejected := false
	stop(root) or { rejected = true }
	if !rejected || !sleeper.is_alive() || os.exists(root + '/stop.json') {
		return error('unrelated live process was not protected')
	}
	write_json(root + '/self-test.json', {
		'unrelated_process_rejected':            json2.Any(true)
		'unrelated_process_alive_after_refusal': json2.Any(true)
	})!
	println('MAPS-SIGNIN-PROBE-SELF-TEST-PASS unrelated live process protected')
}

fn main() {
	if os.args.len != 3 || os.args[1] !in ['start', 'status', 'stop', 'self-test'] {
		eprintln('usage: maps-signin-probe start|status|stop|self-test /external/fresh-state')
		exit(2)
	}
	root := os.abs_path(os.args[2])
	match os.args[1] {
		'start' {
			start(root) or {
				eprintln(err)
				exit(1)
			}
		}
		'stop' {
			stop(root) or {
				eprintln(err)
				exit(1)
			}
		}
		'self-test' {
			self_test(root) or {
				eprintln(err)
				exit(1)
			}
		}
		else {
			owned := ownership(root) or {
				eprintln(err)
				exit(1)
			}
			println('MAPS-SIGNIN-PROBE-OWNED pid=' + owned.pid.str() + ' state=' + root)
		}
	}
}
