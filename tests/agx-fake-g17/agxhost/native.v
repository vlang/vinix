// SPDX-License-Identifier: GPL-2.0-only
module agxhost

import fixturehost
import hosttest
import json2
import os
import encoding.hex

pub struct NativeFailure {
pub:
	kind string
	message string
}

pub fn (e NativeFailure) msg() string { return e.message }
pub fn (e NativeFailure) code() int { return 0 }

fn native_copy_file(source string, target string) ! {
	if state := os.stat(source) {
		if state.get_filetype() == .fifo {
			return NativeFailure{'SpecialFileError', '`' + source + '` is a named pipe'}
		}
		if state.get_filetype() == .directory { return hosttest.ModuleFileError{source, 21, 'Source is a directory'} }
	}
	hosttest.module_copy_file(source, target)!
}

fn native_argument_path(value string) string {
	mut prefix := ''
	if value.starts_with('/') { prefix = if value.starts_with('//') && !value.starts_with('///') { '//' } else { '/' } }
	parts := value.split('/').filter(it != '' && it != '.')
	if parts.len == 0 { return if prefix == '' { '.' } else { prefix } }
	return prefix + parts.join('/')
}

pub fn native_environment(encoded string) !map[string]string {
	bytes := hex.decode(encoded)!
	mut environment := map[string]string{}
	for item in bytes.bytestr().split('\x00') {
		if item == '' { continue }
		separator := item.index('=') or { return error('Invalid inherited environment record') }
		environment[item[..separator].clone()] = item[separator + 1..].clone()
	}
	return environment
}

fn native_mkdir(path string, parents bool, exist_ok bool) ! {
	if path.contains('\x00') { return error('embedded null byte') }
	os.mkdir(path) or {
		if err.code() == C.ENOENT && parents {
			native_mkdir(path.all_before_last('/'), true, true)!
			native_mkdir(path, false, exist_ok)!
			return
		}
		if !exist_ok || !os.is_dir(path) {
			return hosttest.ModuleFileError{path, err.code(), err.msg()}
		}
	}
}

// Path.rglob('*') emits each directory's files before descending into its
// child directories; links to directories are not followed by the walk.
fn native_input_paths(path string) ![]string {
	entries := os.ls(path) or { return hosttest.ModuleFileError{path, err.code(), err.msg()} }
	mut result := []string{}
	for name in entries {
		item := path + '/' + name
		if os.is_file(item) { result << item }
	}
	for name in entries {
		item := path + '/' + name
		if os.is_dir(item) && !os.is_link(item) { result << native_input_paths(item)! }
	}
	return result
}

