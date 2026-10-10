// SPDX-License-Identifier: GPL-2.0-only
module main

import applehost
import fixturehost
import hosttest
import json2
import encoding.hex
import os

fn C.dup2(i32, i32) i32
fn C.close(i32) i32
fn C.fcntl(i32, i32, ...i32) i32
fn C.write(i32, voidptr, usize) isize

const original_revision = 'd4a056552913b73e57bf42905e8fb5914bc9065a'
const hardware_only = ['a_kernel_read32', 'a_kernel_read64', 'a_kernel_write32', 'a_kernel_write64',
	'a_kernel_now', 'a_kernel_delay', 'a_kernel_sync', 'vinix_ans_init']
const quiet = ['-Wno-unused-function', '-Wno-unused-parameter', '-Wno-unused-label', '-fwrapv',
	'-fno-strict-aliasing']

struct Config {
	env map[string]string
	text_encoding string
	root        string
	work        string
	fixture     string
	caller_arch string
	arch        string
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
	fixturehost.inherited_command_environment_preferred(argv, c.env, c.caller_arch)!
}

fn (c Config) capture(argv []string, directory string, binary bool) !string {
	return fixturehost.capture_in_preferred(argv, '', c.env, false, directory, binary, c.caller_arch)!
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
		if name in ['realloc', 'memdup', 'v_malloc'] || name.starts_with('new_array') || (!fixture && name in [
			'malloc',
			'calloc',
			'free',
		]) {
			return true
		}
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
	return strings(lines(imports, true))
}

// The original regex counts every call to either public storage API prefix.
fn calls(text string, mut counts map[string]json2.Any) {
	chars := text.runes()
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
		if next >= chars.len || chars[next] != `(` { continue }
		name := chars[start..index].string()
		if (name.starts_with('a_') && name.len > 2) || (name.starts_with('vinix_ans_') && name.len > 10) {
			counts[name] = json2.Any((counts[name] or { json2.Any(0) }).int() + 1)
		}
	}
}

fn (c Config) fixture(output string, kind string, features []string) ! {
	c.inherited(join(['python3', c.path('tests/apple-ans/compile-fixture.py'), '--kind', kind], features, [output]))!
}

// Keep the producer's actual interpreter output leaves and descriptor behavior.
// The producer itself is an unchanged dependency and receives no port credit.
fn (c Config) generate(source string, output string, arch string) ! {
	call := 'import runpy,sys;runpy.run_path(sys.argv[1])["generate"](sys.argv[2],sys.argv[3],sys.argv[4],("nofloat",))'
	c.inherited(['python3', '-c', call, c.path('build-support/compile-v-module.py'), source, output, arch])!
}

fn (c Config) prepare() !map[string]json2.Any {
	here := c.path('tests/apple-ans')
	host_provider := applehost.copy_provider(c.root, c.output('ext2core'), 'ans', true, true)!
	fixturehost.write(c.output('ans-fixture-v-abi.h'), os.read_file(append_path(here, 'ans-fixture-v-abi.h'))!)!
	c.generate(c.output('ext2core'), c.output('core.c'), c.caller_arch)!
	mut receipt := map[string]json2.Any{
		'original_revision': json2.Any(original_revision)
		'originals':         json2.Any(map[string]json2.Any{})
		'host_provider':     json2.Any(host_provider)
	}
	mut originals := map[string]json2.Any{}
	for name in ['ext2_test.c', 'platform_fixture.c', 'test.c', 'test_rw.h', 'ext2_fixture.h',
		'ans_fixture.h'] {
		raw := c.capture(['git', 'show', original_revision + ':tests/apple-ans/' + name], c.root, true)!
		fixturehost.write(c.output(name), raw)!
		originals[name] = json2.Any({
			'sha256': json2.Any(hashes(c.output(name))!)
			'lines':  json2.Any(lines(raw, false).len)
		})
	}
	receipt['originals'] = originals
	c.fixture(c.output('ext2.c'), 'ext2', ['--entry'])!
	c.fixture(c.output('ext2-library.c'), 'ext2', [])!
	c.fixture(c.output('platform.c'), 'platform', [])!
	c.fixture(c.output('ans.c'), 'ans', [])!
	common := [hosttest.env_default('CC', 'clang'), '-std=gnu11', '-O2', '-g', '-Wall', '-Wextra',
		'-Werror', '-fsanitize=address,undefined', '-fno-omit-frame-pointer']
	quotes := ['-iquote', c.path('kernel/c'), '-iquote', here]
	for name in ['core.c', 'ext2.c', 'ext2-library.c', 'platform.c', 'ans.c'] {
		c.inherited(join(common, quiet, quotes, ['-iquote', c.work, '-ffreestanding', '-fno-builtin'], if name == 'core.c' {
			['-DVINIX_V_RUNTIME']
		} else {
			[]string{}
		}, ['-c', c.output(name), '-o', c.output(name + '.o')]))!
		imports := c.audit(c.output(name + '.o'), name !in ['core.c', 'platform.c'], 'nm')!
		receipt[name] = json2.Any({
			'sha256':  json2.Any(hashes(c.output(name))!)
			'imports': imports
		})
	}
	return {
		'receipt': json2.Any(receipt)
		'markers': json2.Any(map[string]json2.Any{})
	}
}

