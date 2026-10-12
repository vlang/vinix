// SPDX-License-Identifier: GPL-2.0-or-later
module allocationhost

import generators
import hosttest
import json2
import os

pub const darwin_flags = ['-mkernel', '-fno-pie', '-fno-PIC', '-mmacosx-version-min=10.15']

pub struct KextOptions {
pub:
	gcc              string = 'gcc-mp-14'
	library_path     string
	has_library_path bool
	state            string
	vm_config        string
}

pub fn bundle_info() map[string]json2.Any {
	return {
		'CFBundleDevelopmentRegion':     json2.Any('English')
		'CFBundleExecutable':            json2.Any('AllocKernelBench')
		'CFBundleIdentifier':            json2.Any('org.vinix.AllocKernelBench')
		'CFBundleInfoDictionaryVersion': json2.Any('6.0')
		'CFBundleName':                  json2.Any('AllocKernelBench')
		'CFBundlePackageType':           json2.Any('KEXT')
		'CFBundleShortVersionString':    json2.Any('1.0.0')
		'CFBundleVersion':               json2.Any('1.0.0')
		'OSBundleRequired':              json2.Any('Root')
		'OSBundleLibraries':             json2.Any({
			'com.apple.kpi.libkern': json2.Any('8.0.0')
			'com.apple.kpi.iokit':   json2.Any('8.0.0')
		})
	}
}

fn xml_escape(text string) string {
	return text.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
}

fn xml_dict(fields map[string]json2.Any, indent int) !string {
	tabs := '\t'.repeat(indent)
	mut output := tabs + '<dict>\n'
	mut keys := fields.keys()
	keys.sort()
	for key in keys {
		output += tabs + '\t<key>' + xml_escape(key) + '</key>\n'
		value := fields[key]!
		if value is map[string]json2.Any {
			output += xml_dict(value, indent + 1)!
		} else if value is string {
			output += tabs + '\t<string>' + xml_escape(value) + '</string>\n'
		} else {
			return error('unsupported bundle property type')
		}
	}
	return output + tabs + '</dict>\n'
}

pub fn bundle_plist() !string {
	return '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n' + xml_dict(bundle_info(), 0)! + '</plist>\n'
}

pub fn build_kext(options KextOptions) !string {
	gcc := os.find_abs_path_of_executable(options.gcc) or { return InputError{'GCC executable not found: ' + options.gcc} }
	mut env := os.environ()
	if options.library_path != '' { env['DYLD_LIBRARY_PATH'] = options.library_path }
	// /dev/null supplies the original probe's empty input without borrowing
	// an interactive caller's stdin. GCC still preprocesses a C translation unit.
	macros := capture([gcc, '-dM', '-E', '-x', 'c', '/dev/null'], env, -1)!
	if macros.status != 0 {
		return error('GCC macro probe failed: ' + macros.stdout + macros.stderr)
	}
	eprint(macros.stderr)
	if !macros.stdout.contains('#define __GNUC__ ') || macros.stdout.contains('#define __clang__ ') {
		return InputError{'the C compiler must be GNU GCC; Apple /usr/bin/gcc is Clang'}
	}
	if !macros.stdout.contains('#define __APPLE__ ') || !macros.stdout.contains('#define __x86_64__ ') {
		return InputError{'GCC must target x86_64 Apple Darwin for this diagnostic kext'}
	}
	version := capture([gcc, '--version'], env, -1)!
	if version.status != 0 {
		return error('GCC version probe failed: ' + version.stdout + version.stderr)
	}
	eprint(version.stderr)
	compiler_version := first_line(version.stdout)!
	header_result := capture([gcc, '-print-file-name=include'], env, -1)!
	if header_result.status != 0 {
		return error('GCC header probe failed: ' + header_result.stdout + header_result.stderr)
	}
	eprint(header_result.stderr)
	includes := header_result.stdout.trim_space()
	if !os.is_dir(includes) { return InputError{'GCC intrinsic headers not found: ' + includes} }
	work := hosttest.work_dir(if options.state == '' { '.' } else { options.state }, 'vinix-alloc-kext-')!
	bundle := work + '/AllocKernelBench.kext'
	executable := bundle + '/Contents/MacOS/AllocKernelBench'
	make_dirs(os.dir(executable))!
	os.write_file(bundle + '/Contents/Info.plist', bundle_plist()!)!
	generated := work + '/heap_benchmark.c'
	generators.generate_sampler(generated, 'amd64', false)!
	os.cp(root() + '/kernel/c/heap_benchmark_v.h', work + '/heap_benchmark_v.h')!
	metadata := work + '/macos-kext-info.c'
	generators.generate_metadata(metadata, 'amd64')!
	mut commands := []json2.Any{}
	mut objects := []string{}
	log := work + '/build.log'
	os.write_file(log, '')!
	for source in [generated, metadata] {
		assembly := hosttest.replace_suffix(source, '.s')
		object := hosttest.replace_suffix(source, '.o')
		for command in [
			[gcc, ...kernel_flags, ...darwin_flags, '-nostdinc', '-isystem', includes, '-S', source,
				'-o', assembly],
			['xcrun', 'clang', '-target', 'x86_64-apple-macos10.15', '-mkernel', '-mno-red-zone',
				'-c', assembly, '-o', object],
		] {
			commands << json2.Any(command.map(json2.Any(it)))
			logged(command, env, log, true, '', -1)!
		}
		objects << object
	}
	link := ['xcrun', 'ld', '-arch', 'x86_64', '-kext', '-undefined', 'dynamic_lookup', '-no_uuid',
		...objects, '-o', executable]
	commands << json2.Any(link.map(json2.Any(it)))
	logged(link, os.environ(), log, true, '', -1)!
	mut manifest := if options.vm_config != '' {
		hosttest.decode_json(os.read_file(options.vm_config)!)!.as_map().clone()
	} else {
		map[string]json2.Any{}
	}
	identity := os.uname()
	for key, value in {
		'compile_flags':             json2.Any(kernel_flags.map(json2.Any(it)))
		'platform_compile_flags':    json2.Any(darwin_flags.map(json2.Any(it)))
		'source_sha256':             json2.Any(digest(generated)!)
		'adapter_sha256':            json2.Any(digest(metadata)!)
		'metadata_language':         json2.Any('V')
		'metadata_source_sha256':    json2.Any(digest(here() + '/kmodmeta/core.v')!)
		'metadata_generator_sha256': json2.Any(digest(root() + '/tests/native-generators/generators/metadata.v')!)
		'metadata_initialization':   json2.Any('static native data; compiler aggregate initializer promoted before loading')
		'sampler_header_sha256':     json2.Any(digest(work + '/heap_benchmark_v.h')!)
		'sampler_language':          json2.Any('V')
		'compiler':                  json2.Any(compiler_version)
		'build_commands':            json2.Any(commands)
		'compiler_library_path':     if options.has_library_path {
			json2.Any(options.library_path)
		} else {
			json2.Any(json2.Null{})
		}
		'execution_context':         json2.Any('kext')
		'arch':                      json2.Any('x86_64')
		'build_method':              json2.Any('V generated C; GNU GCC C-to-assembly; Apple assembler/linker')
		'compilation_host':          json2.Any({
			'system':  json2.Any(identity.sysname)
			'release': json2.Any(identity.release)
			'machine': json2.Any(identity.machine)
		})
		'binary_sha256':             json2.Any(digest(executable)!)
	} {
		manifest[key] = value
	}
	write_json(work + '/config.json', manifest)!
	println(bundle)
	return bundle
}
