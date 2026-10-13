// Compile without -prod: both deliberately failing controls must execute.
import crypto.sha256
import json2
import os
import strings

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
// An extra early return renumbers V's generated return-value temporaries.
// Canonicalize their first occurrences and references, preserving all other C.
fn canonical_returns(source string) string {
	mut output := strings.new_builder(source.len); mut names := map[string]string{}; mut position := 0
	for position < source.len {
		start := position
		if source[position].is_letter() || source[position] == `_` {
			position++
			for position < source.len && (source[position].is_alnum() || source[position] == `_`) { position++ }
			token := source[start..position]
			if token.starts_with('_t') && token.len > 2 && token[2..].bytes().all(it.is_digit()) {
				if token !in names { names[token] = '_return' + names.len.str() }
				output.write_string(names[token])
			} else { output.write_string(token) }
		} else { output.write_u8(source[position]); position++ }
	}
	return output.str()
}
fn control(args []string, marker string) string {
	mut p := os.new_process(os.executable()); p.set_args(args); p.set_redirect_stdio(); p.run()
	output := p.stdout_slurp() + p.stderr_slurp(); p.wait(); code := p.code; p.close()
	if code != 1 || !output.contains(marker) { panic('audit negative control did not execute') }; return output
}
fn outcomes(log string, passing bool) {
	for ordinary in 0 .. 2 {
		assert log.contains('LINUX OPATHSEEK OUTCOMES: ordinary=' + ordinary.str() + ' cases=3024 failures=' + if passing { '0' } else { '3024' })
		assert log.contains('LINUX OPATHSEEK CONTROLS: ordinary=' + ordinary.str() + ' normal/sparse/negative/invalid/private/metadata PASS')
	}
}
fn native_failure(log string) {
	assert log.contains('offset=0 whence=0 result=0/0 expected=-1/9'), 'native failure markers required'
	assert log.contains('offset=0 whence=0 result=-1/29 expected=-1/9')
	outcomes(log, false)
	assert log.contains('LINUX OPATHSEEK FAIL: pathname seek access or storage')
	assert !log.split_into_lines().any(it.trim_space() == 'LINUX OPATHSEEK: PASS')
}
fn retention(log string, arch string) {
	mut seen := map[string]bool{}; mut rows := [2]int{}; mut pages := [2]int{}
	for line in log.split_into_lines() {
		if !line.starts_with('LINUX OPATHSEEK SLAB:') && !line.starts_with('LINUX OPATHSEEK STORAGE:') { continue }
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
fn main() {
	if '--negative-control' in os.args { assert false, 'audit assertions must execute'; return }
	if '--negative-pass-control' in os.args { native_failure(os.read_file(os.args[2])!); return }
	root := '/Users/alex/code/vinix/'; area := '/tmp/vinix-scalarfd-1013/'; out := root + 'tests/linux-compat/results/2026-10-13/'
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'audit assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control', area + 'after-arm.log'], 'native failure markers required'))!
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == '116ba2c7850ca331a5bf9851470f1bae4a9136d3'
	inputs := object(area + 'kernel-arm/docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 63
	assert digest(root + 'kernel/fs/vfs.v') == inputs['kernel/fs/vfs.v']
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
		assert git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])! == 'kernel/fs/vfs.v'
		for path, hash in inputs { if path.starts_with('kernel/') { assert digest(tree + path) == hash } }
		generated := os.read_file(tree + 'kernel/obj/blob.c')!; baseline_c := os.read_file(area + 'before-' + suffix + '.c')!
		body := definition(generated, 'fs__syscall_seek')
		start := '\n\tif ((handle->flags & resource__o_path) != 0) {'
		assert body.count(start) == 1
		guard := start + body.all_after(start).all_before('\n\t}\n') + '\n\t}\n'
		assert guard.count('file__FD__unref(fd)') == 1 && guard.contains('errno__ebadf') && guard.contains('return _t2;')
		assert !guard.contains('klock__') && !guard.contains('malloc(') && !guard.contains('handle->loc')
		guard_position := body.index(start) or { panic('missing guard') }
		policy_position := body.index('file__Handle__mac_check(') or { panic('missing policy check') }
		lock_position := body.index('klock__Lock__acquire(') or { panic('missing handle lock') }
		assert guard_position < policy_position && guard_position < lock_position
		assert canonical_returns(body.replace(guard, '\n')) == canonical_returns(definition(baseline_c, 'fs__syscall_seek'))
		for name in ['fs__syscall_read', 'fs__syscall_write', 'fs__syscall_close', 'fs__read_pinned_descriptor', 'fs__write_pinned_descriptor', 'file__syscall_pread', 'file__syscall_pwrite', 'table__linux_readv_flags', 'table__linux_positioned_iov'] {
			assert definition(generated, name) == definition(baseline_c, name)
		}
		mut artifacts := {'compiler': digest('/tmp/vinix-iovposition-1013/v-snapshot/v'), 'controller': digest(area + 'run'), 'controller_source': digest(root + 'tests/linux-compat/run.v'),
			'kernel_generated_c': digest(tree + 'kernel/obj/blob.c'), 'kernel_before_generated_c': digest(area + 'before-' + suffix + '.c'),
			'audit': digest(@FILE), 'host_tests': digest(area + 'host-tests.log'), 'allocs_before': digest(area + 'allocs-before.log'), 'allocs_after': digest(area + 'allocs-after.log'),
			'assertion_control': digest(area + 'assertion-control.log'), 'passing_log_control': digest(area + 'passing-log-control.log')}
		for phase in ['before', 'after'] {
			state := area + phase + (if phase == 'before' { '-final-' } else { '-' }) + suffix + '/'; receipt := object(state + 'receipt.json')!
			kernel_hash := digest(if phase == 'before' { area + 'before-' + suffix + '.kernel' } else { tree + 'kernel/bin/vinix' })
			assert receipt['architecture']!.str() == arch && receipt['kernel_sha256']!.str() == kernel_hash && digest(state + 'kernel/bin/vinix') == kernel_hash
			log_path := state.trim_right('/') + '.log'; log := os.read_file(log_path)!
			artifacts[phase + '_kernel'] = kernel_hash; artifacts[phase + '_receipt'] = digest(state + 'receipt.json'); artifacts[phase + '_log'] = digest(log_path)
			rows := receipt['results']!.as_array(); assert rows.len == if phase == 'before' { 1 } else { 5 }
			mut names := []string{}
			for row in rows {
				entry := row.as_map(); name := entry['name']!.str(); assert name !in names; names << name
				image_failure := phase == 'after' && arch == 'x86_64' && name == 'runtime'
				assert entry['exit_code']!.int() == if phase == 'before' || image_failure { 1 } else { 0 }
				assert entry['source_sha256']!.str() == digest(state + 'sources/' + name + 'fixture/core.v') && entry['source_sha256']!.str() == digest(root + 'tests/linux-compat/' + name + 'fixture/core.v')
				assert entry['init_sha256']!.str() == digest(state + name + '/init')
				if image_failure { assert entry['iso_sha256']!.str() == '' && entry['detail']!.str() == 'Command failed' }
				else { assert entry['iso_sha256']!.str() == digest(state + name + '/test.iso') }
				c := state + name + '/fixture.c'; artifacts[phase + '_' + name + '_generated_c'] = digest(c)
				if name == 'opathseek' {
					assert digest(c) == digest(area + 'final-preview.c')
					fixture := os.read_file(c)!; assert !fixture.contains('malloc(') && !fixture.contains('memdup(') && !fixture.contains('new_array') && !fixture.contains('v_fixed_index(')
					assert fixture.contains('alloca(') && fixture.contains('fcntl(') && fixture.contains('fstat(')
					if phase == 'before' { native_failure(log) } else { outcomes(log, true); retention(log, arch) }
				}
				if phase == 'after' && !image_failure { assert log.contains('LINUX ' + name.to_upper() + ': PASS') }
			}
			if phase == 'after' {
				assert names == ['opathseek', 'pathio', 'readerror', 'pipezero', 'runtime']
				if arch == 'x86_64' {
					assert log.contains('No space left on device') && log.contains('libburn : FATAL : Burn run failed')
					assert !log.contains('Linux compatibility guest suite: PASS') && !log.contains('LINUX RUNTIME: PASS')
				} else { assert log.contains('Linux compatibility guest suite: PASS') }
			}
			publish(state + 'receipt.json', out + 'opathseek-' + phase + '-' + arch + '.json')!; publish(log_path, out + 'opathseek-' + phase + '-' + arch + '.log')!
		}
		assert artifacts['before_opathseek_generated_c'] == artifacts['after_opathseek_generated_c']
		if arch == 'x86_64' {
			state := area + 'completion-x86/'; receipt := object(state + 'receipt.json')!
			assert receipt['architecture']!.str() == arch && receipt['kernel_sha256']!.str() == artifacts['after_kernel']
			assert digest(state + 'kernel/bin/vinix') == artifacts['after_kernel']
			rows := receipt['results']!.as_array(); assert rows.len == 1
			entry := rows[0].as_map(); assert entry['name']!.str() == 'runtime' && entry['exit_code']!.int() == 0
			assert entry['source_sha256']!.str() == digest(state + 'sources/runtimefixture/core.v') && entry['source_sha256']!.str() == digest(root + 'tests/linux-compat/runtimefixture/core.v')
			assert entry['init_sha256']!.str() == digest(state + 'runtime/init') && entry['iso_sha256']!.str() == digest(state + 'runtime/test.iso')
			assert digest(state + 'runtime/fixture.c') == artifacts['after_runtime_generated_c']
			log := os.read_file(area + 'completion-x86.log')!
			assert log.contains('LINUX RUNTIME: PASS') && log.contains('Linux compatibility guest suite: PASS') && !log.contains('No space left on device')
			artifacts['completion_receipt'] = digest(state + 'receipt.json'); artifacts['completion_log'] = digest(area + 'completion-x86.log')
			publish(state + 'receipt.json', out + 'opathseek-completion-x86_64.json')!; publish(area + 'completion-x86.log', out + 'opathseek-completion-x86_64.log')!
		}
		rejected := area + 'before-' + suffix
		rejected_log := os.read_file(rejected + '.log')!
		assert rejected_log.contains('format') && rejected_log.contains('long long') && rejected_log.contains('error:')
		assert object(rejected + '/receipt.json')!['results']!.as_array()[0].as_map()['exit_code']!.int() == 1
		artifacts['rejected_compilation_log'] = digest(rejected + '.log'); artifacts['rejected_compilation_receipt'] = digest(rejected + '/receipt.json')
		publish(rejected + '.log', out + 'opathseek-rejected-compile-' + arch + '.log')!; publish(rejected + '/receipt.json', out + 'opathseek-rejected-compile-' + arch + '.json')!
		context := 'Native musl ELF64 O_PATH lseek:3024 raw seeks per root/UID1000 cohort cover six node types, four requested flag variants, original/dup/F_DUPFD_CLOEXEC aliases, six signed64 offsets and seven whence values. Fresh unchanged kernels fail every seek case; candidates pass6048 per architecture. Metadata inode/device/size/type, descriptor flags, ordinary sparse/relative/negative/invalid seeks, unchanged readable contents and private-file access controls pass both kernels. Twelve stable descriptors plus six transient dup/close operations per cycle warm32 and measure200 cycles of510 refused seeks, requiring flat live slab objects and big pages. Only a seek guard in fs/vfs.v changes in isolated kernel worktrees at116ba2c785. Generated C releases the pinned FD once before policy/type/offset checks and any lock; the ordinary consuming body is identical after removing the guard and canonicalizing generated return-temporary names. Read/write/close/positioned/vector bodies remain identical. Independent lifetime review found no blocker. Both architectures also pass pathio, readerror, pipezero and runtime; eight host test files and source inventory checks pass. Existing allocation allowance failures retain406ARM/295x86 sites and identical NEW rows, without raising allowances. All63 source inputs are fingerprinted. Both failing audit controls execute. Initial fixture C compilation rejected a printf long-long/long mismatch; corrected before actual baseline/candidate runtime qualification and retained as failure evidence. Native raw seek coverage does not qualify upper-word FD/whence decoding, ordinary SEEK_DATA/SEEK_HOLE, shared-offset concurrency, GNU wrappers, foreign/ELF32 paths, allocator exhaustion, disk-backed handles, sandbox/portal installation or full Linux compatibility.'
		recovery_note := if arch == 'x86_64' { ' The initial candidate aggregate remains failed: host ENOSPC aborted the runtime image before boot, after four successful guest cases. Its failed runtime row has no image hash and is retained. A fresh runtime-only completion receipt passes on the identical kernel with identical frozen fixture C; it does not relabel the original aggregate.' } else { '' }
		os.write_file(out + 'opathseek-' + arch + '-evidence.json', json2.encode(Evidence{arch, context + recovery_note, base, artifacts, inputs}, prettify: true) + '\n')!
	}
	for name in ['host-tests', 'allocs-before', 'allocs-after', 'assertion-control', 'passing-log-control'] { publish(area + name + '.log', out + 'opathseek-' + name + '.log')! }
	println('O_PATH seek qualification audit: PASS')
}
