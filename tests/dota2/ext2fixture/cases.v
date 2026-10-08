// SPDX-License-Identifier: GPL-2.0-or-later
module ext2fixture

import androidhost as ah

fn disk_block(self string, path string, index string) !string {
	return unit(self, 'bmap', [v(ah.Value(path)), o(index)])!
}

fn read(self string, block string, length ah.Value) !string {
	return method(field(self, 'export')!, 'read', [
		o(call('operator.mul', o(block), v(ah.Value(4096)))!),
		length,
	], {})!
}

fn partial_overlay(self string) ! {
	package_size := attribute(method(field(self, 'package')!, 'stat', [], {})!, 'st_size')!
	block := disk_block(self, 'nested/package.vpk', call('operator.floordiv', o(package_size), v(ah.Value(4096)))!)!
	data := call('operator.add', b('partial block'.bytes().hex()), o(call('builtins.bytes', v(ah.Value(4096 - 13)))!))!
	equal(self, read(self, block, v(ah.Value(4096)))!, o(data))!
	loader := disk_block(self, 'nested/loader', literal(ah.Value(0))!)!
	equal(self, read(self, loader, v(ah.Value(18)))!, b('overlay executable'.bytes().hex()))!
	empty := disk_block(self, 'empty', literal(ah.Value(0))!)!
	equal(self, read(self, empty, v(ah.Value(8)))!, b('replaced'.bytes().hex()))!
	for name in ['short-link', 'long-link'] {
		target := if name == 'short-link' {
			'nested/package.vpk'
		} else {
			'nested/' + 'x'.repeat(90)
		}
		args := collection('list', [call('executable', v(ah.Value('debugfs')))!,
			literal(ah.Value('-R'))!, literal(ah.Value('stat /' + name))!,
			call('builtins.str', o(join(field(self, 'state')!, 'metadata.ext2')!))!])!
		result := invoke('subprocess.check_output', [o(args)], {
			'text':   v(ah.Value(true))
			'stderr': o(call('subprocess.DEVNULL')!)
		})!
		unit(self, 'assertIn', [v(ah.Value('Type: symlink')), o(result)])!
		if name == 'short-link' {
			unit(self, 'assertIn', [v(ah.Value(target)), o(result)])!
		} else {
			link := disk_block(self, name, literal(ah.Value(0))!)!
			equal(self, read(self, link, v(ah.Value(target.len)))!, o(method(literal(ah.Value(target))!, 'encode', [], {})!))!
		}
	}
}

fn valid_layout(self string) ! {
	args := collection('list', [call('executable', v(ah.Value('e2fsck')))!, literal(ah.Value('-fn'))!,
		call('builtins.str', o(join(field(self, 'state')!, 'metadata.ext2')!))!])!
	invoke('subprocess.run', [o(args)], {
		'check':  v(ah.Value(true))
		'stdout': o(call('subprocess.DEVNULL')!)
		'stderr': o(call('subprocess.DEVNULL')!)
	})!
	metadata_blocks := attribute(method(join(field(self, 'state')!, 'metadata.ext2')!, 'stat', [], {})!, 'st_blocks')!
	unit(self, 'assertLess', [
		o(call('operator.mul', o(metadata_blocks), v(ah.Value(512)))!),
		v(ah.Value(2 * 1024 * 1024)),
	])!
	package_blocks := attribute(method(field(self, 'package')!, 'stat', [], {})!, 'st_blocks')!
	unit(self, 'assertLess', [
		o(call('operator.mul', o(package_blocks), v(ah.Value(512)))!),
		v(ah.Value(128 * 1024)),
	])!
	equal(self, item(field(self, 'manifest')!, v(ah.Value('size')))!, v(ah.Value(256 * 1024 * 1024)))!
	server_case(self, 'valid', '', '')!
}