fn (c Config) golden(kind string, state map[string]json2.Any) !map[string]json2.Any {
	here := c.path('tests/apple-ans')
	common := [hosttest.env_default('CC', 'clang'), '-std=gnu11', '-O2', '-g', '-Wall', '-Wextra',
		'-Werror', '-fsanitize=address,undefined', '-fno-omit-frame-pointer']
	quotes := ['-iquote', c.path('kernel/c'), '-iquote', here]
	mut markers := state['markers']!.as_map()
	original := c.output(if kind == 'ext2' { 'ext2_test.c' } else { 'test.c' })
	c.inherited(join(common, quotes, [original, c.output('core.c.o'), c.output('platform_fixture.c'),
		'-o', c.output(kind + '-original')]))!
	model := if kind == 'ext2' {
		[c.output('ext2.c.o')]
	} else {
		[c.output('ans.c.o'), c.output('ext2-library.c.o')]
	}
	c.inherited(join(common, quotes, model, [c.output('core.c.o'), c.output('platform.c.o'), '-o',
		c.output(kind + '-host')]))!
	expected := c.capture([c.output(kind + '-original')], '', true)!
	actual := c.capture([c.output(kind + '-host')], '', true)!
	if expected != actual { return error('Independent original/V ANS/ext2 output mismatch') }
	hosttest.module_decode_utf8(actual)!
	markers[kind] = strings(lines(actual, true))
	fixturehost.write(c.output(kind + '.stdout'), actual)!
	return {
		'receipt': state['receipt']!
		'markers': json2.Any(markers)
		'text':    json2.Any(actual)
	}
}

fn (c Config) finish(state map[string]json2.Any) !map[string]json2.Any {
	mut receipt := state['receipt']!.as_map()
	markers := state['markers']!.as_map()

	mut goldens := map[string]json2.Any{}
	for kind in ['ext2', 'ans'] { goldens[kind] = markers[kind]! }
	receipt['goldens'] = goldens
	json_write(c.output('validation.json'), json2.Any(receipt))!
	return state
}

fn (c Config) native(state map[string]json2.Any) ! {
	here := c.path('tests/apple-ans')
	quotes := ['-iquote', c.path('kernel/c'), '-iquote', here]
	markers := state['markers']!.as_map()

	native_arch := if c.arch == 'aarch64' { 'arm64' } else { 'amd64' }
	mut native_provider := applehost.copy_provider(c.root, c.output('native-provider/ext2core'), 'ans', c.fixture == 'ans', false)!
	mut api_calls := map[string]json2.Any{}
	for name in ['test.c', 'test_rw.h'] {
		calls(hosttest.module_read_text(c.output(name))!, mut api_calls)
	}
	for name in api_calls.keys() {
		if name in hardware_only {
			return error('Independent fixture calls omitted hardware: ' + name)
		}
	}
	native_provider['original_fixture_calls'] = api_calls
	json_write(c.output('native-provider.json'), json2.Any(native_provider))!
	c.generate(c.output('native-provider/ext2core'), c.output('core-native.c'), native_arch)!
	c.fixture(c.output('native.c'), c.fixture, ['--entry', '--guest', '--arch', native_arch])!
	c.fixture(c.output('platform-native.c'), 'platform', ['--arch', native_arch])!
	c.fixture(c.output('ext2-library-native.c'), 'ext2', ['--arch', native_arch])!
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
		cc = [hosttest.env_default('CC_AMD64', 'x86_64-linux-musl-gcc')]
	}
	flags := join(['-std=gnu11', '-O2', '-g', '-Wall', '-Wextra', '-Werror'], quiet, quotes, [
		'-iquote',
		c.work,
	])
	mut native_imports := map[string]json2.Any{}
	nm := hosttest.env_default('NM', if os.exists('/opt/homebrew/opt/llvm/bin/llvm-nm') {
		'/opt/homebrew/opt/llvm/bin/llvm-nm'
	} else {
		'nm'
	})
	for name in ['core-native.c', 'native.c', 'platform-native.c', 'ext2-library-native.c'] {
		mut extra := if name == 'core-native.c' {
			['-DVINIX_V_RUNTIME', '-ffreestanding', '-fno-builtin']
		} else {
			[]string{}
		}
		if name == 'core-native.c' && c.arch == 'x86_64' { extra << '-Wno-array-parameter' }
		c.inherited(join(cc, flags, extra, ['-c', c.output(name), '-o', c.output(name + '.native.o')]))!
		native_imports[name] = c.audit(c.output(name + '.native.o'), name !in [
			'core-native.c',
			'platform-native.c',
		], nm)!
	}
	serial := c.output('serial.o')
	serial_call := 'import runpy,sys,json;runpy.run_path(sys.argv[1])["compile_serial"](sys.argv[2],sys.argv[3],json.loads(sys.argv[4]))'
	c.inherited(['python3', '-c', serial_call, c.path('tests/kernel-gaps/compile-v-fixture.py'),
		serial, c.arch, json2.encode(join(cc, flags))])!
	init := c.output('native-init')
	c.inherited(join(cc, if c.arch == 'aarch64' { ['-fuse-ld=lld'] } else { []string{} }, [
		'-static',
		c.output('core-native.c.native.o'),
		c.output('native.c.native.o'),
		c.output('platform-native.c.native.o'),
	], if c.fixture == 'ans' { [c.output('ext2-library-native.c.native.o')] } else { []string{} }, [
		serial,
		'-o',
		init,
	]))!
	mut command := ['python3', c.path('tests/kernel-gaps/run.py'), '--arch', c.arch, '--prebuilt-init',
		init, '--kernel-dir', c.kernel, '--state-dir', c.guest, '--no-network', '--timeout', '300']
	for marker in markers[c.fixture]!.as_array().map(it.str()) { command << ['--expect', marker] }
	json_write(c.output('native-inputs.json'), json2.Any({
		'arch':             json2.Any(c.arch)
		'provider':         json2.Any(native_provider)
		'object_imports':   json2.Any(native_imports)
		'fixture_sha256':   json2.Any(hashes(init)!)
		'kernel_sha256':    json2.Any(hashes(append_path(c.kernel, 'bin/vinix'))!)
		'expected_markers': markers[c.fixture]!
		'command':          strings(command)
	}))!
	c.inherited(command)!
}

