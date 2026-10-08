module runhost

import androidhost as ah
import json2
import strconv

fn typed(kind string, value ah.Value) ah.Value { return ah.Value([ah.Value(kind), value]) }

fn ordinary(value ah.Value) ah.Value { return typed('value', value) }

fn invoke(module_name string, name string, arguments []ah.Value) !ah.Value {
	return callback('invoke', {
		'module': ah.Value(module_name)
		'name': ah.Value(name)
		'arguments': ah.Value(arguments)
	})!
}

fn context_method(owner ah.Value, name string, arguments []ah.Value) !ah.Value {
	return callback('invoke', {
		'id': owner
		'name': ah.Value(name)
		'arguments': ah.Value(arguments)
	})!
}

fn api(name string, arguments []ah.Value, options map[string]ah.Value) !ah.Value {
	return callback('function', {
		'name': ah.Value(name)
		'arguments': ah.Value(arguments)
		'options': ah.Value(options)
	})!
}

fn numeric(name string, left ah.Value, right ah.Value) !ah.Value {
	return callback('numeric', {
		'name': ah.Value(name)
		'arguments': ah.Value([left, right])
	})!
}

fn builtin(name string, arguments []ah.Value) !ah.Value {
	return callback('builtin', {
		'name': ah.Value(name)
		'arguments': ah.Value(arguments)
	})!
}

fn raise_error(kind string, arguments []ah.Value) !ah.Value {
	return callback('raise', {
		'kind': ah.Value(kind)
		'arguments': ah.Value(arguments)
	})!
}

fn error_is(cause IError, kinds []string) !bool {
	if cause is BindingError {
		return truth(callback('exception_is', {
			'error': error_value(cause)
			'kinds': strings(kinds)
		})!)
	}
	return false
}

fn sleep(seconds f64) ! { invoke('time', 'sleep', [ordinary(ah.Value(ah.Number{seconds.str()}))])! }

fn now() !f64 { return strconv.atof64(ah.encode(invoke('time', 'monotonic', []ah.Value{})!))! }

fn qmp_messages(stream ah.Value, name string, arguments ah.Value) !ah.Value {
	context_method(stream, 'readline', []ah.Value{})!
	commands := [ah.Value({'execute': ah.Value('qmp_capabilities')}),
		ah.Value({'execute': ah.Value(name), 'arguments': arguments})]
	mut reply := null()
	for command in commands {
		encoded := callback('json_dumps', {'data': command})!.text()
		context_method(stream, 'write', [ordinary(ah.Value(encoded + '\n'))])!
		context_method(stream, 'flush', []ah.Value{})!
		for {
			line := context_method(stream, 'readline', []ah.Value{})!
			if !truth(line) { return raise_error('RuntimeError', [ah.Value('QMP disconnected')])! }
			reply = callback('json_loads', {'data': line})!
			if truth(callback('contains', {'value': reply, 'key': ah.Value('error')})!) {
				value := callback('item', {'value': reply, 'key': ah.Value('error')})!
				return raise_error('RuntimeError', [value])!
			}
			if truth(callback('contains', {'value': reply, 'key': ah.Value('return')})!) { break }
		}
	}
	return callback('item', {'value': reply, 'key': ah.Value('return')})!
}

fn qmp_stream(connection ah.Value, name string, arguments ah.Value) !ah.Value {
	stream := callback('enter_context', {
		'id': connection
		'name': ah.Value('makefile')
		'arguments': ah.Value([ordinary(ah.Value('rw'))])
		'options': ah.Value({'encoding': ah.Value('utf-8')})
	})!
	mut result := null()
	mut failed := false
	mut cause := IError(none)
	result = qmp_messages(stream, name, arguments) or {
		failed = true
		cause = err
		null()
	}
	suppressed := retire('exit_context', stream, failed, cause)!
	if failed && !suppressed { return cause }
	return result
}

fn qmp_body(connection ah.Value, socket string, name string, arguments ah.Value) !ah.Value {
	context_method(connection, 'settimeout', [ordinary(ah.Value(20))])!
	context_method(connection, 'connect', [ordinary(ah.Value(socket))])!
	return qmp_stream(connection, name, arguments)!
}

fn qmp_policy(socket string, name string, arguments ah.Value) !ah.Value {
	connection := callback('enter_context', {
		'module': ah.Value('socket')
		'name': ah.Value('socket')
		'arguments': ah.Value([typed('constant', strings(['socket', 'AF_UNIX'])),
			typed('constant', strings(['socket', 'SOCK_STREAM']))])
	})!
	mut result := null()
	mut failed := false
	mut cause := IError(none)
	result = qmp_body(connection, socket, name, arguments) or {
		failed = true
		cause = err
		null()
	}
	suppressed := retire('exit_context', connection, failed, cause)!
	if failed && !suppressed { return cause }
	return result
}

