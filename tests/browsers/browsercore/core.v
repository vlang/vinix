// SPDX-License-Identifier: GPL-2.0-or-later
module browsercore

import androidhost as ah
import gapcore as gc
import json2

fn available_port() !string {
	socket := global('socket.socket')!
	family := global('socket.AF_INET')!
	kind := global('socket.SOCK_STREAM')!
	manager := evaluated(socket, [o(family), o(kind)], {})!
	listener := enter(manager) or {
		release([manager])!
		return err
	}
	port := listen(listener) or {
		cause := err
		if !retire(manager, cause)! { return cause }
		return literal(ah.Value(json2.Null{}))!
	}
	retire(manager, none)!
	return port
}

fn listen(listener string) !string {
	perform_method(listener, 'bind', [ah.Value([ah.Value('tuple'),
		ah.Value([ah.Value('127.0.0.1'), ah.Value(0)])])], {})!
	stringer := global('str')!
	address := method(listener, 'getsockname', [], {}) or {
		release([stringer])!
		return err
	}
	port := get(address, n(1)) or {
		release([address, stringer])!
		return err
	}
	release([address])!
	return temporary_call(stringer, [o(port)], {}, [port])!
}

fn exit_code(status string) !string {
	if truth(call('os.WIFEXITED', o(status))!)! { return call('os.WEXITSTATUS', o(status))! }
	if truth(call('os.WIFSIGNALED', o(status))!)! {
		return call('operator.add', n(128), o(call('os.WTERMSIG', o(status))!))!
	}
	return literal(ah.Value(1))!
}

fn request_exit(master string) ! {
	perform('os.write', o(master), b('0178')) or {
		cause := err
		if !exception(cause, ['OSError'])! { return cause }
		active(none)!
		discard_error(cause)!
	}
	active(none)!
}

struct StopState {
mut:
	deadline string
	waited   string
	ignored  string
}

fn wait_until(pid string, seconds int, mut state StopState) !bool {
	state.deadline = replace(state.deadline, op('add', call('time.monotonic')!, n(seconds))!)!
	for {
		checkpoint := gc.callback('checkpoint', {})!
		done := wait_step(pid, mut state) or {
			cause := err
			gc.callback('release_since', {
				'checkpoint': checkpoint
				'keep':       ah.Value([ah.Value(state.deadline), ah.Value(state.waited),
					ah.Value(state.ignored)])
			})!
			return cause
		}
		gc.callback('release_since', {
			'checkpoint': checkpoint
			'keep':       ah.Value([ah.Value(state.deadline), ah.Value(state.waited),
				ah.Value(state.ignored)])
		})!
		if done != 0 { return done == 1 }
	}
	return false
}

fn wait_step(pid string, mut state StopState) !int {
	if !compare('lt', call('time.monotonic')!, o(state.deadline))! { return 2 }
	target := global('os.waitpid')!
	flag := global('os.WNOHANG')!
	waited := evaluated(target, [o(pid), o(flag)], {})!
	values := gc.callback('unpack_items', {
		'id':    ah.Value(waited)
		'count': ah.Value(2)
	}) or {
		release([waited])!
		return err
	}
	release([waited])!
	unpacked := values.items()
	state.waited = replace(state.waited, unpacked[0].text())!
	state.ignored = replace(state.ignored, unpacked[1].text())!
	if compare('eq', state.waited, o(pid))! { return 1 }
	perform('time.sleep', f('0.05'))!
	return 0
}

fn group_signal(pid string, name string) ! {
	target := global('os.killpg')!
	signal_ := global(name) or {
		release([target])!
		return err
	}
	perform_target(target, [o(pid), o(signal_)], {})!
}

