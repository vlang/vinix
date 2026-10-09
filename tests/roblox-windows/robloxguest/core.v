// SPDX-License-Identifier: MIT
module robloxguest

import androidhost as ah
import gapcore as gc
import json2

fn global(name string) !string {
	return gc.callback('resolve', {
		'name': ah.Value(name)
	})!.text()
}

fn float(text string) ah.Value { return v(ah.Value(ah.Number{text})) }

fn close_guest(pid string, master string) ! {
	gc.callback('retiring', {}) or {
		failure := err
		gc.activate(failure, true)!
		stop_owned(pid, master)!
		return failure
	}
	stop_owned(pid, master)!
}

fn stop_owned(pid string, master string) ! {
	stop_process(pid, master) or { return err }
	call('os.close', o(master))!
	gc.callback('closed', {})!
}

fn terminate(pid string, master string) ! {
	call('os.write', o(master), b('0178'))!
	call('time.sleep', n(1))!
	call('os.killpg', o(pid), o(global('signal.SIGTERM')!))!
}

fn stop_process(pid string, master string) ! {
	terminate(pid, master) or {
		if !exception_any(err, ['OSError', 'ProcessLookupError'])! {
			return err
		}
	}
	gc.activate(none, false)!
	deadline := call('operator.add', o(call('time.monotonic')!), n(5))!
	for compare('lt', call('time.monotonic')!, o(deadline))! {
		waited := call('os.waitpid', o(pid), o(global('os.WNOHANG')!))!
		if eq(get(waited, n(0))!, o(pid))! {
			gc.callback('reaped', {})!
			return
		}
		call('time.sleep', float('0.1'))!
	}
	kill(pid)!
	gc.activate(none, false)!
	waited := call('os.waitpid', o(pid), o(global('os.WNOHANG')!))!
	if eq(get(waited, n(0))!, o(pid))! { gc.callback('reaped', {})! }
}

fn kill(pid string) ! {
	call('os.killpg', o(pid), o(global('signal.SIGKILL')!)) or {
		failure := err
		if !exception_is(failure, 'OSError')! { return failure }
		gc.activate(failure, true)!
		call('os.kill', o(pid), o(global('signal.SIGKILL')!)) or {
			if !exception_is(err, 'ProcessLookupError')! {
				return err
			}
		}
	}
}

fn exception_is(failure IError, name string) !bool {
	return gc.flag(gc.callback('exception_matches', {
		'error': gc.error_detail(failure)
		'class': ah.Value(global(name)!)
	})!)
}

fn exception_any(failure IError, names []string) !bool {
	mut ids := []ah.Value{}
	for name in names { ids << ah.Value(global(name)!) }
	return gc.flag(gc.callback('exception_matches', {
		'error':   gc.error_detail(failure)
		'classes': ah.Value(ids)
	})!)
}

fn environment(args string, work string, archive string) !string {
	env := method(global('os.environ')!, 'copy', [], {})!
	config := dict()!
	for row in [['VINIX_KERNEL_DIR', call('str', o(attr(args, 'kernel_dir')!))!],
		['VINIX_INITRAMFS', call('str', o(archive))!],
		['VINIX_INITRAMFS_COMPRESSED', literal(ah.Value('0'))!],
		['VINIX_QEMU_ROOT_DISK', literal(ah.Value('0'))!],
		['VINIX_BOOT_DISK', call('str', o(join(work, 'boot.img')!))!],
		['VINIX_EFIVARS', call('str', o(join(work, 'efivars.fd')!))!],
		['VINIX_BOOT_DISK_SIZE_MB', literal(ah.Value('4096'))!],
		['VINIX_QEMU_PACKAGE_STORE', call('str', o(join(work, 'packages.tar')!))!],
		['VINIX_QEMU_PACKAGE_PERSIST', literal(ah.Value('0'))!],
		['VINIX_QEMU_HOST_SOURCE', literal(ah.Value('0'))!],
		['VINIX_QEMU_AUDIO', literal(ah.Value('off'))!],
		['VINIX_QEMU_SMP', call('str', o(attr(args, 'cpus')!))!],
		['VINIX_KEEP_TEMP_BOOT_DISK', literal(ah.Value('1'))!]] {
		set(config, row[0], o(row[1]))!
	}
	method(env, 'update', [o(config)], {})!
	return env
}

