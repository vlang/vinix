// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import encoding.hex
import hosttest
import os
import wifihost
import x.json2

fn checked(argv []string, env map[string]string) !hosttest.Result {
	result := hosttest.capture(argv, '', 180, env)!
	if result.code != 0 { return error('${argv}\n${result.stdout}${result.stderr}') }
	return result
}

fn tool(name string) string {
	directory := os.getenv('VINIX_WIFI_TOOLS')
	if directory == '' { panic('Set VINIX_WIFI_TOOLS to the compiled native tool directory') }
	return directory + '/' + name
}

fn package_args(work string, output string) []string {
	return [tool('package'), '--status', work + '/status', '--firmware', work + '/firmware-link',
		'--nvram', work + '/nvram', '--clm', work + '/clm-λ"', '--txcap', work + '/txcap', '--output',
		output]
}

fn expect_package_failure(work string, output string, message string, code int) ! {
	result := hosttest.capture(package_args(work, output), '', 30, os.environ())!
	if result.code != code || !result.stderr.contains(message) {
		return error('Wrong package rejection: ${result.code} ${result.stderr}')
	}
	if os.exists(output) { return error('Invalid input created output: ' + output) }
}

fn package_checks(work string) ! {
	mut status := []u8{len: 256}
	status[0] = 1
	status[8] = 3
	for row in [40, 56, 72, 104, 120] {
		value := match row {
			40 { 'module-a' }
			56 { 'vendor-b' }
			72 { 'r3' }
			104 { '1' }
			else { 'apple,shikoku' }
		}
		copy(mut status[row..row + value.len], value.bytes())
	}
	os.write_file_array(work + '/status', status)!
	mut firmware := []u8{len: 0x74, init: 0x55}
	copy(mut firmware[0x6c..0x70], 'RAMS'.bytes())
	os.write_file_array(work + '/firmware', firmware)!
	os.symlink(work + '/firmware', work + '/firmware-link')!
	os.write_file(work + '/nvram', 'boardrev=0x110\n')!
	os.write_file(work + '/clm-λ"', 'clm\x00binary')!
	os.write_file(work + '/txcap', 'txcap')!
	output := work + '/new\\literal/nested/bundle'
	result := checked(package_args(work, output), os.environ())!
	assert result.stdout == 'Wrote ${output}; selected firmware must match this machine’s board/module.\n'
	golden := hex.decode('0300000000000000' + '6d6f64756c652d610000000000000000' +
		'76656e646f722d620000000000000000' + '72330000000000000000000000000000' +
		'31000000000000000000000000000000' + '6170706c652c7368696b6f6b7500000000000000000000000000000000000000' +
		'000000000000000000000000000000000000000000000000')!
	assert golden.len == 128
	assert os.read_bytes(output + '/manifest.bin')! == golden
	for row in [['firmware.bin', 'firmware'], ['nvram.txt', 'nvram'], ['clm.blob', 'clm-λ"'],
		['txcap.blob', 'txcap']] {
		assert os.read_bytes(output + '/' + row[0])! == os.read_bytes(work + '/' + row[1])!
	}
	provenance := os.read_file(output + '/provenance.json')!
	assert provenance.ends_with('\n') && provenance.contains('\\u03bb\\"')
	records := json2.decode[map[string]json2.Any](provenance)!
	assert records.keys().sorted() == ['clm.blob', 'firmware.bin', 'nvram.txt', 'txcap.blob']
	for name, record in records {
		fields := record.as_map()
		data := os.read_bytes(output + '/' + name)!
		assert fields.keys().sorted() == ['bytes', 'sha256', 'source']
		assert fields['bytes']!.int() == data.len
		assert fields['sha256']!.str() == sha256.sum(data).hex()
		// A separate executable checks the saved file digest too.
		digest := checked(['shasum', '-a', '256', output + '/' + name], os.environ())!.stdout.all_before(' ').trim_left('\\')
		assert fields['sha256']!.str() == digest
	}
	assert records['firmware.bin']!.as_map()['source']!.str() == work + '/firmware-link'
	existing := hosttest.capture(package_args(work, output), '', 30, os.environ())!
	assert existing.code == 1 && os.read_file(output + '/provenance.json')! == provenance
	mut invalid := status.clone()
	invalid[0] = 0
	os.write_file_array(work + '/status', invalid)!
	expect_package_failure(work, work + '/bad-status', 'successful chip-probe', 2)!
	os.write_file_array(work + '/status', status[..255])!
	expect_package_failure(work, work + '/short-status', 'successful chip-probe', 2)!
	invalid = status.clone()
	invalid[8] = 4
	os.write_file_array(work + '/status', invalid)!
	expect_package_failure(work, work + '/bad-revision', 'unsupported chip', 2)!
	invalid = status.clone()
	invalid[120] = `X`
	os.write_file_array(work + '/status', invalid)!
	expect_package_failure(work, work + '/bad-board', 'unsupported chip', 2)!
	for row in [40, 56, 72, 104] {
		invalid = status.clone()
		invalid[row] = 0
		os.write_file_array(work + '/status', invalid)!
		expect_package_failure(work, work + '/empty-identity-${row}', 'incomplete OTP', 2)!
		for i in row .. row + 16 { invalid[i] = `a` }
		os.write_file_array(work + '/status', invalid)!
		expect_package_failure(work, work + '/unterminated-${row}', 'incomplete OTP', 2)!
	}
	os.write_file_array(work + '/status', status)!
	os.write_file(work + '/nvram', 'packed\x00')!
	expect_package_failure(work, work + '/packed', 'textual board NVRAM', 2)!
	os.write_file(work + '/nvram', 'λ')!
	expect_package_failure(work, work + '/unicode', 'not ASCII', 1)!
	os.write_file(work + '/nvram', 'board=1\n')!
	os.write_file(work + '/firmware', 'short')!
	expect_package_failure(work, work + '/short-firmware', 'reset/vector table', 2)!
	firmware[0x6c] = `x`
	os.write_file_array(work + '/firmware', firmware)!
	checked(package_args(work, work + '/no-rams-header'), os.environ())!
	assert os.read_bytes(work + '/no-rams-header/firmware.bin')! == firmware
	firmware[0x6c] = `R`
	os.write_file_array(work + '/firmware', firmware)!
	for row in [['firmware', '4194305'], ['nvram', '65537'], ['clm-λ"', '1048577'],
		['txcap', '1048577']] {
		path := work + '/' + row[0]
		saved := os.read_bytes(path)!
		os.write_file(path, '')!
		expect_package_failure(work, work + '/empty-' + row[0], 'invalid file size', 2)!
		os.write_file_array(path, []u8{len: row[1].int(), init: `a`})!
		expect_package_failure(work, work + '/large-' + row[0], 'invalid file size', 2)!
		os.write_file_array(path, saved)!
	}
	status[8] = 5
	os.write_file_array(work + '/status', status)!
	checked(package_args(work, work + '/revision-five'), os.environ())!
	assert os.read_bytes(work + '/revision-five/manifest.bin')![0] == 5
	println('PASS exact Wi-Fi manifest, payloads/provenance, identities, size limits and exclusive output')
}

