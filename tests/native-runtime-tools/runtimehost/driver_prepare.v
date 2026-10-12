// SPDX-License-Identifier: GPL-2.0-or-later
module runtimehost

import cachecli
import gamehost
import json2
import os
import sourcecommand

pub fn check_sources(source string, expected map[string]json2.Any, label string) ! {
	for name, hash in expected {
		file := gamehost.path(source, name)
		if !os.is_file(file) || gamehost.digest(file)! != hash.str() {
			return error('${label} Mesa source has an unexpected hash: ' + name)
		}
	}
}

fn apply_driver_patch(tools gamehost.Tools, source string, data []u8, label string) ! {
	directory := private_directory(gamehost.parent(source))!
	defer { gamehost.remove(directory) or {} }
	patch := directory + '/patch'
	os.write_file_array(patch, data)!
	argv := ['patch', '-p1', '--batch', '--forward', '-d', source, '-i', patch]
	result := if tools.command_hook != unsafe { nil } {
		tools.command(argv, true)!
	} else {
		sourcecommand.capture_combined(argv, os.environ(), -1, 64 * 1024 * 1024, cachecli.cancelled)!
	}
	if result.status != 0 {
		eprintln(replace_utf8(result.stdout.bytes()))
		return error('patch does not apply to the pinned Mesa source: ' + label)
	}
}

fn package_pin(row map[string]json2.Any) Package {
	return Package{ name: text_field(row, 'name'), version: text_field(row, 'version'), architecture: text_field(row, 'architecture'), filename: text_field(row, 'filename'), sha256: text_field(row, 'sha256'), size: field(row, 'size').i64() }
}

pub fn prepare_driver_sysroot(tools gamehost.Tools, inputs map[string]json2.Any, base string, destination string, downloads string) ! {
	pending := destination + '.pending'
	gamehost.remove(pending)!
	if os.user_os() == 'macos' {
		tools.run(['/bin/cp', '-cRp', base, pending])!
	} else {
		gamehost.copy_tree(base, pending, false)!
	}
	for row in field(inputs, 'packages').as_array() {
		archive := download_package(tools, text_field(inputs, 'mirror'), package_pin(row.as_map()), downloads)!
		extract_deb(archive, pending)!
	}
	gamehost.remove(destination)!
	if C.rename(pending.str, destination.str) != 0 { return os.error_posix() }
}

pub fn prepare_mesa_source(tools gamehost.Tools, inputs map[string]json2.Any, downloads string, destination string) ! {
	mut archives := map[string]string{}
	for key in ['source', 'debian_diff'] {
		row := field(inputs, key).as_map()
		pin := Package{ name: key, version: text_field(inputs, 'debian_version'), architecture: 'source', filename: text_field(row, 'filename'), sha256: text_field(row, 'sha256') }
		archives[key] = download_package(tools, text_field(inputs, 'mirror'), pin, downloads)!
	}
	pending := destination + '.pending'
	gamehost.remove(pending)!
	gamehost.mkdir(pending)!
	tools.run(['tar', 'xzf', archives['source'], '-C', pending, '--strip-components=1'])!
	debian_patch := tools.output(['gzip', '-dc', archives['debian_diff']])!
	apply_driver_patch(tools, pending, debian_patch.bytes(), archives['debian_diff'].all_after_last('/'))!
	patches := pending + '/debian/patches'
	mut series := []string{}
	for line in os.read_file(patches + '/series')!.split_into_lines() {
		stripped := line.trim_space()
		if stripped != '' && !stripped.starts_with('#') { series << stripped.fields()[0] }
	}
	expected := field(inputs, 'debian_patches').as_map()
	if series != expected.keys() {
		return error("Debian's Mesa patch series differs from the pinned series")
	}
	for name in series {
		file := patches + '/' + name
		if gamehost.digest(file)! != expected[name]!.str() {
			return error('Debian Mesa patch has an unexpected hash: ' + name)
		}
		apply_driver_patch(tools, pending, os.read_bytes(file)!, name)!
	}
	check_sources(pending, field(inputs, 'debian_source_sha256').as_map(), 'Debian-patched')!
	for name, hash in field(inputs, 'patches').as_map() {
		file := tools.root + '/build-support/dota2/mesa/' + name
		if gamehost.digest(file)! != hash.str() {
			return error('Lavapipe patch has an unexpected hash: ' + file)
		}
		apply_driver_patch(tools, pending, os.read_bytes(file)!, name)!
	}
	check_sources(pending, field(inputs, 'patched_source_sha256').as_map(), 'patched')!
	gamehost.remove(destination)!
	if C.rename(pending.str, destination.str) != 0 { return os.error_posix() }
}

fn venus_sources() map[string]json2.Any {
	return {
		'src/virtio/vulkan/vn_common.c':          json2.Any('ff8a1431255dd43c8712e4266b3d1e68b9515555053c4abda3e1024b589a12d6')
		'src/virtio/vulkan/vn_physical_device.c': json2.Any('38c4ea81add58393529e36038b90a4ecb9aea56625e180e8b37ef51f6dd19885')
		'src/virtio/vulkan/vn_device.c':          json2.Any('de58c4c59b82f751fe82639a4a4890c1f6199a361273dea2627a5b49e24b482b')
		'src/virtio/vulkan/vn_instance.c':        json2.Any('805837c925d8c4171d1366217a9dbcafc46104a7b713c6295cf16f81ddad85d2')
	}
}

pub fn prepare_venus_source(tools gamehost.Tools, downloads string, destination string) ! {
	archive := downloads + '/mesa-25.0.5.tar.xz'
	expected := 'c0d245dea0aa4b49f74b3d474b16542e4a8799791cd33d676c69f650ad4378d0'
	if !os.is_file(archive) || gamehost.digest(archive)! != expected {
		partial := archive + '.partial'
		tools.run(['curl', '--fail', '--location', '--retry', '3', '--silent', '--show-error',
			'--output', partial, 'https://archive.mesa3d.org/mesa-25.0.5.tar.xz'])!
		if gamehost.digest(partial)! != expected {
			os.rm(partial)!
			return error('Mesa 25.0.5 has an unexpected hash')
		}
		if C.rename(partial.str, archive.str) != 0 { return os.error_posix() }
	}
	pending := destination + '.pending'
	gamehost.remove(pending)!
	gamehost.mkdir(pending)!
	tools.run(['tar', 'xJf', archive, '-C', pending, '--strip-components=1'])!
	for index, patch in venus_patches(tools.root)! {
		if index == 0 && gamehost.digest(patch)! != 'd76f13c09ef7c8ee317b79f0f54eab046a8957c8cc463a3b98483a30503e96d0' {
			return error('Venus patch has an unexpected hash: ' + patch)
		}
		apply_driver_patch(tools, pending, os.read_bytes(patch)!, patch.all_after_last('/'))!
	}
	check_sources(pending, venus_sources(), 'patched Venus')!
	gamehost.remove(destination)!
	if C.rename(pending.str, destination.str) != 0 { return os.error_posix() }
}

pub fn verify_driver(tools gamehost.Tools, library string, base string, compiler_tools string) ! {
	if !buildcore_shared(library)! {
		return error('driver must be an x86-64 shared library: ' + library)
	}
	output := tools.output([compiler_tools + '/llvm-readelf', '-d', '--dyn-syms', library])!
	verify_dynamic(output, base)!
}
