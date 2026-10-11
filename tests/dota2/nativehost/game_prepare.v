// SPDX-License-Identifier: GPL-2.0-or-later
module nativehost

import buildcore
import crypto.sha256
import hosttest
import os

pub const software_drivers = ['swrast_dri.so', 'kms_swrast_dri.so']

fn remove_existing(path string) ! {
	if os.exists(path) || os.is_link(path) { os.rm(path)! }
}

pub fn game_install(source string, destination string) ! {
	if resolve(source)! == resolve(destination)! { return }
	os.mkdir_all(os.dir(destination))!
	remove_existing(destination)!
	hosttest.module_copy_file_preserving_stat(source, destination)!
}

fn clone_tree(source string, destination string) ! {
	$if macos {
		os.mkdir_all(os.dir(destination))!
		run(['/bin/cp',
			if os.stat(source)!.dev == os.stat(os.dir(destination))!.dev { '-cRp' } else { '-Rp' },
			source, destination])!
	} $else {
		hosttest.module_copy_tree(source, destination)!
	}
}

pub fn trim_game_runtime(runtime string) ! {
	for name in ['usr/lib/i386-linux-gnu', 'lib/i386-linux-gnu', 'usr/share/doc', 'usr/share/man',
		'usr/share/locale', 'usr/share/icons'] {
		path := runtime + '/' + name
		if os.exists(path) { os.rmdir_all(path)! }
	}
	dri := runtime + '/usr/lib/x86_64-linux-gnu/dri'
	if os.is_dir(dri) {
		for name in os.ls(dri)! {
			if name in software_drivers { continue }
			path := dri + '/' + name
			if os.is_dir(path) && !os.is_link(path) { os.rmdir_all(path)! } else { os.rm(path)! }
		}
	}
}

pub fn refresh_game_runtime(base string, rootfs string) ! {
	relative := '/usr/libexec/vinix-dota2/root'
	source, target := base + relative, rootfs + relative
	stamp := '/.vinix-dota2-vulkan-generation'
	generation := os.read_file(source + stamp)!
	mut drivers_present := true
	for name in software_drivers {
		from := source + '/usr/lib/x86_64-linux-gnu/dri/' + name
		to := target + '/usr/lib/x86_64-linux-gnu/dri/' + name
		if os.is_file(from) && (!os.is_file(to) || os.file_size(from) != os.file_size(to)) {
			drivers_present = false
			break
		}
	}
	if os.is_file(target + stamp) && os.read_file(target + stamp)! == generation && drivers_present {
		return
	}
	pending := os.dir(target) + '/root-refresh-' + os.getpid().str()
	os.mkdir_all(os.dir(pending))!
	clone_tree(source, pending)!
	trim_game_runtime(pending)!
	if os.exists(target) { os.rmdir_all(target)! }
	os.mv(pending, target)!
}

pub fn stage_game_vulkan_query(query string, rootfs string) ! {
	source := os.dir(query) + '/vulkandriverquery'
	target := rootfs + '/home/dota2/.steam/ubuntu12_64/vulkandriverquery'
	if !os.is_file(source) {
		remove_existing(target)!
		return
	}
	mut file := os.open(source)!
	header := file.read_bytes(64)
	file.close()
	if header.len != 64 || header[..7] != [u8(0x7f), `E`, `L`, `F`, 2, 1, 1] || int(header[18]) + (int(header[19]) << 8) != 62 || int(header[16]) + (int(header[17]) << 8) !in [
		2,
		3,
	] {
		return error("Expected Valve's actual Linux x86-64 Vulkan helper: " + source)
	}
	game_install(source, target)!
}