fn le(data []u8, offset int, width int) u64 {
	mut value := u64(0)
	for i in 0 .. width { value |= u64(data[offset + i]) << (i * 8) }
	return value
}

fn put(mut data []u8, offset int, width int, value u64) {
	for i in 0 .. width { data[offset + i] = u8(value >> (8 * i)) }
}

fn bad_elf(data []u8, message string) ! {
	wifihost.elf_symbols(data) or {
		if !err.msg().contains(message) { return error('Expected ${message}; got ${err}') }
		return
	}
	return error('Accepted corrupt ELF: ' + message)
}

fn elf_checks(work string) ! {
	mut assembly := '.text\n.global _start\n_start:\nret\n'
	for name in wifihost.required_symbols { assembly += '.global ${name}\n.set ${name}, _start\n' }
	assembly += '.section .rodata\n.quad 0xc7b1dd30df4c8b88, 0x0a82e883a194f07b, 0xad97e90e83f1ed67, 0x31eb5d1c5ff23b69\n'
	os.write_file(work + '/kernel.S', assembly)!
	checked(['clang', '--target=aarch64-unknown-none', '-c', work + '/kernel.S', '-o',
		work + '/kernel.o'], os.environ())!
	checked(['ld.lld', '-static', '-e', '_start', work + '/kernel.o', '-o', work + '/kernel'], os.environ())!
	source := 'void console__initialise(void) {\n wifi__initialise();\n sched__set_uart_poll_callback(0);\n}\nvoid console__poll_uart_input(void) {\n wifi__poll();\n virtio_input__poll();\n uart__getc();\n}\n'
	os.write_file(work + '/blob.c', source)!
	data := os.read_bytes(work + '/kernel')!
	checked([tool('verify-build'), work + '/kernel', work + '/blob.c'], os.environ())!
	checked([tool('verify-test'), work + '/kernel', work + '/blob.c'], os.environ())!
	wifihost.verify_regressions(data, source)!
	mut bad := data.clone()
	put(mut bad, 32, 8, 0xffffffffffffffff)
	bad_elf(bad, 'program-header table')!
	bad = data.clone()
	put(mut bad, 40, 8, 0xffffffffffffffff)
	bad_elf(bad, 'section-header table')!
	shoff := int(le(data, 40, 8))
	mut symtab := 0
	for i in 0 .. int(le(data, 60, 2)) {
		if le(data, shoff + i * 64 + 4, 4) == 2 {
			symtab = shoff + i * 64
			break
		}
	}
	assert symtab > 0
	for field in [24, 32, 56] {
		bad = data.clone()
		put(mut bad, symtab + field, 8, 0xffffffffffffffff)
		bad_elf(bad, 'symbol table')!
	}
	bad = data.clone()
	put(mut bad, symtab + 40, 4, 0xffffffff)
	bad_elf(bad, 'symbol table')!
	symbol_offset := int(le(data, symtab + 24, 8))
	bad = data.clone()
	put(mut bad, symbol_offset, 4, 0xffffffff)
	bad_elf(bad, 'symbol name out of bounds')!
	pool_section := shoff + int(le(data, symtab + 40, 4)) * 64
	pool_start := int(le(data, pool_section + 24, 8))
	pool_end := pool_start + int(le(data, pool_section + 32, 8))
	bad = data.clone()
	for i in pool_start .. pool_end { bad[i] = `x` }
	bad_elf(bad, 'unterminated symbol name')!
	bad = data.clone()
	bad[pool_start + 1] = 0xff
	bad_elf(bad, 'not ASCII')!
	bad = data.clone()
	put(mut bad, symbol_offset + 24 + 6, 2, 0)
	bad_elf(bad, 'unresolved symbols')!
	for text in [source.replace('virtio_input__poll();', ''), source.replace('uart__getc()', ''),
		source.replace('wifi__initialise();\n sched__set_uart_poll_callback(0);', 'sched__set_uart_poll_callback(0);\n wifi__initialise();')] {
		wifihost.verify_hooks(text) or { continue }
		return error('Accepted missing/reordered console hook')
	}
	// Column-zero declarations and the first matching body retain the original policy.
	wifihost.verify_hooks('/* void console__initialise(void) {\n}\n */\n' + source)!
	println('PASS linked ARM ELF, all eleven regressions, overflow/bounds, names and console hooks')
}

