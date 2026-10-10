// SPDX-License-Identifier: ISC
module main

import fixturehost
import crypto.sha256
import hosttest
import json2
import encoding.hex
import os

fn C.dup2(i32, i32) i32
fn C.close(i32) i32
fn C.fcntl(i32, i32, ...i32) i32
fn C.write(i32, voidptr, usize) isize
fn C.open(&char, i32, ...i32) i32

const original_revision = '09e70d945ca7d63ebc4969213994afab9e7e1dbe'
const quiet = ['-Wno-unused-function', '-Wno-unused-parameter', '-Wno-unused-label', '-fwrapv', '-fno-strict-aliasing']

struct Config {
	env map[string]string
	text_encoding string
	root string
	work string
	host_arch string
	caller_arch string
	arch string
	build_only bool
	kernel string
	guest string
}

fn join(groups ...[]string) []string {
	mut result := []string{}
	for group in groups { result << group }
	return result
}

// POSIX Path preserves literal backslashes in caller-supplied paths.
fn append_path(parent string, name string) string {
	return if parent == '.' { name } else { parent.trim_right('/') + '/' + name }
}

fn (c Config) path(name string) string { return append_path(c.root, name) }
fn (c Config) output(name string) string { return append_path(c.work, name) }

fn (c Config) inherited(argv []string) ! {
	fixturehost.inherited_command_environment_preferred(argv, c.env, c.caller_arch)!
}

fn (c Config) capture(argv []string, directory string, binary bool) !string {
	closed_stdout := C.fcntl(1, C.F_GETFD) < 0
	if closed_stdout {
		descriptor := C.open(c'/dev/null', C.O_WRONLY)
		if descriptor < 0 { return error('Cannot reserve captured stdout') }
		if descriptor != 1 {
			if C.dup2(descriptor, 1) < 0 {
				C.close(descriptor)
				return error('Cannot reserve captured stdout')
			}
			C.close(descriptor)
		}
	}
	defer { if closed_stdout { C.close(1) } }
	return fixturehost.capture_in_preferred(argv, '', c.env, false, directory, binary, c.caller_arch)!
}

fn strings(values []string) json2.Any { return json2.Any(hosttest.strings(values)) }
fn hashes(path string) !string { return hosttest.sha(path)! }
fn hashes_text(text string) string { return sha256.hexhash(text) }

fn json_write(path string, value json2.Any) ! {
	fixturehost.write(path, json2.encode(value,
		prettify: true
		indent_string: '  '
		escape_unicode: true
	) + '\n')!
}

// Original Git oracle line counts use bytes.splitlines, whose separators are
// CR, LF and CRLF only. Text nm output uses str.splitlines below.
fn byte_lines(text string) int {
	mut count := 0
	mut start := 0
	mut index := 0
	for index < text.len {
		if text[index] in [`\r`, `\n`] {
			count++
			if text[index] == `\r` && index + 1 < text.len && text[index + 1] == `\n` { index++ }
			start = index + 1
		}
		index++
	}
	return count + if start < text.len { 1 } else { 0 }
}

fn text_lines(text string) []string {
	mut values := []string{}
	mut value := ''
	mut skip_lf := false
	for ch in text.runes() {
		if skip_lf && ch == `\n` { skip_lf = false; continue }
		skip_lf = false
		if ch in [`\n`, `\r`, rune(11), rune(12), rune(28), rune(29), rune(30), rune(133), rune(0x2028), rune(0x2029)] {
			values << value
			value = ''
			skip_lf = ch == `\r`
		} else { value += ch.str() }
	}
	if value != '' { values << value }
	return values
}

// Preserve the original regex's Unicode word boundaries and optional single
// leading underscore, including new_array followed by zero or more word chars.
fn imports_forbidden(text string, fixture bool) bool {
	mut word := ''
	for ch in (text + ' ').runes() {
		if hosttest.module_word_rune(ch) { word += ch.str(); continue }
		name := if word.starts_with('_') { word[1..] } else { word }
		if name in ['malloc', 'realloc', 'memdup', 'v_malloc'] || name.starts_with('new_array') || (!fixture && name in ['calloc', 'free']) { return true }
		word = ''
	}
	return false
}

fn (c Config) audit(path string, fixture bool, nm string) !json2.Any {
	// Preserve Python text=True default locale, UTF-8 mode and newline decoding.
	// Only the allocation policy below is native; this decoding leaf is zero credit.
	decode := 'import json,subprocess,sys;value=subprocess.check_output(sys.argv[2:],text=True,encoding=sys.argv[1]);sys.stdout.buffer.write(json.dumps(value).encode("ascii"))'
	wire := c.capture(['python3', '-c', decode, c.text_encoding, nm, '-u', path], '', true)!
	imports := hosttest.decode_json(wire)!.str()
	if imports_forbidden(imports, fixture) { return error('Allocator imports: ' + imports) }
	return strings(text_lines(imports))
}

