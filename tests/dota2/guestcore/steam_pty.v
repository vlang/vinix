// SPDX-License-Identifier: GPL-2.0-or-later
module guestcore

import androidhost as ah
import gapcore as gc

struct SteamGuest {
mut:
	transcript string
	last_data  string
}

fn steam_contains(transcript string, marker string) !bool {
	return truth(call('operator.contains', o(transcript), b(marker.bytes().hex()))!)!
}

fn steam_launch(command string, environment string, options string, work string, mut guest SteamGuest) ! {
	gc.callback('fork', {
		'command': ah.Value(command)
		'env':     ah.Value(environment)
		'root':    ah.Value('REPO')
	})!
	steam_capture('master', options, work, mut guest) or {
		failure := err
		gc.activate(failure, true)!
		steam_stop('pid', 'master', failure)!
		return failure
	}
	steam_stop('pid', 'master', none)!
	gc.callback('retired', {})!
}

fn steam_capture(master string, options string, work string, mut guest SteamGuest) ! {
	guest.transcript = call('builtins.bytearray')!
	deadline := call('operator.add', o(call('time.monotonic')!), o(attr(options, 'timeout')!))!
	manager := method(join(work, 'vinix.log')!, 'open', [s('wb')], {})!
	log := enter(manager)!
	steam_read(master, deadline, log, mut guest) or {
		failure := err
		if !retire(manager, failure)! { return failure }
		return
	}
	retire(manager, none)!
}

fn steam_read(master string, deadline string, log string, mut guest SteamGuest) ! {
	for {
		mark := checkpoint()!
		done := steam_read_step(master, deadline, log, mut guest) or {
			failure := err
			release_since(mark, guest.last_data) or { return failure }
			return failure
		}
		release_since(mark, guest.last_data)!
		if done { return }
	}
}

fn steam_read_step(master string, deadline string, log string, mut guest SteamGuest) !bool {
	if !compare('lt', call('time.monotonic')!, o(deadline))! { return true }
	selected := call('select.select', o(command([o(master)])!), o(list()!), o(list()!), n(1))!
	if !truth(get(selected, n(0))!)! { return false }
	data := call('os.read', o(master), n(65536)) or {
		failure := err
		if !matches(failure, ['OSError'])! { return failure }
		return true
	}
	release(guest.last_data)!
	guest.last_data = data
	if !truth(data)! { return true }
	method(guest.transcript, 'extend', [o(data)], {})!
	method(log, 'write', [o(data)], {})!
	method(log, 'flush', [], {})!
	return steam_contains(guest.transcript, 'VINIX-DOTA2-STEAM-SMOKE-END')! || steam_contains(guest.transcript, 'KERNEL PANIC')!
}

fn steam_stop(pid string, master string, cause ?IError) ! {
	gc.callback('retiring', {}) or {
		failure := err
		gc.activate(failure, true)!
		steam_stop_owned(pid, master, failure)!
		return failure
	}
	steam_stop_owned(pid, master, cause)!
}

fn steam_stop_owned(pid string, master string, cause ?IError) ! {
	steam_stop_process(pid, master, cause) or {
		failure := err
		gc.activate(failure, true)!
		call('os.close', o(master)) or { return failure }
		gc.callback('closed', {})!
		return failure
	}
	call('os.close', o(master))!
	gc.callback('closed', {})!
}

fn steam_stop_process(pid string, master string, cause ?IError) ! {
	steam_terminate(pid, master) or { if !matches(err, ['OSError'])! { return err } }
	deadline := call('operator.add', o(call('time.monotonic')!), n(5))!
	for {
		mark := checkpoint()!
		inside := compare('lt', call('time.monotonic')!, o(deadline)) or {
			failure := err
			release_since(mark) or { return failure }
			return failure
		}
		if !inside {
			release_since(mark)!
			break
		}
		reaped := steam_wait_step(pid) or {
			failure := err
			release_since(mark) or { return failure }
			return failure
		}
		release_since(mark)!
		if reaped { return }
	}
	steam_kill(pid)!
	if original := cause { gc.activate(original, true)! } else { gc.activate(none, false)! }
	row := call('os.waitpid', o(pid), o(call('os.WNOHANG')!))!
	if eq(get(row, n(0))!, o(pid))! { gc.callback('reaped', {})! }
}

fn steam_wait_step(pid string) !bool {
	row := call('os.waitpid', o(pid), o(call('os.WNOHANG')!))!
	if eq(get(row, n(0))!, o(pid))! {
		gc.callback('reaped', {})!
		return true
	}
	call('time.sleep', v(ah.Value(ah.Number{ text: '0.1' })))!
	return false
}

fn steam_terminate(pid string, master string) ! {
	call('os.write', o(master), b('0178'))!
	call('os.killpg', o(pid), o(call('signal.SIGTERM')!))!
}

fn steam_kill(pid string) ! {
	call('os.killpg', o(pid), o(call('signal.SIGKILL')!)) or {
		failure := err
		if !matches(failure, ['OSError'])! { return failure }
		gc.activate(failure, true)!
		call('os.kill', o(pid), o(call('signal.SIGKILL')!)) or {
			if !matches(err, ['OSError'])! { return err }
		}
	}
}
