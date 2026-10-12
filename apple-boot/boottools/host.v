// SPDX-License-Identifier: GPL-2.0-or-later
module boottools

import cachecli
import crypto.sha256
import hosttest
import json2
import os
import sourcecommand

const original_fixture_revision = '5a8e69285e09bedb9f949f5df2b80daa41c18e6a'

fn host_flags() []string {
	return ['-O2', '-g', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined',
		'-fno-omit-frame-pointer', '-ffunction-sections', '-fdata-sections']
}

fn generated_flags() []string {
	return ['-Wno-unused-function', '-Wno-unused-parameter', '-Wno-unused-label', '-fwrapv',
		'-fno-strict-aliasing', '-I' + here() + '/src', '-I' + here() + '/tests']
}

fn gc_flag() string {
	$if macos {
		return '-Wl,-dead_strip'
	}
	return '-Wl,--gc-sections'
}

fn cc() string { return os.getenv_opt('CC') or { 'clang' } }

fn allocator_check(object string, core bool) ! {
	result := sourcecommand.capture(['nm', '-u', object], os.environ(), 30, 1024 * 1024, cachecli.cancelled)!
	if result.status != 0 { return error('nm failed: ' + result.stderr) }
	for symbol in hosttest.undefined_symbols(result.stdout) {
		name := symbol.trim_string_left('_')
		if name in ['calloc', 'realloc', 'memdup'] || name.starts_with('new_array') || (core && name in [
			'malloc',
			'free',
		]) {
			return error('forbidden allocator import: ' + symbol)
		}
	}
}

fn build_core(work string) ! {
	command([here() + '/compile-v', '--host', work + '/core.c'])!
	command([cc(), '-std=gnu11', ...host_flags(), ...generated_flags(), '-ffreestanding', '-fno-builtin',
		'-c', work + '/core.c', '-o', work + '/core.o'])!
	allocator_check(work + '/core.o', true)!
}

fn build_fixture(work string, fixture string) ! {
	command([here() + '/tests/compile-fixture', fixture, work + '/' + fixture + '.c'])!
	command([cc(), '-std=gnu11', ...host_flags(), ...generated_flags(), '-c',
		work + '/' + fixture + '.c', '-o', work + '/' + fixture + '.o'])!
	allocator_check(work + '/' + fixture + '.o', false)!
	command([cc(), ...host_flags(), gc_flag(), work + '/' + fixture + '.o', work + '/core.o', '-o',
		work + '/' + fixture + '-v'])!
}

fn run_core(work string) ! {
	build_core(work)!
	check_abi(work + '/core.c', work)!
	println('Apple loader: V core has no allocator imports')
	for fixture in ['converter', 'boot', 'helpers'] { build_fixture(work, fixture)! }
	$if macos {
		if converter_options(cachecli.Arguments{
			options: {
				'--converter': [work + '/converter-v']
			}
		})! != 0 {
			return error('IORegistry converter comparison failed')
		}
	}
	command([work + '/helpers-v'])!
	// The independent memory oracle was already ported. Keep all its guard
	// page, overlap, zero-length and atoi domains against the loader primitives.
	arch := $if arm64 { 'arm64' } $else { 'amd64' }
	hosttest.generate_module(repo() + '/tests/memory/runtimefixture', work + '/memory.c', arch, []string{})!
	mut aliases := ['-Dvinix_atoi=atoi', '-I' + repo() + '/tests/memory/runtimefixture']
	for name in ['memcpy', 'memset', 'memmove', 'memcmp'] {
		aliases << '-Dvinix_' + name + '=apple_boot_host_' + name
	}
	command([cc(), '-std=gnu11', ...host_flags(), ...generated_flags(), ...aliases, gc_flag(),
		work + '/memory.c', work + '/core.o', '-o', work + '/memory'])!
	command([work + '/memory'])!
	command([work + '/boot-v'])!
}

fn new_state(path string) !string {
	state := hosttest.module_resolve(path)!
	if os.exists(state) || os.is_link(state) {
		return error('state directory already exists: ' + state)
	}
	os.mkdir_all(os.dir(state))!
	os.mkdir(state)!
	return state
}

pub fn core_cli(argv []string) int {
	args := cachecli.arguments(argv, ['--state-dir'], []string{}, []string{}, 0, 0, 'usage: run-v-core [--state-dir NEW_DIRECTORY]') or {
		eprintln(err)
		return 2
	}
	guard := cachecli.own_commands()
	defer { guard.close() }
	work := if '--state-dir' in args.options {
		new_state(args.value('--state-dir', '')) or {
			eprintln(err)
			return 1
		}
	} else {
		sourcecommand.temporary('vinix-apple-host') or {
			eprintln(err)
			return 1
		}
	}
	defer { if '--state-dir' !in args.options { os.rmdir_all(work) or {} } }
	run_core(work) or {
		eprintln(err)
		return if cachecli.cancelled() { cachecli.interrupt_status() } else { 1 }
	}
	return 0
}

