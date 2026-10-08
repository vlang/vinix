// SPDX-License-Identifier: GPL-2.0-or-later
module qemubuild

import buildcore
import crypto.sha256
import fixturehost
import hosttest
import json2
import math.big
import os
import transcriptcore

fn C.fflush(voidptr) i32

fn announce(text string) {
	println(text)
	C.fflush(unsafe { nil })
}

pub const configure = ['--target-list=x86_64-linux-user', '--enable-linux-user', '--disable-system',
	'--disable-tools', '--disable-docs', '--disable-guest-agent', '--disable-bsd-user',
	'--disable-werror', '--disable-plugins', '--disable-capstone', '--disable-debug-info',
	'--disable-strip', '--static', '--cpu=aarch64', '--cross-prefix=aarch64-linux-musl-']
pub const python_packages = ['meson==1.5.0', 'tomli==2.0.1']
const endian_header = '#ifndef VINIX_QEMU_HOST_ENDIAN_H\n#define VINIX_QEMU_HOST_ENDIAN_H\n' +
	'#ifndef LITTLE_ENDIAN\n#define LITTLE_ENDIAN __ORDER_LITTLE_ENDIAN__\n#endif\n' +
	'#ifndef BIG_ENDIAN\n#define BIG_ENDIAN __ORDER_BIG_ENDIAN__\n#endif\n' +
	'#ifndef BYTE_ORDER\n#define BYTE_ORDER __BYTE_ORDER__\n#endif\n#endif\n'

pub struct BuildError {
pub:
	kind    string
	message string
}

pub fn (e BuildError) msg() string { return e.message }

pub fn (e BuildError) code() int { return 0 }

fn failed(message string) IError { return BuildError{'SystemExit', message} }

pub struct Options {
pub:
	repo                  string
	support               string
	builder               string
	work                  string
	staging               string
	base                  string
	jobs                  string
	refresh               bool
	platform              string
	host_arch             string
	python                string
	python_version        string
	environment           map[string]string
	inherited_environment map[string]string
}

fn field(row map[string]json2.Any, name string) json2.Any { return row[name] or { json2.Null{} } }

fn words(values []string) json2.Any { return json2.Any(values.map(json2.Any(it))) }

fn concat(a []string, b []string) []string {
	mut result := a.clone()
	result << b
	return result
}

fn capture(options Options, argv []string, cwd string, merge bool) !string {
	return fixturehost.capture_in_preferred(argv, '', options.inherited_environment, merge, cwd, false, options.host_arch)!
}

fn execute(options Options, argv []string, cwd string) ! {
	status := command_preferred(argv, cwd, options.inherited_environment, '', false, options.host_arch)!
	if status != 0 { return ChildFailure{status, argv.clone()} }
}

pub fn download(options Options, url string, destination string, expected string) ! {
	if exists(destination)! {
		if digest(destination)! != expected {
			return failed('cached download has an unexpected hash: ' + destination)
		}
		return
	}
	partial := destination + '.partial'
	execute(options, [tool('curl', options.environment)!, '--fail', '--location', '--retry', '3',
		'--silent', '--show-error', '--output', partial, url], '')!
	if digest(partial)! != expected {
		unlink(partial)!
		return failed('download has an unexpected hash: ' + url)
	}
	replace(partial, destination)!
}

pub fn apply_source_patch(options Options, source string, patch string) ! {
	mut argv := [tool('git', options.environment)!, 'apply', '--unsafe-paths', '--directory=' + source]
	check := command_preferred(concat(argv, ['--check', patch]), options.repo, options.inherited_environment, '', true, options.host_arch)!
	if check == 0 {
		argv << patch
		execute(options, argv, options.repo)!
	} else {
		output := capture(options, [tool('patch', options.environment)!, '--forward', '-p1', '-i',
			patch], source, true) or {
			if err is fixturehost.CommandError {
				eprintln(err.output)
			}
			return err
		}
		_ = output
	}
}

