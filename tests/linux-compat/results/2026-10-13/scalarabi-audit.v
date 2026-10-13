// Compile without -prod: both deliberately failing controls must execute.
import crypto.sha256
import json2
import os

$if macos {
	#include <CommonCrypto/CommonDigest.h>
}
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32

struct Evidence {
	architecture string
	context string
	base_commit string
	artifacts map[string]string
	source_inputs map[string]string
}
fn digest(path string) string {
	mut input := os.open(path) or { panic(err) }; defer { input.close() }
	mut buffer := []u8{len: 1024 * 1024}; defer { unsafe { buffer.free() } }
	$if macos {
		mut state := C.CC_SHA256_CTX{}
		assert C.CC_SHA256_Init(unsafe { &state }) == 1
		for {
			n := input.read(mut buffer) or { if err is os.Eof { break }; panic(err) }
			if n == 0 { break }; assert C.CC_SHA256_Update(unsafe { &state }, buffer.data, u32(n)) == 1
		}
		mut result := [32]u8{}; assert C.CC_SHA256_Final(unsafe { &result[0] }, unsafe { &state }) == 1
		return result[..].hex()
	} $else {
		mut state := sha256.new()
		for {
			n := input.read(mut buffer) or { if err is os.Eof { break }; panic(err) }
			if n == 0 { break }; assert state.write(buffer[..n]) or { panic(err) } == n
		}
		mut result := []u8{len: 32}; state.checksum_into(mut result); return result.hex()
	}
}
fn object(path string) !map[string]json2.Any { return json2.decode[json2.Any](os.read_file(path)!)!.as_map() }
fn publish(input string, output string) ! {
	data := os.read_bytes(input)!
	if os.exists(output) { assert os.read_bytes(output)! == data } else { os.write_file_array(output, data)! }
}
fn git(tree string, args []string) !string {
	mut command := ['-C', tree]; command << args
	mut p := os.new_process('git'); p.set_args(command); p.set_redirect_stdio(); p.run()
	output := p.stdout_slurp() + p.stderr_slurp(); p.wait(); code := p.code; p.close()
	assert code == 0, output; return output.trim_space()
}
fn definition(source string, name string) string {
	lines := source.split_into_lines().filter(it.contains(' ' + name + '(') && it.ends_with(' {'))
	assert lines.len == 1; return source.all_after(lines[0]).all_before('\n}\n')
}
fn control(args []string, marker string) string {
	mut p := os.new_process(os.executable()); p.set_args(args); p.set_redirect_stdio(); p.run()
	output := p.stdout_slurp() + p.stderr_slurp(); p.wait(); code := p.code; p.close()
	if code != 1 || !output.contains(marker) { panic('audit negative control did not execute') }; return output
}
fn outcomes(log string, passing bool) {
	for ordinary in 0 .. 2 {
		assert log.contains('LINUX SCALARABI OUTCOMES: ordinary=' + ordinary.str() + ' cases=2795 failures=' + if passing { '0' } else { '1528' })
	}
}
fn native_failure(log string) {
	assert log.contains('kind=0 method=0 high=0000000100000000 variant=0 result=-1/9 expected=0/0'), 'native failure markers required'
	assert log.contains('kind=0 high=0000000000000000 selector_high=0000000100000000 offset=0 whence=0 result=-1/22 expected=0/0')
	assert log.contains('LINUX SCALARABI CLOSE: kind=0 high=0000000100000000 result=-1/9 expected=0/0')
	assert log.contains('LINUX SCALARABI SPARSE: method=2 high=0000000100000000 position=4294967419 result=-1/9')
	outcomes(log, false)
	assert log.contains('LINUX SCALARABI FAIL: native descriptor/whence words or storage')
	assert !log.split_into_lines().any(it.trim_space() == 'LINUX SCALARABI: PASS')
}
fn retention(log string, arch string) {
	mut seen := map[string]bool{}; mut rows := [2]int{}; mut pages := [2]int{}
	for line in log.split_into_lines() {
		if !line.starts_with('LINUX SCALARABI SLAB:') && !line.starts_with('LINUX SCALARABI STORAGE:') { continue }
		fields := line.fields(); assert fields.len == 7
		group := fields[3].all_after('=').int(); assert group in [0, 1]
		pair := fields[5].all_after('=').split('/')
		assert pair.len == 2 && pair.all(it != '' && it.bytes().all(it.is_digit())) && pair[0].u64() == pair[1].u64()
		if fields[2] == 'SLAB:' {
			key := fields[3] + '-' + fields[4]; assert key !in seen && fields[6] == 'cycles=200'
			seen[key] = true; rows[group]++
		} else { assert fields[4] == 'cycles=200' && fields[6] == 'PASS'; pages[group]++ }
	}
	for group in 0 .. 2 { assert rows[group] == if arch == 'aarch64' { 18 } else { 14 }; assert pages[group] == 1 }
}
// Reverse only the ABI adapters/casts, then compare the entire emitted kernel.
// This also proves that no existing consumer/owner/lock body changed.
fn restore_generated(generated string, baseline string) {
	mut restored := generated
	for name, callee in {'read': 'fs__syscall_read', 'write': 'fs__syscall_write', 'close': 'fs__syscall_close', 'lseek': 'fs__syscall_seek'} {
		function := 'table__syscall_linux_' + name
		lines := restored.split_into_lines()
		prototypes := lines.filter(it.contains(' ' + function + '(') && it.ends_with(';'))
		signatures := lines.filter(it.contains(' ' + function + '(') && it.ends_with(' {'))
		assert prototypes.len == 1 && signatures.len == 1
		body := definition(restored, function)
		call_args := if name == 'close' { 'gpr_state, (i64)((u32)(fdnum))' }
			else if name == 'lseek' { 'gpr_state, (i64)((u32)(fdnum)), offset, (i64)((u32)(whence))' }
			else { 'gpr_state, (i64)((u32)(fdnum)), buf, count' }
		assert body.trim_space() == 'return ' + callee + '(' + call_args + ');'
		block := signatures[0] + body + '\n}\n\n'
		assert restored.count(block) == 1
		restored = restored.replace(prototypes[0] + '\n', '').replace(block, '')
		dispatch := '= ' + function + ';'
		assert restored.count(dispatch) == 1 // Match the complete identifier, excluding readv etc.
		restored = restored.replace(dispatch, '= ' + callee + ';')
	}
	for name in ['pread64', 'pwrite64'] {
		function := 'table__syscall_linux_' + name
		body := definition(restored, function)
		assert body.count('(i64)((u32)(fdnum))') == 1
		restored = restored.replace(body, body.replace('(i64)((u32)(fdnum))', 'fdnum'))
	}
	assert restored == baseline, 'only native scalar ABI decoding may change generated C'
}
fn main() {
	if '--negative-control' in os.args { assert false, 'audit assertions must execute'; return }
	if '--negative-pass-control' in os.args { native_failure(os.read_file(os.args[2])!); return }
	root := '/Users/alex/code/vinix/'; area := '/tmp/vinix-scalarabi-1013/'; out := root + 'tests/linux-compat/results/2026-10-13/'
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'audit assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control', area + 'after-arm.log'], 'native failure markers required'))!
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == '53e909df86d3afdf9c55bf29f50c461db04a4866'
	inputs := object(area + 'kernel-arm/docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 63
	changed := ['kernel/syscall/table/linux_common.v', 'kernel/syscall/table/linux_table_amd64.v', 'kernel/syscall/table/syscall_table_arm64.v']
	for path in changed { assert digest(root + path) == inputs[path] }
	assert git('/tmp/vinix-iovposition-1013/v-snapshot', ['rev-parse', 'HEAD'])! == 'f6358ecff9cffbf2d8b03e6a09269aac7707e26c'
	assert git('/tmp/vinix-iovposition-1013/v-snapshot', ['diff', '--name-only', 'HEAD'])! == ''
	assert digest(area + 'host-tests.log') == sha256.sum(os.read_bytes(area + 'host-tests.log')!).hex()
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total')
	assert os.read_file(area + 'coverage-check.log')!.contains('Linux dispatch coverage: PASS')
	before_allocs := os.read_file(area + 'allocs-before.log')!; after_allocs := os.read_file(area + 'allocs-after.log')!
	assert before_allocs.split_into_lines().filter(it.starts_with('NEW:')) == after_allocs.split_into_lines().filter(it.starts_with('NEW:'))
	for arch, row in {'aarch64': '657 source files, 406 allocation sites', 'x86_64': '653 source files, 295 allocation sites'} {
		assert before_allocs.contains(arch + ': ' + row + ' (V exit 0)') && after_allocs.contains(arch + ': ' + row + ' (V exit 0)')
	}
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'
		assert git(tree, ['rev-parse', 'HEAD'])! == base
		assert git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])!.split_into_lines() == changed
		for path, hash in inputs { if path.starts_with('kernel/') { assert digest(tree + path) == hash } }
		restore_generated(os.read_file(tree + 'kernel/obj/blob.c')!, os.read_file(area + 'before-' + suffix + '.c')!)
		mut artifacts := {'compiler': digest('/tmp/vinix-iovposition-1013/v-snapshot/v'), 'controller': digest(area + 'run'), 'controller_source': digest(root + 'tests/linux-compat/run.v'),
			'kernel_generated_c': digest(tree + 'kernel/obj/blob.c'), 'kernel_before_generated_c': digest(area + 'before-' + suffix + '.c'),
			'audit': digest(@FILE), 'host_tests': digest(area + 'host-tests.log'), 'allocs_before': digest(area + 'allocs-before.log'), 'allocs_after': digest(area + 'allocs-after.log'),
			'assertion_control': digest(area + 'assertion-control.log'), 'passing_log_control': digest(area + 'passing-log-control.log')}
		for phase in ['before', 'after'] {
			state := area + phase + '-' + suffix + '/'; receipt := object(state + 'receipt.json')!
			kernel_hash := digest(if phase == 'before' { area + 'before-' + suffix + '.kernel' } else { tree + 'kernel/bin/vinix' })
			assert receipt['architecture']!.str() == arch && receipt['kernel_sha256']!.str() == kernel_hash && digest(state + 'kernel/bin/vinix') == kernel_hash
			log_path := state.trim_right('/') + '.log'; log := os.read_file(log_path)!
			artifacts[phase + '_kernel'] = kernel_hash; artifacts[phase + '_receipt'] = digest(state + 'receipt.json'); artifacts[phase + '_log'] = digest(log_path)
			rows := receipt['results']!.as_array(); assert rows.len == if phase == 'before' { 1 } else { 5 }
			mut names := []string{}
			for row in rows {
				entry := row.as_map(); name := entry['name']!.str(); assert name !in names; names << name
				assert entry['exit_code']!.int() == if phase == 'before' { 1 } else { 0 }
				assert entry['source_sha256']!.str() == digest(state + 'sources/' + name + 'fixture/core.v') && entry['source_sha256']!.str() == digest(root + 'tests/linux-compat/' + name + 'fixture/core.v')
				assert entry['init_sha256']!.str() == digest(state + name + '/init') && entry['iso_sha256']!.str() == digest(state + name + '/test.iso')
				c := state + name + '/fixture.c'; artifacts[phase + '_' + name + '_generated_c'] = digest(c)
				if name == 'scalarabi' {
					assert digest(c) == digest(area + 'preview.c')
					fixture := os.read_file(c)!; assert !fixture.contains('malloc(') && !fixture.contains('memdup(') && !fixture.contains('new_array') && !fixture.contains('v_fixed_index(')
					assert fixture.contains('alloca(') && fixture.contains('fcntl(') && fixture.contains('fstat(')
					if phase == 'before' { native_failure(log) } else { outcomes(log, true); retention(log, arch) }
				}
				if phase == 'after' { assert log.contains('LINUX ' + name.to_upper() + ': PASS') }
			}
			if phase == 'after' { assert names == ['scalarabi', 'opathseek', 'iovfd', 'pathio', 'runtime']; assert log.contains('Linux compatibility guest suite: PASS') }
			else { assert names == ['scalarabi'] }
			publish(state + 'receipt.json', out + 'scalarabi-' + phase + '-' + arch + '.json')!; publish(log_path, out + 'scalarabi-' + phase + '-' + arch + '.log')!
		}
		assert artifacts['before_scalarabi_generated_c'] == artifacts['after_scalarabi_generated_c']
		context := 'Native musl ELF64 scalar read/write/pread64/pwrite64/lseek/close ABI words:2795 checks per root/UID1000 cohort cover five upper-word patterns, seven descriptor classes, real file/pipe/socket transfers, closure and surviving aliases, access/seek/copy/count errors, signed64 cursors and sparse data above4GiB/across8GiB. Unchanged kernels fail1528 checks per cohort; candidates pass5590 per architecture. Counts remain64-bit, checked with two4GiB-count refusal paths. Thirty-two warm-up and200 measured cycles make70 probes per cycle, with flat slab live objects and big pages in both credential groups. Only three syscall table files differ at53e909df86. Reversing four one-call adapters, four native dispatch substitutions and two positioned FD casts restores the entire baseline generated kernel C. No consuming body, reference, buffer, allocation or lock owner changes. Frozen fixture C is identical before/after and to preview, without hidden allocation/promotion. Independent final lifetime review confirms source/C/cleanup/retention. Both architectures also pass opathseek, iovfd, pathio and runtime. Eight host test files, both kernel builds and inventory checks pass; existing allowance failures retain406ARM/295x86 sites and identical NEW rows. All63 isolated source inputs are fingerprinted separately from the public committed-parent dispatch inventory. Both failing audit controls execute. This does not qualify other FD APIs, GNU/foreign/ELF32 paths, regular copy-fault cursor behavior, cap-sized transfer limits, ordinary SEEK_DATA/SEEK_HOLE, shared-offset concurrency, disk-backed paths, allocator exhaustion or complete installation/sandbox/portal/runtime compatibility.'
		os.write_file(out + 'scalarabi-' + arch + '-evidence.json', json2.encode(Evidence{arch, context, base, artifacts, inputs}, prettify: true) + '\n')!
	}
	for name in ['host-tests', 'allocs-before', 'allocs-after', 'assertion-control', 'passing-log-control'] { publish(area + name + '.log', out + 'scalarabi-' + name + '.log')! }
	println('Scalar ABI qualification audit: PASS')
}