pub fn verify_game_sdk(rootfs string, readelf string) ! {
	runtime := rootfs + '/usr/libexec/vinix-dota2/root'
	sdk := rootfs + '/home/dota2/.steam/sdk64'
	directories := [sdk, runtime + '/usr/lib/x86_64-linux-gnu', runtime + '/lib/x86_64-linux-gnu',
		runtime + '/lib64']
	mut queue := os.ls(sdk)!.filter(it.ends_with('.so')).map(sdk + '/' + it)
	queue << rootfs + '/home/dota2/.steam/ubuntu12_64/gldriverquery'
	query := rootfs + '/home/dota2/.steam/ubuntu12_64/vulkandriverquery'
	if os.is_file(query) { queue << query }
	for name in software_drivers {
		path := runtime + '/usr/lib/x86_64-linux-gnu/dri/' + name
		if os.is_file(path) {
			queue << path
		} else if name == 'swrast_dri.so' {
			return error("Steam's GPU helper needs the software GL driver: " + path)
		}
	}
	for name in ['libEGL_mesa.so.0', 'libGLX_mesa.so.0'] {
		path := runtime + '/usr/lib/x86_64-linux-gnu/' + name
		if !os.is_file(path) {
			return error("Steam's GPU helper needs the private GL library: " + path)
		}
		queue << path
	}
	mut seen := map[string]bool{}
	mut missing := map[string]bool{}
	for queue.len > 0 {
		binary := queue.pop()
		if binary in seen { continue }
		seen[binary] = true
		for name in buildcore.needed(capture([readelf, '-d', binary])!) {
			mut found := false
			for directory in directories {
				path := if name.starts_with('/') { name } else { directory + '/' + name }
				if os.exists(path) {
					queue << path
					found = true
					break
				}
			}
			if !found { missing[name] = true }
		}
	}
	if missing.len > 0 {
		mut names := missing.keys()
		names.sort()
		return error('Private runtime lacks Steam client dependencies: ' + names.join(', '))
	}
}

pub fn complete_game_native_closure(rootfs string, userland string, binaries []string, readelf string) ! {
	mut queue := binaries.clone()
	mut seen := map[string]bool{}
	for queue.len > 0 {
		binary := queue.pop()
		if binary in seen { continue }
		seen[binary] = true
		for name in buildcore.needed(capture([readelf, '-d', binary])!) {
			mut library := ''
			for directory in ['usr/lib', 'lib'] {
				path := os.join_path(rootfs, directory, name)
				if os.exists(path) {
					library = path
					break
				}
			}
			if library == '' {
				for directory in ['usr/lib', 'lib'] {
					path := os.join_path(userland, directory, name)
					if os.exists(path) {
						library = os.join_path(rootfs, 'usr/lib', name)
						game_install(path, library)!
						break
					}
				}
			}
			if library == '' { return error('Missing native dependency: ' + name) }
			queue << library
		}
	}
}

fn game_paths(directory string) ![]string {
	mut result := []string{}
	if !os.is_dir(directory) { return result }
	for name in os.ls(directory)! {
		path := directory + '/' + name
		result << path
		if os.is_dir(path) && !os.is_link(path) { result << game_paths(path)! }
	}
	return result
}

pub fn overlay_game_translator(source string, rootfs string, userland string, readelf string) ! {
	binary := source + '/usr/bin/qemu-x86_64'
	mut file := os.open(binary)!
	header := file.read_bytes(64)
	file.close()
	if header.len != 64 || header[..7] != [u8(0x7f), `E`, `L`, `F`, 2, 1, 1] || header[18..20] != [
		u8(183),
		0,
	] || !os.is_executable(binary) {
		return error('Expected an executable native ARM64 translator: ' + binary)
	}
	game_install(binary, rootfs + '/usr/bin/qemu-x86_64')!
	for directory in ['lib', 'usr/lib'] {
		mut entries := game_paths(source + '/' + directory)!
		entries.sort()
		for path in entries {
			target := rootfs + path[source.len..]
			if os.is_link(path) {
				os.mkdir_all(os.dir(target))!
				remove_existing(target)!
				os.symlink(os.readlink(path)!, target)!
			} else if os.is_file(path) {
				game_install(path, target)!
			}
		}
	}
	complete_game_native_closure(rootfs, userland, [rootfs + '/usr/bin/qemu-x86_64'], readelf)!
}

fn game_preloads(paths []string) ![]Preload {
	mut result := []Preload{}
	for index, path in paths {
		source := resolve(path)!
		data := os.read_bytes(source)!
		if !buildcore.shared_elf(data) {
			return error('Extra preload must be a Linux x86-64 shared ELF: ' + source)
		}
		result << Preload{source, sha256.sum(data).hex(), '/usr/libexec/vinix-dota2/probes/extra-' + index.str() + '.so', data}
	}
	return result
}