fn metadata(here string, name string) string {
	path := append_path(here, name)
	return if os.exists(path) { path } else { path + '.pending' }
}

fn (c Config) provider(name string, arch string) ! {
	c.inherited(['python3', c.path('tests/m1-wifi/compile-provider.py'), c.output(name + '.c'), '--kind', 'platform', '--arch', arch])!
}

fn (c Config) fixture(name string, arch string, guest bool) ! {
	mut argv := ['python3', c.path('tests/m1-wifi/compile-fixture.py'), '--entry']
	if guest { argv << '--guest' }
	argv << ['--kind', 'platform', '--arch', arch]
	argv << c.output(name + '.c')
	c.inherited(argv)!
}

fn allocation_sites(text string, name string) int {
	mut count := 0
	chars := text.runes()
	mut index := 0
	for index < chars.len {
		if !hosttest.module_word_rune(chars[index]) { index++; continue }
		start := index
		for index < chars.len && hosttest.module_word_rune(chars[index]) { index++ }
		if index < chars.len && chars[index] == `(` && chars[start..index].string() == name { count++ }
	}
	return count
}

fn test_markers(text string) []string {
	mut markers := []string{}
	for line in text.split("\n") {
		if !line.starts_with('fn test_') { continue }
		chars := line['fn test_'.len..].runes()
		mut end := 0
		for end < chars.len && hosttest.module_word_rune(chars[end]) { end++ }
		if end > 0 && end < chars.len && chars[end] == `(` {
			markers << 'PASS test_' + chars[..end].string()
		}
	}
	return markers
}

fn (c Config) host() !map[string]json2.Any {
	here := c.path('tests/m1-wifi')
	original_directory := c.output('original')
	original := c.capture(['git', 'show', original_revision + ':tests/m1-wifi/platform_test.c'], c.root, true)!
	os.mkdir(original_directory)!
	fixturehost.write(append_path(original_directory, 'platform_test.c'), original)!
	original_header := c.capture(['git', 'show', original_revision + ':tests/m1-wifi/platform_fixture.h'], c.root, true)!
	fixturehost.write(append_path(original_directory, 'platform_fixture.h'), original_header)!
	provider := c.path('kernel/apple/wifi/m1core/core.v')
	hosttest.module_copy_file(metadata(here, 'platform-native-abi.h'), c.output('platform-native-abi.h'))!
	hosttest.module_copy_file(append_path(here, 'platform_fixture.h'), c.output('platform_fixture.h'))!
	provider_sha := hashes(provider)!
	mut providers := map[string]json2.Any{}
	for path in ['kernel/apple/wifi/wificore/core.v', 'kernel/apple/wifi/m1core/core.v', 'tests/m1-wifi/platform_fixture.v'] {
		providers[path] = hashes(c.path(path))!
	}
	mut receipt := map[string]json2.Any{
		'original_revision': json2.Any(original_revision)
		'original_sha256': json2.Any(hashes_text(original))
		'original_lines': json2.Any(byte_lines(original))
		'provider_sha256': json2.Any(provider_sha)
		'host_arch': json2.Any(c.host_arch)
		'original_header_sha256': json2.Any(hashes_text(original_header))
		'provider_sources': json2.Any(providers)
	}
	mut files := os.ls(append_path(here, 'platformfixture'))!
	files.sort()
	mut sources := map[string]json2.Any{}
	for name in files {
		if name.ends_with('.v') || name.ends_with('.v.pending') {
			key := if name.ends_with('.pending') { name[..name.len - '.pending'.len] } else { name }
			sources[key] = hashes(append_path(here, 'platformfixture/' + name))!
		}
	}
	receipt['V_sources'] = sources
	c.provider('core', c.host_arch)!
	c.fixture('fixture', c.host_arch, false)!
	quotes := ['-iquote', c.path('kernel/c'), '-iquote', here]
	mut host := [hosttest.env_default('CC', 'clang')]
	$if darwin { host << ['-arch', if c.host_arch == 'arm64' { 'arm64' } else { 'x86_64' }] }
	host << ['-std=gnu11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined', '-fno-omit-frame-pointer']
	for name in ['core', 'fixture'] {
		extra := if name == 'core' { ['-DVINIX_V_RUNTIME', '-ffreestanding', '-fno-builtin'] } else { []string{} }
		c.inherited(join(host, quiet, quotes, ['-iquote', c.work], extra, ['-c', c.output(name + '.c'), '-o', c.output(name + '.o')]))!
		receipt[name + '_imports'] = c.audit(c.output(name + '.o'), name == 'fixture', 'nm')!
	}
	c.inherited(join(host, quotes, [append_path(original_directory, 'platform_test.c'), c.output('core.o'), '-o', c.output('original-host')]))!
	c.inherited(join(host, [c.output('fixture.o'), c.output('core.o'), '-o', c.output('v-host')]))!
	mut env := c.env.clone()
	env['UBSAN_OPTIONS'] = 'halt_on_error=1'
	expected := fixturehost.capture_in_preferred([c.output('original-host')], '', env, false, '', true, c.caller_arch)!
	actual := fixturehost.capture_in_preferred([c.output('v-host')], '', env, false, '', true, c.caller_arch)!
	if actual != expected { return error('Original/V platform output mismatch') }
	fixturehost.write(c.output('original.stdout'), expected)!
	fixturehost.write(c.output('v.stdout'), actual)!
	if actual != '8 platform policy groups passed (simulated MMIO, not hardware)\n' { return error('Unexpected platform golden output') }
	generated := hosttest.module_read_text(c.output('fixture.c'))!
	mut sites := map[string]json2.Any{}
	for name in ['posix_memalign', 'free'] { sites[name] = allocation_sites(generated, name) }
	if (sites['posix_memalign']!).int() != 2 || (sites['free']!).int() != 2 { return error('Changed platform allocation ownership sites') }
	receipt['explicit_allocation_sites'] = sites
	receipt['stdout'] = actual
	receipt['fixture_generated_sha256'] = hashes_text(generated)
	json_write(c.output('validation.json'), json2.Any(receipt))!
	return {'receipt': json2.Any(receipt), 'text': json2.Any(actual)}
}

