// SPDX-License-Identifier: GPL-2.0-only
module main

import applehost
import fixturehost
import hosttest
import json2
import os

fn C.fflush(voidptr) i32

const original_revision = 'e29fe9529b8d998d28f17ac120b27fb93902c6f6'
const hardware_only = ['kernel_read32', 'kernel_write32', 'kernel_now_us', 'kernel_delay_us',
	'kernel_clean', 'kernel_invalidate', 'kernel_power', 'vinix_apple_speakers_init']
const quiet = ['-Wno-unused-function', '-Wno-unused-parameter', '-Wno-unused-label', '-fwrapv',
	'-fno-strict-aliasing']

struct Config {
	root        string
	work        string
	host_arch   string
	caller_arch string
	arch        string
	build_only  bool
	kernel      string
	guest       string
}

fn join(groups ...[]string) []string {
	mut result := []string{}
	for group in groups { result << group }
	return result
}

fn space(ch rune) bool {
	return ch in [rune(9), rune(10), rune(11), rune(12), rune(13), rune(28), rune(29), rune(30),
		rune(31), rune(32), rune(133), rune(160), rune(0x1680), rune(0x2000), rune(0x2001),
		rune(0x2002), rune(0x2003), rune(0x2004), rune(0x2005), rune(0x2006), rune(0x2007),
		rune(0x2008), rune(0x2009), rune(0x200a), rune(0x2028), rune(0x2029), rune(0x202f),
		rune(0x205f), rune(0x3000)]
}

fn append_path(parent string, name string) string {
	return if parent == '.' { name } else { parent.trim_right('/') + '/' + name }
}

fn (c Config) path(name string) string { return append_path(c.root, name) }

fn (c Config) output(name string) string { return append_path(c.work, name) }

fn (c Config) inherited(argv []string) ! {
	fixturehost.inherited_command_environment_preferred(argv, os.environ(), c.caller_arch)!
}

fn (c Config) capture(argv []string, directory string, binary bool) !string {
	return fixturehost.capture_in_preferred(argv, '', os.environ(), false, directory, binary, c.caller_arch)!
}

fn strings(values []string) json2.Any { return json2.Any(hosttest.strings(values)) }

fn hashes(path string) !string { return hosttest.sha(path)! }

fn json_write(path string, value json2.Any) ! {
	fixturehost.write(path, json2.encode(value,
		prettify:       true
		indent_string:  '  '
		escape_unicode: true
	) + '\n')!
}

// Python 3.9 str.splitlines includes the Unicode separators used by receipts.
fn lines(text string, unicode bool) []string {
	mut values := []string{}
	mut value := ''
	mut skip_lf := false
	for ch in text.runes() {
		if skip_lf && ch == `\n` {
			skip_lf = false
			continue
		}
		skip_lf = false
		if ch in [`\n`, `\r`] || (unicode && ch in [rune(11), rune(12), rune(28), rune(29), rune(30),
			rune(133), rune(0x2028), rune(0x2029)]) {
			values << value
			value = ''
			skip_lf = ch == `\r`
		} else {
			value += ch.str()
		}
	}
	if value != '' { values << value }
	return values
}

fn imports_forbidden(text string, fixture bool) bool {
	mut word := ''
	for ch in (text + ' ').runes() {
		if hosttest.module_word_rune(ch) {
			word += ch.str()
			continue
		}
		name := if word.starts_with('_') { word[1..] } else { word }
		if name in ['calloc', 'memdup', 'v_malloc'] || name.starts_with('new_array') || (!fixture && name in [
			'malloc',
			'realloc',
			'free',
		]) {
			return true
		}
		word = ''
	}
	return false
}

fn (c Config) audit(path string, fixture bool, nm string) !json2.Any {
	imports := c.capture([nm, '-u', path], '', false)!
	if imports_forbidden(imports, fixture) { return error('Allocator imports: ' + imports) }
	return strings(lines(imports, true))
}

// Python text reads normalize universal newlines before regex and digest use.
fn text_read(path string) !string {
	text := hosttest.module_read_text(path)!
	return text.replace('\r\n', '\n').replace('\r', '\n')
}