fn split_lines(value string) []string {
	mut result := []string{}
	mut start := 0
	mut offset := 0
	mut skip_lf := false
	for ch in value.runes() {
		width := ch.str().len
		if skip_lf && ch == `\n` {
			offset += width
			start = offset
			skip_lf = false
			continue
		}
		skip_lf = false
		if ch in [`\n`, `\r`, rune(11), rune(12), rune(28), rune(29), rune(30), rune(133),
			rune(0x2028), rune(0x2029)] {
			result << value[start..offset]
			start = offset + width
			skip_lf = ch == `\r`
		}
		offset += width
	}
	if start < value.len { result << value[start..] }
	return result
}

// UTF-8 replacement follows the original log.read_text(errors='replace').
fn replacement_text(raw string) string {
	mut result := raw
	mut prefix := ''
	for {
		hosttest.module_decode_utf8(result) or {
			if err is hosttest.ModuleDecodeError {
				prefix += result[..err.start] + '\ufffd'
				result = result[err.end..]
				continue
			}
			return prefix + result
		}
		return (prefix + result).replace('\r\n', '\n').replace('\r', '\n')
	}
	return prefix
}

pub fn logged(options Options, argv []string, directory string, log string, environment map[string]string) ! {
	status := command_preferred(argv, directory, environment, log, false, options.host_arch)!
	if status != 0 {
		lines := split_lines(replacement_text(read(log)!))
		eprintln(lines[if lines.len > 35 { lines.len - 35 } else { 0 }..].join('\n'))
		return failed('QEMU build failed; see ' + log)
	}
}

fn matches(source string, expected map[string]json2.Any) !bool {
	for relative, hash in expected {
		path := join(source, relative)
		if !is_file(path)! || digest(path)! != hash.str() { return false }
	}
	return true
}

fn integer_space(ch rune) bool {
	return ch in [`\t`, `\n`, `\v`, `\f`, `\r`, ` `, rune(0x85), rune(0xa0), rune(0x1680),
		rune(0x2028), rune(0x2029), rune(0x202f), rune(0x205f), rune(0x3000)] || (ch >= 0x2000 && ch <= 0x200a)
}

fn strip_space(value string) string {
	runes := value.runes()
	mut first := 0
	mut last := runes.len
	for first < last && (integer_space(runes[first]) || (runes[first] >= 0x1c && runes[first] <= 0x1f)) {
		first++
	}
	for last > first && (integer_space(runes[last - 1]) || (runes[last - 1] >= 0x1c && runes[last - 1] <= 0x1f)) {
		last--
	}
	return runes[first..last].string()
}

fn version_integer(value string) !big.Integer {
	runes := value.runes()
	mut begin := 0
	mut end := runes.len
	for begin < end && integer_space(runes[begin]) { begin++ }
	for end > begin && integer_space(runes[end - 1]) { end-- }
	mut normal := ''
	if begin < end && runes[begin] in [`+`, `-`] {
		normal += runes[begin].str()
		begin++
	}
	mut digit_ready := false
	for index in begin .. end {
		ch := runes[index]
		if ch == `_` {
			if !digit_ready || index + 1 >= end || transcriptcore.decimal_digit(runes[index + 1]) < 0 {
				return BuildError{'ValueError', 'invalid literal for int() with base 10: ' + python_repr(value)}
			}
			digit_ready = false
			continue
		}
		digit := transcriptcore.decimal_digit(ch)
		if digit < 0 {
			return BuildError{'ValueError', 'invalid literal for int() with base 10: ' + python_repr(value)}
		}
		normal += rune(digit + 48).str()
		digit_ready = true
	}
	if !digit_ready {
		return BuildError{'ValueError', 'invalid literal for int() with base 10: ' + python_repr(value)}
	}
	return big.integer_from_string(normal)!
}

fn gcc_version(path string) ![]big.Integer {
	mut values := []big.Integer{}
	for item in basename(path).split('.') {
		values << version_integer(item)!
	}
	return values
}