fn (c Config) native_build(receipt map[string]json2.Any, actual string) !string {
	quotes := ['-iquote', c.path('kernel/c'), '-iquote', c.path('tests/m1-wifi')]
	native_arch := if c.arch == 'aarch64' { 'arm64' } else { 'amd64' }
	c.provider('core-native', native_arch)!
	c.fixture('fixture-native', native_arch, true)!
	cc := if c.arch == 'aarch64' {
		gcc_root := c.path('build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl')
		mut versions := os.ls(gcc_root)!
		versions.sort()
		if versions.len == 0 { return error('No AArch64 GCC runtime') }
		[hosttest.env_default('CC_AARCH64', '/opt/homebrew/opt/llvm/bin/clang'), '--target=aarch64-linux-musl', '--sysroot=' + c.path('build-aarch64-userland/sysroot'), '--gcc-install-dir=' + append_path(gcc_root, versions.last())]
	} else { [hosttest.env_default('CC_AMD64', '/opt/homebrew/Cellar/musl-cross/0.9.11/libexec/bin/x86_64-linux-musl-gcc')] }
	flags := join(['-std=gnu11', '-O2', '-g', '-Wall', '-Wextra', '-Werror'], quiet, quotes, ['-iquote', c.work])
	mut imports := map[string]json2.Any{}
	for name in ['core-native', 'fixture-native'] {
		mut extra := if name == 'core-native' { ['-DVINIX_V_RUNTIME', '-ffreestanding', '-fno-builtin'] } else { []string{} }
		if name == 'core-native' && c.arch == 'x86_64' { extra << '-Wno-array-parameter' }
		c.inherited(join(cc, flags, extra, ['-c', c.output(name + '.c'), '-o', c.output(name + '.o')]))!
		imports[name] = c.audit(c.output(name + '.o'), name == 'fixture-native', '/opt/homebrew/opt/llvm/bin/llvm-nm')!
	}
	serial := c.output('serial.o')
	serial_call := 'import runpy,sys,json;runpy.run_path(sys.argv[1])["compile_serial"](sys.argv[2],sys.argv[3],json.loads(sys.argv[4]))'
	c.inherited(['python3', '-c', serial_call, c.path('tests/kernel-gaps/compile-v-fixture.py'), serial, c.arch, json2.encode(join(cc, flags))])!
	linker := if c.arch == 'aarch64' { ['-fuse-ld=lld'] } else { []string{} }
	init := c.output('native-init')
	c.inherited(join(cc, linker, ['-static', c.output('fixture-native.o'), c.output('core-native.o'), serial, '-o', init]))!
	mut markers := test_markers(hosttest.module_read_text(metadata(c.path('tests/m1-wifi/platformfixture'), 'tests.v'))!)
	markers << text_lines(actual)
	if markers.len != 9 { return error('Expected nine native platform markers') }
	mut command := ['python3', c.path('tests/kernel-gaps/run.py'), '--arch', c.arch, '--prebuilt-init', init, '--kernel-dir', c.kernel, '--state-dir', c.guest, '--no-network', '--timeout', '3600']
	for marker in markers { command << ['--expect', marker] }
	json_write(c.output('native-inputs.json'), json2.Any({'arch': json2.Any(c.arch), 'provider_sha256': receipt['provider_sha256']!, 'object_imports': json2.Any(imports), 'fixture_sha256': json2.Any(hashes(init)!), 'kernel_sha256': json2.Any(hashes(append_path(c.kernel, 'bin/vinix'))!), 'expected_markers': strings(markers), 'command': strings(command)}))!
	if !c.build_only { c.inherited(command)!; return 'PASS all 8 native M1 MMIO policy groups ' + c.arch }
	return 'PASS strict native M1 MMIO fixture objects/ELF ' + c.arch
}

