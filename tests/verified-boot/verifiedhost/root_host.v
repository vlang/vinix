// SPDX-License-Identifier: GPL-2.0-or-later
module verifiedhost

import bundlehost as bh
import crypto.sha256
import dl
import os
import policyhost
import verityimage

#flag -iquote @DIR/../../../kernel/c
#include "verity.h"
struct C.vinix_verity {
mut:
	data_blocks  u64
	total_blocks u64
	level_start  [8]u64
	levels       u32
	root_hash    [32]u8
}

type ShaFunction = fn (voidptr, usize, voidptr)
type InitFunction = fn (&C.vinix_verity, u64, &char, usize) i32

// Stable local xorshift stream. Its inputs are independent of production SHA/geometry.
struct Random {
mut:
	state u64
}

fn (mut state Random) word() u64 {
	state.state ^= state.state << 13
	state.state ^= state.state >> 7
	state.state ^= state.state << 17
	return state.state
}

fn independent(library string) ! {
	handle := dl.open_opt(library, dl.rtld_now)!
	defer { dl.close(handle) }
	hash := unsafe { ShaFunction(dl.sym_opt(handle, 'vinix_verity_sha256')!) }
	init := unsafe { InitFunction(dl.sym_opt(handle, 'vinix_verity_init')!) }
	mut seed := Random{ state: 734 }
	mut lengths := []int{}
	for n in 0 .. 130 { lengths << n }
	lengths << [255, 256, 511, 512, 4095, 4096, 4097, 65535, 65536]
	for _ in 0 .. 128 { lengths << int(seed.word() % 200000) }
	for length in lengths {
		mut value := []u8{len: length}
		for i in 0 .. length { value[i] = u8(seed.word()) }
		mut actual := [32]u8{}
		unsafe { hash(value.data, usize(length), &actual[0]) }
		assert actual == sha256.sum(value)
	}
	println('PASS production V SHA256 vs independent V crypto: ' + lengths.len.str() + ' lengths')
	mut lower := u64(1)
	mut upper := verityimage.max_bytes / 4096
	for lower < upper {
		middle := (lower + upper + 1) / 2
		verityimage.layout(middle) or {
			upper = middle - 1
			continue
		}
		lower = middle
	}
	mut counts := [u64(0), 1, 2, 128, 129, 16384, 16385, lower, lower + 1,
		verityimage.max_bytes / 4096, ~u64(0)]
	for _ in 0 .. 128 { counts << 1 + seed.word() % ((u64(1) << 51) - 1) }
	digest := '0'.repeat(64)
	for count in counts {
		mut actual := C.vinix_verity{}
		result := init(&actual, count, digest.str, 64)
		expected := verityimage.layout(count) or {
			assert result == -1
			continue
		}
		assert result == 0 && actual.levels == u32(expected.len) && actual.data_blocks == count
		mut total := count
		for i, level in expected {
			assert actual.level_start[i] == level.offset
			total += level.count
		}
		assert actual.total_blocks == total
	}
	println('PASS production V geometry vs builder: ' + counts.len.str() + ' counts; maximum=' + lower.str())
}

fn root_host(args []string) ! {
	parsed := bh.parse(args, options(['--builder']), [], 0, 'Usage: run-host [--builder tools/verified-root/build.v]')!
	if parsed.has('--builder') {
		supplied := os.real_path(parsed.value('--builder', ''))
		if supplied !in [os.real_path(bh.root() + '/tools/verified-root/build.v'),
			os.real_path(bh.root() + '/tools/verified-root/build')] {
			return error('The native host test uses the shared verityimage builder; --builder must select its native entry point')
		}
	}
	work := temporary('vinix-verity-host-')!
	defer { bh.retire(work) }
	os.write_file(work + '/v.mod', "Module {name:'vinix_verity_host_tests'}\n")!
	bh.mkdirs(work + '/verity')!
	bh.mkdirs(work + '/krandom')!
	os.cp(bh.root() + '/kernel/block/verity/primitives.v', work + '/verity/primitives.v')!
	os.write_file(work + '/verity/index.v', "module verity\nfn C.abort()\n@[export:'v_fixed_index']\nfn fixed_index(index i64,length i64) i64 {if index<0 || index>=length {C.abort()}; return index}\n")!
	for name in ['sha256.v', 'erase.v'] {
		os.cp(bh.root() + '/kernel/krandom/' + name, work + '/krandom/' + name)!
	}
	compiler := bh.capture(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'find-v',
		bh.root()])!
	production := work + '/verity.c'
	bh.run([compiler, '-shared', '-no-builtin', '-os', 'vinix', '-arch', policyhost.caller_arch(),
		'-target-libc-headers', '-d', 'nofloat', '-gc', 'none', '-manualfree', '-o', production,
		work + '/verity'])!
	cc := os.getenv_opt('CC') or { 'clang' }
	mut common := [cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-iquote',
		bh.root() + '/kernel/c']
	// The compiler may itself be ARM while this controller runs under Rosetta.
	// dlopen requires the generated shared library to match this executable.
	$if macos {
		common << ['-arch', if policyhost.caller_arch() == 'amd64' { 'x86_64' } else { 'arm64' }]
	}
	flags := ['-DVINIX_V_RUNTIME', '-I', bh.root() + '/kernel/c', '-Wno-unused-function',
		'-ffreestanding', '-fno-builtin', '-fno-strict-aliasing']
	normal, sanitized := work + '/host', work + '/host-sanitized'
	for binary in [normal, sanitized] {
		sanitizer := if binary == sanitized {
			['-fsanitize=address,undefined', '-fno-omit-frame-pointer']
		} else {
			[]string{}
		}
		bh.run(joined(common, flags, sanitizer, ['-c', production, '-o', binary + '.o']))!
		bh.run(joined(common, sanitizer, [binary + '.o', bh.root() + '/tests/verified-root/host.c',
			'-o', binary]))!
		bh.run([binary])!
	}
	dynamic := work + '/verity.so'
	bh.run(joined(common, flags, ['-shared', '-fPIC', production, '-o', dynamic]))!
	independent(dynamic)!
	object := work + '/verity.o'
	bh.run(joined(common, flags, ['-c', production, '-o', object]))!
	symbols := bh.capture(['nm', '-u', object])!
	for line in symbols.split('\n') {
		for token in line.split_any(' \t').filter(it != '') {
			assert token.trim_left('_') !in ['malloc', 'calloc', 'realloc', 'free', 'aligned_alloc',
				'posix_memalign']
		}
	}
	println('PASS production object: no allocator imports')
	for count in [1, 2, 128, 129, 16384, 16385] {
		fixture(work + '/data', count)!
		metadata := verityimage.build(work + '/data', work + '/image', false)!
		for binary in [normal, sanitized] {
			bh.run([binary, work + '/image', count.str(), metadata.root_hash])!
		}
		os.rm(work + '/image')!
	}
	println('VERITY V HOST PASS')
}
