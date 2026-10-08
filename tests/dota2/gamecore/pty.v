// SPDX-License-Identifier: GPL-2.0-or-later
module gamecore

import androidhost as ah
import gapcore as gc

fn stop_vm(pid string, master string) ! {
	gc.callback('retiring', {}) or {
		failure := err
		gc.activate(failure, true)!
		stop_owned(pid, master)!
		return failure
	}
	stop_owned(pid, master)!
}

fn stop_owned(pid string, master string) ! {
	stop_process(pid, master) or {
		failure := err
		gc.activate(failure, true)!
		call('os.close', o(master)) or { return failure }
		gc.callback('closed', {})!
		return failure
	}
	call('os.close', o(master))!
	gc.callback('closed', {})!
}

fn stop_process(pid string, master string) ! {
	terminate(pid, master) or { if !exception_is(err, 'OSError')! { return err } }
	deadline := call('operator.add', o(call('time.monotonic')!), n(5))!
	for compare('lt', call('time.monotonic')!, o(deadline))! {
		row := call('os.waitpid', o(pid), o(call('os.WNOHANG')!))!
		if eq(get(row, n(0))!, o(pid))! {
			gc.callback('reaped', {})!
			return
		}
		call('time.sleep', o(call('builtins.float', s('0.1'))!))!
	}
	kill(pid)!
	gc.activate(none, false)!
	row := call('os.waitpid', o(pid), o(call('os.WNOHANG')!))!
	if eq(get(row, n(0))!, o(pid))! { gc.callback('reaped', {})! }
}

fn terminate(pid string, master string) ! {
	call('os.write', o(master), b('0178'))!
	call('os.killpg', o(pid), o(call('signal.SIGTERM')!))!
}

fn kill(pid string) ! {
	call('os.killpg', o(pid), o(call('signal.SIGKILL')!)) or {
		failure := err
		if !exception_is(failure, 'OSError')! { return failure }
		gc.activate(failure, true)!
		call('os.kill', o(pid), o(call('signal.SIGKILL')!)) or {
			if !exception_is(err, 'OSError')! {
				return err
			}
		}
	}
}

struct Guest {
mut:
	transcript string
	captures   string
	failure    string
	failed_at  string
}

fn launch(command string, environment string, options string, work string, socket string, mut state Guest) ! {
	fork := gc.callback('fork', {
		'command': ah.Value(command)
		'env':     ah.Value(environment)
		'root':    ah.Value('REPO')
	})!.items()
	pid := literal(fork[0])!
	master := literal(fork[1])!
	guest_owned(master, options, work, socket, mut state) or {
		failure := err
		gc.activate(failure, true)!
		public_stop(pid, master)!
		return failure
	}
	public_stop(pid, master)!
	gc.callback('retired', {})!
}

fn guest_owned(master string, options string, work string, socket string, mut state Guest) ! {
	start := call('time.monotonic')!
	next_capture := call('operator.add', o(start), n(30))!
	state.failed_at = null_id()!
	manager := method(join(work, 'vinix.log')!, 'open', [s('wb')], {})!
	log := enter(manager)!
	guest_loop(master, options, work, socket, start, next_capture, log, mut state) or {
		failure := err
		if !retire(manager, failure)! { return failure }
		final_capture(work, socket, mut state)!
		return
	}
	retire(manager, none)!
	final_capture(work, socket, mut state)!
}

fn final_capture(work string, socket string, mut state Guest) ! {
	final := join(work, 'guest-final.png')!
	if truth(call('screenshot', o(socket), o(final))!)! {
		append(state.captures, o(call('builtins.str', o(final))!))!
	}
}

fn guest_loop(master string, options string, work string, socket string, start string, initial_capture string, log string, mut state Guest) ! {
	mut next_capture := initial_capture
	for compare('lt', call('operator.sub', o(call('time.monotonic')!), o(start))!, o(attr(options, 'timeout')!))! {
		selected := call('select.select', o(command([o(master)])!), o(list()!), o(list()!), n(1))!
		if truth(get(selected, n(0))!)! {
			data := call('os.read', o(master), n(65536)) or {
				failure := err
				if !exception_is(failure, 'OSError')! { return failure }
				state.failure = literal(ah.Value('VM serial connection closed'))!
				return
			}
			if !truth(data)! {
				state.failure = literal(ah.Value('VM exited'))!
				return
			}
			method(state.transcript, 'extend', [o(data)], {})!
			method(log, 'write', [o(data)], {})!
			method(log, 'flush', [], {})!
			method(attr(call('sys.stdout')!, 'buffer')!, 'write', [o(data)], {})!
			method(attr(call('sys.stdout')!, 'buffer')!, 'flush', [], {})!
			tail := get(state.transcript, o(call('builtins.slice', n(-131072), o(null_id()!))!))!
			mut marker := ''
			for value in ['VINIX-DOTA2-PROBE-FAIL', 'VINIX-DOTA2-GAME-EXIT:', 'VINIX-DOTA2-GAME-GONE',
				'KERNEL PANIC', 'FATAL EXCEPTION', 'uncaught target signal', 'LLVM ERROR:',
				'lwip: assertion'] {
				if truth(call('operator.contains', o(tail), b(value.bytes().hex()))!)! {
					marker = value
					break
				}
			}
			if marker != '' && compare('is_', state.failure, o(null_id()!))! {
				state.failure = method(call('builtins.bytes.fromhex', s(marker.bytes().hex()))!, 'decode', [], {})!
				state.failed_at = call('time.monotonic')!
			}
		}
		if !compare('is_', state.failed_at, o(null_id()!))! && compare('ge', call('operator.sub', o(call('time.monotonic')!), o(state.failed_at))!, n(2))! {
			return
		}
		if compare('ge', call('time.monotonic')!, o(next_capture))! {
			elapsed := call('builtins.int', o(call('operator.sub', o(call('time.monotonic')!), o(start))!))!
			filename := 'guest-' + text(call('builtins.format', o(elapsed), s('04d'))!)! + '.png'
			target := join(work, filename)!
			if truth(call('screenshot', o(socket), o(target))!)! {
				append(state.captures, o(call('builtins.str', o(target))!))!
			}
			next_capture = call('operator.add', o(call('time.monotonic')!), o(attr(options, 'capture_interval')!))!
		}
	}
}

fn command(items []ah.Value) !string {
	result := list()!
	for item in items { append(result, item)! }
	return result
}

fn public_stop(pid string, master string) ! {
	call('stop_vm', o(pid), o(master))!
	gc.callback('reaped', {})!
	gc.callback('closed', {})!
}
