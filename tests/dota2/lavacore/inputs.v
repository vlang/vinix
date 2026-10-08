// SPDX-License-Identifier: GPL-2.0-or-later
module lavacore

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
	for {
		block := method(stream, 'read', [n(1024 * 1024)], {})!
		if eq(block, b(''))! { return }
		method(hash, 'update', [o(block)], {})!
	}
}
fn elf(path string, machine string, limit string) !string {
	resolved := method(path, 'resolve', [], {'strict': v(ah.Value(true))})!
	size := attr(method(resolved, 'stat', [], {})!, 'st_size')!
	if !truth(method(resolved, 'is_file', [], {})!)! || compare('lt', size, n(64))! || compare('gt', size, o(limit))! {
		fail('ValueError', 'Expected a bounded ELF file: ' + format(path)!)!
	}
	manager := method(resolved, 'open', [s('rb')], {})!
	stream := enter(manager)!
	mut captured := Header{}
	mut header := ''
	read_header(stream, mut captured) or {
		failure := err
		if !retire(manager, failure)! { return failure }
	}
	header = captured.id
	if header == '' {
		fail('UnboundLocalError', "local variable 'header' referenced before assignment")!
	} else { retire(manager, none)! }
	prefix := get(header, o(call('builtins.slice', n(0), n(6))!))!
	if !eq(prefix, b('7f454c460201'))! || !type_valid(header)! || !eq(get(call('struct.unpack_from', s('<H'), o(header), n(18))!, n(0))!, o(machine))! {
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
fn read_header(stream string, mut result Header) ! { result.id = method(stream, 'read', [n(64)], {})! }
fn type_valid(header string) !bool {
	kind := get(call('struct.unpack_from', s('<H'), o(header), n(16))!, n(0))!
	return eq(kind, n(2))! || eq(kind, n(3))!
}
fn pin(record string, destination string) ! {
	mkdir(attr(destination, 'parent')!)!
	call('shutil.copy2', o(get(record, s('resolved_source'))!), o(destination))!
	if !eq(attr(method(destination, 'stat', [], {})!, 'st_size')!, o(get(record, s('bytes'))!))! || !eq(call('digest', o(destination))!, o(get(record, s('sha256'))!))! {
		fail('ValueError', 'Input changed while preparing the fixture: ' + format(get(record, s('source'))!)!)!
	}
}
fn needed(readelf string, path string) !string {
	command := list()!
	for item in [o(readelf), s('-d'), o(call('builtins.str', o(path))!)] { append(command, item)! }
	output := invoke('subprocess.check_output', [o(command)], {'text': v(ah.Value(true))})!
	return call('re.findall', s(r'\(NEEDED\).*\[([^]]+)\]'), o(output))!
}
fn closure(readelf string, runtime string, roots string) !string {
	pins := dict()!
	queue := call('builtins.list', o(roots))!
	for truth(queue)! {
		current := method(queue, 'pop', [], {})!
		names := iter(call('needed', o(readelf), o(current))!)!
		for {
			row := next(names)!
			if row.done { break }
			name := row.id
			if truth(call('operator.contains', o(pins), o(name))!)! { continue }
			mut source := ''
			directories := iter(call('LIBRARY_DIRECTORIES')!)!
			for {
				directory := next(directories)!
				if directory.done { break }
				candidate := call('operator.truediv', o(call('operator.truediv', o(runtime), o(directory.id))!), o(name))!
				if truth(method(candidate, 'is_file', [], {})!)! { source = candidate; break }
			}
			if source == '' { fail('ValueError', 'Private runtime lacks ' + format(name)!)! }
			record := call('elf_input', o(source), n(62))!
			call('operator.setitem', o(pins), o(name), o(record))!
			append(queue, o(path(get(record, s('resolved_source'))!)!))!
		}
	}
	return pins
}
