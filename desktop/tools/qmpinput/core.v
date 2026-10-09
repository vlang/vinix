// SPDX-License-Identifier: GPL-2.0-or-later
module qmpinput

import androidhost as ah
import json2

fn absolute(value string, extent string) !string {
	integer := resolve('int')!
	rounder := resolve('round') or {
		release(integer)!
		return err
	}
	maximum_axis := resolve('ABS_MAX') or {
		release(rounder, integer)!
		return err
	}
	product := binary('mul', value, o(maximum_axis)) or {
		cause := err
		release(maximum_axis, rounder, integer)!
		return cause
	}
	release(maximum_axis)!
	maximum := resolve('max') or {
		release(product, rounder, integer)!
		return err
	}
	difference := binary('sub', extent, n(1)) or {
		release(maximum, product, rounder, integer)!
		return err
	}
	denominator := invoke(maximum, [o(difference), n(1)], {}, [difference]) or {
		release(product, rounder, integer)!
		return err
	}
	divided := binary('truediv', product, o(denominator)) or {
		cause := err
		release(product, denominator, rounder, integer)!
		return cause
	}
	release(product, denominator)!
	rounded := invoke(rounder, [o(divided)], {}, [divided]) or {
		release(integer)!
		return err
	}
	scaled := invoke(integer, [o(rounded)], {}, [rounded])!
	maximum_clamp := resolve('max')!
	minimum := resolve('min') or {
		release(maximum_clamp)!
		return err
	}
	clamp_axis := resolve('ABS_MAX') or {
		release(minimum, maximum_clamp)!
		return err
	}
	bounded := invoke(minimum, [o(clamp_axis), o(scaled)], {}, [clamp_axis]) or {
		release(maximum_clamp)!
		return err
	}
	return invoke(maximum_clamp, [n(0), o(bounded)], {}, [bounded])!
}

fn key_events(character string) !string {
	mut name := ''
	mut shift := ''
	if test(method(character, 'isalpha', [])!)! && test(method(character, 'isascii', [])!)! {
		name = method(character, 'lower', [])!
		shift = method(character, 'isupper', [])!
	} else if test(method(character, 'isdigit', [])!)! {
		name = character
		shift = literal(ah.Value(false))!
	} else if test(binary('contains', resolve('SHIFTED')!, o(character))!)! {
		name = binary('getitem', resolve('SHIFTED')!, o(character))!
		shift = literal(ah.Value(true))!
	} else if test(binary('contains', resolve('KEY_NAMES')!, o(character))!)! {
		name = binary('getitem', resolve('KEY_NAMES')!, o(character))!
		shift = literal(ah.Value(false))!
	} else {
		return literal(ah.Value(json2.Null{}))!
	}
	shifted := truth(shift)!
	mut events := []string{}
	if shifted { events << named_press('shift', true)! }
	events << press(name, v(ah.Value(true)))!
	events << press(name, v(ah.Value(false)))!
	if shifted { events << named_press('shift', false)! }
	result := list(events)!
	release(...events)!
	return result
}

fn axis(axis string, value string) !string {
	data := dictionary(['axis', 'value'], [s(axis), o(value)])!
	result := dictionary(['type', 'data'], [s('abs'), o(data)])!
	release(data)!
	return result
}

fn move_events(args []string) !string {
	x := call('absolute', [o(args[0]), o(args[2])])!
	x_event := axis('x', x)!
	release(x)!
	y := call('absolute', [o(args[1]), o(args[3])])!
	y_event := axis('y', y)!
	release(y)!
	result := list([x_event, y_event])!
	release(x_event, y_event)!
	return result
}

fn button_events(down string) !string {
	data := dictionary(['down', 'button'], [o(down), s('left')])!
	event := dictionary(['type', 'data'], [s('btn'), o(data)])!
	release(data)!
	result := list([event])!
	release(event)!
	return result
}

fn monitor_init(self string, path string) ! {
	target := resolve('socket.socket')!
	family := resolve('socket.AF_UNIX') or {
		release(target)!
		return err
	}
	kind := resolve('socket.SOCK_STREAM') or {
		release(family, target)!
		return err
	}
	socket := invoke(target, [o(family), o(kind)], {}, [family, kind])!
	set_attr(self, 'sock', socket)!
	release(socket)!
	held := attr(self, 'sock')!
	connect := attr(held, 'connect')!
	release(held)!
	discarded(invoke(connect, [o(path)], {}, [])!)!
	held_again := attr(self, 'sock')!
	makefile := attr(held_again, 'makefile')!
	release(held_again)!
	stream := invoke(makefile, [s('rw')], {
		'encoding': s('utf-8')
		'newline':  s('\n')
	}, [])!
	set_attr(self, 'stream', stream)!
	release(stream)!
	read_stream := attr(self, 'stream')!
	read := attr(read_stream, 'readline')!
	release(read_stream)!
	discarded(invoke(read, [], {}, [])!)!
	discarded(method(self, 'command', [s('qmp_capabilities')])!)!
}

