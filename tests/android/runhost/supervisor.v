module runhost

import androidhost as ah
import encoding.hex
import strconv

fn group(name string) !ah.Value {
	return callback('group_get', {'name': ah.Value(name)})!
}

fn group_set(name string, value ah.Value) ! {
	callback('group_set', {'name': ah.Value(name), 'value': value})!
}

fn group_method(name string, method string, arguments []ah.Value, options map[string]ah.Value) !ah.Value {
	return callback('group_method', {
		'name': ah.Value(name), 'method': ah.Value(method),
		'arguments': ah.Value(arguments), 'options': ah.Value(options)
	})!
}

fn group_bytes(recent bool) !string {
	row := if recent {
		{'name': ah.Value('transcript'), 'slice': ah.Value([ah.Value(-262144), null()])}
	} else { {'name': ah.Value('transcript')} }
	return hex.decode(callback('group_bytes', row)!.text())!.bytestr()
}

fn observed_policy() !ah.Value {
	lines := group_bytes(true)!.replace('\r', '').split('\n')
	if lines.len > 1 {
		for index := lines.len - 2; index >= 0; index-- {
			line := lines[index]
			if line.starts_with('ANDROID-INPUT ') {
				return callback('bytes_decode', {
					'data': ah.Value(line['ANDROID-INPUT '.len..].bytes().hex()),
					'options': ah.Value({'encoding': ah.Value('utf-8')})
				})!
			}
		}
	}
	return ah.Value('')
}

fn read_serial_body(log ah.Value) ! {
	master := group('master')!
	for !truth(group_method('reader_stop', 'is_set', []ah.Value{}, map[string]ah.Value{})!) {
		ready := invoke('select', 'select', [ordinary(ah.Value([master])), ordinary(ah.Value([]ah.Value{})),
			ordinary(ah.Value([]ah.Value{})), ordinary(ah.Value(ah.Number{'0.1'}))])!
		if !truth(ready.items()[0]) { continue }
		chunk := callback('invoke_bytes', {'module': ah.Value('os'), 'name': ah.Value('read'),
			'arguments': ah.Value([ordinary(master), ordinary(ah.Value(65536))])}) or {
			if !error_is(err, ['OSError'])! { return err }
			number := callback('error_attribute', {'error': error_value(err), 'name': ah.Value('errno')})!
			eio := callback('constant', {'module': ah.Value('errno'), 'name': ah.Value('EIO')})!
			if !truth(numeric('eq', number, eio)!) { return err }
			break
		}
		if !truth(chunk) { break }
		bytes_arg := [typed('bytes', chunk)]
		group_method('transcript', 'extend', bytes_arg, map[string]ah.Value{})!
		context_method(log, 'write', bytes_arg)!
		context_method(log, 'flush', []ah.Value{})!
		for name in ['write', 'flush'] {
			callback('stream_method', {'stream': ah.Value('stdout'), 'field': ah.Value('buffer'),
				'name': ah.Value(name), 'arguments': ah.Value(if name == 'write' { bytes_arg } else { []ah.Value{} })})!
		}
	}
}

fn read_serial() !ah.Value {
	log := callback('enter_context', {
		'module': ah.Value('Path'), 'name': ah.Value('open'),
		'arguments': ah.Value([typed('path', ah.Value(join([group('state')!.text(), 'serial.log'])!)), ordinary(ah.Value('wb'))])
	})!
	mut failed := false
	mut cause := IError(none)
	read_serial_body(log) or { failed = true; cause = err }
	suppressed := retire('exit_context', log, failed, cause)!
	if failed && !suppressed { return cause }
	return null()
}

fn send_input(args map[string]ah.Value) !ah.Value {
	invoke('time', 'sleep', [ordinary(ah.Value(3))])!
	socket := typed('path', group('socket')!)
	api('screenshot', [socket, typed('path', ah.Value(join([group('state')!.text(), 'ready.png'])!))], map[string]ah.Value{})!
	callback('function', {'name': ah.Value('click'), 'arguments': ah.Value([socket]), 'star_attribute': ah.Value('click')})!
	retries := api('keyboard', [socket, ordinary(attribute(args, 'keys')!), typed('callback', ah.Value('observed_input'))], map[string]ah.Value{})!
	group_method('input_retries', 'append', [ordinary(retries)], map[string]ah.Value{})!
	return null()
}