fn qemu_reads(self string, server string) ! {
	port := item(attribute(server, 'server_address')!, v(ah.Value(1)))!
	uri := literal(ah.Value('nbd://127.0.0.1:' + text(port)! + '/'))!
	io_arguments := collection('list', [call('executable', v(ah.Value('qemu-io')))!,
		literal(ah.Value('-r'))!, literal(ah.Value('-f'))!, literal(ah.Value('raw'))!])!
	iter := iterator(field(self, 'patterns')!)!
	for {
		row := next(iter)!
		if row.done { break }
		values := unpack2(row.value)!
		mut offset := values[0]
		pattern := values[1]
		mut remaining := literal(ah.Value(8192))!
		for truth(remaining)! {
			position := call('builtins.divmod', o(offset), v(ah.Value(4096)))!
			block := item(position, v(ah.Value(0)))!
			inside := item(position, v(ah.Value(1)))!
			take := call('builtins.min', o(call('operator.sub', v(ah.Value(4096)), o(inside))!), o(remaining))!
			disk := call('operator.add', o(call('operator.mul', o(disk_block(self, 'nested/package.vpk', block)!), v(ah.Value(4096)))!), o(inside))!
			command := literal(ah.Value('read -P ' + text(pattern)! + ' ' + text(disk)! + ' ' + text(take)!))!
			method(io_arguments, 'extend', [o(collection('list', [
				literal(ah.Value('-c'))!,
				command,
			])!)], {})!
			offset = call('operator.add', o(offset), o(take))!
			remaining = call('operator.sub', o(remaining), o(take))!
		}
	}
	invoke('subprocess.run', [o(call('operator.add', o(io_arguments), o(collection('list', [uri])!))!)], {
		'check':  v(ah.Value(true))
		'stdout': o(call('subprocess.DEVNULL')!)
	})!
}

fn original_pattern() !string { return call('operator.mul', b('a5'), v(ah.Value(16)))! }

fn request(client string, command int, offset string, length int, data string) !string {
	mut args := [v(ah.Value(command)), o(offset), v(ah.Value(length))]
	if data != '' { args << o(data) }
	return method(client, 'request', args, {})!
}

fn readonly_change(self string) ! {
	server_case(self, 'readonly', '', '')!
}

fn readonly_body(self string, client string, block string, original string) ! {
	equal(self, call('operator.and_', o(field(client, 'flags')!), v(ah.Value(2)))!, v(ah.Value(2)))!
	expected := collection('tuple', [literal(ah.Value(0))!, original])!
	offset := call('operator.mul', o(block), v(ah.Value(4096)))!
	equal(self, request(client, 0, offset, 16, '')!, o(expected))!
	write_result := request(client, 1, offset, 16, call('operator.mul', b('58'), v(ah.Value(16)))!)!
	equal(self, item(write_result, v(ah.Value(0)))!, o(call('errno.EROFS')!))!
	equal(self, request(client, 0, offset, 16, '')!, o(expected))!
	invalid := request(client, 0, call('operator.sub', o(field(client, 'size')!), v(ah.Value(1)))!, 2, '')!
	equal(self, item(invalid, v(ah.Value(0)))!, o(call('errno.EINVAL')!))!
	change_package(self)!
	equal(self, item(request(client, 0, offset, 16, '')!, v(ah.Value(0)))!, o(call('errno.EIO')!))!
}

fn change_package(self string) ! {
	manager := method(field(self, 'package')!, 'open', [v(ah.Value('r+b'))], {})!
	output := enter(manager)!
	method(output, 'write', [b('changed'.bytes().hex())], {}) or {
		failure := err
		if !retire(manager, failure)! { return failure }
		return
	}
	retire(manager, none)!
}

fn remounted_volume(self string) ! {
	iter := iterator(field(field(self, 'export')!, 'files')!)!
	for {
		row := next(iter)!
		if row.done { break }
		identity := item(row.value, v(ah.Value('identity')))!
		set_item(identity, v(ah.Value(0)), o(call('operator.add', o(item(identity, v(ah.Value(0)))!), v(ah.Value(1)))!))!
	}
	block := disk_block(self, 'nested/package.vpk', literal(ah.Value(0))!)!
	equal(self, read(self, block, v(ah.Value(16)))!, o(original_pattern()!))!
	change_package(self)!
	manager := unit(self, 'assertRaises', [o(lookup('OSError')!)])!
	enter(manager)!
	read(self, block, v(ah.Value(16))) or {
		failure := err
		if !retire(manager, failure)! { return failure }
		return
	}
	retire(manager, none)!
}

fn idle_timeout(self string, observed string, handler string) ! {
	server_case(self, 'idle', observed, handler)!
}