fn keyboard_policy(socket string, text_value ah.Value, root string) !ah.Value {
	callback('load_source', {
		'module': ah.Value('vinix_input')
		'source': ah.Value(join([root, 'desktop/tools/input.py'])!)
	})!
	mut retries := 0
	mut actual := null()
	mut seen_actual := false
	for index, character in callback('characters', {'value': text_value})!.items() {
		events := invoke('vinix_input', 'key_events', [ordinary(character)])!
		if events is json2.Null {
			return raise_error('ValueError', [ah.Value('QMP cannot type ' + builtin('repr', [character])!.text())])!
		}
		previous := callback('slice', {'value': text_value, 'start': ah.Value(0), 'stop': ah.Value(index)})!
		expected := callback('slice', {'value': text_value, 'start': ah.Value(0), 'stop': ah.Value(index + 1)})!
		for attempt in 0 .. 3 {
			if attempt != 0 { retries++ }
			for event in events.items() {
				api('qmp', [typed('path', ah.Value(socket)), ordinary(ah.Value('input-send-event'))],
					{'events': ah.Value([event])})!
				sleep(0.35)!
			}
			deadline := now()! + 8
			for now()! < deadline {
				actual = callback('observed', map[string]ah.Value{})!
				seen_actual = true
				if truth(numeric('eq', actual, expected)!) { break }
				if !truth(numeric('eq', actual, previous)!) {
					return raise_error('RuntimeError', [ah.Value('APK input became ' + builtin('repr', [actual])!.text() + '; expected ' + builtin('repr', [expected])!.text())])!
				}
				sleep(0.1)!
			}
			if !seen_actual {
				version := callback('python_version', map[string]ah.Value{})!.items()
				message := if (ah.integer(version[1]) or { u64(0) }) >= 11 {
					"cannot access local variable 'actual' where it is not associated with a value"
				} else { "local variable 'actual' referenced before assignment" }
				return raise_error('UnboundLocalError', [ah.Value(message)])!
			}
			if truth(numeric('eq', actual, expected)!) { break }
			if attempt == 2 {
				return raise_error('RuntimeError', [ah.Value('APK did not acknowledge ' + builtin('repr', [character])!.text() + '; input remains ' + builtin('repr', [actual])!.text())])!
			}
		}
	}
	return ah.Value(retries)
}

fn click_policy(args map[string]ah.Value) !ah.Value {
	mut events := []ah.Value{}
	for index, axis in ['x', 'y'] {
		value := numeric('mul', ah.field(args, axis), ah.Value(32767))!
		fraction := numeric('truediv', value, ah.Value(if index == 0 { 1023 } else { 767 }))!
		events << ah.Value({'type': ah.Value('abs'), 'data': ah.Value({
			'axis': ah.Value(axis), 'value': builtin('round', [fraction])!
		})})
	}
	socket := typed('path', ah.field(args, 'socket'))
	event_name := ordinary(ah.Value('input-send-event'))
	api('qmp', [socket, event_name], {'events': ah.Value(events)})!
	sleep(0.2)!
	for down in [true, false] {
		api('qmp', [socket, event_name], {'events': ah.Value([
			ah.Value({'type': ah.Value('btn'), 'data': ah.Value({
				'down': ah.Value(down), 'button': ah.Value('left')
			})})
		])})!
		sleep(0.35)!
	}
	sleep(3)!
	return null()
}

fn screenshot_policy(args map[string]ah.Value) !ah.Value {
	// Import precedes even destination suffix validation in the original API.
	callback('import', {'name': ah.Value('PIL.Image')})!
	ppm := path('with_suffix', text(args, 'destination'), [ah.Value('.ppm')], map[string]ah.Value{})!.text()
	api('qmp', [typed('path', ah.field(args, 'socket')), ordinary(ah.Value('screendump'))],
		{'filename': ah.Value(ppm)})!
	image := callback('enter_context', {
		'module': ah.Value('PIL.Image')
		'name': ah.Value('open')
		'arguments': ah.Value([typed('path', ah.Value(ppm))])
	})!
	mut failed := false
	mut cause := IError(none)
	context_method(image, 'save', [typed('path', ah.field(args, 'destination'))]) or {
		failed = true
		cause = err
		null()
	}
	suppressed := retire('exit_context', image, failed, cause)!
	if failed && !suppressed { return cause }
	unlink(ppm)!
	return null()
}

fn signal_stop(pid ah.Value, signal_name string) ! {
	signal_args := [ordinary(pid), typed('constant', strings(['signal', signal_name]))]
	invoke('os', 'killpg', signal_args) or {
		if !error_is(err, ['ProcessLookupError', 'PermissionError'])! { return err }
		invoke('os', 'kill', signal_args) or {
			if !error_is(err, ['ProcessLookupError', 'PermissionError'])! { return err }
			null()
		}
		null()
	}
}

fn stop_policy(args map[string]ah.Value) !ah.Value {
	invoke('os', 'write', [ordinary(ah.field(args, 'master')), typed('bytes', ah.Value('0178'))]) or {
		if !error_is(err, ['OSError'])! { return err }
		null()
	}
	for index, signal_name in ['', 'SIGTERM', 'SIGKILL'] {
		if signal_name != '' { signal_stop(ah.field(args, 'pid'), signal_name)! }
		deadline := now()! + if index == 2 { 1 } else { 3 }
		for now()! < deadline {
			status := invoke('os', 'waitpid', [ordinary(ah.field(args, 'pid')),
				typed('constant', strings(['os', 'WNOHANG']))]) or {
				if error_is(err, ['ChildProcessError'])! { return null() }
				return err
			}
			value := callback('item', {'value': status, 'key': ah.Value(0)})!
			if truth(numeric('eq', value, ah.field(args, 'pid'))!) { return null() }
			sleep(0.1)!
		}
	}
	return null()
}
