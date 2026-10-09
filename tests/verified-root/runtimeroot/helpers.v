// SPDX-License-Identifier: GPL-2.0-or-later
module runtimeroot

import androidhost as ah
import json2

fn global(name string) !string { return callback('resolve', {'name': ah.Value(name)})!.text() }
fn lit(value string) !string { return literal(ah.Value(value))! }
fn get(id string, key ah.Value) !string { return call('operator.getitem', o(id), v(key))! }
fn list(items []string) !string { return collection('list', items)! }
fn target_call(target string, args []ah.Value, kwargs map[string]ah.Value) !string {
	return callback('function', {'target': ah.Value(target), 'call': ah.Value(true), 'args': ah.Value(args), 'kwargs': ah.Value(kwargs)})!.text()
}
fn pair(id string) !(string, string) {
	row := callback('unpack_pair', {'owner': ah.Value(id)}) or {
		cause := err
		release_error([id], cause)!
		return cause
	}
	release(id)!
	values := row.items()
	return values[0].text(), values[1].text()
}
fn slice(start string, end string) !string { return call('builtins.slice', o(start), o(end))! }

// Expression operands disappear while a raised error is still pending. Keep
// the existing caller exception context; context exit activates the new cause.
fn release_error(ids []string, _cause IError) ! {
	release(...ids)!
}
struct Converted {
mut:
	last string
}
fn convert(values string, factory string, expression bool) !string {
	result := list([])!
	items := iterator(values) or {
		cause := err
		if expression { release_error([values, result], cause)! } else { release_error([result], cause)! }
		return cause
	}
	if expression { release(values)! }
	mut state := Converted{}
	convert_loop(items, factory, result, mut state) or {
		cause := err
		release_error([items, state.last, result], cause)!
		return cause
	}
	release(items, state.last)!
	return result
}
fn convert_loop(items string, factory string, result string, mut state Converted) ! {
	for {
		item := next(items)!
		if item.done { return }
		release(state.last)!
		state.last = item.value
		value := call(factory, o(item.value))!
		method(result, 'append', [o(value)], {})!
		release(value)!
	}
}
fn command(args string, kwargs string) !string {
	target := global('subprocess.run')!
	values := convert(args, 'str', false) or {
		cause := err
		release_error([target], cause)!
		return cause
	}
	result := callback('function', {
		'target': ah.Value(target)
		'call': ah.Value(true)
		'args': ah.Value([o(values)])
		'kwargs': ah.Value({'check': v(ah.Value(true))})
		'kwargs_owner': ah.Value(kwargs)
	}) or {
		cause := err
		release_error([target, values], cause)!
		return cause
	}
	release(target, values)!
	return result.text()
}

fn device_blocks(args string, image string, path string) !string {
	target := global('command')!
	request := list([attribute(args, 'debugfs')!, lit('-R')!, lit('blocks ' + text(path)!)!, image])!
	result := target_call(target, [o(request)], {'capture_output': v(ah.Value(true)), 'text': v(ah.Value(true))}) or {
		cause := err
		release_error([target, request], cause)!
		return cause
	}
	release(target, request)!
	output := attribute(result, 'stdout')!
	words := method(output, 'split', [], {}) or {
		cause := err
		release_error([output], cause)!
		return cause
	}
	release(output)!
	blocks := convert(words, 'int', true)!
	if !truth(blocks)! { failed('RuntimeError', 'no filesystem data blocks for ' + text(path)! + ': ' + text(attribute(result, 'stderr')!)!, none)! }
	return blocks
}