fn (c Config) phase(name string, state json2.Any) !map[string]json2.Any {
	return match name {
		'prepare' { c.prepare()! }
		'ext2', 'ans' { c.golden(name, state.as_map())! }
		'finish' { c.finish(state.as_map())! }
		'native' {
			c.native(state.as_map())!
			map[string]json2.Any{}
		}
		else { return error('Unknown controller phase: ' + name) }
	}
}

fn main() {
	parsed := hosttest.parse_arguments(os.args[1..], [
		hosttest.Option{'--root', true, []},
		hosttest.Option{'--phase', true, ['prepare', 'ext2', 'ans', 'finish', 'native']},
		hosttest.Option{'--parent-stdin', true, []},
		hosttest.Option{'--parent-stdout', true, []},
		hosttest.Option{'--work', true, []},
		hosttest.Option{'--fixture', true, ['ext2', 'ans']},
		hosttest.Option{'--caller-arch', true, ['arm64', 'amd64']},
		hosttest.Option{'--arch', true, ['aarch64', 'x86_64']},
		hosttest.Option{'--kernel-dir', true, []},
		hosttest.Option{'--guest-state-dir', true, []},
	], 0, 'Storage native controller', 'Validated original argparse frontend options') or {
		eprintln(err)
		exit(2)
	}
	values := parsed.options
	if '--root' !in values || '--work' !in values {
		eprintln('Missing root/work directory')
		exit(2)
	}
	input := fixturehost.read('/dev/stdin') or {
		eprintln(err.msg())
		exit(1)
	}
	decoded := hosttest.decode_json(input) or {
		eprintln(err.msg())
		exit(1)
	}
	row := decoded.as_map()
	state := row['state']!
	mut caller_env := map[string]string{}
	for value in row['environment']!.as_array() {
		pair := value.as_array()
		key := hex.decode(pair[0].str()) or { eprintln(err.msg()); exit(1) }
		data := hex.decode(pair[1].str()) or { eprintln(err.msg()); exit(1) }
		caller_env[key.bytestr()] = data.bytestr()
	}
	config := Config{env: caller_env, text_encoding: row['text_encoding']!.str(),  root: values['--root'], work: values['--work'], fixture: values['--fixture'], caller_arch: values['--caller-arch'], arch: values['--arch'], kernel: values['--kernel-dir'], guest: values['--guest-state-dir'] }
	protocol := C.fcntl(1, C.F_DUPFD_CLOEXEC, 3)
	if protocol < 0 {
		eprintln('Unable to retain response descriptor')
		exit(1)
	}
	defer { C.close(protocol) }
	for number, name in ['--parent-stdin', '--parent-stdout'] {
		descriptor := (values[name] or {
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
	phase := values['--phase'] or {
		eprintln('Missing phase')
		exit(2)
	}
	result := config.phase(phase, state) or {
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
