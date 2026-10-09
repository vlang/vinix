// SPDX-License-Identifier: GPL-2.0-or-later
module guestcore

import androidhost as ah

fn steam_install(source string, destination string) ! {
	mkdir(attr(destination, 'parent')!)!
	if truth(method(destination, 'is_symlink', [], {})!)! {
		method(destination, 'unlink', [], {})!
	}
	call('shutil.copy2', o(source), o(destination))!
}

fn steam_hash(data string) !string {
	hash := call('hashlib.sha256', o(data))!
	result := method(hash, 'hexdigest', [], {})!
	release(hash)!
	return result
}

fn steam_file_hash(input string) !string {
	data := method(input, 'read_bytes', [], {})!
	result := steam_hash(data)!
	release(data)!
	return result
}

fn steam_environment(options string, parser string) !string {
	result := dict()!
	entries := call('_vm.iterate_value', o(attr(options, 'game_env')!))!
	for {
		entry := next(entries)!
		if entry.done { break }
		parts := method(entry.id, 'partition', [s('=')], {})!
		name, separator, value := get(parts, n(0))!, get(parts, n(1))!, get(parts, n(2))!
		if !truth(separator)! || !truth(call('re.fullmatch', s('[A-Za-z_][A-Za-z0-9_]*'), o(name))!)! {
			argument_error(parser, 'invalid --game-env: ' + format(entry.id)!)!
		}
		if truth(call('operator.contains', o(value), s('\0'))!)! || truth(call('operator.contains', o(value), s(','))!)! {
			argument_error(parser, "--game-env values cannot contain NUL or QEMU's comma separator")!
		}
		call('operator.setitem', o(result), o(name), o(value))!
	}
	return result
}

struct SteamPreloads {
	records string
	data    string
}

fn steam_preloads(options string, parser string) !SteamPreloads {
	records, contents := list()!, list()!
	entries := call('_vm.iterate_value', o(attr(options, 'extra_preload')!))!
	for {
		entry := next(entries)!
		if entry.done { break }
		input := method(entry.id, 'resolve', [], {})!
		if !truth(method(input, 'is_file', [], {})!)! {
			argument_error(parser, 'extra preload is not a file: ' + format(input)!)!
		}
		data := method(input, 'read_bytes', [], {})!
		if compare('ne', get(data, o(call('_vm.slice_value', n(0), n(6))!))!, b('7f454c460201'))! || compare('lt', call('builtins.len', o(data))!, n(20))! || compare('ne', method(global('int')!, 'from_bytes', [
			o(get(data, o(call('_vm.slice_value', n(16), n(18))!))!),
			s('little'),
		], {})!, n(3))! || compare('ne', method(global('int')!, 'from_bytes', [
			o(get(data, o(call('_vm.slice_value', n(18), n(20))!))!),
			s('little'),
		], {})!, n(62))! {
			argument_error(parser, 'extra preload must be a Linux x86-64 shared ELF: ' + format(input)!)!
		}
		record := dict()!
		set(record, 'source', o(str(input)!))!
		set(record, 'sha256', o(steam_hash(data)!))!
		append(records, o(record))!
		append(contents, o(data))!
	}
	return SteamPreloads{records, contents}
}

fn steam_source(source string, root string) ! {
	inputs := dict()!
	for relative in ['usr/libexec/vinix-dota2/root/.vinix-dota2-vulkan-generation',
		'home/dota2/.steam/sdk64/steamclient.so', 'home/dota2/.steam/sdk64/libtier0_s.so',
		'home/dota2/.steam/sdk64/libvstdlib_s.so', 'home/dota2/.steam/ubuntu12_64/gldriverquery',
		'usr/bin/qemu-x86_64', 'usr/bin/Xvfb'] {
		set(inputs, relative, o(steam_file_hash(join(source, relative)!)!))!
	}
	set(inputs, 'source', o(str(source)!))!
	stamp := join(root, '.steam-smoke-source.json')!
	if !truth(method(stamp, 'is_file', [], {})!)! || compare('ne', call('json.loads', o(method(stamp, 'read_text', [], {})!))!, o(inputs))! {
		if truth(method(root, 'exists', [], {})!)! { call('shutil.rmtree', o(root))! }
		if eq(call('sys.platform')!, s('darwin'))! {
			invoke('subprocess.run', [o(command([s('/bin/cp'), s('-cRp'), o(str(source)!),
				o(str(root)!)])!)], {
				'check': v(ah.Value(true))
			})!
		} else {
			invoke('shutil.copytree', [o(source), o(root)], {
				'symlinks': v(ah.Value(true))
			})!
		}
		encoded := invoke('json.dumps', [o(inputs)], {
			'sort_keys': v(ah.Value(true))
		})!
		method(stamp, 'write_text', [o(call('operator.add', o(encoded), s('\n'))!)], {})!
	}
}

fn steam_copy_preloads(root string, preloads SteamPreloads) ! {
	entries := call('_vm.iterate_value', o(call('builtins.enumerate', o(call('builtins.zip', o(preloads.records), o(preloads.data))!))!))!
	for {
		entry := next(entries)!
		if entry.done { break }
		pair := call('_vm.unpack_pair', o(entry.id))!
		index, values := get(pair, n(0))!, call('_vm.unpack_pair', o(get(pair, n(1))!))!
		record, data := get(values, n(0))!, get(values, n(1))!
		guest := '/usr/libexec/vinix-dota2/smoke/preloads/extra-' + format(index)! + '.so'
		set(record, 'guest_path', s(guest))!
		destination := call('operator.truediv', o(root), o(method(get(record, s('guest_path'))!, 'lstrip', [s('/')], {})!))!
		mkdir(attr(destination, 'parent')!)!
		if truth(method(destination, 'is_symlink', [], {})!)! {
			method(destination, 'unlink', [], {})!
		}
		method(destination, 'write_bytes', [o(data)], {})!
		method(destination, 'chmod', [n(0o644)], {})!
	}
}

fn steam_game_libraries(options string, root string) !string {
	game := join(root, 'usr/libexec/vinix-dota2/smoke/game-bin')!
	if truth(attr(options, 'game_library_priority')!)! {
		mkdir(game)!
		entries := call('_vm.iterate_value', o(method(attr(method(attr(options, 'library')!, 'resolve', [], {})!, 'parent')!, 'iterdir', [], {})!))!
		for {
			entry := next(entries)!
			if entry.done { break }
			input := entry.id
			if truth(method(input, 'is_file', [], {})!)! && (truth(method(attr(input, 'name')!, 'endswith', [s('.so')], {})!)! || truth(call('operator.contains', o(attr(input, 'name')!), s('.so.'))!)!) {
				destination := call('operator.truediv', o(game), o(attr(input, 'name')!))!
				if truth(method(destination, 'is_symlink', [], {})!)! {
					method(destination, 'unlink', [], {})!
				}
				if eq(call('sys.platform')!, s('darwin'))! {
					invoke('subprocess.run', [o(command([s('cp'), s('-cp'), o(str(input)!),
						o(str(destination)!)])!)], {
						'check': v(ah.Value(true))
					})!
				} else {
					call('install', o(input), o(destination))!
				}
			}
		}
	}
	return game
}