fn archive(root string, work string) !string {
	path := join(work, 'initramfs.tar')!
	manager := invoke('tarfile.open', [o(path), s('w')], {
		'format': o(global('tarfile.USTAR_FORMAT')!)
	})!
	tar := enter(manager)!
	method(tar, 'add', [o(root)], {
		'arcname': s('.')
	}) or {
		if !retire(manager, err)! { return err }
		return path
	}
	retire(manager, none)!
	return path
}

fn say(message string) ! {
	invoke('print', [s(message)], {
		'flush': v(ah.Value(true))
	})!
}

fn list_with(values []string) !string {
	items := list()!
	for item in values { append(items, o(item))! }
	return items
}

struct State {
mut:
	transcript   string
	last_chunk   string
	last_command string
	pipe         string
	typed        string
}

fn run_guest(args string, work string, root string) !string {
	archive_path := archive(root, work)!
	env := environment(args, work, archive_path)!
	command := list_with([
		call('str', o(join(attr(args, 'repo')!, 'scripts/run-aarch64.sh')!))!,
		literal(ah.Value('--no-build'))!,
		literal(ah.Value('--no-persist'))!,
		literal(ah.Value('--mem=' + format(attr(args, 'mem')!)!))!,
		literal(ah.Value('--serial'))!,
	])!
	say('Booting Vinix with the Windows Player')!
	gc.callback('fork', {
		'command':    ah.Value(command)
		'env':        ah.Value(env)
		'root_owner': ah.Value(attr(args, 'repo')!)
	})!
	pid, master := 'pid', 'master'
	mut state := State{}
	capture(args, work, master, mut state) or {
		cause := err
		gc.activate(cause, true)!
		cleanup(pid, master, work, archive_path, state)!
		return cause
	}
	cleanup(pid, master, work, archive_path, state)!
	gc.callback('retired', {})!
	return call('bytes', o(state.transcript))!
}

fn capture(args string, work string, master string, mut state State) ! {
	state.transcript = call('bytearray')!
	deadline := call('operator.add', o(call('time.monotonic')!), o(attr(args, 'timeout')!))!
	state.pipe = join(work, 'shell.in')!
	state.typed = literal(ah.Value(-1))!
	if truth(attr(args, 'shell')!)! {
		if truth(method(state.pipe, 'exists', [], {})!)! { method(state.pipe, 'unlink', [], {})! }
		call('os.mkfifo', o(state.pipe))!
		flags := call('operator.or_', o(global('os.O_RDWR')!), o(global('os.O_NONBLOCK')!))!
		state.typed = gc.callback('function', {
			'owner':  ah.Value('intrinsic-open-fd')
			'method': ah.Value('__call__')
			'args':   ah.Value([o(state.pipe), o(flags)])
			'result': ah.Value('owner')
		})!.text()
		say('Guest shell: write commands to ' + format(state.pipe)! + ', read ' + format(work)! + "/vinix.log; 'poweroff-test' ends it")!
	}
	manager := method(join(work, 'vinix.log')!, 'open', [s('wb')], {})!
	log := enter(manager)!
	serial(args, master, deadline, log, mut state) or {
		if !retire(manager, err)! { return err }
		return
	}
	retire(manager, none)!
}

fn serial(args string, master string, deadline string, log string, mut state State) ! {
	for {
		mark := gc.callback('checkpoint', {})!
		done := serial_step(args, master, deadline, log, mut state) or {
			failure := err
			gc.callback('release_since', {
				'checkpoint': mark
				'keep':       ah.Value([ah.Value(state.last_chunk), ah.Value(state.last_command)])
			}) or { return failure }
			return failure
		}
		gc.callback('release_since', {
			'checkpoint': mark
			'keep':       ah.Value([ah.Value(state.last_chunk), ah.Value(state.last_command)])
		})!
		if done { return }
	}
}

