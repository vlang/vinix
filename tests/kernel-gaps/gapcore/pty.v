// SPDX-License-Identifier: GPL-2.0-or-later
module gapcore

import androidhost as ah

fn drain(master ah.Value) ! {
	for {
		data := invoke('os.read', [v(master), v(ah.Value(65536))], {}, 'bytes') or {
			if kind(err, 'blocking') || errno(err, 5) { return }
			return err
		}
		if data.text() == '' { return }
		method('output', 'extend', [b(data.text())], {}, 'value')!
		text := invoke('builtins.bytes.decode', [b(data.text())], {
			'errors': v(ah.Value('replace'))
		}, 'value')!
		invoke('builtins.print', [v(text)], {
			'end':   v(ah.Value(''))
			'flush': v(ah.Value(true))
		}, 'value')!
	}
}

fn socket_protocol(id string, state string) ! {
	method(id, 'settimeout', [v(ah.Value(1))], {}, 'value')!
	method(id, 'connect', [v(ah.Value(join(state, 'qmp.sock')!))], {}, 'value')!
	method(id, 'recv', [v(ah.Value(4096))], {}, 'bytes')!
	method(id, 'sendall', [b('{"execute":"qmp_capabilities"}\n'.bytes().hex())], {}, 'value')!
	method(id, 'recv', [v(ah.Value(4096))], {}, 'bytes')!
	method(id, 'sendall', [b('{"execute":"quit"}\n'.bytes().hex())], {}, 'value')!
}

fn quit_monitor(state string) ! {
	family := call('builtins.int', v(call('socket.AF_UNIX')!))!
	id := invoke('socket.socket', [v(family)], {}, 'owner')!.text()
	entered := method(id, '__enter__', [], {}, 'owner')!.text()
	mut failed := false
	mut failure := IError(none)
	socket_protocol(entered, state) or {
		failed = true
		failure = err
	}
	detail := if failed { error_detail(failure) } else { null() }
	suppressed := flag(callback('context_exit', {
		'id':    ah.Value(id)
		'error': detail
	})!)
	if failed && !suppressed { return failure }
}

fn stop(pid ah.Value, master ah.Value, state string, external bool) ! {
	quit_monitor(state) or { if !kind(err, 'os_error') { return err } }
	invoke('os.write', [v(master), b('0178')], {}, 'value') or {
		if !kind(err, 'os_error') { return err }
		null()
	}
	for phase in 0 .. 3 {
		if phase > 0 {
			sig := call('builtins.int', v(call(if phase == 1 {
				'signal.SIGTERM'
			} else {
				'signal.SIGKILL'
			})!))!
			call('os.killpg', v(pid), v(sig)) or {
				if kind(err, 'permission') {
					call('os.kill', v(pid), v(sig)) or {
						if !kind(err, 'missing') { return err }
						null()
					}
				} else if !kind(err, 'missing') {
					return err
				}
				null()
			}
		}
		deadline := now()! + 3
		for now()! < deadline {
			if external { callback('drain', {})! } else { drain(master)! }
			status := call('os.waitpid', v(pid), v(call('os.WNOHANG')!)) or {
				if kind(err, 'child_error') {
					callback('reaped', {})!
					return
				}
				return err
			}
			if integer(status.items()[0]) == integer(pid) {
				callback('reaped', {})!
				return
			}
			call('time.sleep', v(ah.Value(ah.Number{'0.05'})))!
		}
	}
	return error('QEMU runner ' + integer(pid).str() + ' did not stop')
}

fn release(ids []string) {
	callback('release', {
		'ids': ah.Value(ids.map(ah.Value(it)))
	}) or {}
}

fn marker_present(id string) !bool {
	defer { release([id]) }
	encoded := method(id, 'encode', [], {}, 'owner')!.text()
	defer { release([encoded]) }
	return flag(call('operator.contains', owner('output'), owner(encoded))!)
}

fn has_markers(group string, all bool) !bool {
	iterator := invoke('builtins.iter', [owner(group)], {}, 'owner')!.text()
	defer { release([iterator]) }
	for {
		next := callback('next', {
			'id': ah.Value(iterator)
		})!.object()
		if flag(ah.field(next, 'done')) { return all }
		present := marker_present(ah.field(next, 'owner').text())!
		if present != all { return !all }
	}
	return all
}

