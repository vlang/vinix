// SPDX-License-Identifier: GPL-2.0-or-later
module desktopprep

import androidhost as ah
import json2

// Only handles are native. Python still owns the actual socket, reply, command,
// arithmetic operands and callback targets. Each expression retires its stack.
struct QmpExpression {
mut:
	owned []string
}

fn (mut q QmpExpression) own(id string) string {
	q.owned << id
	return id
}

fn (mut q QmpExpression) detach(id string) {
	index := q.owned.index(id)
	if index >= 0 { q.owned.delete(index) }
}

fn (mut q QmpExpression) drop(id string) ! {
	if id in q.owned {
		q.detach(id)
		release([id])!
	}
}

fn (mut q QmpExpression) clear() ! {
	for q.owned.len > 0 {
		id := q.owned.last()
		q.owned.delete_last()
		release([id])!
	}
}

fn (mut q QmpExpression) constant(value ah.Value) !string {
	return q.own(literal(value)!)
}

fn (mut q QmpExpression) target(name string) !string {
	return q.own(global(name)!)
}

fn (mut q QmpExpression) intrinsic(name string) !string {
	return q.own(resolve(name)!)
}

fn (mut q QmpExpression) attribute(receiver string, name string) !string {
	value := member(receiver, name) or {
		q.drop(receiver)!
		return err
	}
	q.drop(receiver)!
	return q.own(value)
}

fn (mut q QmpExpression) invoke_(target string, args []string) !string {
	result := callback('function', {
		'target': ah.Value(target)
		'call':   ah.Value(true)
		'args':   ah.Value(args.map(o(it)))
	}) or {
		cause := err
		for i := args.len - 1; i >= 0; i-- { q.drop(args[i])! }
		q.drop(target)!
		return cause
	}
	for i := args.len - 1; i >= 0; i-- { q.drop(args[i])! }
	q.drop(target)!
	return q.own(result.text())
}

fn (mut q QmpExpression) binary_(name string, left string, right string) !string {
	target := q.intrinsic('operator.' + name)!
	result := callback('function', {
		'target': ah.Value(target)
		'call':   ah.Value(true)
		'args':   ah.Value([o(left), o(right)])
	}) or {
		cause := err
		q.drop(left)!
		q.drop(right)!
		q.drop(target)!
		return cause
	}
	q.drop(left)!
	q.drop(right)!
	q.drop(target)!
	return q.own(result.text())
}

fn (mut q QmpExpression) truth_(id string) !bool {
	target := q.intrinsic('_QMP_TRUTH')!
	result := callback('function', {
		'target': ah.Value(target)
		'call':   ah.Value(true)
		'args':   ah.Value([o(id)])
		'data':   ah.Value(true)
	}) or {
		q.drop(target)!
		return err
	}
	q.drop(target)!
	return result as bool
}

fn (mut q QmpExpression) dict_(keys []string, values []string) !string {
	target := q.intrinsic('_QMP_DICT')!
	tuple_target := q.intrinsic('_tuple')!
	mut key_ids := []string{}
	for key in keys { key_ids << q.constant(ah.Value(key))! }
	key_tuple := q.invoke_(tuple_target, key_ids)!
	mut args := [key_tuple]
	args << values
	return q.invoke_(target, args)!
}

fn qmp_sleep(mut q QmpExpression, duration string) ! {
	target := q.target('time.sleep')!
	q.invoke_(target, [duration])!
	q.clear()!
}

fn qmp_pause(mut q QmpExpression, duration string) ! {
	target := q.target('time.sleep')!
	q.invoke_(target, [q.constant(ah.Value(ah.Number{ text: duration }))!])!
	q.clear()!
}

fn qmp_coordinate(mut q QmpExpression, value string, dimension string) !string {
	target := q.target('round')!
	scaled := q.binary_('mul', value, q.constant(ah.Value(32767))!)!
	divisor := q.target(dimension)!
	divided_ := q.binary_('truediv', scaled, divisor)!
	return q.invoke_(target, [divided_])!
}