fn fake_compiler() ! {
	if os.args.len == 2 && os.args[1] == 'version' {
		println('V 0.5.2 Wi-Fi fixture')
		return
	}
	args := os.args[1..]
	arch := os.getenv('VINIX_WIFI_FAKE_ARCH')
	kind := os.getenv('VINIX_WIFI_FAKE_KIND')
	expected := ['-shared', '-no-builtin', '-no-closures', '-os', 'vinix', '-arch', arch,
		'-target-libc-headers', '-nofloat', '-gc', 'none', '-manualfree', '-o']
	assert args.len == expected.len + 2 && args[..expected.len] == expected
	output := args[expected.len]
	work := args.last()
	os.write_file(os.getenv('VINIX_WIFI_FAKE_RECORD'), work)!
	if kind == 'control' {
		assert os.read_file(work + '/entry.v')! == 'module main\nimport wificli as _\n'
		assert os.read_file(work + '/v.mod')! == "Module {name: 'wifi_cli'}\n"
		for name in os.ls(hosttest.root() + '/tools/m1-wifi/core')! {
			assert hosttest.sha(work + '/wificli/' + name)! == hosttest.sha(hosttest.root() + '/tools/m1-wifi/core/' + name)!
		}
	} else {
		name := if kind == 'platform' { 'm1core' } else { 'wificore' }
		assert os.read_file(work + '/entry.v')! == 'module main\nimport apple.wifi.${name} as _\n'
		assert os.read_file(work + '/v.mod')! == "Module { name: 'wifi_fixture_provider' }\n"
		assert hosttest.sha(work + '/apple/wifi/wificore/core.v')! == hosttest.sha(hosttest.root() + '/kernel/apple/wifi/wificore/core.v')!
		if kind == 'platform' {
			assert hosttest.sha(work + '/apple/wifi/m1core/core.v')! == hosttest.sha(hosttest.root() + '/kernel/apple/wifi/m1core/core.v')!
			assert hosttest.sha(work + '/apple/wifi/m1core/platform.v')! == hosttest.sha(hosttest.root() + '/tests/m1-wifi/platform_fixture.v')!
		}
	}
	assert os.getenv('V_C_ERROR_BUG_REPORT_DISABLED') == '1'
	os.write_file(output, '_vinit _vcleanup _vinit_caller _vcleanup_caller _vno_main_init_caller _v3_no_main_initialized\r\na_vinit _vinitX λ_vinit\n')!
	if os.getenv('VINIX_WIFI_FAKE_FAIL') == '1' {
		eprintln('selected compiler failed')
		exit(23)
	}
}