pub fn (mut out Transcript) native_fixture(root string, arch string, kernel string, state_arg string,
	reference string, fixture string, timeout_text string, python string, environment map[string]string) !int {
	state := hosttest.module_resolve(state_arg) or {
		if err.msg().starts_with('Symlink loop from ') { return NativeFailure{'NativeResolveError', state_arg} }
		return err
	}
	native_mkdir(state, true, false)!
	sources := state + '/sources'
	native_mkdir(sources, false, false)!
	provider := sources + '/lib'
	native_mkdir(provider, false, false)!
	for name in ['agx_fake_g17.v', 'agx_fake_g17_encode.v'] {
		mut text := fixturehost.read(root + '/kernel/lib/' + name)!
		hosttest.module_decode_utf8(text)!
		text = text.replace('\r\n', '\n').replace('\r', '\n')
		for header in ['agx_fake_g17.h', 'agx_fake_g17_encode.h'] {
			text = text.replace('#include "' + header + '"', '#include <' + header + '>')
		}
		fixturehost.write(provider + '/' + name, text)!
	}
	for name in ['agx_fake_g17.h', 'agx_fake_g17_encode.h'] {
		native_copy_file(root + '/kernel/c/' + name, provider + '/' + name)!
	}
	fixture_name := if fixture == 'encoder' { 'encodefixture' } else { 'verifyfixture' }
	for module_name, source in {
		fixture_name: root + '/tests/agx-fake-g17/' + fixture_name
		'fixturedriver': root + '/tests/kernel-gaps/fixturedriver'
		'serialcore': root + '/tests/kernel-gaps/serialcore'
	} {
		hosttest.module_copy_tree(source, sources + '/' + module_name)!
	}
	mut cc := []string{}
	mut target := []string{}
	mut link := []string{}
	if arch == 'aarch64' {
		sysroot_arg := hosttest.env_default('VINIX_AARCH64_SYSROOT', root + '/build-aarch64-userland/sysroot')
		// pathlib.Path keeps Unix backslashes and collapses empty/dot parts.
		sysroot := native_argument_path(sysroot_arg)
		cc = hosttest.shell_split(hosttest.env_default('CC', 'clang'))!
		target = ['--target=aarch64-linux-musl', '--sysroot=' + sysroot]
		link = ['-L' + (if sysroot == '.' { 'lib' } else if sysroot in ['/', '//'] { sysroot + 'lib' } else { sysroot + '/lib' }), '-fuse-ld=lld']
	} else {
		cc = hosttest.shell_split(hosttest.env_default('CC_AMD64', 'x86_64-linux-musl-gcc'))!
	}
	flags := [...cc, ...target, '-O2', '-Wall', '-Wextra', '-Werror', '-D_GNU_SOURCE', '-fno-stack-protector', '-fno-strict-aliasing']
	mut objects := []string{}
	for module_name in ['lib', fixture_name, 'fixturedriver', 'serialcore'] {
		object := state + '/' + module_name + '.o'
		if module_name == fixture_name && reference != '' {
			original := sources + '/original.c'
			native_copy_file(reference, original)!
			out.command([...flags, '-iquote', root + '/tests/agx-fake-g17', '-Dmain=vinix_independent_fixture', '-c', original, '-o', object], environment)!
		} else {
			mut extra := if module_name == fixture_name {
				['-Dmain=vinix_independent_fixture', '-iquote', provider]
			} else { []string{} }
			if module_name == 'lib' { extra = ['-DVINIX_V_RUNTIME', '-ffreestanding', '-fno-builtin'] }
			out.compile_module_environment(sources + '/' + module_name, object, arch, [...flags, ...extra], environment)!
		}
		imports := out.capture_output([hosttest.env_default('NM', 'nm'), '-u', object], environment)!
		scale := module_name == fixture_name && fixture == 'verifier'
		if forbidden_imports(imports, scale) { return NativeFailure{'RuntimeError', 'unexpected allocator import: ' + imports} }
		if scale && reference == '' {
			generated := fixturehost.read(hosttest.replace_suffix(object, '.c'))!
			hosttest.module_decode_utf8(generated)!
			if allocation_call_count(generated, 'calloc') != 1 || allocation_call_count(generated, 'free') != 1 {
				return NativeFailure{'RuntimeError', 'G17 verifier fixture changed its original allocation ownership'}
			}
		}
		objects << object
	}
	executable := state + '/init'
	out.command([...cc, ...target, '-static', '-O2', ...objects, ...link, '-o', executable], environment)!
	mut inputs := map[string]json2.Any{}
	for path in native_input_paths(sources)! { inputs[path[state.len + 1..]] = hosttest.sha(path)! }
	fixturehost.write_receipt(state + '/native-inputs.json', json2.Any({
		'scope': json2.Any('unchanged production G17 policy and original independent ' + fixture + ' oracle')
		'arch': json2.Any(arch)
		'inputs': json2.Any(inputs)
		'init_sha256': json2.Any(hosttest.sha(executable)!)
	}))!
	argv := [python, root + '/tests/kernel-gaps/run.py', '--arch', arch, '--kernel-dir', kernel,
		'--prebuilt-init', executable, '--state-dir', state + '/guest', '--timeout', timeout_text,
		'--expect', 'INDEPENDENT FIXTURE PASS', '--expect', if fixture == 'encoder' {
			'fake G17 recovered 3D encoder tests passed'
		} else { 'fake G17 HAL300 verifier tests passed' }, '--fail', 'INDEPENDENT FIXTURE FAIL', '--fail', 'check failed at line']
	out.command(argv, environment) or {
		if err is fixturehost.CommandError { return err.status }
		if err is CommandFailure { return err.result.code }
		return err
	}
	return 0
}
