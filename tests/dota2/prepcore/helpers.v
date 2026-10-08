// SPDX-License-Identifier: GPL-2.0-or-later
module prepcore

import crypto.sha256
import encoding.hex
import json2

fn digest(path string) !string {
	handle := primitive('open_read', [path])!.str()
	mut hash := sha256.new()
	mut inner_error := ?IError(none)
	for {
		value := callback('read_handle', {
			'handle': json2.Any(handle)
			'limit':  json2.Any(1024 * 1024)
		}) or {
			inner_error = err
			break
		}
		data := hex.decode(value.str()) or {
			inner_error = err
			break
		}
		if data.len == 0 { break }
		hash.write(data) or {
			inner_error = err
			break
		}
	}
	callback('close_handle', {
		'handle': json2.Any(handle)
	})!
	if err := inner_error { return err }
	return hash.sum([]u8{}).hex()
}

fn install(source string, target string) ! {
	if path('resolve', [source])! == path('resolve', [target])! { return }
	mkdir(parent(target)!)!
	remove_existing(target)!
	primitive('copy2', [source, target])!
}

fn elf(data []u8, exact bool, shared_elf bool, machine u16) bool {
	if data.len < 64 || (exact && data.len != 64) { return false }
	if data[..7] != [u8(0x7f), `E`, `L`, `F`, 2, 1, 1] { return false }
	kind := u16(data[16]) | u16(data[17]) << 8
	return (kind == 3 || (!shared_elf && kind == 2))
		&& (u16(data[18]) | u16(data[19]) << 8) == machine
}

fn stage_vulkan_query(query string, root string) ! {
	source := path('with_name', [query, 'vulkandriverquery'])!
	target := join(root, 'home/dota2/.steam/ubuntu12_64/vulkandriverquery')!
	if !test('is_file', source)! {
		remove_existing(target)!
		return
	}
	if !elf(read(source, 64)!, true, false, 62) {
		return failed("Expected Valve's actual Linux x86-64 Vulkan helper: " + source)
	}
	install(source, target)!
}

fn probe_preloads() !json2.Any {
	mut records := []json2.Any{}
	mut contents := []json2.Any{}
	mut index := 0
	for {
		if primitive('next', [])!.as_map()['ended']!.bool() { break }
		value := decode(callback('reference_path', {
			'function': json2.Any('resolve')
		})!.str())!
		if !test('is_file', value)! { return failed('Extra preload is not a file: ' + value) }
		data := read(value, -1)!
		if !elf(data, false, true, 62) {
			return failed('Extra preload must be a Linux x86-64 shared ELF: ' + value)
		}
		records << json2.Any({
			'source':     json2.Any(value.bytes().hex())
			'sha256':     json2.Any(sha256.sum(data).hex())
			'guest_path': json2.Any(('/usr/libexec/vinix-dota2/probes/extra-${index}.so').bytes().hex())
		})
		contents << json2.Any(data.hex())
		index++
	}
	return json2.Any([json2.Any(records), json2.Any(contents)])
}

const software_drivers = ['swrast_dri.so', 'kms_swrast_dri.so']

fn trim_runtime(root string) ! {
	for relative in ['usr/lib/i386-linux-gnu', 'lib/i386-linux-gnu', 'usr/share/doc', 'usr/share/man',
		'usr/share/locale', 'usr/share/icons'] {
		value := join(root, relative)!
		if test('exists', value)! { primitive('rmtree', [value])! }
	}
	dri := join(root, 'usr/lib/x86_64-linux-gnu/dri')!
	if test('is_dir', dri)! {
		for value in listing('iterdir', [dri])! {
			if path('name', [value])! in software_drivers { continue }
			if test('is_dir', value)! && !test('is_symlink', value)! {
				primitive('rmtree', [value])!
			} else {
				primitive('unlink', [value])!
			}
		}
	}
}

fn clone(source string, target string) ! {
	if decode(primitive('system', [])!.str())! == 'Darwin' {
		checked(['cp', '-cRp', source, target])!
	} else {
		callback('copytree', {
			'args':     encoded([source, target])
			'symlinks': json2.Any(true)
		})!
	}
}

fn refresh_runtime(root string) ! {
	relative := 'usr/libexec/vinix-dota2/root'
	source := join(field('base_root')!, relative)!
	target := join(root, relative)!
	stamp := '.vinix-dota2-vulkan-generation'
	generation := text(join(source, stamp)!)!
	mut drivers_present := true
	for name in software_drivers {
		from := join(source, 'usr/lib/x86_64-linux-gnu/dri', name)!
		to := join(target, 'usr/lib/x86_64-linux-gnu/dri', name)!
		if test('is_file', from)! && (!test('is_file', to)!
			|| primitive('size', [to])! != primitive('size', [from])!) {
			drivers_present = false
			break
		}
	}
	if test('is_file', join(target, stamp)!)! && text(join(target, stamp)!)! == generation && drivers_present {
		return
	}
	pid := primitive('pid', [])!.str()
	pending := path('with_name', [target, 'root-refresh-' + pid])!
	clone(source, pending)!
	trim_runtime(pending)!
	if test('exists', target)! { primitive('rmtree', [target])! }
	primitive('rename', [pending, target])!
}