fn collect(group string, present bool) !string {
	result := callback('list_new', {})!.text()
	iterator := invoke('builtins.iter', [owner(group)], {}, 'owner')!.text()
	defer { release([iterator]) }
	for {
		next := callback('next', {
			'id': ah.Value(iterator)
		})!.object()
		if flag(ah.field(next, 'done')) { break }
		id := ah.field(next, 'owner').text()
		encoded := method(id, 'encode', [], {}, 'owner')!.text()
		found := flag(call('operator.contains', owner('output'), owner(encoded))!)
		if found == present { method(result, 'append', [owner(id)], {}, 'value')! }
		release([id, encoded])
	}
	return result
}

struct BootState {
mut:
	has_status bool
	status     ah.Value
	timed_out  bool
}

fn drive(pid ah.Value, master ah.Value, mut result BootState) ! {
	call('os.set_blocking', v(master), v(ah.Value(false)))!
	// Keep Python's actual addition/type/overflow semantics, including float APIs.
	deadline := number(call('operator.add', v(call('time.monotonic')!), owner('timeout'))!)
	mut settled := false
	mut verdict_at := f64(0)
	for now()! < deadline {
		ready := call('select.select', v(ah.Value([master])), v(ah.Value([]ah.Value{})), v(ah.Value([]ah.Value{})), v(ah.Value(ah.Number{'0.2'})))!.items()
		if ready[0].items().len > 0 { drain(master)! }
		waited := call('os.waitpid', v(pid), v(call('os.WNOHANG')!))!.items()
		if integer(waited[0]) != 0 {
			result.has_status = true
			result.status = call('os.waitstatus_to_exitcode', v(waited[1]))!
			callback('reaped', {})!
			drain(master)!
			return
		}
		if has_markers('failures', false)! { return }
		if has_markers('expected', true)! {
			if !settled {
				verdict_at = now()!
				settled = true
			} else if now()! - verdict_at >= 2 {
				return
			}
		}
	}
	result.timed_out = true
}

fn boot(args map[string]ah.Value) !ah.Value {
	pair := callback('fork', {})!.items()
	pid, master := pair[0], pair[1]
	state := ah.field(args, 'state').text()
	mut result := BootState{}
	mut failed := false
	mut failure := IError(none)
	drive(pid, master, mut result) or {
		failed = true
		failure = err
	}
	activate(failure, failed)!
	callback('retiring', {}) or {
		failed = true
		failure = err
		null()
	}
	activate(failure, failed)!
	if !result.has_status {
		if flag(ah.field(args, 'native_stop')) {
			stop(pid, master, state, false) or {
				failed = true
				failure = err
			}
		} else {
			callback('stop', {}) or {
				failed = true
				failure = err
				null()
			}
		}
	}
	activate(failure, failed)!
	// Preserve the original nested-finally order and cleanup error precedence.
	drain(master) or {
		// The old finally skipped close when drain raised. Retire this owned FD
		// while retaining that same drain exception and omitting the serial write.
		cause := err
		activate(cause, true)!
		call('os.close', v(master)) or { null() }
		callback('closed', {})!
		return cause
	}
	call('os.close', v(master))!
	callback('closed', {})!
	path_method(join(state, 'serial.log')!, 'write_bytes', [owner('output')], {}, 'value')!
	if failed { return failure }
	missing := collect('expected', false)!
	observed := collect('failures', true)!
	if result.has_status && integer(result.status) != 0 {
		method(observed, 'append', [v(ah.Value('QEMU runner exited ' + integer(result.status).str()))], {}, 'value')!
	}
	if result.timed_out {
		method(observed, 'append', [v(ah.Value('QEMU runner timed out'))], {}, 'value')!
	}
	if integer(call('builtins.len', owner(missing))!) > 0 || integer(call('builtins.len', owner(observed))!) > 0 {
		missing_repr := call('builtins.repr', owner(missing))!.text()
		failures_repr := call('builtins.repr', owner(observed))!.text()
		print_text('Missing verdicts: ' + missing_repr + '; failures: ' + failures_repr)!
		return ah.Value(1)
	}
	print_text('All requested guest verdicts passed.')!
	return ah.Value(0)
}