fn version_less(a []big.Integer, b []big.Integer) bool {
	for i in 0 .. if a.len < b.len { a.len } else { b.len } {
		if a[i] != b[i] { return a[i] < b[i] }
	}
	return a.len < b.len
}

fn gcc_library(root string) !string {
	names := os.ls(root) or {
		if err.code() in [int(C.ENOENT), int(C.ENOTDIR), int(C.EACCES)] { return '' }
		return FileError{err.code(), root}
	}
	mut selected := ''
	mut version := []big.Integer{}
	for name in names {
		candidate := gcc_version(name)!
		if selected == '' || !version_less(candidate, version) {
			selected = join(root, name)
			version = candidate.clone()
		}
	}
	return selected
}

fn policy_sources(repo string) ![]string {
	mut result := [join(repo, 'tests/dota2/_native.py'), join(repo, 'tests/dota2/transcript_query.v')]
	for path in ['build-support/dota2/buildcore', 'tests/dota2/transcriptcore',
		'tests/linuxkpi/hosttest'] {
		mut files := os.ls(join(repo, path))!
		files.sort()
		for name in files { if name.ends_with('.v') { result << join(join(repo, path), name) } }
		if path == 'tests/linuxkpi/hosttest' {
			for name in files { if name.ends_with('.h') { result << join(join(repo, path), name) } }
		}
	}
	result << [join(repo, 'build-support/find-v.sh'), join(repo, 'build-support/run-v-tool.sh')]
	return result
}

fn producer_sources(repo string) ![]string {
	mut result := [join(repo, 'build-support/dota2/qemu_builder.v')]
	for path in ['build-support/dota2/qemubuild', 'build-support/cachekey',
		'tests/qemu-core/fixturehost'] {
		mut files := os.ls(join(repo, path))!
		files.sort()
		for name in files {
			if name.ends_with('.v') || name.ends_with('.h') {
				result << join(join(repo, path), name)
			}
		}
	}
	return result
}

