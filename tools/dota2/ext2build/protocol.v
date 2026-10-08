// SPDX-License-Identifier: GPL-2.0-or-later
module ext2build

import androidhost as ah

fn receive(connection string, count string) !string {
	parts := call('builtins.list')!
	mut remaining := count
	for truth(remaining)! {
		part := method(connection, 'recv', [o(remaining)], {})!
		if !truth(part)! { failed('EOFError')! }
		append(parts, o(part))!
		remaining = call('operator.sub', o(remaining), o(call('builtins.len', o(part))!))!
	}
	return method(call('builtins.bytes')!, 'join', [o(parts)], {})!
}

fn option_reply(self string, option string, kind string, data string) ! {
	packet := call('struct.pack', v(ah.Value('>QIII')), o(call('REPLY_MAGIC')!), o(option), o(kind), o(call('builtins.len', o(data))!))!
	method(attribute(self, 'request')!, 'sendall', [o(call('operator.add', o(packet), o(data))!)], {})!
}

fn reply(self string, option string, kind u32, data string) ! {
	mut args := [o(option), v(ah.Value(i64(kind)))]
	if data != '' { args << o(data) }
	api_method(self, 'option_reply', args)!
}

fn server_export(self string) !string { return attribute(attribute(self, 'server')!, 'export')! }

fn server_name(self string) !string { return attribute(attribute(self, 'server')!, 'export_name')! }

fn negotiated_size(self string) !string { return attribute(server_export(self)!, 'size')! }

fn incoming(self string, length ah.Value) !string {
	return api('receive', o(attribute(self, 'request')!), length)!
}

fn packed_fields(format string, payload string, count int) ![]string {
	return unpack(call('struct.unpack', v(ah.Value(format)), o(payload))!, count)!
}

fn negotiate(self string) !string {
	socket := attribute(self, 'request')!
	packet := call('struct.pack', v(ah.Value('>QQH')), o(call('NBD_MAGIC')!), o(call('OPTION_MAGIC')!), v(ah.Value(3)))!
	method(socket, 'sendall', [o(packet)], {})!
	flags := packed_fields('>I', incoming(self, v(ah.Value(4)))!, 1)![0]
	if !truth(call('operator.and_', o(flags), v(ah.Value(1)))!)! || truth(call('operator.and_', o(flags), v(ah.Value(~i64(3))))!)! {
		return literal(ah.Value(false))!
	}
	for _ in 0 .. 64 {
		fields := packed_fields('>QII', incoming(self, v(ah.Value(16)))!, 3)!
		magic, option, length := fields[0], fields[1], fields[2]
		if compare('ne', magic, call('OPTION_MAGIC')!)! || compare('gt', length, literal(ah.Value(65536))!)! {
			return literal(ah.Value(false))!
		}
		data := incoming(self, o(length))!
		if compare('eq', option, literal(ah.Value(2))!)! {
			reply(self, option, 1, '')!
			return literal(ah.Value(false))!
		}
		if compare('eq', option, literal(ah.Value(1))!)! {
			if compare('ne', data, server_name(self)!)! { return literal(ah.Value(false))! }
			response := call('struct.pack', v(ah.Value('>QH')), o(negotiated_size(self)!), o(call('EXPORT_FLAGS')!))!
			method(attribute(self, 'request')!, 'sendall', [o(response)], {})!
			if !truth(call('operator.and_', o(flags), v(ah.Value(2)))!)! {
				method(attribute(self, 'request')!, 'sendall', [o(call('builtins.bytes', v(ah.Value(124)))!)], {})!
			}
			return literal(ah.Value(true))!
		}
		if compare('eq', option, literal(ah.Value(3))!)! {
			name := server_name(self)!
			data_name := call('operator.add', o(call('struct.pack', v(ah.Value('>I')), o(call('builtins.len', o(name))!))!), o(name))!
			reply(self, option, 2, data_name)!
			reply(self, option, 1, '')!
		} else if compare('eq', option, literal(ah.Value(6))!)! || compare('eq', option, literal(ah.Value(7))!)! {
			if compare('lt', call('builtins.len', o(data))!, literal(ah.Value(6))!)! {
				reply(self, option, 0x80000003, '')!
				continue
			}
			name_length := unpack(call('struct.unpack_from', v(ah.Value('>I')), o(data))!, 1)![0]
			if compare('gt', name_length, call('operator.sub', o(call('builtins.len', o(data))!), v(ah.Value(6)))!)! {
				reply(self, option, 0x80000003, '')!
				continue
			}
			position := call('operator.add', v(ah.Value(4)), o(name_length))!
			name := item(data, o(call('builtins.slice', v(ah.Value(4)), o(position))!))!
			infos := unpack(call('struct.unpack_from', v(ah.Value('>H')), o(data), o(position))!, 1)![0]
			size_expected := call('operator.add', o(call('operator.add', o(name_length), v(ah.Value(6)))!), o(call('operator.mul', o(infos), v(ah.Value(2)))!))!
			if compare('ne', call('builtins.len', o(data))!, size_expected)! {
				reply(self, option, 0x80000003, '')!
			} else if compare('ne', name, server_name(self)!)! {
				reply(self, option, 0x80000006, '')!
			} else {
				info := call('struct.pack', v(ah.Value('>HQH')), v(ah.Value(0)), o(negotiated_size(self)!), o(call('EXPORT_FLAGS')!))!
				reply(self, option, 3, info)!
				requested := call('struct.unpack_from', v(ah.Value('>' + formatted(infos)! + 'H')), o(data), o(call('operator.add', v(ah.Value(6)), o(name_length))!))!
				if truth(call('operator.contains', o(requested), v(ah.Value(3)))!)! {
					block_info := call('struct.pack', v(ah.Value('>HIII')), v(ah.Value(3)), v(ah.Value(1)), o(call('BLOCK')!), o(call('MAX_REQUEST')!))!
					reply(self, option, 3, block_info)!
				}
				reply(self, option, 1, '')!
				if compare('eq', option, literal(ah.Value(7))!)! { return literal(ah.Value(true))! }
			}
		} else {
			reply(self, option, 0x80000001, '')!
		}
	}
	return literal(ah.Value(false))!
}

