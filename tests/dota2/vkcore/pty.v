// SPDX-License-Identifier: GPL-2.0-or-later
module vkcore

import androidhost as ah
import gapcore as gc

fn raw_boot(command string, environment string, work string, timeout string) !string {
	fork := gc.callback('fork', {'command': ah.Value(command), 'env': ah.Value(environment), 'root': ah.Value('REPO')})!.items()
	pid := literal(fork[0])!
	master := literal(fork[1])!
	transcript := call('builtins.bytearray')!
	mut pending := IError(none)
	mut failed := false
	read_guest(master, work, timeout, transcript) or { pending = err; failed = true }
	gc.callback('retiring', {}) or { if !failed { pending = err; failed = true } }
	if failed { gc.activate(pending, true)! }
	mut stop_failed := false
	stop_child(pid, master, pending, failed) or {
		pending = err
		failed = true
		stop_failed = true
	}
	if stop_failed {
		gc.activate(pending, true)!
		// The legacy stop exception skips close. Recover the descriptor while
		// retaining that earlier error and its original overriding precedence.
		close_master(master) or {}
	} else { close_master(master)! }
	if failed { return pending }
	gc.callback('retired', {})!
	return transcript
}
fn close_master(master string) ! {
	call('os.close', o(master))!
	gc.callback('closed', {})!
}
fn read_guest(master string, work string, timeout string, transcript string) ! {
	deadline := call('operator.add', o(call('time.monotonic')!), o(timeout))!
	manager := method(join(work, 'vinix.log')!, 'open', [s('wb')], {})!
	log := enter(manager)!
	read_loop(master, log, deadline, transcript) or {
		failure := err
		if !retire(manager, failure)! { return failure }
		return
	}
	retire(manager, none)!
}
fn read_loop(master string, log string, deadline string, transcript string) ! {
	for compare('lt', call('time.monotonic')!, o(deadline))! {
		inputs := list()!
		append(inputs, o(master))!
		selected := call('select.select', o(inputs), o(list()!), o(list()!), n(1))!
		if !truth(get(selected, n(0))!)! { continue }
		block := call('os.read', o(master), n(65536)) or {
			if gc.kind(err, 'os_error') { return }
			return err
		}
		if !truth(block)! { return }
		method(transcript, 'extend', [o(block)], {})!
		method(log, 'write', [o(block)], {})!
		method(log, 'flush', [], {})!
		for marker in ['VINIX-DOTA2-VULKAN-PASS', 'VINIX-DOTA2-VULKAN-FAIL', 'KERNEL PANIC'] {
			if truth(call('operator.contains', o(transcript), b(marker.bytes().hex()))!)! { return }
		}
	}
}
fn stop_child(pid string, master string, prior IError, failed bool) ! {
	request_termination(pid, master) or {
		if !gc.kind(err, 'os_error') { return err }
	}
	stop := call('operator.add', o(call('time.monotonic')!), n(5))!
	for compare('lt', call('time.monotonic')!, o(stop))! {
		result := call('os.waitpid', o(pid), o(call('os.WNOHANG')!))!
		if eq(get(result, n(0))!, o(pid))! { gc.callback('reaped', {})!; return }
		call('time.sleep', o(call('builtins.float', s('0.1'))!))!
	}
	request_kill(pid)!
	gc.activate(prior, failed)!
	result := call('os.waitpid', o(pid), o(call('os.WNOHANG')!))!
	if eq(get(result, n(0))!, o(pid))! { gc.callback('reaped', {})! }
}
fn request_termination(pid string, master string) ! {
	call('os.write', o(master), b('0178'))!
	call('os.killpg', o(pid), o(call('signal.SIGTERM')!))!
}
fn request_kill(pid string) ! {
	call('os.killpg', o(pid), o(call('signal.SIGKILL')!)) or {
		if !gc.kind(err, 'os_error') { return err }
		gc.activate(err, true)!
		call('os.kill', o(pid), o(call('signal.SIGKILL')!)) or {
			if !gc.kind(err, 'os_error') { return err }
		}
	}
}