fn native_library(root string, userland string, name string) !string {
	for directory in ['usr/lib', 'lib'] {
		value := join(root, directory, name)!
		if test('exists', value)! { return value }
	}
	for directory in ['usr/lib', 'lib'] {
		value := join(userland, directory, name)!
		if test('exists', value)! {
			target := join(root, 'usr/lib', name)!
			install(value, target)!
			return target
		}
	}
	return failed('Missing native dependency: ' + name)
}

fn closure(root string, repo string, mut queue []string, external bool) ! {
	userland := join(repo, 'build-aarch64-userland/staging')!
	mut seen := map[string]bool{}
	for if external {
		callback('sequence', {
			'function': json2.Any('len')
		})!.i64() != 0
	} else {
		queue.len != 0
	} {
		binary := if external {
			decode(callback('sequence', {
				'function': json2.Any('pop')
			})!.str())!
		} else {
			queue.pop()
		}
		if binary in seen { continue }
		seen[binary] = true
		for name in needed(output(['aarch64-linux-musl-readelf', '-d', binary])!)! {
			library := native_library(root, userland, name)!
			if external {
				callback('sequence', {
					'function': json2.Any('append')
					'args':     encoded([library])
				})!
			} else {
				queue << library
			}
		}
	}
}

fn verify_sdk_closure(root string) ! {
	runtime := join(root, 'usr/libexec/vinix-dota2/root')!
	sdk := join(root, 'home/dota2/.steam/sdk64')!
	libraries := [sdk, join(runtime, 'usr/lib/x86_64-linux-gnu')!,
		join(runtime, 'lib/x86_64-linux-gnu')!, join(runtime, 'lib64')!]
	mut queue := listing('glob', [sdk, '*.so'])!
	queue << join(root, 'home/dota2/.steam/ubuntu12_64/gldriverquery')!
	vulkan_query := join(root, 'home/dota2/.steam/ubuntu12_64/vulkandriverquery')!
	if test('is_file', vulkan_query)! { queue << vulkan_query }
	for name in software_drivers {
		driver := join(runtime, 'usr/lib/x86_64-linux-gnu/dri', name)!
		if test('is_file', driver)! {
			queue << driver
		} else if name == 'swrast_dri.so' {
			return failed("Steam's GPU helper needs the software GL driver: " + driver)
		}
	}
	for name in ['libEGL_mesa.so.0', 'libGLX_mesa.so.0'] {
		library := join(runtime, 'usr/lib/x86_64-linux-gnu', name)!
		if !test('is_file', library)! {
			return failed("Steam's GPU helper needs the private GL library: " + library)
		}
		queue << library
	}
	mut seen := map[string]bool{}
	mut missing := map[string]bool{}
	for queue.len != 0 {
		binary := queue.pop()
		if binary in seen { continue }
		seen[binary] = true
		for name in needed(output(['x86_64-linux-musl-readelf', '-d', binary])!)! {
			mut found := false
			for directory in libraries {
				library := join(directory, name)!
				if test('exists', library)! {
					queue << library
					found = true
					break
				}
			}
			if !found { missing[name] = true }
		}
	}
	if missing.len != 0 {
		mut names := missing.keys()
		names.sort()
		return failed('Private runtime lacks Steam client dependencies: ' + names.join(', '))
	}
}

fn path_compare(left &string, right &string) int {
	a := left.split('/')
	b := right.split('/')
	for index in 0 .. if a.len < b.len { a.len } else { b.len } {
		if a[index] < b[index] { return -1 }
		if a[index] > b[index] { return 1 }
	}
	return if a.len < b.len {
		-1
	} else if a.len > b.len {
		1
	} else {
		0
	}
}

fn overlay_translator(source string, root string, repo string) ! {
	binary := join(source, 'usr/bin/qemu-x86_64')!
	header := read(binary, 64)!
	// The original accepts any ELF type for the translator, while checking its
	// first seven bytes, ARM64 machine and executable access explicitly.
	if header.len != 64 || header[..7] != [u8(0x7f), `E`, `L`, `F`, 2, 1, 1]
		|| header[18..20] != [u8(0xb7), 0] || !callback('access', {
		'args': encoded([binary])
		'mode': json2.Any(1)
	})!.bool() {
		return failed('Expected an executable native ARM64 translator: ' + binary)
	}
	install(binary, join(root, 'usr/bin/qemu-x86_64')!)!
	for directory in ['lib', 'usr/lib'] {
		mut paths := listing('rglob', [join(source, directory)!, '*'])!
		paths.sort_with_compare(path_compare)
		for value in paths {
			target := join(root, path('relative_to', [value, source])!)!
			if test('is_symlink', value)! {
				mkdir(parent(target)!)!
				remove_existing(target)!
				primitive('symlink', [target, decode(primitive('readlink', [value])!.str())!])!
			} else if test('is_file', value)! {
				install(value, target)!
			}
		}
	}
	mut binaries := [join(root, 'usr/bin/qemu-x86_64')!]
	closure(root, repo, mut binaries, false)!
}