fn handle(self string) ! {
	method(attribute(self, 'request')!, 'settimeout', [v(ah.Value(120))], {})!
	method(attribute(self, 'request')!, 'setsockopt', [o(call('socket.IPPROTO_TCP')!),
		o(call('socket.TCP_NODELAY')!), v(ah.Value(1))], {})!
	handle_session(self) or {
		if caught(err, ['EOFError', 'ConnectionError', 'socket.timeout'])! { return }
		return err
	}
}

fn error_errno(cause IError) !string {
	if cause is BindingError {
		error_object := callback('error_object', {
			'error': ah.Value(cause.value)
		})!.text()
		code := callback('attribute', {
			'owner':        ah.Value(error_object)
			'name':         ah.Value('errno')
			'active_error': ah.Value(cause.value)
		})!.text()
		valid := callback('function', {
			'name':         ah.Value('builtins.bool')
			'args':         ah.Value([o(code)])
			'data':         ah.Value(true)
			'active_error': ah.Value(cause.value)
		})! as bool
		if valid { return code }
		return callback('function', {
			'name':         ah.Value('errno.EIO')
			'active_error': ah.Value(cause.value)
		})!.text()
	}
	return cause
}

fn handle_session(self string) ! {
	if !truth(api_method(self, 'negotiate', [])!)! { return }
	method(attribute(self, 'request')!, 'settimeout', [o(null()!)], {})!
	for {
		fields := packed_fields('>IHH8sQI', incoming(self, v(ah.Value(28)))!, 6)!
		magic, flags, command, handle_id, offset, length := fields[0], fields[1], fields[2], fields[3], fields[4], fields[5]
		if compare('ne', magic, call('REQUEST_MAGIC')!)! || compare('gt', length, call('MAX_REQUEST')!)! {
			return
		}
		if compare('eq', command, literal(ah.Value(2))!)! { return }
		mut error_code := literal(ah.Value(0))!
		mut data := callback('literal', {
			'value': b('')
		})!.text()
		if compare('eq', command, literal(ah.Value(1))!)! {
			incoming(self, o(length))!
			error_code = call('errno.EROFS')!
		} else if truth(flags)! {
			error_code = call('errno.EINVAL')!
		} else if compare('eq', command, literal(ah.Value(0))!)! {
			data = api_method(server_export(self)!, 'read', [o(offset), o(length)]) or {
				failure := err
				if !caught(failure, ['OSError'])! { return failure }
				error_code = error_errno(failure)!
				data
			}
		} else if compare('eq', command, literal(ah.Value(3))!)! {
			// Flush on the read-only export succeeds without mutation.
		} else {
			error_code = if compare('eq', command, literal(ah.Value(4))!)! || compare('eq', command, literal(ah.Value(6))!)! {
				call('errno.EROFS')!
			} else {
				call('errno.EINVAL')!
			}
		}
		packet := call('struct.pack', v(ah.Value('>II8s')), v(ah.Value(0x67446698)), o(error_code), o(handle_id))!
		method(attribute(self, 'request')!, 'sendall', [o(call('operator.add', o(packet), o(data))!)], {})!
	}
}