fn qmp_absolute(mut q QmpExpression, value string, axis string, dimension string) !string {
	coordinate := qmp_coordinate(mut q, value, dimension)!
	data := q.dict_(['axis', 'value'], [q.constant(ah.Value(axis))!, coordinate])!
	return q.dict_(['type', 'data'], [q.constant(ah.Value('abs'))!, data])!
}

fn qmp_button(mut q QmpExpression, down bool) !string {
	data := q.dict_(['button', 'down'], [q.constant(ah.Value('left'))!, q.constant(ah.Value(down))!])!
	return q.dict_(['type', 'data'], [q.constant(ah.Value('btn'))!, data])!
}

fn qmp_events(mut q QmpExpression, receiver string, x string, y string, press bool, release_ bool) ! {
	target := q.attribute(receiver, 'call')!
	command := q.constant(ah.Value('input-send-event'))!
	mut events := []string{}
	if !release_ {
		events << qmp_absolute(mut q, x, 'x', 'WIDTH')!
		events << qmp_absolute(mut q, y, 'y', 'HEIGHT')!
	}
	if press || release_ { events << qmp_button(mut q, !release_)! }
	list_target := q.intrinsic('_list')!
	list := q.invoke_(list_target, events)!
	arguments := q.dict_(['events'], [list])!
	q.invoke_(target, [command, arguments])!
	q.clear()!
}

fn qmp_init(mut q QmpExpression, f &Frame) ! {
	factory := q.target('socket.socket')!
	family := q.target('socket.AF_UNIX')!
	socket := q.invoke_(factory, [family])!
	store := q.intrinsic('_QMP_STORE_SOCKET')!
	q.invoke_(store, [f.names['self'], socket])!
	q.clear()!
	target := q.attribute(q.attribute(f.names['self'], 'socket')!, 'settimeout')!
	q.invoke_(target, [q.constant(ah.Value(10))!])!
	q.clear()!
	connect := q.attribute(q.attribute(f.names['self'], 'socket')!, 'connect')!
	converter := q.target('str')!
	path := q.invoke_(converter, [f.names['path']])!
	q.invoke_(connect, [path])!
	q.clear()!
	makefile := q.attribute(q.attribute(f.names['self'], 'socket')!, 'makefile')!
	file := q.invoke_(makefile, [q.constant(ah.Value('rb'))!])!
	store_file := q.intrinsic('_QMP_STORE_FILE')!
	q.invoke_(store_file, [f.names['self'], file])!
	q.clear()!
	decoder := q.target('json.loads')!
	readline := q.attribute(q.attribute(f.names['self'], 'file')!, 'readline')!
	greeting := q.invoke_(readline, [])!
	q.invoke_(decoder, [greeting])!
	q.clear()!
	capabilities := q.attribute(f.names['self'], 'call')!
	q.invoke_(capabilities, [q.constant(ah.Value('qmp_capabilities'))!])!
	q.clear()!
}

fn qmp_call(mut q QmpExpression, mut f Frame) !string {
	sender := q.attribute(q.attribute(f.names['self'], 'socket')!, 'sendall')!
	encoder := q.target('json.dumps')!
	mut arguments := f.names['arguments']
	if !q.truth_(arguments)! { arguments = q.dict_([], [])! }
	payload := q.dict_(['execute', 'arguments'], [f.names['command'], arguments])!
	text := q.invoke_(encoder, [payload])!
	line := q.binary_('add', text, q.constant(ah.Value('\n'))!)!
	encode := q.attribute(line, 'encode')!
	bytes := q.invoke_(encode, [])!
	q.invoke_(sender, [bytes])!
	q.clear()!
	for {
		decoder := q.target('json.loads')!
		readline := q.attribute(q.attribute(f.names['self'], 'file')!, 'readline')!
		line_ := q.invoke_(readline, [])!
		reply := q.invoke_(decoder, [line_])!
		q.detach(reply)
		f.named('reply', reply)!
		has_error := q.binary_('contains', reply, q.constant(ah.Value('error'))!)!
		fail := q.truth_(has_error)!
		q.clear()!
		if fail {
			factory := q.target('RuntimeError')!
			cause := q.invoke_(factory, [reply])!
			raiser := q.intrinsic('_QMP_RAISE')!
			q.invoke_(raiser, [cause])!
			return error('QMP error factory did not raise')
		}
		has_return := q.binary_('contains', reply, q.constant(ah.Value('return'))!)!
		done := q.truth_(has_return)!
		q.clear()!
		if done {
			result := q.binary_('getitem', reply, q.constant(ah.Value('return'))!)!
			q.detach(result)
			return result
		}
	}
	return error('unreachable QMP reply loop')
}

