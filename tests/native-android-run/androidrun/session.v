// SPDX-License-Identifier: GPL-2.0-or-later
module androidrun

import androidhost as ah
import cachecli
import hosttest
import os
import sourcecommand
import sync
import time

#include <signal.h>

const failures = ['ANDROID-FAIL', 'KERNEL PANIC', 'FATAL EXCEPTION', 'JNI DETECTED ERROR IN APPLICATION',
	'Fatal signal ']

@[heap]
struct Session {
	state  string
	socket string
	args   map[string]ah.Value
mut:
	child         sourcecommand.PtyChild
	mutex         sync.Mutex
	transcript    []u8
	reader_stop   bool
	input_stop    bool
	input_done    bool
	serial_errors []string
	input_errors  []string
	input_retries []ah.Value
}

fn (mut session Session) recent() string {
	session.mutex.lock()
	defer { session.mutex.unlock() }
	start := if session.transcript.len > 262144 { session.transcript.len - 262144 } else { 0 }
	return session.transcript[start..].bytestr().clone()
}

fn (mut session Session) observed_input() !string {
	lines := session.recent().replace('\r', '').split('\n')
	for index := lines.len - 2; index >= 0; index-- {
		if lines[index].starts_with('ANDROID-INPUT ') {
			value := lines[index]['ANDROID-INPUT '.len..]
			hosttest.module_decode_utf8(value)!
			return value
		}
	}
	return ''
}

fn input_cancelled(pointer voidptr) bool {
	mut session := unsafe { &Session(pointer) }
	session.mutex.lock()
	defer { session.mutex.unlock() }
	return session.input_stop
}

fn (mut session Session) input_pause(seconds f64) ! {
	deadline := time.sys_mono_now() + u64(seconds * f64(time.second))
	for time.sys_mono_now() < deadline {
		if input_cancelled(session) || cachecli.cancelled() { return error('input interrupted') }
		time.sleep(10 * time.millisecond)
	}
}

fn (mut session Session) command(name string, options map[string]ah.Value) !ah.Value {
	mut monitor := connect_cancelled(session.socket, 20, input_cancelled, session)!
	defer { monitor.close() }
	return monitor.command(name, options)
}

fn (mut session Session) capture(destination string) ! {
	ppm := with_suffix(destination, '.ppm')!
	session.command('screendump', {
		'filename': ah.Value(ppm)
	})!
	encode_screenshot(ppm, destination)!
	os.rm(ppm)!
}

fn (mut session Session) click() ! {
	coordinates := ah.field(session.args, 'click').items()
	mut events := []ah.Value{}
	for index, axis in ['x', 'y'] {
		value := round_even(f64(number(coordinates[index])!) * 32767 / if index == 0 {
			1023.0
		} else {
			767.0
		})
		events << ah.Value({
			'type': ah.Value('abs')
			'data': ah.Value({
				'axis':  ah.Value(axis)
				'value': ah.Value(value)
			})
		})
	}
	session.command('input-send-event', {
		'events': ah.Value(events)
	})!
	session.input_pause(0.2)!
	for down in [true, false] {
		session.command('input-send-event', {
			'events': ah.Value(button_events(down))
		})!
		session.input_pause(0.35)!
	}
	session.input_pause(3)!
}

fn (mut session Session) keyboard() !int {
	characters := text(session.args, 'keys').runes()
	mut retries := 0
	for index, character in characters {
		events := key_events(character.str()) or { return error('QMP cannot type ' + ah.encode(ah.Value(character.str()))) }
		previous := characters[..index].string()
		expected := characters[..index + 1].string()
		for attempt in 0 .. 3 {
			if attempt > 0 { retries++ }
			// Deliver a complete tap together. Holding a key across host waits
			// can trigger the guest's repeat timer under load.
			session.command('input-send-event', {'events': ah.Value(events)})!
			deadline := time.sys_mono_now() + 8 * time.second
			mut actual := ''
			for time.sys_mono_now() < deadline {
				actual = session.observed_input()!
				if actual == expected { break }
				if actual != previous {
					return error('APK input became ' + ah.encode(ah.Value(actual)) + '; expected ' + ah.encode(ah.Value(expected)))
				}
				session.input_pause(0.1)!
			}
			if actual == expected { break }
			if attempt == 2 {
				return error('APK did not acknowledge ' + ah.encode(ah.Value(character.str())) + '; input remains ' + ah.encode(ah.Value(actual)))
			}
		}
	}
	return retries
}

fn input_body(mut session Session) ! {
	session.input_pause(3)!
	session.capture(session.state + '/ready.png')!
	session.click()!
	retries := session.keyboard()!
	session.mutex.lock()
	session.input_retries << ah.Value(retries)
	session.mutex.unlock()
}

fn input_worker(mut session Session) {
	input_body(mut session) or {
		session.mutex.lock()
		session.input_errors << err.msg()
		session.mutex.unlock()
	}
	session.mutex.lock()
	session.input_done = true
	session.mutex.unlock()
}

fn read_serial(mut session Session) ! {
	mut log := os.create(session.state + '/serial.log')!
	defer { log.close() }
	mut bytes := []u8{len: 65536}
	for {
		session.mutex.lock()
		stopped := session.reader_stop
		session.mutex.unlock()
		if stopped { break }
		count := session.child.read(mut bytes, 100)!
		if count == 0 { break }
		if count < 0 { continue }
		session.mutex.lock()
		session.transcript << bytes[..count]
		session.mutex.unlock()
		write_bytes(mut log, bytes[..count])!
		log.flush()
		mut output := os.stdout()
		write_bytes(mut output, bytes[..count])!
		output.flush()
	}
}

fn serial_worker(mut session Session) {
	read_serial(mut session) or {
		session.mutex.lock()
		session.serial_errors << err.msg()
		session.mutex.unlock()
	}
}

