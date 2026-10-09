// SPDX-License-Identifier: GPL-2.0-or-later
module wakeguest

import androidhost as ah
import gapcore as gc
import json2

fn wait_for_exit(pid string) !bool {
	mark := gc.callback('checkpoint', {})!
	result := wait_for_exit_body(pid)!
	gc.callback('release_since', {
		'checkpoint': mark
	})!
	return result
}

fn wait_for_exit_body(pid string) !bool {
	initial := call('time.monotonic')!
	deadline := call('operator.add', o(initial), n(5)) or {
		discard(initial)!
		return err
	}
	discard(initial)!
	for {
		now := call('time.monotonic')!
		condition := call('operator.lt', o(now), o(deadline)) or {
			discard(now)!
			return err
		}
		discard(now)!
		ready := truth(condition) or {
			discard(condition)!
			return err
		}
		discard(condition)!
		if !ready { return false }
		status := gc.callback('wait_once', {
			'result': ah.Value('owner')
		})!.text()
		waited := item(status, 0) or {
			discard(status)!
			return err
		}
		discard(status)!
		comparison := call('operator.eq', o(waited), o(pid)) or {
			discard(waited)!
			return err
		}
		discard(waited)!
		matched := truth(comparison) or {
			discard(comparison)!
			return err
		}
		discard(comparison)!
		if matched {
			gc.callback('reaped', {})!
			return true
		}
		discard(call('time.sleep', v(ah.Value(ah.Number{'0.1'})))!)!
	}
}

fn request_exit(master string) ! {
	written := call('os.write', o(master), b('0178')) or {
		if !exception(err, 'OSError')! { return err }
		active(none)!
		return
	}
	discard(written)!
	active(none)!
}

fn stop_guest(pid string, master string) !bool {
	request_exit(master) or {
		cause := err
		active(cause)!
		gc.callback('close_fd', {})!
		return cause
	}
	gc.callback('close_fd', {})!
	if wait_for_exit(pid)! { return true }
	for name in ['signal.SIGTERM', 'signal.SIGKILL'] {
		signal_id := global(name)!
		group := call('os.killpg', o(pid), o(signal_id)) or {
			cause := err
			if !exception_any(cause, ['ProcessLookupError', 'PermissionError'])! { return cause }
			active(cause)!
			killed := call('os.kill', o(pid), o(signal_id)) or {
				if !exception(err, 'ProcessLookupError')! { return err }
				''
			}
			discard(killed)!
			''
		}
		discard(group)!
		active(none)!
		if wait_for_exit(pid)! { return true }
	}
	return false
}

struct Capture {
mut:
	transcript string
	last       string
	log        string
	deadline   string
}

fn read_guest(args string, work string, master string, mut capture Capture) ! {
	deadline := call('operator.add', o(call('time.monotonic')!), o(attr(args, 'timeout')!))!
	capture.deadline = deadline
	manager := method(join(work, 'vinix.log')!, 'open', [s('wb')], {})!
	log := enter(manager) or {
		active(err)!
		gc.callback('release', {
			'ids': ah.Value([ah.Value(manager)])
		})!
		return err
	}
	capture.log = log
	serial(deadline, master, log, mut capture) or {
		cause := err
		suppressed := retire(manager, cause) or {
			active(err)!
			gc.callback('release', {
				'ids': ah.Value([ah.Value(manager)])
			})!
			return err
		}
		active(cause)!
		gc.callback('release', {
			'ids': ah.Value([ah.Value(manager)])
		})!
		active(none)!
		if !suppressed { return cause }
		return
	}
	retire(manager, none) or {
		active(err)!
		gc.callback('release', {
			'ids': ah.Value([ah.Value(manager)])
		})!
		return err
	}
	gc.callback('release', {
		'ids': ah.Value([ah.Value(manager)])
	})!
}

fn serial(deadline string, master string, log string, mut capture Capture) ! {
	for {
		mark := gc.callback('checkpoint', {})!
		done := serial_step(deadline, master, log, mut capture) or {
			cause := err
			active(cause)!
			gc.callback('release_since', {
				'checkpoint': mark
				'keep':       ah.Value([ah.Value(capture.last)])
			}) or { return cause }
			active(none)!
			return cause
		}
		gc.callback('release_since', {
			'checkpoint': mark
			'keep':       ah.Value([ah.Value(capture.last)])
		})!
		if done { return }
	}
}

fn serial_step(deadline string, master string, log string, mut capture Capture) !bool {
	if !compare('lt', call('time.monotonic')!, deadline)! { return true }
	ready := call('select.select', o(list([master])!), o(list([]string{})!), o(list([]string{})!), n(1))!
	if !truth(item(ready, 0)!)! { return false }
	chunk := call('os.read', o(master), n(65536)) or {
		if !exception(err, 'OSError')! { return err }
		active(none)!
		return true
	}
	gc.callback('release', {
		'ids': ah.Value([ah.Value(capture.last)])
	})!
	capture.last = chunk
	if !truth(chunk)! { return true }
	discard(method(capture.transcript, 'extend', [o(chunk)], {})!)!
	discard(method(log, 'write', [o(chunk)], {})!)!
	discard(method(log, 'flush', [], {})!)!
	return truth(call('operator.contains', o(capture.transcript), b('WAKE-OP-GUEST-END'.bytes().hex()))!)! || truth(call('operator.contains', o(capture.transcript), b('KERNEL PANIC'.bytes().hex()))!)!
}

fn boot(args string, work string, command string, env string) !string {
	gc.callback('fork', {
		'command':     ah.Value(command)
		'env':         ah.Value(env)
		'root_owner':  ah.Value('wake-root')
		'root_method': ah.Value('resolve')
	})!
	mut capture := Capture{ transcript: call('bytearray')! }
	read_guest(args, work, 'master', mut capture) or {
		cause := err
		active(cause)!
		gc.callback('retiring', {})!
		gc.callback('stop_public', {})!
		return cause
	}
	gc.callback('retiring', {})!
	reaped := gc.callback('stop_public', {})!.text()
	gc.callback('retired', {})!
	last := if capture.last == '' {
		gc.callback('literal', {
			'value': ah.Value(json2.Null{})
		})!.text()
	} else {
		capture.last
	}
	log := if capture.log == '' {
		gc.callback('literal', {
			'value': ah.Value(json2.Null{})
		})!.text()
	} else {
		capture.log
	}
	deadline := if capture.deadline == '' {
		gc.callback('literal', {
			'value': ah.Value(json2.Null{})
		})!.text()
	} else {
		capture.deadline
	}
	return call('_wake_capture', o(capture.transcript), o(reaped), o(last), o(log), o(deadline), o('pid'), o('master'))!
}

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	op := ah.field(ah.field(row, 'arguments').object(), 'public_operation').text()
	match op {
		'stop_guest' { return ah.Value(stop_guest('arg0', 'arg1')!) }
		'boot' { return export(boot('arg0', 'arg1', 'arg2', 'arg3')!) }
		else { return error('unknown Wake guest operation') }
	}
}