fn command(self string, name string, arguments string) !string {
	request := dictionary(['execute'], [o(name)])!
	if truth(arguments)! {
		discarded(call('operator.setitem', [o(request), s('arguments'), o(arguments)])!)!
	}
	stream := attr(self, 'stream')!
	writer := attr(stream, 'write')!
	release(stream)!
	encoder := resolve('json.dumps') or {
		release(writer)!
		return err
	}
	encoded := invoke(encoder, [o(request)], {}, []) or {
		release(writer)!
		return err
	}
	line_ := binary('add', encoded, s('\n')) or {
		cause := err
		release(encoded, writer)!
		return cause
	}
	release(encoded)!
	discarded(invoke(writer, [o(line_)], {}, [line_])!)!
	flush_stream := attr(self, 'stream')!
	flusher := attr(flush_stream, 'flush')!
	release(flush_stream)!
	discarded(invoke(flusher, [], {}, [])!)!
	mut line := ''
	mut message := ''
	for {
		mark := checkpoint()!
		read_stream := attr(self, 'stream')!
		reader := attr(read_stream, 'readline')!
		release(read_stream)!
		fresh := invoke(reader, [], {}, [])!
		release(line)!
		line = fresh
		if !truth(line)! {
			callback('raise', {
				'kind': ah.Value('RuntimeError')
				'args': ah.Value([s('QMP closed the connection')])
			})!
		}
		decoded := call('json.loads', [o(line)])!
		release(message)!
		message = decoded
		if test(binary('contains', message, s('return'))!)! || test(binary('contains', message, s('error'))!)! {
			if test(binary('contains', message, s('error'))!)! {
				callback('raise', {
					'kind': ah.Value('RuntimeError')
					'args': ah.Value([o(binary('getitem', message, s('error'))!)])
				})!
			}
			return binary('getitem', message, s('return'))!
		}
		sweep(mark, [line, message])!
	}
	return error('unreachable QMP reply')
}

fn send_input(self string, events string) ! {
	discarded(invoke(attr(self, 'command')!, [s('input-send-event')], {
		'events': o(events)
	}, [])!)!
}

fn hold_command_tab(self string, taps string, hold string, settle string) ! {
	first_target := attr(self, 'send_input')!
	first := named_press('meta_l', true)!
	events := list([first])!
	release(first)!
	discarded(invoke(first_target, [o(events)], {}, [events])!)!
	sleep(o(settle))!
	ranger := resolve('range')!
	count := call('max', [o(taps), n(1)])!
	range_ := invoke(ranger, [o(count)], {}, [count])!
	iterator := iterate(range_)!
	release(range_)!
	mut ignored := ''
	for {
		row := next(iterator)!.object()
		if ah.field(row, 'done') as bool { break }
		release(ignored)!
		ignored = ah.field(row, 'value').text()
		down_target := attr(self, 'send_input')!
		down := named_press('tab', true)!
		down_events := list([down])!
		release(down)!
		discarded(invoke(down_target, [o(down_events)], {}, [down_events])!)!
		sleep(v(ah.Value(ah.Number{'0.05'})))!
		up_target := attr(self, 'send_input')!
		up := named_press('tab', false)!
		up_events := list([up])!
		release(up)!
		discarded(invoke(up_target, [o(up_events)], {}, [up_events])!)!
		sleep(o(settle))!
	}
	release(iterator)!
	sleep(o(hold))!
	last_target := attr(self, 'send_input')!
	last := named_press('meta_l', false)!
	last_events := list([last])!
	release(last)!
	discarded(invoke(last_target, [o(last_events)], {}, [last_events])!)!
}

fn type_text(self string, text string) ! {
	iterator := iterate(text)!
	mut character := ''
	mut events := ''
	mut event := ''
	for {
		row := next(iterator)!.object()
		if ah.field(row, 'done') as bool { break }
		release(character)!
		character = ah.field(row, 'value').text()
		fresh := call('key_events', [o(character)])!
		release(events)!
		events = fresh
		if test(call('operator.is_', [o(events), v(ah.Value(json2.Null{}))])!)! { continue }
		each := iterate(events)!
		for {
			item := next(each)!.object()
			if ah.field(item, 'done') as bool { break }
			release(event)!
			event = ah.field(item, 'value').text()
			target := attr(self, 'command')!
			singular := list([event])!
			discarded(invoke(target, [s('input-send-event')], {
				'events': o(singular)
			}, [singular])!)!
		}
		release(each)!
		sleep(v(ah.Value(ah.Number{'0.03'})))!
	}
	release(iterator)!
}

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	args := ah.field(row, 'arguments').items().map(it.text())
	result := match ah.field(row, 'operation').text() {
		'absolute' { absolute(args[0], args[1])! }
		'key_events' { key_events(args[0])! }
		'move_events' { move_events(args)! }
		'button_events' { button_events(args[0])! }
		'__init__' {
			monitor_init(args[0], args[1])!
			''
		}
		'command' { command(args[0], args[1], args[2])! }
		'send_input' {
			send_input(args[0], args[1])!
			''
		}
		'hold_command_tab' {
			hold_command_tab(args[0], args[1], args[2], args[3])!
			''
		}
		'type_text' {
			type_text(args[0], args[1])!
			''
		}
		else { return error('Unknown QMP input operation') }
	}
	sweep(ah.Value(0), [result])!
	return if result == '' { ah.Value(json2.Null{}) } else { ah.Value(result) }
}
