// SPDX-License-Identifier: GPL-2.0-or-later
module linuxcheck

import os
import json2

struct CxxSanitizer {
	archive string
	sha256  string
}

fn cxx_sanitizer_at(value string) !CxxSanitizer {
	if value == '' || value.contains('\x00') {
		return error('sanitized C++ modes require VINIX_IOS_LINUX_CXX_UBSAN_ARCHIVE with a compatible ARM64 static UBSan runtime')
	}
	path := os.real_path(value)
	if os.lstat(path)!.get_filetype() != .regular {
		return error('the selected C++ UBSan archive must be a regular file')
	}
	mut file := os.open(path)!
	header := file.read_bytes(8)
	file.close()
	if header.bytestr() != '!<arch>\n' || os.file_size(path) <= 8 {
		return error('the selected C++ UBSan input is not a populated static archive')
	}
	return CxxSanitizer{ archive: path, sha256: digest(path)!.sha256 }
}

fn cxx_sanitizer_profile(profile CxxProfile) !CxxSanitizer {
	if !profile.enabled || !profile.manifest.sanitizers { return CxxSanitizer{} }
	return cxx_sanitizer_at(os.getenv('VINIX_IOS_LINUX_CXX_UBSAN_ARCHIVE'))
}

fn cxx_sanitizer_unchanged(sanitizer CxxSanitizer) ! {
	if sanitizer.archive == '' { return }
	if os.lstat(sanitizer.archive)!.get_filetype() != .regular
		|| digest(sanitizer.archive)!.sha256 != sanitizer.sha256 {
		return error('the selected C++ UBSan archive changed during the capture')
	}
}

fn cxx_sanitizer_copy(sanitizer CxxSanitizer, out string) ! {
	if sanitizer.archive == '' { return }
	cxx_sanitizer_unchanged(sanitizer)!
	// Give GCC an isolated search directory containing only this selected
	// archive. An external SDK directory must not shadow unrelated libraries.
	directory := out + '/payload/cxx-sanitizer'
	os.mkdir(directory)!
	os.cp(sanitizer.archive, directory + '/libubsan.a')!
	cxx_sanitizer_copy_unchanged(sanitizer, out)!
	cxx_sanitizer_unchanged(sanitizer)!
	os.write_file(out + '/cxx-sanitizer-input.json', json2.encode(sanitizer, prettify: true))!
}

fn cxx_sanitizer_copy_unchanged(sanitizer CxxSanitizer, out string) ! {
	if sanitizer.archive == '' { return }
	path := out + '/payload/cxx-sanitizer/libubsan.a'
	if os.lstat(path)!.get_filetype() != .regular || digest(path)!.sha256 != sanitizer.sha256 {
		return error('copied C++ UBSan archive differs from its selected input')
	}
}

fn cxx_sanitizer_link_flags(sanitizer CxxSanitizer, out string) []string {
	if sanitizer.archive == '' { return []string{} }
	return ['-static-libubsan', '-L' + out + '/payload/cxx-sanitizer']
}

// The low-level RTTI implementation cannot instrument its own vptr queries:
// the vptr checker calls that same RTTI. These separate caller controls prove
// that the exception did not disable vptr or function-type checks in clients.
fn cxx_sanitizer_controls(profile CxxProfile, sanitizer CxxSanitizer, out string,
	cc string, sysroot string, invocation []string, build_env map[string]string,
	run_env map[string]string) ! {
	if sanitizer.archive == '' {
		return error('C++ sanitizer controls require the static UBSan profile')
	}
	compiler := os.find_abs_path_of_executable(profile.manifest.compiler)!
	if digest(compiler)!.sha256 != profile.manifest.compiler_sha256 {
		return error('GNU C++ compiler differs from the selected backend build')
	}
	source := out + '/payload/gnu-cxx-sanitizer-control.cpp'
	os.cp(cxx_regular(profile.root, 'gnu-cxx-sanitizer-control.cpp')!, source)!
	object := out + '/payload/gnu-cxx-sanitizer-control.o'
	mut compile := [compiler]
	compile << cxx_consumer_flags(profile)!
	compile << ['-std=c++17', '-O1', '-g', '-c', source, '-o', object]
	checked(out, 'cxx-sanitizer-control-object', compile, out, build_env)!
	binary_path := out + '/cxx-sanitizer-control'
	mut link := [cc, '-g', '-no-pie', '-fsanitize=address,undefined']
	link << cxx_sanitizer_link_flags(sanitizer, out)
	if sysroot != '' { link << '--sysroot=' + sysroot }
	link << object
	link << cxx_link(profile)
	link << ['-pthread', '-ldl', '-lm', '-o', binary_path]
	checked(out, 'cxx-sanitizer-control-link', link, out, build_env)!
	target_executable := require_arm64_executable(binary_path)!
	os.write_file(out + '/cxx-sanitizer-executable.json', json2.encode(target_executable, prettify: true))!
	cxx_verify_linkage(out, 'cxx-sanitizer-control', binary_path, build_env)!
	mut command := invocation[..invocation.len - 1].clone()
	command << binary_path
	valid := checked_arm64_exit(target_executable, out, 'cxx-sanitizer-valid', [...command, 'valid'], out, run_env, 37)!
	if valid.split_into_lines().filter(it == 'IOS-CXX-SANITIZER-CONTROL: valid virtual and function calls').len != 1 {
		return error('C++ sanitizer positive control omitted its completed operations')
	}
	for mode in ['vptr', 'function'] {
		code, output := guarded_arm64_command(target_executable, out, 'cxx-sanitizer-' + mode, [...command, mode],
			out, run_env, 60)!
		expected := if mode == 'vptr' {
			'does not point to an object of type'
		} else {
			'through pointer to incorrect function type'
		}
		if code != 1 || !output.contains('runtime error:') || !output.contains(expected)
			|| output.contains('ERROR: AddressSanitizer') {
			return error('C++ ' + mode + ' sanitizer control did not reject its specific violation')
		}
	}
	if digest(compiler)!.sha256 != profile.manifest.compiler_sha256 {
		return error('GNU C++ compiler changed while compiling sanitizer controls')
	}
}