fn idle_body(self string, server string, client string, block string, original string, observed string) ! {
	offset := call('operator.mul', o(block), v(ah.Value(4096)))!
	expected := collection('tuple', [literal(ah.Value(0))!, original])!
	equal(self, request(client, 0, offset, 16, '')!, o(expected))!
	call('time.sleep', o(call('builtins.float', v(ah.Value('0.3')))!))!
	equal(self, request(client, 0, offset, 16, '')!, o(expected))!
	manager := invoke('socket.create_connection', [o(field(server, 'server_address')!)], {
		'timeout': v(ah.Value(1))
	})!
	unfinished := enter(manager)!
	idle_unfinished(self, unfinished) or {
		failure := err
		if !retire(manager, failure)! { return failure }
		retire_observed(self, observed)!
		return
	}
	retire(manager, none)!
	retire_observed(self, observed)!
}

fn idle_unfinished(self string, unfinished string) ! {
	equal(self, call('builtins.len', o(call('EXPORTER.receive', o(unfinished), v(ah.Value(18)))!))!, v(ah.Value(18)))!
	equal(self, method(unfinished, 'recv', [v(ah.Value(1))], {})!, b(''))!
}

fn retire_observed(self string, observed string) ! {
	equal(self, observed, v(ah.Value([ah.Value(120), ah.Value(120)])))!
}

fn cleanup(server string, worker string, client string, cause ?IError) ! {
	if client != '' { active_method(client, 'close', [], cause)! }
	active_method(server, 'shutdown', [], cause)!
	active_method(worker, 'join', [], cause)!
}

fn server_case(self string, mode string, observed string, handler string) ! {
	// Readonly and idle cases compute these values before entering the server.
	mut block := ''
	mut original := ''
	if mode != 'valid' {
		block = disk_block(self, 'nested/package.vpk', literal(ah.Value(0))!)!
		original = original_pattern()!
	}
	manager := call('EXPORTER.Server', o(field(self, 'state')!), v(ah.Value(0)))!
	server := enter(manager)!
	mut retired := false
	server_entered(self, server, mode, block, original, observed, handler) or {
		failure := err
		retired = true
		if !retire(manager, failure)! { return failure }
	}
	if !retired { retire(manager, none)! }
}

fn server_entered(self string, server string, mode string, block string, original string, observed string, handler string) ! {
	if mode == 'idle' { set_attr(server, 'RequestHandlerClass', o(handler))! }
	worker := invoke('threading.Thread', [], {
		'target': o(attribute(server, 'serve_forever')!)
	})!
	method(worker, 'start', [], {})!
	mut client := ''
	if mode != 'valid' {
		client = call('Client', o(item(field(server, 'server_address')!, v(ah.Value(1)))!))!
	}
	server_body(self, server, mode, client, block, original, observed) or {
		failure := err
		cleanup(server, worker, client, failure)!
		return failure
	}
	cleanup(server, worker, client, none)!
}

fn server_body(self string, server string, mode string, client string, block string, original string, observed string) ! {
	match mode {
		'valid' { qemu_reads(self, server)! }
		'readonly' { readonly_body(self, client, block, original)! }
		'idle' { idle_body(self, server, client, block, original, observed)! }
		else { return error('unknown ext2 fixture server case') }
	}
}

fn refuse_oversized(self string) ! {
	manager := unit(self, 'assertRaisesRegex', [o(lookup('ValueError')!),
		v(ah.Value('outside every exported root'))])!
	enter(manager)!
	call('EXPORTER.build', o(field(self, 'source')!), o(join(field(self, 'source')!, 'export')!)) or {
		failure := err
		if !retire(manager, failure)! { return failure }
		create_oversized(self)!
		return
	}
	retire(manager, none)!
	create_oversized(self)!
}

fn create_oversized(self string) ! {
	manager := method(join(field(self, 'source')!, 'too-large')!, 'open', [v(ah.Value('wb'))], {})!
	output := enter(manager)!
	mut retired := false
	method(output, 'truncate', [v(ah.Value(i64(1) << 32))], {}) or {
		failure := err
		retired = true
		if !retire(manager, failure)! { return failure }
	}
	if !retired { retire(manager, none)! }
	raises := unit(self, 'assertRaisesRegex', [o(lookup('ValueError')!),
		v(ah.Value('larger than 4 GiB'))])!
	enter(raises)!
	call('EXPORTER.build', o(field(self, 'source')!), o(join(field(self, 'base')!, 'oversized')!)) or {
		failure := err
		if !retire(raises, failure)! { return failure }
		return
	}
	retire(raises, none)!
}
