// SPDX-License-Identifier: GPL-2.0-or-later
module pcivm

import androidhost as ah
import json2
import wakehost

fn executable(name string) !string {
	found := call('shutil.which', o(name))!
	if null(found)! { runtime_error('required executable unavailable: ', name)! }
	return found
}

fn poll(process string) !bool {
	result := method(process, 'poll', [], {})!
	done := !null(result) or {
		discard(result)!
		return err
	}
	discard(result)!
	return done
}

fn stop_owned(process string) ! {
	if poll(process)! { return }
	discard(method(process, 'terminate', [], {})!)!
	result := method(process, 'wait', [], {
		'timeout': v(ah.Value(5))
	}) or {
		cause := err
		if !matches(cause, 'subprocess.TimeoutExpired')! { return cause }
		active(cause)!
		discard(method(process, 'kill', [], {})!)!
		discard(method(process, 'wait', [], {})!)!
		active(none)!
		callback('retire_error', {
			'error': detail(cause)
		})!
		return
	}
	discard(result)!
}

struct Observer {
	args     string
	state    string
	process  string
	serial   string
	report   string
	deadline string
	frame    string
mut:
	output          string
	failed          string
	failure_started string
	passed_started  string
	final_output    string
}

fn (mut w Observer) assign(slot int, value string) ! {
	discard(call('operator.setitem', o(w.frame), v(ah.Value(slot)), o(value))!)!
	old := match slot {
		1 { w.output }
		2 { w.failed }
		3 { w.failure_started }
		4 { w.passed_started }
		else { w.final_output }
	}
	match slot {
		1 { w.output = value }
		2 { w.failed = value }
		3 { w.failure_started = value }
		4 { w.passed_started = value }
		else { w.final_output = value }
	}
	if old != '' { discard(old)! }
}

fn (w &Observer) keep() []string {
	return [w.args, w.state, w.process, w.serial, w.report, w.deadline, w.frame, w.output, w.failed,
		w.failure_started, w.passed_started, w.final_output]
}

fn clock() !string { return call('time.monotonic')! }

fn before(deadline string) !bool {
	now := clock()!
	compared := call('operator.lt', o(now), o(deadline)) or {
		discard(now)!
		return err
	}
	discard(now)!
	result := truth(compared) or {
		discard(compared)!
		return err
	}
	discard(compared)!
	return result
}

fn elapsed(start string) !bool {
	now := clock()!
	difference := call('operator.sub', o(now), o(start)) or {
		discard(now)!
		return err
	}
	discard(now)!
	compared := call('operator.ge', o(difference), v(ah.Value(1))) or {
		discard(difference)!
		return err
	}
	discard(difference)!
	result := truth(compared) or {
		discard(compared)!
		return err
	}
	discard(compared)!
	return result
}

fn read_serial(serial string, check_exists bool) !string {
	if check_exists {
		exists := method(serial, 'exists', [], {})!
		present := truth(exists) or {
			discard(exists)!
			return err
		}
		discard(exists)!
		if !present { return literal(ah.Value(''))! }
	}
	return method(serial, 'read_text', [], {
		'errors': v(ah.Value('replace'))
	})!
}

fn failures(output string) !string {
	any_target := resolve('any')!
	checks_target := resolve('_pci_checks') or {
		discard(any_target)!
		return err
	}
	markers := resolve('FAILURES') or {
		release(checks_target, any_target)!
		return err
	}
	checks := target_call(checks_target, [o(markers), o(output)], {}) or {
		release(markers, checks_target, any_target)!
		return err
	}
	release(markers, checks_target)!
	result := target_call(any_target, [o(checks)], {}) or {
		release(checks, any_target)!
		return err
	}
	release(checks, any_target)!
	return result
}

fn contains(output string, name string) !bool {
	marker := resolve(name)!
	result := datum('operator.contains', [o(output), o(marker)]) or {
		discard(marker)!
		return err
	}
	discard(marker)!
	return result as bool
}

fn unexpected(args string, output string) !bool {
	if flag(args, 'no_config_test')! && contains(output, 'CONFIG_MARKER')! { return true }
	if !flag(args, 'mmap_lease_test')! && contains(output, 'MMAP_LEASE_MARKER')! { return true }
	return !flag(args, 'pci_topology_test')! && contains(output, 'TOPOLOGY_MARKER')!
}

fn ready(args string, output string) !bool {
	return contains(output, 'INIT_MARKER')! && (flag(args, 'no_config_test')! || contains(output, 'CONFIG_MARKER')!) && (!flag(args, 'mmap_lease_test')! || contains(output, 'MMAP_LEASE_MARKER')!) && (!flag(args, 'pci_topology_test')! || contains(output, 'TOPOLOGY_MARKER')!)
}

