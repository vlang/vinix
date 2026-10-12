// SPDX-License-Identifier: GPL-2.0-or-later
module androidrun

import androidhost as ah
import androidtools
import cachecli
import math
import os
import strconv
import time

const key_names = {
	' ':  'spc'
	'-':  'minus'
	'=':  'equal'
	'[':  'bracket_left'
	']':  'bracket_right'
	';':  'semicolon'
	"'":  'apostrophe'
	'`':  'grave_accent'
	'\\': 'backslash'
	',':  'comma'
	'.':  'dot'
	'/':  'slash'
	'\n': 'ret'
	'\t': 'tab'
}
const shifted_names = {
	'!': '1'
	'@': '2'
	'#': '3'
	'$': '4'
	'%': '5'
	'^': '6'
	'&': '7'
	'*': '8'
	'(': '9'
	')': '0'
	'_': 'minus'
	'+': 'equal'
	'{': 'bracket_left'
	'}': 'bracket_right'
	':': 'semicolon'
	'"': 'apostrophe'
	'~': 'grave_accent'
	'|': 'backslash'
	'<': 'comma'
	'>': 'dot'
	'?': 'slash'
}

pub fn key_press(name string, down bool) ah.Value {
	return ah.Value({
		'type': ah.Value('key')
		'data': ah.Value({
			'down': ah.Value(down)
			'key':  ah.Value({
				'type': ah.Value('qcode')
				'data': ah.Value(name)
			})
		})
	})
}

pub fn key_events(character string) ?[]ah.Value {
	mut name := ''
	mut shift := false
	if character.len == 1 && ((character[0] >= `a` && character[0] <= `z`) || (character[0] >= `A` && character[0] <= `Z`)) {
		name = character.to_lower()
		shift = character[0] <= `Z`
	} else if character_digit(character) {
		name = character
	} else if character in shifted_names {
		name = shifted_names[character]
		shift = true
	} else if character in key_names {
		name = key_names[character]
	} else {
		return none
	}
	mut events := []ah.Value{}
	if shift { events << key_press('shift', true) }
	events << key_press(name, true)
	events << key_press(name, false)
	if shift { events << key_press('shift', false) }
	return events
}

fn round_even(value f64) i64 {
	floor := math.floor(value)
	fraction := value - floor
	return i64(floor) + if fraction > 0.5 || (fraction == 0.5 && i64(floor) % 2 != 0) {
		1
	} else {
		0
	}
}

pub fn absolute(value i64, extent i64) i64 {
	denominator := if extent > 1 { extent - 1 } else { i64(1) }
	if value <= 0 { return 0 }
	if value >= denominator { return 32767 }
	result := round_even(f64(value) * 32767 / f64(denominator))
	return if result < 0 {
		0
	} else if result > 32767 {
		32767
	} else {
		result
	}
}

pub fn move_events(x i64, y i64, width i64, height i64) []ah.Value {
	return [
		ah.Value({
			'type': ah.Value('abs')
			'data': ah.Value({
				'axis':  ah.Value('x')
				'value': ah.Value(absolute(x, width))
			})
		}),
		ah.Value({
			'type': ah.Value('abs')
			'data': ah.Value({
				'axis':  ah.Value('y')
				'value': ah.Value(absolute(y, height))
			})
		}),
	]
}

pub fn button_events(down bool) []ah.Value {
	return [ah.Value({
		'type': ah.Value('btn')
		'data': ah.Value({
			'down':   ah.Value(down)
			'button': ah.Value('left')
		})
	})]
}

fn pause(seconds f64) ! {
	if seconds < 0 || !math.is_finite(seconds) {
		return error('sleep length must be non-negative and finite')
	}
	deadline := time.sys_mono_now() + u64(seconds * f64(time.second))
	for time.sys_mono_now() < deadline {
		cachecli.checkpoint()!
		remaining := deadline - time.sys_mono_now()
		time.sleep(time.Duration(if remaining < time.millisecond * 10 {
			remaining
		} else {
			time.millisecond * 10
		}))
	}
}

fn send_events(mut monitor Monitor, events []ah.Value) ! {
	monitor.command('input-send-event', {
		'events': ah.Value(events)
	})!
}

pub fn input_cli(argv []string) !int {
	args := cachecli.arguments(argv, ['--socket', '--size', '--settle', '--hold'], [], [], 1, -1, 'input move|click|drag|type|switch [coordinates or text] [--socket PATH --size WIDTHxHEIGHT --settle SECONDS --hold SECONDS]') or { return androidtools.InputError{err.msg()} }
	action := args.positional[0]
	if action !in ['move', 'click', 'drag', 'type', 'switch'] {
		return androidtools.InputError{'invalid input action: ' + action}
	}
	dimensions := args.value('--size', '1024x768').split('x')
	if dimensions.len != 2 { return error('display size must be WIDTHxHEIGHT') }
	width := strconv.parse_int(dimensions[0], 10, 64)!
	height := strconv.parse_int(dimensions[1], 10, 64)!
	settle := strconv.atof64(args.value('--settle', '0.25'))!
	hold := strconv.atof64(args.value('--hold', '0'))!
	mut monitor := connect_monitor(args.value('--socket', if os.getenv('VINIX_QMP_SOCKET') != '' {
		os.getenv('VINIX_QMP_SOCKET')
	} else {
		'/tmp/vinix-qmp'
	}), 0)!
	defer { monitor.close() }
	coordinates := args.positional[1..]
	if action == 'switch' {
		taps := if coordinates.len > 0 {
			strconv.parse_int(coordinates[0], 10, 64)!
		} else {
			i64(1)
		}
		send_events(mut monitor, [key_press('meta_l', true)])!
		pause(settle)!
		for _ in 0 .. int(if taps > 1 { taps } else { 1 }) {
			send_events(mut monitor, [key_press('tab', true)])!
			pause(0.05)!
			send_events(mut monitor, [key_press('tab', false)])!
			pause(settle)!
		}
		pause(hold)!
		send_events(mut monitor, [key_press('meta_l', false)])!
	} else if action == 'type' {
		for character in coordinates.join(' ').runes() {
			events := key_events(character.str()) or { continue }
			for event in events { send_events(mut monitor, [event])! }
			pause(0.03)!
		}
	} else {
		mut values := []i64{}
		for value in coordinates { values << strconv.parse_int(value, 10, 64)! }
		required := if action == 'drag' { 4 } else { 2 }
		if values.len < required {
			return error(action + ' requires ' + required.str() + ' coordinates')
		}
		send_events(mut monitor, move_events(values[0], values[1], width, height))!
		if action != 'move' {
			pause(settle)!
			send_events(mut monitor, button_events(true))!
			pause(settle)!
			if action == 'drag' {
				for step in 1 .. 13 {
					x := values[0] + i64(math.floor(f64(values[2] - values[0]) * step / 12))
					y := values[1] + i64(math.floor(f64(values[3] - values[1]) * step / 12))
					send_events(mut monitor, move_events(x, y, width, height))!
					pause(0.05)!
				}
				pause(settle)!
			}
			send_events(mut monitor, button_events(false))!
		}
	}
	pause(settle)!
	return 0
}