fn supervise_body(args map[string]ah.Value) ! {
	interactive := truth(attribute(args, 'interactive')!)
	mut deadline := strconv.atof64(ah.encode(group('deadline')!))!
	for now()! < deadline {
		pid := group('pid')!
		status := invoke('os', 'waitpid', [ordinary(pid), typed('constant', strings(['os', 'WNOHANG']))])!
		if truth(numeric('eq', status.items()[0], pid)!) {
			group_set('failure', ah.Value(if interactive { 'VM exited before observing a window' } else { 'VM exited before passing' }))!
			break
		}
		sleep(0.1)!
		recent := group_bytes(true)!
		if recent.contains('ANDROID-READY') && attribute_text(args, 'input')! == 'qmp' && !truth(attribute(args, 'observe')!) && !truth(group('typed')!) {
			group_set('typed', ah.Value(true))!
			callback('thread_start', {'name': ah.Value('input_thread'), 'worker': ah.Value('send_input')})!
		}
		input_errors := group('input_errors')!
		serial_errors := group('serial_errors')!
		if truth(input_errors) || truth(serial_errors) {
			group_set('guest_failed', ah.Value(true))!
			first := if truth(input_errors) { input_errors.items()[0] } else { serial_errors.items()[0] }
			group_set('failure', ah.Value('host I/O failed: ' + first.text()))!
			break
		}
		mut failed := false
		for value in callback('constant_bytes', {'name': ah.Value('FAILURES')})!.items() {
			if recent.contains(hex.decode(value.text())!.bytestr()) { failed = true; break }
		}
		if failed {
			group_set('guest_failed', ah.Value(true))!
			group_set('failure', ah.Value('guest reported a failure'))!
			if interactive { group_set('observed', ah.Value(false))! }
			else { ending := now()! + 4; if ending < deadline { deadline = ending } }
		}
		if interactive && recent.contains('ANDROID-READY') && !truth(group('observed')!) && !truth(group('guest_failed')!) {
			group_set('observed', ah.Value(true))!
			callback('print', {'data': ah.Value('Interactive APK window ready; application functionality is unchecked. Use the QEMU window locally; Ctrl-C stops the session.'),
				'options': ah.Value({'flush': ah.Value(true)})})!
		}
		if !interactive && recent.contains('ANDROID-PASS') && !truth(group('guest_failed')!) {
			group_set('passed', ah.Value(true))!
			invoke('time', 'sleep', [ordinary(ah.Value(2))])!
			break
		}
		if !interactive && recent.contains('ANDROID-OBSERVED') && truth(attribute(args, 'observe')!) && !truth(group('guest_failed')!) {
			group_set('observed', ah.Value(true))!
			invoke('time', 'sleep', [ordinary(ah.Value(2))])!
			break
		}
	}
	if truth(callback('group_truth', {'name': ah.Value('input_thread')})!) {
		group_method('input_thread', 'join', []ah.Value{}, {'timeout': ah.Value(25)})!
		alive := truth(group_method('input_thread', 'is_alive', []ah.Value{}, map[string]ah.Value{})!)
		input_errors := group('input_errors')!
		if alive || truth(input_errors) {
			group_set('passed', ah.Value(false))!
			group_set('failure', ah.Value('keyboard input failed: ' + if truth(input_errors) { input_errors.items()[0].text() } else { 'timeout' }))!
		}
	}
}

fn supervise(args map[string]ah.Value) !ah.Value {
	supervise_body(args) or {
		if !error_is(err, ['KeyboardInterrupt'])! || !truth(attribute(args, 'interactive')!) { return err }
		if !truth(group('observed')!) && !truth(group('guest_failed')!) {
			group_set('failure', ah.Value('interactive session stopped before observing a window'))!
		}
	}
	return null()
}