fn qmp_execute(operation string, mut q QmpExpression, mut f Frame) !string {
	self := f.names['self']
	match operation {
		'qmp_init' { qmp_init(mut q, &f)! }
		'qmp_call' { return qmp_call(mut q, mut f)! }
		'qmp_close' {
			file := q.attribute(q.attribute(self, 'file')!, 'close')!
			q.invoke_(file, [])!
			q.clear()!
			socket := q.attribute(q.attribute(self, 'socket')!, 'close')!
			q.invoke_(socket, [])!
			q.clear()!
		}
		'qmp_click' {
			hold := q.attribute(self, 'hold')!
			q.invoke_(hold, [f.names['x'], f.names['y'], q.constant(ah.Value(ah.Number{ text: '0.15' }))!])!
			q.clear()!
			qmp_pause(mut q, '0.5')!
		}
		'qmp_click_direct', 'qmp_hold' {
			qmp_events(mut q, self, f.names['x'], f.names['y'], true, false)!
			if operation == 'qmp_click_direct' {
				qmp_pause(mut q, '0.15')!
			} else {
				qmp_sleep(mut q, f.names['seconds'])!
			}
			qmp_events(mut q, self, '', '', false, true)!
			if operation == 'qmp_click_direct' { qmp_pause(mut q, '0.5')! }
		}
		'qmp_move' { qmp_events(mut q, self, f.names['x'], f.names['y'], false, false)! }
		'qmp_drag' {
			qmp_pause(mut q, '0.25')!
			qmp_events(mut q, self, f.names['start_x'], f.names['start_y'], true, false)!
			qmp_pause(mut q, '0.25')!
			move := q.attribute(self, 'move')!
			q.invoke_(move, [f.names['end_x'], f.names['end_y']])!
			q.clear()!
			qmp_sleep(mut q, f.names['seconds'])!
			qmp_events(mut q, self, '', '', false, true)!
			qmp_pause(mut q, '0.25')!
		}
		else { return error('unknown desktop QMP operation') }
	}
	return literal(ah.Value(json2.Null{}))!
}

fn qmp_dispatch(row map[string]ah.Value) !ah.Value {
	ids := ah.field(row, 'arguments').items().map(it.text())
	operation := ah.field(row, 'operation').text()
	current_builtins = ids[1]
	mut f := Frame{ start: checkpoint()!, pins: ids[0], order: ['reply'] }
	keys := match operation {
		'qmp_init' { ['self', 'path'] }
		'qmp_call' { ['self', 'command', 'arguments'] }
		'qmp_click', 'qmp_click_direct', 'qmp_move' { ['self', 'x', 'y'] }
		'qmp_hold' { ['self', 'x', 'y', 'seconds'] }
		'qmp_drag' { ['self', 'start_x', 'start_y', 'end_x', 'end_y', 'seconds'] }
		else { ['self'] }
	}
	for key in keys { f.named(key, get(ids[2], key)!)! }
	mut q := QmpExpression{}
	result := qmp_execute(operation, mut q, mut f) or {
		cause := err
		q.clear()!
		f.pin()!
		clean_since(f.start, [f.pins])!
		return cause
	}
	q.clear()!
	f.pin()!
	clean_since(f.start, [f.pins, result])!
	return ah.Value(result)
}
