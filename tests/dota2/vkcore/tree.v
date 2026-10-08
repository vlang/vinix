// SPDX-License-Identifier: GPL-2.0-or-later
module vkcore

import androidhost as ah

fn copy_layer(source string, target string) ! {
	mkdir(target)!
	entries := iter(method(source, 'iterdir', [], {})!)!
	for {
		entry := next(entries)!
		if entry.done { break }
		destination := call('operator.truediv', o(target), o(attr(entry.id, 'name')!))!
		if truth(method(entry.id, 'is_symlink', [], {})!)! {
			if truth(method(destination, 'exists', [], {})!)! || truth(method(destination, 'is_symlink', [], {})!)! {
				if truth(method(destination, 'is_dir', [], {})!)! && !truth(method(destination, 'is_symlink', [], {})!)! { continue }
				method(destination, 'unlink', [], {})!
			}
			method(destination, 'symlink_to', [o(call('os.readlink', o(entry.id))!)], {})!
		} else if truth(method(entry.id, 'is_dir', [], {})!)! {
			call('copy_layer', o(entry.id), o(destination))!
		} else {
			if truth(method(destination, 'is_symlink', [], {})!)! { method(destination, 'unlink', [], {})! }
			call('shutil.copy2', o(entry.id), o(destination))!
		}
	}
}
fn library(base string, name string) !string {
	for directory in ['usr/lib', 'lib'] {
		candidate := call('operator.truediv', o(join(base, directory)!), o(name))!
		if truth(method(candidate, 'exists', [], {})!)! {
			return call('operator.truediv', o(join(base, directory)!), o(name))!
		}
	}
	return null_id()!
}
fn closure(root string) ! {
	userland := join('repo', 'build-aarch64-userland/staging')!
	queue := list()!
	for name in ['usr/bin/Xvfb', 'usr/bin/xkbcomp', 'usr/bin/qemu-x86_64'] { append(queue, o(join(root, name)!))! }
	seen := call('builtins.set')!
	for truth(queue)! {
		binary := method(queue, 'pop', [], {})!
		if truth(call('operator.contains', o(seen), o(binary))!)! || !truth(method(binary, 'exists', [], {})!)! { continue }
		method(seen, 'add', [o(binary)], {})!
		command := list()!
		for value in [s('aarch64-linux-musl-readelf'), s('-d'), o(text_id(binary)!)] { append(command, value)! }
		output := invoke('subprocess.check_output', [o(command)], {'text': v(ah.Value(true))})!
		names := iter(call('re.findall', s(r'\(NEEDED\).*\[([^]]+)\]'), o(output))!)!
		for {
			row := next(names)!
			if row.done { break }
			mut found := library(root, row.id)!
			if compare('is_', found, o(null_id()!))! {
				source := library(userland, row.id)!
				if compare('is_', source, o(null_id()!))! { system_exit(s('native probe dependency is missing: ' + format(row.id)!))! }
				found = call('operator.truediv', o(join(root, 'usr/lib')!), o(row.id))!
				if truth(method(found, 'is_symlink', [], {})!)! { method(found, 'unlink', [], {})! }
				call('shutil.copy2', o(source), o(found))!
			}
			append(queue, o(found))!
		}
	}
}
fn text_id(value string) !string { return call('builtins.str', o(value))! }
fn system_exit(value ah.Value) ! {
	imported_raise('SystemExit', value)!
}
fn imported_raise(name string, value ah.Value) ! {
	imported_callback('raise_builtin', {'kind': ah.Value(name), 'value': value})!
}
fn install_translator(staging string, root string) ! {
	binary := join(staging, 'usr/bin/qemu-x86_64')!
	manager := method(binary, 'open', [s('rb')], {})!
	stream := enter(manager)!
	mut result := ReadResult{}
	read_into(stream, 20, mut result) or {
		failure := err
		if !retire(manager, failure)! { return failure }
	}
	if result.id == '' { fail('UnboundLocalError', "local variable 'header' referenced before assignment")! }
	else { retire(manager, none)! }
	header := result.id
	if !translator_valid(header, binary)! {
		system_exit(s('Expected an executable native AArch64 translator: ' + format(binary)!))!
	}
	for directory in ['usr/lib', 'lib'] {
		if truth(method(join(staging, directory)!, 'is_dir', [], {})!)! { call('copy_layer', o(join(staging, directory)!), o(join(root, directory)!))! }
	}
	mkdir(join(root, 'usr/bin')!)!
	target := join(root, 'usr/bin/qemu-x86_64')!
	if truth(method(target, 'is_symlink', [], {})!)! { method(target, 'unlink', [], {})! }
	call('shutil.copy2', o(binary), o(target))!
}
struct ReadResult {
mut:
	id string
}
fn read_into(stream string, count int, mut result ReadResult) ! { result.id = method(stream, 'read', [n(count)], {})! }
fn retain_gl(source string, guest string) ! {
	relative := 'usr/lib/x86_64-linux-gnu/dri'
	destination := join(guest, relative)!
	mkdir(destination)!
	keep := call('builtins.set', o(literal(ah.Value([ah.Value('swrast_dri.so'), ah.Value('kms_swrast_dri.so')]))!))!
	names := iter(keep)!
	for {
		row := next(names)!
		if row.done { break }
		library := call('operator.truediv', o(join(source, relative)!), o(row.id))!
		if truth(method(library, 'is_file', [], {})!)! {
			target := call('operator.truediv', o(destination), o(row.id))!
			if truth(method(target, 'is_symlink', [], {})!)! { method(target, 'unlink', [], {})! }
			call('shutil.copy2', o(library), o(target))!
		}
	}
	entries := iter(method(destination, 'iterdir', [], {})!)!
	for {
		entry := next(entries)!
		if entry.done { break }
		if truth(call('operator.contains', o(keep), o(attr(entry.id, 'name')!))!)! { continue }
		if truth(method(entry.id, 'is_dir', [], {})!)! && !truth(method(entry.id, 'is_symlink', [], {})!)! { call('shutil.rmtree', o(entry.id))! }
		else { method(entry.id, 'unlink', [], {})! }
	}
}

fn translator_valid(header string, binary string) !bool {
	if !eq(get(header, o(call('builtins.slice', n(0), n(7))!))!, b('7f454c46020101'))! { return false }
	kind := get(header, o(call('builtins.slice', n(16), n(18))!))!
	if !eq(kind, b('0200'))! && !eq(kind, b('0300'))! { return false }
	if !eq(get(header, o(call('builtins.slice', n(18), n(20))!))!, b('b700'))! { return false }
	return truth(call('os.access', o(binary), o(call('os.X_OK')!))!)!
}