fn serial_step(args string, master string, deadline string, log string, mut state State) !bool {
	if !compare('lt', call('time.monotonic')!, o(deadline))! { return true }
	if compare('ge', state.typed, n(0))! {
		ready := call('select.select', o(list_with([state.typed])!), o(list()!), o(list()!), n(0))!
		if truth(get(ready, n(0))!)! {
			command := call('os.read', o(state.typed), n(65536))!
			gc.callback('release', {
				'ids': ah.Value([ah.Value(state.last_command)])
			})!
			state.last_command = command
			if truth(call('operator.contains', o(command), b('poweroff-test'.bytes().hex()))!)! {
				return true
			}
			call('os.write', o(master), o(command))!
		}
	}
	ready := call('select.select', o(list_with([master])!), o(list()!), o(list()!), if truth(attr(args, 'shell')!)! {
		float('0.2')
	} else {
		n(1)
	})!
	if truth(get(ready, n(0))!)! {
		chunk := call('os.read', o(master), n(65536)) or {
			if !exception_is(err, 'OSError')! { return err }
			gc.activate(none, false)!
			return true
		}
		gc.callback('release', {
			'ids': ah.Value([ah.Value(state.last_chunk)])
		})!
		state.last_chunk = chunk
		if !truth(chunk)! { return true }
		method(state.transcript, 'extend', [o(chunk)], {})!
		method(log, 'write', [o(chunk)], {})!
		method(log, 'flush', [], {})!
	}
	if !truth(attr(args, 'shell')!)! {
		if truth(call('operator.contains', o(state.transcript), b('ROBLOX-WINDOWS-DONE'.bytes().hex()))!)! {
			return true
		}
		if failures(state.transcript)! { return true }
	}
	return false
}

fn failures(transcript string) !bool {
	checked_by := global('any')!
	checks := call('_checks', o(global('FAILURES')!), o(transcript))!
	checked := gc.callback('invoke', {
		'target': ah.Value(checked_by)
		'args': ah.Value([o(checks)])
	}) or {
		failure := err
		gc.activate(failure, true)!
		gc.callback('release', {'ids': ah.Value([ah.Value(checks)])}) or { return failure }
		gc.activate(none, false)!
		return failure
	}
	gc.callback('release', {'ids': ah.Value([ah.Value(checks)])})!
	return truth(checked.text())!
}

fn cleanup(pid string, master string, work string, archive_path string, state State) ! {
	gc.callback('retiring', {}) or {
		cause := err
		gc.activate(cause, true)!
		cleanup_body(pid, master, work, archive_path, state)!
		return cause
	}
	cleanup_body(pid, master, work, archive_path, state)!
}

fn cleanup_body(pid string, master string, work string, archive_path string, state State) ! {
	call('stop', o(pid), o(master))!
	gc.callback('reaped', {})!
	gc.callback('closed', {})!
	if state.typed != '' && compare('ge', state.typed, n(0))! {
		gc.callback('function', {
			'owner':  ah.Value('intrinsic-close-fd')
			'method': ah.Value('__call__')
			'args':   ah.Value([o(state.typed)])
			'result': ah.Value('owner')
		})!
		method(state.pipe, 'unlink', [], {})!
	}
	for scratch in [archive_path, join(work, 'boot.img')!] {
		method(scratch, 'unlink', [], {
			'missing_ok': v(ah.Value(true))
		})!
	}
}

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	operation := ah.field(ah.field(row, 'arguments').object(), 'public_operation').text()
	match operation {
		'stop' { close_guest('arg0', 'arg1')! }
		'run_guest' { return export(run_guest('arg0', 'arg1', 'arg2')!) }
		else { return error('unknown Roblox Windows guest policy') }
	}
	return ah.Value(json2.Null{})
}
