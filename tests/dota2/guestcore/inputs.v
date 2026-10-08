// SPDX-License-Identifier: GPL-2.0-or-later
module guestcore

import androidhost as ah

fn digest(path string) !string {
	hash := call('hashlib.sha256')!
	manager := method(path, 'open', [s('rb')], {})!
	stream := enter(manager)!
	digest_stream(stream, hash) or {
		failure := err
		if !retire(manager, failure)! { return failure }
		return method(hash, 'hexdigest', [], {})!
	}
	retire(manager, none)!
	return method(hash, 'hexdigest', [], {})!
}

fn digest_stream(stream string, hash string) ! {
	read := call('_vm.method_callable', o('arg1'), o(stream), s('read'), n(1024 * 1024))!
	blocks := call('_vm.iterate_value', o(call('builtins.iter', o(read), b(''))!))!
	for {
		block := next(blocks)!
		if block.done { return }
		method(hash, 'update', [o(block.id)], {})!
	}
}

fn elf(path string, machine string, limit string) !string {
	resolved := method(path, 'resolve', [], {
		'strict': v(ah.Value(true))
	})!
	size := attr(method(resolved, 'stat', [], {})!, 'st_size')!
	if !truth(method(resolved, 'is_file', [], {})!)! || compare('lt', size, n(64))! || compare('gt', size, o(limit))! {
		fail('ValueError', 'Expected a bounded ELF file: ' + format(path)!)!
	}
	manager := method(resolved, 'open', [s('rb')], {})!
	stream := enter(manager)!
	mut captured := Header{}
	mut retired := false
	read_header(stream, mut captured) or {
		failure := err
		retired = true
		if !retire(manager, failure)! { return failure }
	}
	header := captured.id
	if header == '' {
		fail('UnboundLocalError', "local variable 'header' referenced before assignment")!
	} else if !retired {
		retire(manager, none)!
	}
	prefix := get(header, o(call('_vm.slice_value', n(0), n(6))!))!
	if compare('ne', prefix, b('7f454c460201'))! || !type_valid(header)! || compare('ne', get(call('struct.unpack_from', s('<H'), o(header), n(18))!, n(0))!, o(machine))! {
		fail('ValueError', 'ELF architecture or type does not match: ' + format(path)!)!
	}
	result := dict()!
	set(result, 'source', o(call('builtins.str', o(path))!))!
	set(result, 'resolved_source', o(call('builtins.str', o(resolved))!))!
	set(result, 'bytes', o(size))!
	set(result, 'sha256', o(call('digest', o(resolved))!))!
	return result
}

struct Header {
mut:
	id string
}

fn read_header(stream string, mut result Header) ! {
	result.id = method(stream, 'read', [n(64)], {})!
}

fn type_valid(header string) !bool {
	kind := get(call('struct.unpack_from', s('<H'), o(header), n(16))!, n(0))!
	return truth(call('operator.contains', o(call('_vm.tuple_value', o(command([n(2), n(3)])!))!), o(kind))!)!
}

fn pin(record string, destination string) ! {
	mkdir(attr(destination, 'parent')!)!
	call('shutil.copy2', o(get(record, s('resolved_source'))!), o(destination))!
	if compare('ne', attr(method(destination, 'stat', [], {})!, 'st_size')!, o(get(record, s('bytes'))!))! || compare('ne', call('digest', o(destination))!, o(get(record, s('sha256'))!))! {
		fail('ValueError', 'Input changed while preparing the fixture: ' + format(get(record, s('source'))!)!)!
	}
}