fn stop_child(pid string, master string) ! {
	request_exit(master)!
	mut state := StopState{}
	if wait_until(pid, 5, mut state)! { return }
	group_signal(pid, 'signal.SIGTERM') or {
		if exception(err, ['ProcessLookupError', 'PermissionError'])! {
			active(none)!
			discard_error(err)!
			return
		}
		return err
	}
	if wait_until(pid, 2, mut state)! { return }
	group_signal(pid, 'signal.SIGKILL') or {
		if !exception(err, ['ProcessLookupError', 'PermissionError'])! { return err }
		active(none)!
		discard_error(err)!
	}
	active(none)!
	perform('os.waitpid', o(pid), n(0)) or {
		if !exception(err, ['ChildProcessError'])! { return err }
		active(none)!
		discard_error(err)!
	}
	active(none)!
}

fn environment(state string, initramfs string, profile string) !string {
	env := method(global('os.environ')!, 'copy', [], {})!
	perform('operator.setitem', o(env), s('VINIX_INITRAMFS'), o(text(initramfs)!))!
	compressed := if compare('eq', attr(initramfs, 'suffix')!, s('.gz'))! { '1' } else { '0' }
	perform('operator.setitem', o(env), s('VINIX_INITRAMFS_COMPRESSED'), s(compressed))!
	for row in [['VINIX_BOOT_DISK', 'boot.img'], ['VINIX_EFIVARS', 'efivars.fd'],
		['VINIX_QEMU_PACKAGE_STORE', 'packages.tar'], ['VINIX_QEMU_PERSIST_DISK', 'root.ext2']] {
		perform('operator.setitem', o(env), s(row[0]), o(path_text(state, row[1])!))!
	}
	stringer := global('str')!
	size := method(profile, 'get', [s('persist_size_mb'), n(256)], {}) or {
		release([stringer])!
		return err
	}
	perform('operator.setitem', o(env), s('VINIX_QEMU_PERSIST_SIZE_MB'), o(temporary_call(stringer, [o(size)], {}, [size])!))!
	perform_method(env, 'pop', [s('VINIX_QEMU_PERSIST'), null()], {})!
	perform('operator.setitem', o(env), s('VINIX_KEEP_TEMP_BOOT_DISK'), s('1'))!
	setter := attr(env, 'setdefault')!
	port := call('available_port') or {
		release([setter])!
		return err
	}
	release([temporary_call(setter, [s('VINIX_QEMU_PACKAGE_STORE_PORT'), o(port)], {}, [port])!])!
	perform_method(env, 'setdefault', [s('VINIX_QEMU_PACKAGE_PERSIST'), s('0')], {})!
	if compare('ne', call('platform.system')!, s('Darwin'))! {
		perform_method(env, 'setdefault', [s('USE_TCG'), s('1')], {})!
	}
	return env
}

struct Capture {
mut:
	transcript   string
	status       string
	forced       bool
	shutdown     string
	deadline     string
	chunk        string
	waited       string
	child_status string
	ignored      string
	readable     string
	recent       string
	finished     string
}

fn (c Capture) keep() []ah.Value {
	return [c.transcript, c.status, c.shutdown, c.deadline, c.chunk, c.waited, c.child_status,
		c.readable, c.ignored, c.recent, c.finished].map(ah.Value(it))
}

fn serial(profile string, failures string, master string, mut capture Capture) ! {
	for {
		checkpoint := gc.callback('checkpoint', {})!
		done := step(profile, failures, master, mut capture) or {
			cause := err
			gc.callback('release_since', {
				'checkpoint': checkpoint
				'keep':       ah.Value(capture.keep())
			})!
			return cause
		}
		gc.callback('release_since', {
			'checkpoint': checkpoint
			'keep':       ah.Value(capture.keep())
		})!
		if done { return }
	}
}

fn replace(old string, new string) !string {
	release([old])!
	return new
}