fn (c Config) phase(name string, state map[string]json2.Any) !map[string]json2.Any {
	if name == 'host' { return c.host()! }
	if name == 'native' { return {'text': json2.Any(c.native_build(state['receipt']!.as_map(), state['text']!.str())!)} }
	return error('Unknown platform phase')
}

fn main() {
	parsed := hosttest.parse_arguments(os.args[1..], [
		hosttest.Option{'--phase', true, ['host', 'native']}, hosttest.Option{'--parent-stdin', true, []}, hosttest.Option{'--parent-stdout', true, []},
		hosttest.Option{'--root', true, []}, hosttest.Option{'--work', true, []},
		hosttest.Option{'--host-arch', true, ['arm64', 'amd64']}, hosttest.Option{'--caller-arch', true, ['arm64', 'amd64']},
		hosttest.Option{'--arch', true, ['aarch64', 'x86_64']}, hosttest.Option{'--build-only', false, []},
		hosttest.Option{'--kernel-dir', true, []}, hosttest.Option{'--guest-state-dir', true, []},
	], 0, 'Wi-Fi platform fixture controller', 'Validated original argparse frontend options') or { eprintln(err); exit(2) }
	v := parsed.options
	if '--root' !in v || '--work' !in v { eprintln('Missing root/work directory'); exit(2) }
	input := fixturehost.read('/dev/stdin') or {
		eprintln(err.msg())
		exit(1)
	}
	decoded := hosttest.decode_json(input) or {
		eprintln(err.msg())
		exit(1)
	}
	row := decoded.as_map()
	state := row['state']!.as_map()
	mut caller_env := map[string]string{}
	for value in row['environment']!.as_array() {
		pair := value.as_array()
		key := hex.decode(pair[0].str()) or { eprintln(err.msg()); exit(1) }
		data := hex.decode(pair[1].str()) or { eprintln(err.msg()); exit(1) }
		caller_env[key.bytestr()] = data.bytestr()
	}
	c := Config{env: caller_env, text_encoding: row['text_encoding']!.str(), root: v['--root'], work: v['--work'], host_arch: v['--host-arch'], caller_arch: v['--caller-arch'], arch: v['--arch'], build_only: '--build-only' in v, kernel: v['--kernel-dir'], guest: v['--guest-state-dir']}
	protocol := C.fcntl(1, C.F_DUPFD_CLOEXEC, 3)
	if protocol < 0 {
		eprintln('Unable to retain response descriptor')
		exit(1)
	}
	defer { C.close(protocol) }
	for number, name in ['--parent-stdin', '--parent-stdout'] {
		descriptor := (v[name] or {
			eprintln('Missing parent descriptor')
			exit(2)
		}).int()
		if descriptor >= 0 {
			if C.dup2(i32(descriptor), i32(number)) < 0 {
				eprintln('Unable to restore parent descriptor')
				exit(1)
			}
			C.close(i32(descriptor))
		} else {
			C.close(i32(number))
		}
	}
	phase := v['--phase'] or {
		eprintln('Missing phase')
		exit(2)
	}
	result := c.phase(phase, state) or {
		eprintln(err.msg())
		exit(1)
	}
	response := json2.encode(json2.Any(result))
	mut offset := 0
	for offset < response.len {
		count := C.write(protocol, unsafe { response.str + offset }, usize(response.len - offset))
		if count < 0 {
			if C.errno == C.EINTR { continue }
			eprintln('Unable to write controller response')
			exit(1)
		}
		if count == 0 {
			eprintln('Empty controller response write')
			exit(1)
		}
		offset += int(count)
	}
}