pub fn build(options Options) ! {
	work := resolve(options.work)!
	staging := resolve(options.staging)!
	base := resolve(options.base)!
	if !separate(work, base) {
		return BuildError{'ArgumentError', 'the native QEMU work directory must be separate from the source sysroot'}
	}
	mut clang := options.environment['VINIX_DOTA2_QEMU_CLANG'] or { '/opt/homebrew/opt/llvm/bin/clang' }
	if !is_file(clang)! { clang = tool('clang', options.environment)! }
	cc_default := tool('cc', options.environment)!
	host_cc := options.environment['VINIX_DOTA2_QEMU_HOST_CC'] or { cc_default }
	gcc := gcc_library(join(options.repo, 'build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl'))!
	if gcc == '' { return failed('the AArch64 userland GCC support library is missing') }
	atomic_library := join(options.repo, 'build-aarch64-userland/staging/usr/lib/libatomic.a')
	for path in [join(base, 'usr/include/elf.h'), join(base, 'usr/lib/libc.a'), atomic_library,
		join(gcc, 'libgcc.a')] {
		if !is_file(path)! {
			return failed('the native X11 sysroot or AArch64 static compiler libraries are incomplete')
		}
	}
	configuration := hosttest.decode_json(read_text(join(options.support, 'inputs.json'))!)!.as_map()
	mut patches := []string{}
	for raw in field(configuration, 'alpine_patches').as_array() {
		patch := raw.as_map()
		path := join(options.support, field(patch, 'path').str())
		patches << path
		if digest(path)! != field(patch, 'sha256').str() {
			return failed('the inherited Alpine patch has an unexpected hash: ' + path)
		}
	}
	for name in ['noreplace.patch', 'wake-op.patch', 'internal-fault.patch', 'drm-passthrough.patch'] {
		patches << join(options.support, name)
	}
	mut static_inputs := map[string]bool{}
	for root in [base, gcc] {
		for path in paths(root)! {
			if path.ends_with('.a') && is_file(path)! { static_inputs[path] = true }
		}
	}
	for root in [join(base, 'usr/lib'), gcc] {
		for name in os.ls(root)! {
			crt := if root == gcc { name.starts_with('crt') } else { name.contains('crt') }
			path := join(root, name)
			if crt && name.ends_with('.o') && is_file(path)! { static_inputs[path] = true }
		}
	}
	static_inputs[atomic_library] = true
	mut patch_hashes := map[string]json2.Any{}
	for path in patches { patch_hashes[path[options.support.len + 1..]] = digest(path)! }
	mut policy := map[string]json2.Any{}
	for path in policy_sources(options.repo)! {
		policy[path[options.repo.len + 1..]] = digest(path)!
	}
	mut producer := map[string]json2.Any{}
	for path in producer_sources(options.repo)! {
		producer[path[options.repo.len + 1..]] = digest(path)!
	}
	mut inputs := map[string]json2.Any{}
	inputs['configuration'] = configuration
	inputs['patches'] = patch_hashes
	inputs['builder'] = digest(options.builder)!
	inputs['configure'] = words(configure)
	inputs['native_policy'] = policy
	inputs['native_builder'] = producer
	inputs['python_packages'] = words(python_packages)
	inputs['python'] = options.python_version
	inputs['clang'] = capture(options, [clang, '--version'], '', false)!
	inputs['host_cc'] = capture(options, [host_cc, '--version'], '', false)!
	inputs['sysroot'] = base
	inputs['headers'] = tree_digest(join(base, 'usr/include'))!
	mut libraries := map[string]json2.Any{}
	mut static_paths := static_inputs.keys()
	static_paths.sort_with_compare(path_compare)
	for path in static_paths { libraries[path] = digest(path)! }
	inputs['static_libraries'] = libraries
	inputs['gcc'] = gcc
	generation := sha256.hexhash(dumps(json2.Any(inputs), true, false))
	mkdir(work, true, true)!
	downloads := join(work, 'downloads')
	mkdir(downloads, false, true)!
	source := join(work, 'qemu-' + field(configuration, 'version').str())
	build_dir := join(work, 'build')
	sysroot := join(work, 'sysroot')
	marker := join(work, '.qemu-stage-generation')
	expected := field(configuration, 'patched_source_sha256').as_map()
	current := is_file(marker)! && strip_space(read_text(marker)!) == generation && matches(source, expected)!
	if options.refresh || !current || !is_dir(source)! || !is_dir(sysroot)! {
		announce('Preparing pinned native QEMU source and development libraries')
		archive := join(downloads, 'qemu-' + field(configuration, 'version').str() + '.tar.xz')
		download(options, field(configuration, 'source_url').str(), archive, field(configuration, 'source_sha256').str())!
		mut packages := []string{}
		for raw in field(configuration, 'packages').as_array() {
			row := raw.as_map()
			package := join(downloads, field(row, 'filename').str())
			url := field(configuration, 'alpine_mirror').str() + '/' + field(row, 'repository').str() + '/aarch64/' + basename(package)
			download(options, url, package, field(row, 'sha256').str())!
			packages << package
		}
		for directory in [source, build_dir, sysroot] {
			if exists(directory)! { remove_tree(directory)! }
		}
		if options.platform == 'darwin' {
			execute(options, ['/bin/cp', '-cRp', base, sysroot], '')!
		} else {
			clone_tree(base, sysroot)!
		}
		for package in packages {
			command_preferred([tool('tar', options.environment)!, 'xzf', package, '-C', sysroot], '', options.inherited_environment, '', true, options.host_arch)!
		}
		for relative in ['usr/lib/libglib-2.0.a', 'usr/lib/libpcre2-8.a', 'usr/lib/libintl.a'] {
			if !is_file(join(sysroot, relative))! {
				return failed('the pinned development package did not install ' + relative)
			}
		}
		copy2(atomic_library, join(sysroot, 'usr/lib/libatomic.a'))!
		execute(options, [tool('tar', options.environment)!, 'xf', archive, '-C', work], '')!
		for patch in patches { apply_source_patch(options, source, patch)! }
		if !matches(source, expected)! {
			return failed('the patched QEMU source files have unexpected hashes')
		}
		mkdir(build_dir, false, false)!
		write(marker, generation + '\n')!
	}
	mkdir(build_dir, false, true)!
	includes := join(work, 'host-include')
	mkdir(includes, false, true)!
	copy2(join(sysroot, 'usr/include/elf.h'), join(includes, 'elf.h'))!
	write(join(includes, 'endian.h'), endian_header)!
	cc := join(work, 'aarch64-cc')
	host := join(work, 'host-cc')
	pkg := join(work, 'aarch64-pkg-config')
	wrapper(cc, 'exec ' + shell_quote(clang) + ' --target=aarch64-linux-musl --sysroot=' + shell_quote(sysroot) +
		' --gcc-install-dir=' + shell_quote(gcc) + ' -fuse-ld=lld -static-libgcc "$@" -Wno-unused-command-line-argument')!
	wrapper(host, 'exec ' + shell_quote(host_cc) + ' -I' + shell_quote(includes) + ' "$@"')!
	wrapper(pkg, 'export PKG_CONFIG_SYSROOT_DIR=' + shell_quote(sysroot) + '\nexport PKG_CONFIG_LIBDIR=' +
		shell_quote(join(sysroot, 'usr/lib/pkgconfig')) + '\nexec ' + shell_quote(tool('pkg-config', options.environment)!) + ' "$@"')!
	venv := join(work, 'host-venv')
	python := join(venv, 'bin/python3')
	if !exists(python)! { execute(options, [options.python, '-m', 'venv', venv], '')! }
	package_stamp := join(venv, '.dota2-packages')
	if !is_file(package_stamp)! || split_lines(read_text(package_stamp)!) != python_packages {
		execute(options, concat([python, '-m', 'pip', 'install', '--quiet'], python_packages), '')!
		write(package_stamp, python_packages.join('\n') + '\n')!
	}
	mut environment := options.environment.clone()
	environment['PKG_CONFIG'] = pkg
	if !is_file(join(build_dir, 'build.ninja'))! {
		announce('Configuring the static AArch64 translator')
		logged(options, concat(concat([join(source, 'configure')], configure), [
			'--cc=' + cc,
			'--host-cc=' + host,
			'--python=' + python,
		]), build_dir, join(build_dir, 'configure.log'), environment)!
	}
	announce('Building qemu-x86_64')
	logged(options, [tool('ninja', options.environment)!, '-j', options.jobs, 'qemu-x86_64'], build_dir, join(build_dir, 'build.log'), options.inherited_environment)!
	binary := join(build_dir, 'qemu-x86_64')
	contents := read(binary)!
	dynamic := capture(options, [
		tool('aarch64-linux-musl-readelf', options.environment)!,
		'-d',
		binary,
	], '', false)!
	if !buildcore.static_translator(contents.bytes(), dynamic) {
		return failed('the translator must be a static native AArch64 ELF')
	}
	destination := join(staging, 'usr/bin/qemu-x86_64')
	mkdir(destination.all_before_last('/'), true, true)!
	partial := join(destination.all_before_last('/'), '.qemu-x86_64.partial')
	copy2(binary, partial)!
	os.chmod(partial, 0o755) or { return FileError{err.code(), partial} }
	replace(partial, destination)!
	manifest := join(staging, 'usr/libexec/vinix-dota2/qemu-build.json')
	mkdir(manifest.all_before_last('/'), true, true)!
	write(manifest, dumps(json2.Any({
		'generation':          json2.Any(generation)
		'binary_sha256':       json2.Any(digest(binary)!)
		'native_dependencies': json2.Any([]json2.Any{})
		'inputs':              json2.Any(inputs)
	}), false, true) + '\n')!
	announce('Staged patched native translator: ' + destination)
}
