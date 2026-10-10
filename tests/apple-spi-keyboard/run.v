// SPDX-License-Identifier: GPL-2.0-only
module main

import applehost
import fixturehost
import hosttest
import json2
import os

fn C.fflush(voidptr) i32

const original_revision = 'fb74d12ab3ac2510500fbd3393f3374864d23967'
const hardware_only = ['kernel_read32', 'kernel_write32', 'kernel_now_us', 'kernel_delay_us',
	'vinix_apple_spi_keyboard_init']
const quiet = ['-Wno-unused-function', '-Wno-unused-parameter', '-Wno-unused-label',
	'-Wno-unused-variable', '-fwrapv', '-fno-strict-aliasing']

struct Config {
 text_encoding string
	root        string
	work        string
	suite       string
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

// Path.mkdir(parents=True, exist_ok=True) uses only Unix slash separators.
// os.mkdir_all normalizes backslashes, which are literal caller path bytes here.
fn parent_path(path string) string {
	return path.trim_right('/').all_before_last('/')
}

fn mkdir_parents(path string) ! {
	os.mkdir(path) or {
		if err.code() == C.EEXIST && os.is_dir(path) { return }
		if err.code() == C.ENOENT {
			parent := parent_path(path)
			if parent != '' && parent != path {
				mkdir_parents(parent)!
				os.mkdir(path) or { return fixturehost.FileError{path, err.code(), os.get_error_msg(err.code())} }
				return
			}
		}
		return fixturehost.FileError{path, err.code(), os.get_error_msg(err.code())}
	}
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

fn imports_forbidden(text string) bool {
	mut word := ''
	for ch in (text + ' ').runes() {
		if hosttest.module_word_rune(ch) {
			word += ch.str()
			continue
		}
		name := if word.starts_with('_') { word[1..] } else { word }
		if name in ['malloc', 'calloc', 'realloc', 'free', 'memdup', 'v_malloc'] || name.starts_with('new_array') {
			return true
		}
		word = ''
	}
	return false
}

fn (c Config) audit(path string, nm string) !json2.Any {
	// Decode nm with the actual invoking Python codec and newline policy.
 // This mechanical text/process leaf receives zero migration credit.
 decode := 'import json,subprocess,sys;value=subprocess.check_output(sys.argv[2:],text=True,encoding=sys.argv[1]);sys.stdout.buffer.write(json.dumps(value).encode("ascii"))'
 wire := c.capture(['python3', '-c', decode, c.text_encoding, nm, '-u', path], '', true)!
 imports := hosttest.decode_json(wire)!.str()
	if imports_forbidden(imports) { return error('Allocator imports: ' + imports) }
	return strings(lines(imports, true))
}

fn (c Config) fixture(kind string, output string, arch string, features []string) ! {
	mut argv := ['python3', c.path('tests/apple-spi-keyboard/compile-fixture.py'), '--kind', kind,
		'--arch', arch, '--entry']
	argv << features
	argv << output
	c.inherited(argv)!
}

fn ports(c Config, kind string) string {
	return c.path('tests/apple-spi-' + kind + '/' + kind + 'fixture')
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

fn (c Config) execute() ! {
	here := c.path('tests/apple-spi-keyboard')
	reference := c.output('original')
	mut receipt := map[string]json2.Any{
		'original_revision': json2.Any(original_revision)
		'originals':         json2.Any(map[string]json2.Any{})
		'host_arch':         json2.Any(c.host_arch)
		'source_hashes':     json2.Any(map[string]json2.Any{})
	}
	mut originals := map[string]json2.Any{}
	for name in ['tests/apple-spi-keyboard/test.c', 'tests/apple-spi-touchpad/test.c',
		'tests/apple-spi-keyboard/core_fixture.h', 'kernel/c/apple_spi_keyboard.h'] {
		raw := c.capture(['git', 'show', original_revision + ':' + name], c.root, true)!
		path := append_path(reference, name)
		mkdir_parents(parent_path(path))!
		fixturehost.write(path, raw)!
		originals[name] = json2.Any({
			'sha256': json2.Any(hashes(path)!)
			'lines':  json2.Any(lines(raw, false).len)
		})
	}
	receipt['originals'] = originals
	mut source_hashes := map[string]json2.Any{}
	for kind in ['keyboard', 'touchpad'] {
		module_path := ports(c, kind)
		mut names := os.ls(module_path)!.filter(it.ends_with('.v'))
		names.sort()
		for name in names {
			path := append_path(module_path, name)
			source_hashes[path[c.root.trim_right('/').len + 1..]] = hashes(path)!
		}
		header := append_path(parent_path(module_path), kind + '-native-abi.h')
		source_hashes[header[c.root.trim_right('/').len + 1..]] = hashes(header)!
	}
	receipt['source_hashes'] = source_hashes
	receipt['host_provider'] = applehost.copy_provider(c.root, c.output('spicore'), 'spi', false, c.host_arch == 'arm64')!
	hosttest.generate_module(c.output('spicore'), c.output('core.c'), c.host_arch, ['nofloat'])!
	c.inherited(['python3', c.path('tests/apple-ans/compile-fixture.py'), '--kind', 'platform',
		'--arch', c.host_arch, c.output('platform.c')])!
	quotes := ['-iquote', here, '-iquote', c.path('kernel/c'), '-iquote', c.path('tests/apple-ans'),
		'-iquote', c.path('tests/apple-spi-touchpad')]
	mut common := [hosttest.env_default('CC', 'clang')]
	$if macos {
		common << ['-arch', if c.host_arch == 'arm64' { 'arm64' } else { 'x86_64' }]
	}
	common << ['-std=gnu11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined',
		'-fno-omit-frame-pointer']
	for name in ['core', 'platform'] {
		mut argv := common.clone()
		argv << quiet
		argv << quotes
		argv << ['-ffreestanding', '-fno-builtin']
		if name == 'core' { argv << '-DVINIX_V_RUNTIME' }
		argv << ['-c', c.output(name + '.c'), '-o', c.output(name + '.o')]
		c.inherited(argv)!
		receipt[name + '_imports'] = c.audit(c.output(name + '.o'), 'nm')!
	}
	suites := if c.suite == 'both' { ['keyboard', 'touchpad'] } else { [c.suite] }
	mut expected := ''
	mut original := ''
	for kind in suites {
		original = append_path(reference, 'tests/apple-spi-' + kind + '/test.c')
		c.inherited(join(common, quotes, [original, c.output('core.o'), c.output('platform.o'),
			'-o', c.output(kind + '-original-host')]))!
		expected = c.capture([c.output(kind + '-original-host')], '', true)!
		fixturehost.write(c.output(kind + '-original.stdout'), expected)!
		c.fixture(kind, c.output(kind + '.c'), c.host_arch, [])!
		c.inherited(join(common, quiet, quotes, ['-ffreestanding', '-fno-builtin', '-c',
			c.output(kind + '.c'), '-o', c.output(kind + '.o')]))!
		receipt[kind + '_imports'] = c.audit(c.output(kind + '.o'), 'nm')!
		c.inherited(join(common, [c.output(kind + '.o'), c.output('core.o'), c.output('platform.o'),
			'-o', c.output(kind + '-v-host')]))!
		actual := c.capture([c.output(kind + '-v-host')], '', true)!
		fixturehost.write(c.output(kind + '-v.stdout'), actual)!
		if actual != expected { return error('Independent original/V SPI output mismatch') }
		receipt[kind + '_generated_sha256'] = hashes(c.output(kind + '.c'))!
		hosttest.module_decode_utf8(expected)!
		golden := lines(expected, true)
		groups := if kind == 'keyboard' { 21 } else { 19 }
		if golden.len != groups + 1 { return error('Incomplete SPI fixture verdict: ' + expected) }
		receipt[kind + '_golden'] = strings(golden)
		print(expected)
		C.fflush(unsafe { nil })
	}
	json_write(c.output('validation.json'), json2.Any(receipt))!
	println('PASS frozen original/V SPI goldens, native callbacks, ASan/UBSan and no allocator imports')
	C.fflush(unsafe { nil })
	if c.arch == '' { return }
	arch := if c.arch == 'aarch64' { 'arm64' } else { 'amd64' }
	mut native_provider := applehost.copy_provider(c.root, c.output('native/spicore'), 'spi', false, c.arch == 'aarch64')!
	called := calls(hosttest.module_read_text(original)!)
	if called.any(it in hardware_only) {
		return error('Independent fixture calls unexecuted hardware entry')
	}
	native_provider['original_fixture_calls'] = strings(called)
	receipt['native_provider'] = native_provider
	json_write(c.output('native-provider.json'), json2.Any(native_provider))!
	hosttest.generate_module(c.output('native/spicore'), c.output('core-native.c'), arch, ['nofloat'])!
	c.fixture(c.suite, c.output('fixture-native.c'), arch, ['--guest'])!
	c.fixture(c.suite, c.output('reference-entry.c'), arch, ['--guest', '--reference'])!
	c.inherited(['python3', c.path('tests/apple-ans/compile-fixture.py'), '--kind', 'platform',
		'--arch', arch, c.output('platform-native.c')])!
	mut cc := []string{}
	if c.arch == 'aarch64' {
		sysroot := c.path('build-aarch64-userland/sysroot')
		gcc_root := c.path('build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl')
		mut gcc_paths := os.ls(gcc_root)!
		gcc_paths.sort()
		if gcc_paths.len == 0 { return error('Missing AArch64 GCC installation') }
		cc = [hosttest.env_default('CC_AARCH64', '/opt/homebrew/opt/llvm/bin/clang'),
			'--target=aarch64-linux-musl', '--sysroot=' + sysroot,
			'--gcc-install-dir=' + append_path(gcc_root, gcc_paths.last())]
	} else {
		cc = [hosttest.env_default('CC_AMD64', '/opt/homebrew/Cellar/musl-cross/0.9.11/libexec/bin/x86_64-linux-musl-gcc')]
	}
	flags := join(['-std=gnu11', '-O2', '-g', '-Wall', '-Wextra', '-Werror'], quotes)
	mut imports := map[string]json2.Any{}
	for name in ['core-native', 'fixture-native', 'reference-entry', 'platform-native'] {
		mut extra := if name == 'core-native' {
			['-DVINIX_V_RUNTIME', '-ffreestanding', '-fno-builtin']
		} else {
			[]string{}
		}
		if name == 'core-native' && c.arch == 'x86_64' { extra << '-Wno-array-parameter' }
		c.inherited(join(cc, flags, quiet, extra, ['-c', c.output(name + '.c'), '-o',
			c.output(name + '.o')]))!
		imports[name] = c.audit(c.output(name + '.o'), '/opt/homebrew/opt/llvm/bin/llvm-nm')!
	}
	c.inherited(join(cc, flags, ['-Dmain=vsf_reference_entry', '-c', original, '-o',
		c.output('original-native.o')]))!
	serial := c.output('serial.o')
	// The unchanged serial generator and compiler policy remain the independent dependency.
	serial_call := 'import runpy,sys,json;runpy.run_path(sys.argv[1])["compile_serial"](sys.argv[2],sys.argv[3],json.loads(sys.argv[4]))'
	c.inherited(['python3', '-c', serial_call, c.path('tests/kernel-gaps/compile-v-fixture.py'),
		serial, c.arch, json2.encode(join(cc, flags))])!
	for variant in ['original', 'v'] {
		init := c.output(variant + '-native-init')
		mut objects := if variant == 'original' {
			[c.output('original-native.o'), c.output('reference-entry.o')]
		} else {
			[c.output('fixture-native.o')]
		}
		objects << [c.output('core-native.o'), c.output('platform-native.o'), serial]
		c.inherited(join(cc, (if c.arch == 'aarch64' { ['-fuse-ld=lld'] } else { []string{} }), ['-static'], objects, [
			'-o',
			init,
		]))!
		mut command := ['python3', c.path('tests/kernel-gaps/run.py'), '--arch', c.arch,
			'--prebuilt-init', init, '--kernel-dir', c.kernel, '--state-dir', c.guest + '-' + variant,
			'--no-network', '--timeout', '3600', '--fail', 'SPI FIXTURE FAIL']
		for marker in lines(expected, true) { command << ['--expect', marker] }
		json_write(c.output(variant + '-native-inputs.json'), json2.Any({
			'arch':          json2.Any(c.arch)
			'provider':      json2.Any(native_provider)
			'imports':       json2.Any(imports)
			'init_sha256':   json2.Any(hashes(init)!)
			'kernel_sha256': json2.Any(hashes(append_path(c.kernel, 'bin/vinix'))!)
			'command':       strings(command)
		}))!
		if !c.build_only {
			c.inherited(command)!
			println('PASS complete native SPI ' + c.suite + ' ' + variant + ' ' + c.arch)
			C.fflush(unsafe { nil })
		}
	}
}

fn main() {
	parsed := hosttest.parse_arguments(os.args[1..], [
		hosttest.Option{'--root', true, []},
  hosttest.Option{'--text-encoding', true, []},
		hosttest.Option{'--work', true, []},
		hosttest.Option{'--suite', true, ['keyboard', 'touchpad', 'both']},
		hosttest.Option{'--host-arch', true, ['arm64', 'amd64']},
		hosttest.Option{'--caller-arch', true, ['arm64', 'amd64']},
		hosttest.Option{'--arch', true, ['aarch64', 'x86_64']},
		hosttest.Option{'--build-only', false, []},
		hosttest.Option{'--kernel-dir', true, []},
		hosttest.Option{'--guest-state-dir', true, []},
	], 0, 'SPI native controller', 'Validated original argparse frontend options') or {
		eprintln(err)
		exit(2)
	}
	values := parsed.options
	if '--root' !in values || '--work' !in values {
		eprintln('Missing root/work directory')
		exit(2)
	}
	config := Config{ text_encoding: values['--text-encoding'], root: values['--root'], work: values['--work'], suite: values['--suite'], host_arch: values['--host-arch'], caller_arch: values['--caller-arch'], arch: values['--arch'], build_only: '--build-only' in values, kernel: values['--kernel-dir'], guest: values['--guest-state-dir'] }
	config.execute() or {
		eprintln(err.msg())
		exit(1)
	}
}