fn stop_vm(child &sourcecommand.PtyChild) ! {
	child.write([u8(1), `x`]) or {}
	for index, signal in [0, C.SIGTERM, C.SIGKILL] {
		if signal != 0 { child.signal(signal)! }
		if child.settle(if index == 2 { 1.0 } else { 3.0 })! { return }
	}
}

pub fn (mut context Context) run_session(overlay ah.Value) !int {
	state := text(context.args, 'state_dir')
	socket := state + '/qmp.sock'
	plan := if context.plan_hook != unsafe { nil } {
		context.plan_hook(context.args, overlay)!
	} else {
		value := context.call('vm_plan', {
			'args':    ah.Value(context.args)
			'overlay': overlay
		})!.object()
		mut environment := map[string]string{}
		for key, item in ah.field(value, 'environment').object() { environment[key] = item.text() }
		Plan{ah.field(value, 'command').items().map(it.text()), environment, text(context.args, 'repo')}
	}
	mut session := &Session{ child: sourcecommand.spawn_pty(plan.command, plan.environment, plan.directory)!, state: state, socket: socket, args: context.args }
	mut reader := spawn serial_worker(mut session)
	mut workers := []thread{}
	mut typed := false
	mut input_joined := false
	mut reader_joined := false
	mut retired := false
	defer {
		if !retired {
			session.mutex.lock()
			session.input_stop = true
			session.reader_stop = true
			session.mutex.unlock()
			if typed && !input_joined { workers[0].wait() }
			if !reader_joined { reader.wait() }
			session.child.close() or {}
			os.rm(socket) or {}
		}
	}
	interactive := truth(ah.field(context.args, 'interactive'))
	observe := truth(ah.field(context.args, 'observe'))
	mut passed := false
	mut observed := false
	mut guest_failed := false
	mut failure := 'timeout'
	seconds := number(ah.field(context.args, 'timeout'))!
	mut deadline := if interactive {
		~u64(0)
	} else if seconds <= 0 {
		u64(0)
	} else {
		time.sys_mono_now() + u64(seconds) * time.second
	}
	for time.sys_mono_now() < deadline {
		if cachecli.cancelled() {
			if interactive && !observed && !guest_failed {
				failure = 'interactive session stopped before observing a window'
			}
			break
		}
		if session.child.poll()!.exited {
			failure = if interactive {
				'VM exited before observing a window'
			} else {
				'VM exited before passing'
			}
			break
		}
		time.sleep(100 * time.millisecond)
		recent := session.recent()
		if recent.contains('ANDROID-READY') && text(context.args, 'input') == 'qmp' && !observe && !typed {
			typed = true
			workers << spawn input_worker(mut session)
		}
		session.mutex.lock()
		io_failure := if session.input_errors.len > 0 {
			session.input_errors[0]
		} else if session.serial_errors.len > 0 {
			session.serial_errors[0]
		} else {
			''
		}
		session.mutex.unlock()
		if io_failure != '' {
			guest_failed = true
			failure = 'host I/O failed: ' + io_failure
			break
		}
		mut failed := false
		for marker in failures {
			if recent.contains(marker) {
				failed = true
				break
			}
		}
		if failed {
			guest_failed = true
			failure = 'guest reported a failure'
			if interactive {
				observed = false
			} else {
				ending := time.sys_mono_now() + 4 * time.second
				if ending < deadline { deadline = ending }
			}
		}
		if interactive && recent.contains('ANDROID-READY') && !observed && !guest_failed {
			observed = true
			println('Interactive APK window ready; application functionality is unchecked. Use the QEMU window locally; Ctrl-C stops the session.')
			flush_stdout()
		}
		if !interactive && !guest_failed && (recent.contains('ANDROID-PASS') || (observe && recent.contains('ANDROID-OBSERVED'))) {
			passed = recent.contains('ANDROID-PASS')
			observed = !passed
			pause(2) or { break }
			break
		}
	}
	if typed {
		ending := time.sys_mono_now() + 25 * time.second
		mut done := false
		for time.sys_mono_now() < ending {
			session.mutex.lock()
			done = session.input_done
			session.mutex.unlock()
			if done || cachecli.cancelled() { break }
			time.sleep(10 * time.millisecond)
		}
		session.mutex.lock()
		if !done || session.input_errors.len > 0 {
			passed = false
			failure = 'keyboard input failed: ' + if session.input_errors.len > 0 {
				session.input_errors[0]
			} else {
				'timeout'
			}
		}
		session.input_stop = true
		session.mutex.unlock()
		workers[0].wait()
		input_joined = true
	}
	if !interactive {
		if os.exists(socket) {
			screenshot(socket, text(context.args, 'screenshot')) or {
				eprintln('Screenshot failed: ' + err.msg())
				passed = false
				observed = false
				failure = 'screenshot failed'
			}
		} else {
			passed = false
			observed = false
			failure = 'VM did not expose QMP'
		}
	}
	stop_vm(&session.child)!
	session.mutex.lock()
	session.reader_stop = true
	session.mutex.unlock()
	reader.wait()
	reader_joined = true
	session.child.close()!
	os.rm(socket) or {}
	retired = true
	if cachecli.cancelled() && !interactive { cachecli.checkpoint()! }
	result := context.call('finalize', {
		'args':           ah.Value(context.args)
		'state':          ah.Value(state)
		'transcript_hex': ah.Value(session.transcript.hex())
		'passed':         ah.Value(passed)
		'observed':       ah.Value(observed)
		'failure':        ah.Value(failure)
		'guest_failed':   ah.Value(guest_failed)
		'input_retries':  ah.Value(session.input_retries)
	})!
	return int(number(result)!)
}