fn (c Config) fixture(output string, arch string, guest bool) ! {
	mut argv := ['python3', c.path('tests/apple-speakers/compile-fixture.py'), '--entry']
	if guest { argv << '--guest' }
	argv << ['--arch', arch, output]
	c.inherited(argv)!
}

// Same Unicode word/space policy as re.findall(r'\b(\w+)\s*\(', source).
fn calls(text string) []string {
	chars := text.runes()
	mut result := []string{}
	mut index := 0
	for index < chars.len {
		if !hosttest.module_word_rune(chars[index]) {
			index++
			continue
		}
		start := index
		for index < chars.len && hosttest.module_word_rune(chars[index]) { index++ }
		mut next := index
		for next < chars.len && space(chars[next]) { next++ }
		if next < chars.len && chars[next] == `(` {
			name := chars[start..index].string()
			if name !in result { result << name }
		}
	}
	result.sort()
	return result
}

fn allocation_counts(text string) map[string]json2.Any {
	mut counts := map[string]json2.Any{}
	for name in ['malloc', 'realloc', 'aligned_alloc', 'free'] {
		mut count := 0
		chars := text.runes()
		mut index := 0
		for index < chars.len {
			if !hosttest.module_word_rune(chars[index]) {
				index++
				continue
			}
			start := index
			for index < chars.len && hosttest.module_word_rune(chars[index]) { index++ }
			if index < chars.len && chars[index] == `(` && chars[start..index].string() == name {
				count++
			}
		}
		counts[name] = count
	}
	return counts
}

fn group_names(text string) []string {
	mut groups := []string{}
	for line in text.split('\n') {
		if !line.starts_with('fn test_') { continue }
		chars := line[8..].runes()
		mut count := 0
		for count < chars.len && hosttest.module_word_rune(chars[count]) { count++ }
		if count > 0 && count < chars.len && chars[count] == `(` {
			groups << chars[..count].string()
		}
	}
	return groups
}

