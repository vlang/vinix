// SPDX-License-Identifier: GPL-2.0-or-later
module perfrunner

import hosttest
import json2
import math
import os
import perfconsole
import perfreport
import qmpclient
import sync
import time

@[heap]
struct Pointer {
	path     string
	deadline u64
mut:
	lock      sync.Mutex
	monitor   qmpclient.Monitor
	connected bool
	stopped   i32
	tasks     []thread
	retired   bool
}

fn (pointer &Pointer) cancelled() bool {
	return perfconsole.cancelled() || unsafe { C.__atomic_load_n(&pointer.stopped, C.__ATOMIC_RELAXED) } != 0
}

fn (mut pointer Pointer) command(name string, arguments map[string]json2.Any) ! {
	pointer.lock.lock()
	defer { pointer.lock.unlock() }
	if !pointer.connected {
		pointer.monitor = qmpclient.connect_policy(pointer.path, pointer.deadline, fn [pointer] () bool {
			return pointer.cancelled()
		}, true)!
		pointer.connected = true
	}
	pointer.monitor.command(name, arguments)!
}

pub fn move_events(x f64, y f64) []json2.Any {
	return [
		json2.Any({
			'type': json2.Any('abs')
			'data': json2.Any({
				'axis':  json2.Any('x')
				'value': json2.Any(int(x * 32767))
			})
		}),
		json2.Any({
			'type': json2.Any('abs')
			'data': json2.Any({
				'axis':  json2.Any('y')
				'value': json2.Any(int(y * 32767))
			})
		}),
	]
}

fn (mut pointer Pointer) move(x f64, y f64) ! {
	pointer.command('input-send-event', {
		'events': json2.Any(move_events(x, y))
	})!
}

fn (mut pointer Pointer) button(down bool) ! {
	pointer.command('input-send-event', {
		'events': json2.Any([json2.Any({
			'type': json2.Any('btn')
			'data': json2.Any({
				'down':   json2.Any(down)
				'button': json2.Any('left')
			})
		})])
	})!
}

fn (pointer &Pointer) pause(seconds f64) ! {
	deadline := time.sys_mono_now() + u64(seconds * f64(time.second))
	for time.sys_mono_now() < deadline {
		if pointer.cancelled() { return error('pointer interrupted') }
		time.sleep(1 * time.millisecond)
	}
}

fn (mut pointer Pointer) drive(scenario string, seconds f64) ! {
	started := time.sys_mono_now()
	if scenario == 'pointer' {
		for f64(time.sys_mono_now() - started) / f64(time.second) < seconds {
			t := f64(time.sys_mono_now() - started) / f64(time.second)
			pointer.move(0.5 + 0.4 * math.cos(t), 0.5 + 0.45 * math.sin(t * 1.3))!
			pointer.pause(1.0 / 60)!
		}
		return
	}
	x, y := 766.0 / 2048, 72.0 / 1536
	pointer.move(x, y)!
	pointer.pause(0.2)!
	pointer.button(true)!
	pointer.pause(0.1)!
	for f64(time.sys_mono_now() - started) / f64(time.second) < seconds - 0.5 {
		t := f64(time.sys_mono_now() - started) / f64(time.second)
		pointer.move(x + 0.2 * (math.cos(t) - 1), y + 0.3 * (1 - math.cos(t * 0.7)))!
		pointer.pause(1.0 / 60)!
	}
	pointer.button(false)!
}

fn drive_task(mut pointer Pointer, scenario string, seconds f64) {
	pointer.drive(scenario, seconds) or { if !pointer.cancelled() {
		eprintln('pointer driver: ' + err.msg())
	} }
}

fn (mut pointer Pointer) close() {
	if pointer.retired { return }
	pointer.retired = true
	unsafe { C.__atomic_store_n(&pointer.stopped, 1, C.__ATOMIC_RELAXED) }
	for task in pointer.tasks { task.wait() }
	pointer.monitor.close()
}

struct Session {
	shots ?string
mut:
	pointer &Pointer
}

// Search the same fixed byte patterns used by the original serial supervisor.
pub fn marker(line string, prefix string, fields []string) []string {
	mut search := 0
	for search < line.len {
		at := line.index_after(prefix, search) or { return []string{} }
		mut cursor := at + prefix.len
		mut values := []string{}
		mut valid := true
		for index, field in fields {
			if !line[cursor..].starts_with(field) {
				valid = false
				break
			}
			cursor += field.len
			begin := cursor
			if index == fields.len - 1 {
				for cursor < line.len && line[cursor].is_digit() { cursor++ }
			} else {
				for cursor < line.len && line[cursor] !in [u8(` `), `\t`, `\r`, `\n`, 11, 12] {
					cursor++
				}
			}
			if cursor == begin {
				valid = false
				break
			}
			values << line[begin..cursor]
			if index < fields.len - 1 {
				if cursor >= line.len || line[cursor] != ` ` {
					valid = false
					break
				}
				cursor++
			}
		}
		if valid { return values }
		search = at + 1
	}
	return []string{}
}

fn observe(line string, context voidptr) !bool {
	mut session := unsafe { &Session(context) }
	drive := marker(line, 'PERF-DRIVE ', ['', ''])
	if drive.len == 2 {
		if directory := session.shots {
			os.mkdir_all(directory)!
			absolute := hosttest.module_resolve(directory)!
			session.pointer.command('screendump', { 'filename': json2.Any(absolute + '/before-drag.ppm') })!
		}
		session.pointer.tasks << spawn drive_task(mut session.pointer, drive[0], drive[1].f64())
	}
	shot := marker(line, 'PERF-SHOT ', ['variant=', 'scenario=', 'round='])
	if shot.len == 3 {
		if directory := session.shots {
			os.mkdir_all(directory)!
			absolute := hosttest.module_resolve(directory)!
			session.pointer.command('screendump', {
				'filename': json2.Any(absolute + '/' + shot.join('-') + '.ppm')
			})!
		}
	}
	return line.trim(' \t\r\n\x0b\x0c') == perfreport.done || ['KERNEL PANIC', 'FATAL EXCEPTION',
		'PERF-ERROR'].any(line.contains(it))
}

pub fn drive(plan Plan, launch Launch, work string, grace f64, echo bool) !int {
	mut pointer := &Pointer{ path: launch.socket, deadline: time.sys_mono_now() + u64(plan.timeout) * u64(time.second) }
	defer { pointer.close() }
	mut session := &Session{ shots: plan.shots, pointer: pointer }
	output := perfconsole.capture(launch.command, launch.env, plan.root, f64(plan.timeout), grace, echo, observe, session)!
	pointer.close()
	return finish_capture(plan, work, output)!
}

pub fn finish_capture(plan Plan, work string, output perfconsole.Output) !int {
	log := work + '/serial.log'
	os.write_file_array(log, output.data)!
	println('\n==> Serial log: ' + log)
	if output.failure != '' { return error(output.failure) }
	report := perfreport.finish_policy(output.data, plan.builds.map(it.name), plan.scenarios, plan.rounds, plan.json_path, output.timed_out, perfreport.Value(perfreport.Number{output.status.str()}), plan.libc != '')!
	print(report.stdout)
	eprint(report.stderr)
	if !output.drained {
		eprintln('ERROR: serial console did not finish draining after guest shutdown')
		return 1
	}
	return report.status
}
