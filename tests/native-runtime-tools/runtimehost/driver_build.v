// SPDX-License-Identifier: GPL-2.0-or-later
module runtimehost

import buildcore
import cachecli
import crypto.sha256
import gamehost
import json2
import os
import sourcecommand

fn buildcore_shared(file string) !bool { return buildcore.shared_elf(os.read_bytes(file)!) }

fn verify_dynamic(output string, base string) ! { buildcore.verify_dynamic(output, base)! }

fn logged_driver(tools gamehost.Tools, argv []string, directory string, log string, environment map[string]string) ! {
	result := if tools.command_hook != unsafe { nil } {
		captured := tools.command(argv, false)!
		os.write_file(log, captured.stdout + captured.stderr)!
		captured
	} else {
		sourcecommand.run_logged_owned(argv, environment, cachecli.cancelled, log, false, directory, unsafe { nil }, unsafe { nil }, 0)!
	}
	if result.status != 0 {
		lines := replace_utf8(os.read_bytes(log)!).split_into_lines()
		eprintln(lines[int_max(0, lines.len - 35)..].join('\n'))
		return error('driver build failed; see ' + log)
	}
}

pub fn build_driver(tools gamehost.Tools, venus bool, base_arg string, work_arg string, jobs int, refresh bool) ![]string {
	if jobs < 1 { return error_with_code('--jobs must be positive', 2) }
	base, work := normalized_driver_paths(base_arg, work_arg)!
	inputs := load_mesa_inputs(tools.root)!
	if !venus {
		llvm := base + '/usr/lib/x86_64-linux-gnu/libLLVM-15.so.1'
		if !os.is_file(llvm) || gamehost.digest(llvm)! != text_field(inputs, 'llvm_runtime_sha256') {
			return error('the base root lacks the pinned LLVM 15 runtime: ' + llvm)
		}
	}
	compiler_tools := llvm_tools()!
	for name in ['clang', 'clang++', 'llvm-ar', 'llvm-strip', 'llvm-readelf'] {
		if !os.is_file(compiler_tools + '/' + name) {
			return error('missing LLVM tool ${name} in ${compiler_tools}; set VINIX_DOTA2_LLVM_BIN')
		}
	}
	// Build systems and their upstream generators are external prerequisites.
	// No first-party Python environment or generated helper is bootstrapped here.
	meson := os.getenv_opt('VINIX_DOTA2_MESON') or {
		cached := work + '/host-venv/bin/meson'
		if os.is_file(cached) { cached } else { os.find_abs_path_of_executable('meson')! }
	}
	mut source_hashes := map[string]json2.Any{}
	for path in native_sources(tools.root)! {
		source_hashes[path[tools.root.len + 1..]] = json2.Any(gamehost.digest(path)!)
	}
	mut patches := map[string]json2.Any{}
	if venus {
		for patch in venus_patches(tools.root)! {
			patches[patch.all_after_last('/')] = json2.Any(gamehost.digest(patch)!)
		}
	} else {
		for name in field(inputs, 'patches').as_map().keys() {
			patches[name] = json2.Any(gamehost.digest(tools.root + '/build-support/dota2/mesa/' + name)!)
		}
	}
	generation := json2.Any({
		'format':         json2.Any(3)
		'inputs':         json2.Any(inputs)
		'native_builder': json2.Any(source_hashes)
		'patches':        json2.Any(patches)
		'options':        json2.Any(driver_options(venus).map(json2.Any(it)))
		'clang':          json2.Any(tools.output([compiler_tools + '/clang', '--version'])!)
		'base':           json2.Any(base_identity(base)!)
		'venus':          json2.Any(venus)
		'meson':          json2.Any(meson)
		'meson_sha256':   json2.Any(gamehost.digest(meson)!)
	})
	key := sha256.hexhash(native_dumps(generation, true, false)!)
	output := work + '/out/' + if venus { 'libvulkan_virtio.so' } else { 'libvulkan_lvp.so' }
	manifest := work + '/out/virtio_icd.x86_64.json'
	marker := work + '/out/generation'
	if !refresh && os.is_file(output) && os.is_file(marker) && (!venus || os.is_file(manifest)) && os.read_file(marker)!.trim_space() == key + ' ' + gamehost.digest(output)! {
		return if venus { [output, manifest] } else { [output] }
	}
	downloads := work + '/downloads'
	gamehost.mkdir(downloads)!
	source := work + '/source'
	objects := work + '/obj'
	stamp := work + '/.prepared-generation'
	if refresh || !os.is_file(stamp) || os.read_file(stamp)!.trim_space() != key {
		println('Preparing pinned Mesa source and amd64 development libraries')
		flush_stdout()
		if venus {
			prepare_venus_source(tools, downloads, source)!
		} else {
			prepare_mesa_source(tools, inputs, downloads, source)!
		}
		prepare_driver_sysroot(tools, inputs, base, work + '/sysroot', downloads)!
		gamehost.remove(objects)!
		os.write_file(stamp, key + '\n')!
	}
	check_sources(source, if venus {
		venus_sources()
	} else {
		field(inputs, 'patched_source_sha256').as_map()
	}, if venus { 'prepared Venus' } else { 'prepared' })!
	mut environment := os.environ()
	environment['PATH'] = gamehost.parent(meson) + ':' + os.getenv('PATH')
	if !os.is_file(objects + '/build.ninja') {
		cross := write_driver_configuration(tools, work, inputs, compiler_tools, venus)!
		logged_driver(tools, [meson, 'setup', objects, source, '--cross-file', cross,
			...driver_options(venus)], work, work + '/configure.log', environment)!
	}
	target := if venus {
		'src/virtio/vulkan/libvulkan_virtio.so'
	} else {
		'src/gallium/targets/lavapipe/libvulkan_lvp.so'
	}
	mut command := [os.find_abs_path_of_executable('ninja')!, '-C', objects, '-j', jobs.str(),
		target]
	if venus { command << 'src/virtio/vulkan/virtio_icd.x86_64.json' }
	logged_driver(tools, command, work, work + '/build.log', environment)!
	built := objects + '/' + target
	verify_driver(tools, built, base, compiler_tools)!
	gamehost.mkdir(work + '/out')!
	for pair in if venus {
		[[built, output], [objects + '/src/virtio/vulkan/virtio_icd.x86_64.json', manifest]]
	} else {
		[[built, output]]
	} {
		partial := gamehost.parent(pair[1]) + '/.' + pair[1].all_after_last('/') + '.partial'
		gamehost.copy_file(pair[0], partial)!
		if C.rename(partial.str, pair[1].str) != 0 { return os.error_posix() }
	}
	os.write_file(marker, key + ' ' + gamehost.digest(output)! + '\n')!
	return if venus { [output, manifest] } else { [output] }
}