fn generator_checks(work string) ! {
	for arch in ['arm64', 'amd64'] {
		for kind in ['control', 'protocol', 'platform'] {
			mut env := os.environ()
			env['V'] = os.executable()
			env['VINIX_WIFI_FAKE'] = '1'
			env['VINIX_WIFI_FAKE_ARCH'] = arch
			env['VINIX_WIFI_FAKE_KIND'] = kind
			env['VINIX_WIFI_FAKE_RECORD'] = work + '/staged'
			output := work + '/fake-${kind}-${arch}.c'
			argv := if kind == 'control' {
				[tool('compile-v'), output, '--arch', arch]
			} else {
				[tool('compile-provider'), output, '--kind', kind, '--arch', arch]
			}
			checked(argv, env)!
			staged := os.read_file(work + '/staged')!
			assert !os.exists(staged)
			text := os.read_file(output)!
			assert !text.contains('\r')
			if kind == 'control' {
				assert text.starts_with('#define _POSIX_C_SOURCE 200809L\n') && text.contains('\n_vinit _vcleanup ')
			} else {
				assert text.starts_with('wifi_${kind}_provider__vinit wifi_${kind}_provider__vcleanup ')
				assert text.ends_with('a_vinit _vinitX λ_vinit\n')
			}
			env['VINIX_WIFI_FAKE_FAIL'] = '1'
			failed := hosttest.capture(argv, '', 30, env)!
			assert failed.code == 1 && failed.stderr.contains('selected compiler failed')
			assert !os.exists(os.read_file(work + '/staged')!)
			assert os.read_file(output)!.starts_with('_vinit _vcleanup ')
		}
	}
	for argv in [[tool('compile-v'), work + '/never.c', '--arch', 'bad'],
		[tool('compile-provider'), work + '/never.c', '--kind', 'bad'], [tool('package')]] {
		result := hosttest.capture(argv, '', 30, os.environ())!
		assert result.code == 2 && !os.exists(work + '/never.c')
	}
	println('PASS exact producer flags/staged sources, token boundaries and success/failure cleanup on both targets')
}