fn step(profile string, failures string, master string, mut c Capture) !bool {
	if !compare('lt', call('time.monotonic')!, o(c.deadline))! { return true }
	waiter := global('os.waitpid')!
	pair := evaluated(waiter, [o('pid'), o(global('os.WNOHANG')!)], {})!
	values := gc.callback('unpack_items', {
		'id':    ah.Value(pair)
		'count': ah.Value(2)
	}) or {
		release([pair])!
		return err
	}
	release([pair])!
	unpacked := values.items()
	c.waited = replace(c.waited, unpacked[0].text())!
	c.child_status = replace(c.child_status, unpacked[1].text())!
	if compare('eq', c.waited, o('pid'))! {
		c.status = c.child_status
		gc.callback('reaped', {})!
		return true
	}
	ready := call('select.select', o(list([o(master)])!), o(list([])!), o(list([])!), f('0.25'))!
	selected := gc.callback('unpack_items', {
		'id':    ah.Value(ready)
		'count': ah.Value(3)
	}) or {
		release([ready])!
		return err
	}
	release([ready])!
	selection := selected.items()
	c.readable = replace(c.readable, selection[0].text())!
	c.ignored = replace(c.ignored, selection[1].text())!
	c.ignored = replace(c.ignored, selection[2].text())!
	if truth(c.readable)! {
		chunk := call('os.read', o(master), n(65536)) or {
			cause := err
			if !exception(cause, ['OSError'])! { return cause }
			active(cause)!
			matches := compare_eio(cause, 'eq')!
			active(none)!
			if matches {
				discard_error(cause)!
				return false
			}
			return cause
		}
		c.chunk = replace(c.chunk, chunk)!
		if truth(chunk)! {
			perform_method(c.transcript, 'extend', [o(chunk)], {})!
			buffer := attr(global('sys.stdout')!, 'buffer')!
			perform_method(buffer, 'write', [o(chunk)], {}) or {
				release([buffer])!
				return err
			}
			release([buffer])!
			flusher := attr(global('sys.stdout')!, 'buffer')!
			perform_method(flusher, 'flush', [], {}) or {
				release([flusher])!
				return err
			}
			release([flusher])!
		}
	}
	byter := global('bytes')!
	slice := call('operator.getitem', o(c.transcript), o(evaluated(attr('intrinsic-slice', '__call__')!, [
		n(-131072),
		null(),
	], {})!)) or {
		release([byter])!
		return err
	}
	recent := temporary_call(byter, [o(slice)], {}, [slice])!
	c.recent = replace(c.recent, recent)!
	passed := op('contains', c.recent, o(get(profile, s('pass'))!))!
	finished := if truth(passed)! {
		passed
	} else {
		checker := global('any')!
		checks := call('_checks', o(failures), o(c.recent)) or {
			release([checker])!
			return err
		}
		temporary_call(checker, [o(checks)], {}, [checks])!
	}
	c.finished = replace(c.finished, finished)!
	if truth(c.finished)! && is_none(c.shutdown)! {
		perform('os.write', o(master), b('0178')) or {
			cause := err
			if !exception(cause, ['OSError'])! { return cause }
			active(cause)!
			raise_error := compare_eio(cause, 'ne')!
			active(none)!
			if raise_error { return cause }
			discard_error(cause)!
		}
		c.shutdown = op('add', call('time.monotonic')!, n(10))!
	}
	return !is_none(c.shutdown)! && compare('ge', call('time.monotonic')!, o(c.shutdown))!
}

fn cleanup(mut c Capture) ! {
	if is_none(c.status)! {
		c.forced = true
		gc.callback('stop_public', {})!
	}
	gc.callback('close_fd', {})!
}

fn collect(iterator string, output string, result string, failure_mode bool) ! {
	mut marker := ''
	for {
		next := gc.callback('next', {
			'id': ah.Value(iterator)
		}) or {
			release([marker, iterator])!
			return err
		}
		row := next.object()
		if gc.flag(ah.field(row, 'done')) {
			release([marker, iterator])!
			return
		}
		marker = replace(marker, ah.field(row, 'owner').text())!
		collect_one(marker, output, result, failure_mode) or {
			release([marker, iterator])!
			return err
		}
	}
}