fn enroll(bundle string, contents string, args string, work string) ! {
	config := join(bundle, 'boot/limine.conf')!
	release(method(config, 'write_text', [o(contents)], {'encoding': v(ah.Value('ascii'))})!)!
	array := global('bytearray')!
	payload := method(attribute(args, 'loader')!, 'read_bytes', [], {}) or {
		cause := err
		release_error([array], cause)!
		return cause
	}
	data := target_call(array, [o(payload)], {}) or {
		cause := err
		release_error([array, payload], cause)!
		return cause
	}
	release(array, payload)!
	pe_info := global('boot.pe_info')!
	info_pair := target_call(pe_info, [o(data), o(attribute(args, 'arch')!)], {}) or {
		cause := err
		release_error([pe_info], cause)!
		return cause
	}
	release(pe_info)!
	field, _ := pair(info_pair)!
	receiver := call('boot.digest', o(config))!
	digest := method(receiver, 'encode', [], {}) or {
		cause := err
		release_error([receiver], cause)!
		return cause
	}
	release(receiver)!
	end := call('operator.add', o(field), v(ah.Value(128))) or {
		cause := err
		release_error([digest], cause)!
		return cause
	}
	target := slice(field, end) or {
		cause := err
		release_error([digest, end], cause)!
		return cause
	}
	release(end)!
	assigned := call('operator.setitem', o(data), o(target), o(digest)) or {
		cause := err
		release_error([digest, target], cause)!
		return cause
	}
	release(digest, target, assigned)!
	info := call('operator.getitem', o(global('boot.ARCHES')!), o(attribute(args, 'arch')!))!
	image := join(bundle, 'EFI/BOOT/' + text(get(info, ah.Value(2))!)!)!
	if truth(attribute(args, 'secure_boot')!)! {
		enrolled := join(work, 'enrolled.efi')!
		release(method(enrolled, 'write_bytes', [o(data)], {})!)!
		release(method(image, 'unlink', [], {})!)!
		sign := global('boot.sign_image')!
		release(target_call(sign, [o(enrolled), o(image), o(attribute(args, 'key')!), o(attribute(args, 'certificate')!), o(attribute(args, 'backend')!)], {})!)!
	} else { release(method(image, 'write_bytes', [o(data)], {})!)! }
}

fn tamper(image string, offset string) ! {
	manager := method(image, 'open', [v(ah.Value('r+b'))], {})!
	stream := enter_temporary(manager) or {
		$if cpython_host ? { release(manager)! }
		return err
	}
	$if cpython_host ? { release(manager)! }
	tamper_body(stream, offset) or {
		if !retire(manager, err)! { return err }
		return
	}
	retire(manager, none)!
}
fn tamper_body(stream string, offset string) ! {
	release(method(stream, 'seek', [o(offset)], {})!)!
	original := method(stream, 'read', [v(ah.Value(1))], {})!
	if compare('ne', call('len', o(original))!, literal(ah.Value(1))!)! { failed('RuntimeError', 'tamper offset outside image', none)! }
	release(method(stream, 'seek', [o(offset)], {})!)!
	write := attribute(stream, 'write')!
	byte_constructor := global('bytes')!
	changed := changed_byte(byte_constructor, original) or {
		cause := err
		release_error([write, byte_constructor], cause)!
		return cause
	}
	release(byte_constructor)!
	written := target_call(write, [o(changed)], {}) or {
		cause := err
		release_error([write, changed], cause)!
		return cause
	}
	release(write, changed, written)!
	release(method(stream, 'flush', [], {})!)!
	fsync := global('os.fsync')!
	fd := method(stream, 'fileno', [], {}) or {
		cause := err
		release_error([fsync], cause)!
		return cause
	}
	result := target_call(fsync, [o(fd)], {}) or {
		cause := err
		release_error([fsync, fd], cause)!
		return cause
	}
	release(fsync, fd, result)!
}

fn changed_byte(factory string, original string) !string {
	raw := get(original, ah.Value(0))!
	value := call('operator.xor', o(raw), v(ah.Value(1))) or {
		cause := err
		release_error([raw], cause)!
		return cause
	}
	release(raw)!
	values := list([value])!
	release(value)!
	changed := target_call(factory, [o(values)], {}) or {
		cause := err
		release_error([values], cause)!
		return cause
	}
	release(values)!
	return changed
}

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	args := ah.field(row, 'arguments').items().map(it.text())
	match ah.field(row, 'operation').text() {
		'command' { return ah.Value(command(args[0], args[1])!) }
		'device_blocks' { return ah.Value(device_blocks(args[0], args[1], args[2])!) }
		'enroll' { enroll(args[0], args[1], args[2], args[3])! }
		'tamper' { tamper(args[0], args[1])! }
		'main' { main_workflow(args[0], args[1])! }
		else { return error('unknown verified-root runtime helper') }
	}
	return ah.Value(json2.Null{})
}