fn (mut w Observer) test_unexpected() ! {
	// Assign after each original condition: later property reads can observe it.
	if flag(w.args, 'no_config_test')! && contains(w.output, 'CONFIG_MARKER')! {
		w.assign(2, literal(ah.Value(true))!)!
	}
	if !flag(w.args, 'mmap_lease_test')! && contains(w.output, 'MMAP_LEASE_MARKER')! {
		w.assign(2, literal(ah.Value(true))!)!
	}
	if !flag(w.args, 'pci_topology_test')! && contains(w.output, 'TOPOLOGY_MARKER')! {
		w.assign(2, literal(ah.Value(true))!)!
	}
}

fn print_pass(args string) ! {
	target := resolve('print')!
	disabled := flag(args, 'no_config_test') or {
		discard(target)!
		return err
	}
	message := if disabled {
		'Default ARM guest: PASS (Linux ABI PID1; config fixture disabled)'
	} else {
		'ARM PCI guest: PASS (ECAM/full-DAIF controller fixture, Linux ABI PID1)'
	}
	result := target_call(target, [v(ah.Value(message))], {}) or {
		discard(target)!
		return err
	}
	release(target, result)!
}

fn print_serial(serial string) ! {
	target := resolve('print')!
	text := formatted(serial) or {
		discard(target)!
		return err
	}
	message := joined('Serial log: ', text) or {
		release(text, target)!
		return err
	}
	discard(text)!
	result := target_call(target, [o(message)], {}) or {
		release(message, target)!
		return err
	}
	release(message, target, result)!
}

fn (mut w Observer) passed() ! {
	discard(call('stop_owned', o(w.process))!)!
	w.assign(5, read_serial(w.serial, false)!)!
	failed := failures(w.final_output)!
	failure := truth(failed) or {
		discard(failed)!
		return err
	}
	discard(failed)!
	if failure || unexpected(w.args, w.final_output)! {
		runtime_error('ARM guest failed during final drain; see ', w.serial)!
	}
	digest := call('digest', o(w.serial))!
	set_item(w.report, 'serial_sha256', o(digest))!
	discard(digest)!
	set_item(w.report, 'status', v(ah.Value('passed')))!
	print_pass(w.args)!
	print_serial(w.serial)!
	discard(call('operator.setitem', o(w.frame), v(ah.Value(0)), v(ah.Value(0)))!)!
}

fn observe(ids []ah.Value) ! {
	mut w := Observer{ args: ids[0].text(), state: ids[1].text(), process: ids[2].text(), serial: ids[3].text(), report: ids[4].text(), deadline: ids[5].text(), frame: ids[6].text() }
	w.assign(3, literal(ah.Value(json2.Null{}))!)!
	w.assign(4, literal(ah.Value(json2.Null{}))!)!
	for before(w.deadline)! || !null(w.failure_started)! {
		point := checkpoint()!
		w.assign(1, read_serial(w.serial, true)!)!
		w.assign(2, failures(w.output)!)!
		w.test_unexpected()!
		if truth(w.failed)! || !null(w.failure_started)! {
			if null(w.failure_started)! { w.assign(3, clock()!)! }
			if elapsed(w.failure_started)! || poll(w.process)! {
				runtime_error('ARM guest failed; see ', w.serial)!
			}
		} else if ready(w.args, w.output)! {
			if null(w.passed_started)! { w.assign(4, clock()!)! }
			if elapsed(w.passed_started)! {
				if poll(w.process)! { error_text('QEMU exited after the guest marker')! }
				w.passed()!
				return
			}
		}
		if poll(w.process)! {
			target := resolve('RuntimeError')!
			path := call('operator.truediv', o(w.state), v(ah.Value('qemu.log'))) or {
				discard(target)!
				return err
			}
			text := formatted(path) or {
				release(path, target)!
				return err
			}
			discard(path)!
			message := joined('QEMU exited; see ', text) or {
				release(text, target)!
				return err
			}
			discard(text)!
			raise_message(target, message)!
		}
		discard(call('time.sleep', v(ah.Value(ah.Number{'0.1'})))!)!
		sweep(point, w.keep())!
	}
	runtime_error('ARM guest timed out; see ', w.serial)!
}

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	args := ah.field(row, 'arguments').items()
	match ah.field(row, 'operation').text() {
		'digest' { return wakehost.dispatch(row)! }
		'executable' { return ah.Value(executable(args[0].text())!) }
		'stop_owned' { stop_owned(args[0].text())! }
		'observe' { observe(args)! }
		'prepare_start' { prepare_start(args)! }
		'prepare_finish' { prepare_finish(args)! }
		else { return error('unknown ARM PCI host operation') }
	}
	return ah.Value(json2.Null{})
}