fn collect_one(marker string, output string, result string, failure_mode bool) ! {
	contains := compare('contains', output, o(marker))!
	if contains != failure_mode { return }
	decoded := method(marker, 'decode', [s('ascii')], if failure_mode {
		{
			'errors': s('replace')
		}
	} else {
		map[string]ah.Value{}
	})!
	perform_method(result, 'append', [o(decoded)], {}) or {
		release([decoded])!
		return err
	}
	release([decoded])!
}

fn report(profile string, failures string, c Capture) !string {
	output := call('bytes', o(c.transcript))!
	missing := list([])!
	features := get(profile, s('features'))!
	members := gc.callback('unpack', {
		'owner': ah.Value(features)
	})!.text()
	release([features])!
	perform_method(members, 'append', [o(get(profile, s('pass'))!)], {})!
	iterator := gc.callback('iterate', {
		'id': ah.Value(members)
	})!.text()
	release([members])!
	collect(iterator, output, missing, false)!
	failed := list([])!
	failure_iter := gc.callback('iterate', {
		'id': ah.Value(failures)
	})!.text()
	collect(failure_iter, output, failed, true)!

	if !is_none(c.status)! && compare('ne', call('exit_code', o(c.status))!, n(0))! {
		code := format(call('exit_code', o(c.status))!)!
		perform_method(failed, 'append', [s('VM runner exit status ' + code)], {})!
	}
	if c.forced { method(failed, 'append', [s('VM did not exit after the test')], {})! }
	if truth(missing)! || truth(failed)! {
		for row in [[missing, 'ERROR: missing expected browser result: '],
			[failed, 'ERROR: observed browser failure: ']] {
			it := gc.callback('iterate', {
				'id': ah.Value(row[0])
			})!.text()
			for {
				next := gc.callback('next', {
					'id': ah.Value(it)
				})!.object()
				if gc.flag(ah.field(next, 'done')) { break }
				target := global('print')!
				message := row[1] + format(ah.field(next, 'owner').text())!
				perform_target(target, [s(message)], {
					'file': o(global('sys.stderr')!)
				})!
			}
		}
		return literal(ah.Value(1))!
	}
	perform('print', s('==> AArch64 QEMU browser boot passed'))!
	return literal(ah.Value(0))!
}

fn run_vm() !string {
	perform_method('arg3', 'mkdir', [], {
		'parents':  gc.v(ah.Value(true))
		'exist_ok': gc.v(ah.Value(true))
	})!
	env := environment('arg3', 'arg2', 'arg7')!
	command := list([o(path_text('arg0', 'scripts/run-aarch64.sh')!), s('--serial'),
		s('--mem=' + format('arg4')!), s('--guest-init=' + format('arg1')!)])!
	if !truth('arg6')! { method(command, 'insert', [n(1), s('--no-build')], {})! }
	failures := op('add', get('arg7', s('fail'))!, o(global('COMMON_FAIL_MARKERS')!))!
	perform('print', s('==> Starting AArch64 QEMU browser boot'))!
	gc.callback('fork', {
		'command':    ah.Value(command)
		'env':        ah.Value(env)
		'root_owner': ah.Value('arg0')
		'exec':       ah.Value('execve')
	})!
	mut c := Capture{ transcript: call('bytearray')!, deadline: op('add', call('time.monotonic')!, o('arg5'))! }
	serial('arg7', failures, 'master', mut c) or {
		cause := err
		active(cause)!
		cleanup(mut c)!
		return cause
	}
	cleanup(mut c)!
	return report('arg7', failures, c)!
}

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	operation := ah.field(ah.field(row, 'arguments').object(), 'public_operation').text()
	result := match operation {
		'available_port' { available_port()! }
		'exit_code' { exit_code('arg0')! }
		'stop_child' {
			stop_child('pid', 'master')!
			''
		}
		'run_vm' { run_vm()! }
		else { return error('unknown browser controller operation') }
	}
	gc.callback('release_since', {
		'checkpoint': ah.Value(0)
		'keep':       ah.Value([ah.Value(result)])
	})!
	return if result == '' { ah.Value(json2.Null{}) } else { export(result) }
}