fn real_generators(work string) ! {
	root := hosttest.root()
	for arch in ['arm64', 'amd64'] {
		cc := if arch == 'arm64' {
			['/opt/homebrew/opt/llvm/bin/clang', '--target=aarch64-linux-musl',
				'--sysroot=' + root + '/build-aarch64-userland/sysroot',
				'--gcc-install-dir=' + root + '/build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl/14.2.0']
		} else {
			['/opt/homebrew/Cellar/musl-cross/0.9.11/libexec/bin/x86_64-linux-musl-gcc']
		}
		for kind in ['control', 'protocol', 'platform'] {
			output := work + '/real-${kind}-${arch}.c'
			argv := if kind == 'control' {
				[tool('compile-v'), output, '--arch', arch]
			} else {
				[tool('compile-provider'), output, '--kind', kind, '--arch', arch]
			}
			checked(argv, os.environ())!
			mut flags := ['-std=gnu11', '-O2', '-g', '-Wall', '-Wextra', '-Werror',
				'-Wno-unused-function', '-Wno-unused-parameter', '-Wno-unused-label', '-fwrapv',
				'-fno-strict-aliasing', '-iquote', root + '/kernel/c', '-iquote',
				root + '/tests/m1-wifi', '-I' + root + '/tools/m1-wifi']
			if kind != 'control' {
				flags << ['-DVINIX_V_RUNTIME', '-ffreestanding', '-fno-builtin']
			}
			if kind == 'platform' && arch == 'amd64' { flags << '-Wno-array-parameter' }
			object := work + '/real-${kind}-${arch}.o'
			mut command := cc.clone()
			command << flags
			command << ['-c', output, '-o', object]
			checked(command, os.environ())!
			data := os.read_bytes(object)!
			assert data[..4] == [u8(0x7f), `E`, `L`, `F`] && le(data, 16, 2) == 1
			assert le(data, 18, 2) == if arch == 'arm64' { u64(183) } else { u64(62) }
			imports := checked(['/opt/homebrew/opt/llvm/bin/llvm-nm', '-u', object], os.environ())!.stdout
			if kind != 'platform' {
				assert !hosttest.allocation_symbols(imports) && !imports.contains('v_malloc')
			}
			if kind == 'control' {
				mut link := cc.clone()
				if arch == 'arm64' { link << '-fuse-ld=lld' }
				link << ['-static', object, '-o', work + '/wifi-ctl-${arch}']
				checked(link, os.environ())!
				binary := os.read_bytes(work + '/wifi-ctl-${arch}')!
				assert le(binary, 16, 2) == 2 && le(binary, 18, 2) == le(data, 18, 2)
			}
		}
	}
	println('PASS real V producers, strict ARM/x86 musl object compilation, allocator audits and static control links')
}

fn run_checks(work string) ! {
	if os.getenv('VINIX_WIFI_TOOLS') == '' {
		compiler := checked(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'find-v',
			hosttest.root()], os.environ())!.stdout
		directory := work + '/bin'
		os.mkdir(directory)!
		for row in [['tools/m1-wifi/package.v', 'package'], ['tools/m1-wifi/compile-v.v', 'compile-v'],
			['tests/m1-wifi/compile-provider.v', 'compile-provider'],
			['tests/m1-wifi/verify-build.v', 'verify-build'],
			['tests/m1-wifi/verify-test.v', 'verify-test']] {
			checked([compiler, '-cc', 'cc', '-o', directory + '/' + row[1],
				hosttest.root() + '/' + row[0]], os.environ())!
		}
		os.setenv('VINIX_WIFI_TOOLS', directory, true)
	}
	package_checks(work)!
	elf_checks(work)!
	generator_checks(work)!
	if '--real-generators' in os.args { real_generators(work)! }
}

fn main() {
	if os.getenv('VINIX_WIFI_FAKE') == '1' {
		fake_compiler() or {
			eprintln(err)
			exit(1)
		}
		return
	}
	work := hosttest.work_dir('', 'vinix-wifi-tools-') or {
		eprintln(err)
		exit(1)
	}
	run_checks(work) or {
		eprintln(err)
		hosttest.remove_work_dir(work) or { eprintln(err) }
		exit(1)
	}
	hosttest.remove_work_dir(work) or {
		eprintln(err)
		exit(1)
	}
}