fn (c Config) execute() ! {
	here := c.path('tests/apple-speakers')
	reference := c.output('original')
	os.mkdir(reference)!
	mut receipt := map[string]json2.Any{
		'original_revision': json2.Any(original_revision)
		'originals':         json2.Any(map[string]json2.Any{})
		'host_arch':         json2.Any(c.host_arch)
	}
	mut sources := map[string]json2.Any{}
	mut model_files := os.ls(append_path(here, 'model'))!
	model_files.sort()
	for name in model_files {
		if name.ends_with('.v') { sources[name] = hashes(append_path(here, 'model/' + name))! }
	}
	receipt['V_sources'] = sources
	mut metadata := map[string]json2.Any{}
	for name in ['core_fixture.h', 'fixture-native-abi.h'] {
		metadata[name] = hashes(append_path(here, name))!
	}
	receipt['metadata'] = metadata
	mut originals := map[string]json2.Any{}
	for name in ['test.c', 'core_fixture.h'] {
		raw := c.capture(['git', 'show', original_revision + ':tests/apple-speakers/' + name], c.root, true)!
		path := append_path(reference, name)
		fixturehost.write(path, raw)!
		originals[name] = json2.Any({
			'sha256': json2.Any(hashes(path)!)
			'lines':  json2.Any(lines(raw, false).len)
		})
	}
	receipt['originals'] = originals
	for name in ['fixture-native-abi.h', 'core_fixture.h'] {
		fixturehost.write(c.output(name), os.read_file(append_path(here, name))!)!
	}
	receipt['host_provider'] = applehost.copy_provider(c.root, c.output('spkcore'), 'speaker', false, c.host_arch == 'arm64')!
	hosttest.generate_module(c.output('spkcore'), c.output('core.c'), c.host_arch, ['nofloat'])!
	c.fixture(c.output('fixture.c'), c.host_arch, false)!
	c.inherited(['python3', c.path('tests/apple-ans/compile-fixture.py'), '--kind', 'platform',
		'--arch', c.host_arch, c.output('platform.c')])!
	quotes := ['-iquote', c.path('kernel/c'), '-iquote', here]
	mut common := [hosttest.env_default('CC', 'clang')]
	$if macos {
		common << ['-arch', if c.host_arch == 'arm64' { 'arm64' } else { 'x86_64' }]
	}
	common << ['-std=gnu11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined',
		'-fno-omit-frame-pointer']
	for name in ['core', 'fixture', 'platform'] {
		c.inherited(join(common, quiet, quotes, ['-iquote', c.work, '-iquote',
			c.path('tests/apple-ans'), '-ffreestanding', '-fno-builtin'], if name == 'core' {
			['-DVINIX_V_RUNTIME']
		} else {
			[]string{}
		}, ['-c', c.output(name + '.c'), '-o', c.output(name + '.o')]))!
		receipt[name + '_imports'] = c.audit(c.output(name + '.o'), name == 'fixture', 'nm')!
	}
	c.inherited(join(common, quotes, [append_path(reference, 'test.c'), c.output('core.o'),
		c.output('platform.o'), '-lm', '-o', c.output('original-host')]))!
	c.inherited(join(common, [c.output('fixture.o'), c.output('core.o'), c.output('platform.o'),
		'-lm', '-o', c.output('v-host')]))!
	expected := c.capture([c.output('original-host')], '', true)!
	actual := c.capture([c.output('v-host')], '', true)!
	if expected != actual { return error('Original/V J313 output mismatch') }
	fixturehost.write(c.output('original.stdout'), expected)!
	fixturehost.write(c.output('v.stdout'), actual)!
	if actual != 'apple-speakers: 20 tests passed\n' {
		return error('Incomplete original J313 fixture')
	}
	generated := text_read(c.output('fixture.c'))!
	allocations := allocation_counts(generated)
	if (allocations['malloc'] or { json2.Any(0) }).int() != 1 || (allocations['realloc'] or { json2.Any(0) }).int() != 1 || (allocations['aligned_alloc'] or { json2.Any(0) }).int() != 2 || (allocations['free'] or { json2.Any(0) }).int() != 2 {
		return error('Unexpected explicit allocation sites: ' + json2.encode(allocations))
	}
	receipt['golden'] = actual
	receipt['explicit_allocation_sites'] = allocations
	receipt['fixture_generated_sha256'] = hosttest.text_sha(generated)
	json_write(c.output('validation.json'), json2.Any(receipt))!
	print(actual)
	C.fflush(unsafe { nil })
	println('PASS original/V J313 goldens, C ABI, ASan/UBSan and explicit allocator sites')
	C.fflush(unsafe { nil })
	if c.arch == '' { return }
	native_arch := if c.arch == 'aarch64' { 'arm64' } else { 'amd64' }
	mut native_provider := applehost.copy_provider(c.root, c.output('native/spkcore'), 'speaker', false, false)!
	called := calls(text_read(append_path(reference, 'test.c'))!)
	for name in called {
		if name in hardware_only {
			return error('Original fixture calls omitted hardware: ' + name)
		}
	}
	native_provider['original_fixture_calls'] = strings(called)
	receipt['native_provider'] = native_provider
	json_write(c.output('native-provider.json'), json2.Any(native_provider))!
	hosttest.generate_module(c.output('native/spkcore'), c.output('core-native.c'), native_arch, ['nofloat'])!
	c.fixture(c.output('fixture-native.c'), native_arch, true)!
	c.inherited(['python3', c.path('tests/apple-ans/compile-fixture.py'), '--kind', 'platform',
		'--arch', native_arch, c.output('platform-native.c')])!
	mut cc := []string{}
	if c.arch == 'aarch64' {
		gcc_root := c.path('build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl')
		mut gcc_paths := os.ls(gcc_root)!
		gcc_paths.sort()
		if gcc_paths.len == 0 { return error('Missing AArch64 GCC installation') }
		cc = [hosttest.env_default('CC_AARCH64', '/opt/homebrew/opt/llvm/bin/clang'),
			'--target=aarch64-linux-musl', '--sysroot=' + c.path('build-aarch64-userland/sysroot'),
			'--gcc-install-dir=' + append_path(gcc_root, gcc_paths.last())]
	} else {
		cc = [hosttest.env_default('CC_AMD64', '/opt/homebrew/Cellar/musl-cross/0.9.11/libexec/bin/x86_64-linux-musl-gcc')]
	}
	flags := join(['-std=gnu11', '-O2', '-g', '-Wall', '-Wextra', '-Werror'], quiet, quotes, [
		'-iquote',
		c.work,
		'-iquote',
		c.path('tests/apple-ans'),
	])
	mut imports := map[string]json2.Any{}
	for name in ['core-native', 'fixture-native', 'platform-native'] {
		mut extra := if name == 'core-native' {
			['-DVINIX_V_RUNTIME', '-ffreestanding', '-fno-builtin']
		} else {
			[]string{}
		}
		if name == 'core-native' && c.arch == 'x86_64' { extra << '-Wno-array-parameter' }
		c.inherited(join(cc, flags, extra, ['-c', c.output(name + '.c'), '-o', c.output(name + '.o')]))!
		imports[name] = c.audit(c.output(name + '.o'), name == 'fixture-native', '/opt/homebrew/opt/llvm/bin/llvm-nm')!
	}
	serial := c.output('serial.o')
	serial_call := 'import runpy,sys,json;runpy.run_path(sys.argv[1])["compile_serial"](sys.argv[2],sys.argv[3],json.loads(sys.argv[4]))'
	c.inherited(['python3', '-c', serial_call, c.path('tests/kernel-gaps/compile-v-fixture.py'),
		serial, c.arch, json2.encode(join(cc, flags))])!
	init := c.output('native-init')
	c.inherited(join(cc, if c.arch == 'aarch64' { ['-fuse-ld=lld'] } else { []string{} }, [
		'-static',
		c.output('fixture-native.o'),
		c.output('core-native.o'),
		c.output('platform-native.o'),
		serial,
		'-lm',
		'-o',
		init,
	]))!
	groups := group_names(text_read(append_path(here, 'model/tests.v'))!)
	mut markers := groups.map('apple-speakers: ' + it + ' ok')
	markers << 'apple-speakers: 20 tests passed'
	if groups.len != 20 { return error('Incomplete native J313 groups') }
	mut command := ['python3', c.path('tests/kernel-gaps/run.py'), '--arch', c.arch, '--prebuilt-init',
		init, '--kernel-dir', c.kernel, '--state-dir', c.guest, '--no-network', '--timeout', '3600']
	for marker in markers { command << ['--expect', marker] }
	json_write(c.output('native-inputs.json'), json2.Any({
		'arch':             json2.Any(c.arch)
		'provider':         json2.Any(native_provider)
		'object_imports':   json2.Any(imports)
		'fixture_sha256':   json2.Any(hashes(init)!)
		'kernel_sha256':    json2.Any(hashes(append_path(c.kernel, 'bin/vinix'))!)
		'expected_markers': strings(markers)
		'command':          strings(command)
	}))!
	if !c.build_only {
		c.inherited(command)!
		println('PASS all 20 native J313 injected transport/thermal groups ' + c.arch)
	} else {
		println('PASS strict native J313 fixture objects/ELF ' + c.arch)
	}
}

fn main() {
	parsed := hosttest.parse_arguments(os.args[1..], [
		hosttest.Option{'--root', true, []},
		hosttest.Option{'--work', true, []},
		hosttest.Option{'--host-arch', true, ['arm64', 'amd64']},
		hosttest.Option{'--caller-arch', true, ['arm64', 'amd64']},
		hosttest.Option{'--arch', true, ['aarch64', 'x86_64']},
		hosttest.Option{'--build-only', false, []},
		hosttest.Option{'--kernel-dir', true, []},
		hosttest.Option{'--guest-state-dir', true, []},
	], 0, 'J313 native controller', 'Validated original argparse frontend options') or {
		eprintln(err)
		exit(2)
	}
	values := parsed.options
	if '--root' !in values || '--work' !in values {
		eprintln('Missing root/work directory')
		exit(2)
	}
	config := Config{ root: values['--root'], work: values['--work'], host_arch: values['--host-arch'], caller_arch: values['--caller-arch'], arch: values['--arch'], build_only: '--build-only' in values, kernel: values['--kernel-dir'], guest: values['--guest-state-dir'] }
	config.execute() or {
		eprintln(err.msg())
		exit(1)
	}
}