struct CaseReceipt {
	index      int
	returncode int
	stdout     string
	stderr     string
	fdt_sha256 string
}

struct ParityReceipt {
	original_revision string
	original_sha256   map[string]string
	boot              string
	cases             []CaseReceipt
}

struct CaseResult {
	status int
	stdout string
	stderr string
	exists bool
	data   []u8
}

fn fixture_parity(work string) ! {
	build_core(work)!
	mut receipts := ParityReceipt{ original_revision: original_fixture_revision }
	mut hashes := map[string]string{}
	for fixture, original in {
		'converter': 'adt2fdt.c'
		'boot':      'boot-runtime.c'
	} {
		frozen := work + '/' + original
		result := sourcecommand.capture(['git', '-C', repo(), 'show',
			original_fixture_revision + ':apple-boot/tests/' + original], os.environ(), 30, 1024 * 1024, cachecli.cancelled)!
		if result.status != 0 {
			return error('cannot recover immutable C golden: ' + result.stderr)
		}
		os.write_file(frozen, result.stdout)!
		hashes[original] = sha256.sum(result.stdout.bytes()).hex()
		command([cc(), '-std=gnu11', ...host_flags(), '-DAPPLE_BOOT_HOST', '-I' + here() + '/tests',
			gc_flag(), frozen, work + '/core.o', '-o', work + '/' + fixture + '-c'])!
		build_fixture(work, fixture)!
		if fixture == 'boot' {
			c := sourcecommand.capture([work + '/boot-c'], os.environ(), 30, 1024 * 1024, cachecli.cancelled)!
			v := sourcecommand.capture([work + '/boot-v'], os.environ(), 30, 1024 * 1024, cachecli.cancelled)!
			if c.status != 0 || v.status != 0 || c.stdout != 'Apple loader boot ABI/runtime: PASS\n' || c.stdout != v.stdout {
				return error('boot C/V golden mismatch')
			}
		}
	}
	synthetic := work + '/synthetic.adt'
	data := build_adt(0x43000000, true)
	os.write_file_array(synthetic, data)!
	os.write_file_array(work + '/truncated.adt', data[..data.len - 1])!
	os.write_file(work + '/empty.adt', '')!
	mut cases := [[]string{}, [work + '/missing.adt', 'OUT'], [synthetic, 'OUT'],
		[synthetic, 'OUT', 'fixture bootargs'],
		[synthetic, 'OUT', '--reg', '/arm-io/wdt', '--reg', '/missing'],
		[synthetic, 'OUT', 'args', '--reg', '/arm-io/aic', 'ignored', '/chosen'],
		[synthetic, work + '/missing-directory/out'], [work + '/truncated.adt', 'OUT'],
		[work + '/empty.adt', 'OUT']]
	$if macos {
		os.write_file_array(work + '/ioreg.adt', ioreg(false)!.data)!
		cases << [work + '/ioreg.adt', 'OUT', 'vinix.converter_check=1', '--reg', '/arm-io/wdt']
	}
	mut records := []CaseReceipt{}
	for index, arguments in cases {
		mut results := []CaseResult{}
		for variant in ['c', 'v'] {
			output := work + '/output-' + index.str() + '-' + variant + '.fdt'
			argv := ['adt2fdt', ...arguments.map(if it == 'OUT' { output } else { it })]
			result := sourcecommand.capture_as(work + '/converter-' + variant, argv, os.environ(), 30, 64 * 1024 * 1024, cachecli.cancelled)!
			exists := os.exists(output)
			results << CaseResult{result.status, result.stdout, result.stderr.replace(output, 'OUT'), exists, if exists {
				os.read_bytes(output)!
			} else {
				[]u8{}
			}}
		}
		if results[0] != results[1] {
			return error('converter C/V mismatch at case ' + index.str() + ': ' + results.str())
		}
		result := results[0]
		records << CaseReceipt{index, result.status, result.stdout, result.stderr, if result.exists {
			sha256.sum(result.data).hex()
		} else {
			''
		}}
	}
	receipts = ParityReceipt{original_fixture_revision, hashes, 'Apple loader boot ABI/runtime: PASS', records}
	os.write_file(work + '/validation.json', json2.encode(receipts, prettify: true) + '\n')!
	println('Apple loader fixture C/V parity: PASS (' + cases.len.str() + ' converter cases, all boot goldens)')
}

pub fn parity_cli(argv []string) int {
	args := cachecli.arguments(argv, ['--state-dir'], []string{}, []string{}, 0, 0, 'usage: fixture-parity --state-dir NEW_DIRECTORY') or {
		eprintln(err)
		return 2
	}
	state := args.required('--state-dir') or {
		eprintln(err)
		return 2
	}
	guard := cachecli.own_commands()
	defer { guard.close() }
	work := new_state(state) or {
		eprintln(err)
		return 1
	}
	fixture_parity(work) or {
		eprintln(err)
		return if cachecli.cancelled() { cachecli.interrupt_status() } else { 1 }
	}
	return 0
}
