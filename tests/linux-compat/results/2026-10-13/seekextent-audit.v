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
fn canonical_returns(source string) string {
	mut output := strings.new_builder(source.len); mut names := map[string]string{}; mut position := 0
	for position < source.len {
		start := position
		if source[position].is_letter() || source[position] == `_` {
			position++
			for position < source.len && (source[position].is_alnum() || source[position] == `_`) { position++ }
			token := source[start..position]
			if (token.starts_with('_t') && token.len > 2 && token[2..].bytes().all(it.is_digit()))
				|| (token.starts_with('__discard_') && token.len > 10 && token[10..].bytes().all(it.is_digit() || it == `_`)) {
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
		assert log.contains('LINUX SEEKEXTENT OUTCOMES: ordinary=' + ordinary.str() + ' cases=9000 failures=' + if passing { '0' } else { '9000' })
		assert log.contains('LINUX SEEKEXTENT CONTROLS: ordinary=' + ordinary.str() + ' metadata/blocks/flags/bytes/aliases/descriptor-errors PASS')
	}
}
fn native_failure(log string) {
	assert log.contains('raw=1 size=4 offset=0 whence=3 result=-1/22 expected=0/0'), 'native failure markers required'
	assert log.contains('raw=0 size=4 offset=0 whence=4 result=-1/22 expected=4/0')
	assert log.contains('size=0 offset=0 whence=3 result=-1/22 expected=-1/6')
	assert log.contains('size=8589934609 offset=0 whence=4 result=-1/22 expected=8589934609/0')
	outcomes(log, false)
	assert log.contains('LINUX SEEKEXTENT FAIL: generic DATA/HOLE behavior or storage')
	assert !log.split_into_lines().any(it.trim_space() == 'LINUX SEEKEXTENT: PASS')
}
fn retention(log string, arch string) {
	mut seen := map[string]bool{}; mut rows := [2]int{}; mut pages := [2]int{}
	for line in log.split_into_lines() {
		if !line.starts_with('LINUX SEEKEXTENT SLAB:') && !line.starts_with('LINUX SEEKEXTENT STORAGE:') { continue }
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
// Reverse only the generic extent branch, equivalent selector constants and
// generated return temporaries; all other kernel C must match baseline.
fn restore_generated(generated string, baseline string) {
	body := definition(generated, 'fs__syscall_seek')
	start := '\n\t} else if ((whence == fs__seek_data) || (whence == fs__seek_hole)) {'
	assert body.count(start) == 1
	branch := start + body.all_after(start).all_before('\n\t} else {\n')
	assert branch.count('klock__Lock__release(&handle->l)') == 2 && branch.count('file__FD__unref(fd)') == 2
	assert branch.count('errno__einval') == 1 && branch.count('errno__enxio') == 1
	assert !branch.contains('malloc(') && !branch.contains('memdup(') && !branch.contains('new_array')
	assert branch.contains('offset < 0') && branch.contains('offset >=') && branch.contains('stat__ifreg')
	for error_body in branch.split('multi_return_u64_u64 ')[1..] {
		release := error_body.index('klock__Lock__release(&handle->l)') or { panic('missing unlock') }
		unref := error_body.index('file__FD__unref(fd)') or { panic('missing FD unref') }; assert release < unref
	}
	before := definition(baseline, 'fs__syscall_seek')
	restored_body := body.replace(branch, '').replace('whence < fs__seek_set', 'whence < 0').replace('whence > fs__seek_hole', 'whence > 4')
	assert canonical_returns(restored_body) == canonical_returns(before)
	mut restored := generated.replace(body, before)
	for declaration in ['#define fs__seek_data (3)\n', '#define fs__seek_hole (4)\n'] {
		assert restored.count(declaration) == 1; restored = restored.replace(declaration, '')
	}
	assert restored == baseline, 'only generic seek behavior and its constants may change generated kernel C'
}
fn main() {
	if '--negative-control' in os.args { assert false, 'audit assertions must execute'; return }
	if '--negative-pass-control' in os.args { native_failure(os.read_file(os.args[2])!); return }
	root := '/Users/alex/code/vinix/'; area := '/tmp/vinix-seekextent-1013/'; out := root + 'tests/linux-compat/results/2026-10-13/'
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'audit assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control', area + 'after-final-arm.log'], 'native failure markers required'))!
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == '001a3b9967f14a1c08cebf74247656f8343c5815'
	inputs := object(area + 'kernel-arm/docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 63
	changed := ['kernel/fs/vfs.v']
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
		assert os.stat(area + 'after-' + suffix + '/seekextent/rootfs/tmp')!.mode & 0o777 == 0o755
		original_fixture := os.read_file(area + 'preview.c')!; final_fixture := os.read_file(area + 'final-preview.c')!
		for name in ['probe', 'retained', 'prepare', 'cleanup', 'errors', 'snapshot', 'storage', 'storage_cycle', 'qualify', 'copy_file'] {
			assert canonical_returns(definition(original_fixture, 'seekextentfixture__' + name)) == canonical_returns(definition(final_fixture, 'seekextentfixture__' + name))
		}
		old_walk := definition(original_fixture, 'seekextentfixture__copy_walk')
		assert old_walk.replace('/tmp/linux-seekextent-copy-user', '/tmp/linux-seekextent-copy/user').replace('/tmp/linux-seekextent-copy-root', '/tmp/linux-seekextent-copy/root') == definition(final_fixture, 'seekextentfixture__copy_walk')
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
			rows := receipt['results']!.as_array(); assert rows.len == if phase == 'before' { 1 } else if arch == 'aarch64' { 5 } else { 4 }
			mut names := []string{}
			for row in rows {
				entry := row.as_map(); name := entry['name']!.str(); assert name !in names; names << name
				assert entry['exit_code']!.int() == if name == 'seekextent' { 1 } else { 0 }
				assert entry['source_sha256']!.str() == digest(state + 'sources/' + name + 'fixture/core.v')
				if name == 'seekextent' { assert entry['source_sha256']!.str() == digest(area + 'before-' + suffix + '/sources/seekextentfixture/core.v') }
				else { assert entry['source_sha256']!.str() == digest(root + 'tests/linux-compat/' + name + 'fixture/core.v') }
				assert entry['init_sha256']!.str() == digest(state + name + '/init') && entry['iso_sha256']!.str() == digest(state + name + '/test.iso')
				c := state + name + '/fixture.c'; artifacts[phase + '_' + name + '_generated_c'] = digest(c)
				if name == 'seekextent' {
					assert digest(c) == digest(area + 'preview.c')
					fixture := os.read_file(c)!; assert !fixture.contains('malloc(') && !fixture.contains('memdup(') && !fixture.contains('new_array') && !fixture.contains('v_fixed_index(')
					assert fixture.contains('alloca(') && fixture.contains('fcntl(') && fixture.contains('fstat(')
					if phase == 'before' { native_failure(log) }
					else {
						outcomes(log, true); retention(log, arch)
						assert log.contains('LINUX SEEKEXTENT COPY: ordinary=0 empty/small/page-crossing byte comparison PASS')
						assert !log.contains('LINUX SEEKEXTENT COPY: ordinary=1') && log.contains('LINUX SEEKEXTENT FAIL: generic DATA/HOLE behavior or storage')
					}
				}
				if phase == 'after' && name != 'seekextent' { assert log.contains('LINUX ' + name.to_upper() + ': PASS') }
			}
			if phase == 'after' {
				assert names == if arch == 'aarch64' { ['seekextent', 'seekerror', 'opathseek', 'scalarabi', 'runtime'] } else { ['seekextent', 'seekerror', 'opathseek', 'scalarabi'] }
				assert !log.contains('Linux compatibility guest suite: PASS')
				if arch == 'x86_64' { assert log.contains('LINUX RUNTIME: PASS') && log.contains('failed to open file') && log.contains('/receipt.json') }
			}
			else { assert names == ['seekextent'] }
			publish(state + 'receipt.json', out + 'seekextent-' + phase + '-' + arch + '.json')!; publish(log_path, out + 'seekextent-' + phase + '-' + arch + '.log')!
		}
		assert artifacts['before_seekextent_generated_c'] == artifacts['after_seekextent_generated_c']
		if arch == 'x86_64' {
			rejected := area + 'completion-x86/'; rejected_receipt := object(rejected + 'receipt.json')!
			assert rejected_receipt['architecture']!.str() == arch && rejected_receipt['kernel_sha256']!.str() == artifacts['after_kernel']
			rejected_rows := rejected_receipt['results']!.as_array(); assert rejected_rows.len == 1
			rejected_entry := rejected_rows[0].as_map(); assert rejected_entry['name']!.str() == 'runtime' && rejected_entry['exit_code']!.int() == 1
			assert rejected_entry['init_sha256']!.str() == '' && rejected_entry['iso_sha256']!.str() == ''
			assert rejected_entry['source_sha256']!.str() == digest(rejected + 'sources/runtimefixture/core.v') && rejected_entry['source_sha256']!.str() == digest(root + 'tests/linux-compat/runtimefixture/core.v')
			assert os.read_file(area + 'completion-x86.log')!.contains('serial.c: No space left on device')
			artifacts['rejected_completion_receipt'] = digest(rejected + 'receipt.json'); artifacts['rejected_completion_log'] = digest(area + 'completion-x86.log')
			publish(rejected + 'receipt.json', out + 'seekextent-rejected-completion-x86_64.json')!; publish(area + 'completion-x86.log', out + 'seekextent-rejected-completion-x86_64.log')!
			state := area + 'completion-success-x86/'; receipt := object(state + 'receipt.json')!
			assert receipt['architecture']!.str() == arch && receipt['kernel_sha256']!.str() == artifacts['after_kernel'] && digest(state + 'kernel/bin/vinix') == artifacts['after_kernel']
			rows := receipt['results']!.as_array(); assert rows.len == 1
			entry := rows[0].as_map(); assert entry['name']!.str() == 'runtime' && entry['exit_code']!.int() == 0
			assert entry['source_sha256']!.str() == digest(state + 'sources/runtimefixture/core.v') && entry['source_sha256']!.str() == digest(root + 'tests/linux-compat/runtimefixture/core.v')
			assert entry['init_sha256']!.str() == digest(state + 'runtime/init') && entry['iso_sha256']!.str() == digest(state + 'runtime/test.iso')
			assert digest(state + 'runtime/fixture.c') == digest(area + 'after-x86/runtime/fixture.c')
			log := os.read_file(area + 'completion-success-x86.log')!; assert log.contains('LINUX RUNTIME: PASS') && log.contains('Linux compatibility guest suite: PASS')
			artifacts['completion_receipt'] = digest(state + 'receipt.json'); artifacts['completion_log'] = digest(area + 'completion-success-x86.log')
			artifacts['completion_runtime_generated_c'] = digest(state + 'runtime/fixture.c')
			artifacts['unrecorded_runtime_init'] = digest(area + 'after-x86/runtime/init'); artifacts['unrecorded_runtime_image'] = digest(area + 'after-x86/runtime/test.iso')
			publish(state + 'receipt.json', out + 'seekextent-completion-x86_64.json')!; publish(area + 'completion-success-x86.log', out + 'seekextent-completion-x86_64.log')!
		}
		for phase in ['before', 'after'] {
			state := area + phase + '-final-' + suffix + '/'; receipt := object(state + 'receipt.json')!
			assert receipt['architecture']!.str() == arch && receipt['kernel_sha256']!.str() == artifacts[phase + '_kernel'] && digest(state + 'kernel/bin/vinix') == artifacts[phase + '_kernel']
			rows := receipt['results']!.as_array(); assert rows.len == 1
			entry := rows[0].as_map(); assert entry['name']!.str() == 'seekextent' && entry['exit_code']!.int() == if phase == 'before' { 1 } else { 0 }
			assert entry['source_sha256']!.str() == digest(state + 'sources/seekextentfixture/core.v') && entry['source_sha256']!.str() == digest(root + 'tests/linux-compat/seekextentfixture/core.v')
			assert entry['init_sha256']!.str() == digest(state + 'seekextent/init') && entry['iso_sha256']!.str() == digest(state + 'seekextent/test.iso')
			c := state + 'seekextent/fixture.c'; assert digest(c) == digest(area + 'final-preview.c')
			fixture := os.read_file(c)!; assert !fixture.contains('malloc(') && !fixture.contains('memdup(') && !fixture.contains('new_array') && !fixture.contains('v_fixed_index(')
			log_path := state.trim_right('/') + '.log'; log := os.read_file(log_path)!
			if phase == 'before' { native_failure(log) } else {
				outcomes(log, true); retention(log, arch)
				for group in 0 .. 2 { assert log.contains('LINUX SEEKEXTENT COPY: ordinary=' + group.str() + ' empty/small/page-crossing byte comparison PASS') }
				assert log.contains('LINUX SEEKEXTENT: PASS') && log.contains('Linux compatibility guest suite: PASS')
			}
			artifacts['final_' + phase + '_receipt'] = digest(state + 'receipt.json'); artifacts['final_' + phase + '_log'] = digest(log_path); artifacts['final_' + phase + '_generated_c'] = digest(c)
			publish(state + 'receipt.json', out + 'seekextent-final-' + phase + '-' + arch + '.json')!; publish(log_path, out + 'seekextent-final-' + phase + '-' + arch + '.log')!
		}
		context := 'Native musl ELF64 generic SEEK_DATA/SEEK_HOLE: 9,000 checks per root/UID1000 cohort cover five file sizes (empty, four bytes, page crossing, above 4GiB and across 8GiB), three access modes, original/dup/F_DUPFD_CLOEXEC aliases, ten signed64 positions, raw upper FD/selector words and libc lseek. Every in-file position is conservatively reported as data; the final EOF is the hole. Negative/EOF/beyond positions return ENXIO without changing the cursor. Unchanged kernels fail all 9,000 checks per cohort; candidates pass 18,000 per architecture. Metadata inode/device/type/size/blocks, alias flags, real A/zero/Z contents and EOF buffers are retained. Invalid/O_PATH descriptors and pipes/sockets retain EBADF/ESPIPE. Forty-five stable descriptors warm 32 and measure 200 cycles of 900 raw/libc seeks plus three temporary alias probes and metadata/data controls, with flat slab live objects and big pages. A bounded backup-style DATA/HOLE walker copies empty/small/page-crossing files and compares every byte. Only fs/vfs.v changes in isolated trees at001a3b9967. Emitted new error branches release the existing handle lock before exactly one FD unref; no new owner/allocation/lock. Reversing the extent branch, selector constants and return temporaries restores the seek body; replacing that body and removing two constant declarations restores the entire baseline kernel C. All four fixture C captures match preview, with bounded Handles/Slabs/copy buffers and no hidden heap promotion. Independent final lifetime review is closed. Both architectures also pass seekerror, opathseek, scalarabi and runtime; eight host test files, fresh builds and inventory checks pass. Existing allocation allowance failures retain406 ARM/295 x86 sites and identical NEW rows. All63 isolated semantic inputs are fingerprinted separately from the public committed-parent inventory. Both failing audit controls execute. Physical unallocated-extent discovery, concurrent truncate/shared-offset races, disk-backed qualification, GNU wrappers/foreign ELF32 paths, allocator exhaustion and full Linux installation/sandbox/portal/runtime compatibility remain separate work.'
		correction := ' Initial candidate aggregates remain failed: all syscall/storage checks and root copy passed, but UID1000 copy creation used the minimal guest root-owned0755 /tmp. The final fixture creates/chmods its own writable copy directory and moves only copy targets. All check/owner/observer/copy bodies otherwise remain identical after canonicalizing source-position-derived unused loop-counter names. Fresh final baseline and candidate runs bind the corrected source/C and preserve original failures; final candidate passes both copy cohorts on the identical kernel.'
		receipt_note := if arch == 'x86_64' { ' The initial x86 aggregate additionally could not open its final receipt for writing after a logged runtime PASS, leaving four recorded rows. The first runtime-only completion failed before init/image creation when host ENOSPC stopped serial.c generation; its failed log and blank artifact hashes remain published. A fresh completion receipt passes on the identical kernel and identical generated fixture C; the original partial receipt remains unchanged.' } else { '' }
		os.write_file(out + 'seekextent-' + arch + '-evidence.json', json2.encode(Evidence{arch, context + correction + receipt_note, base, artifacts, inputs}, prettify: true) + '\n')!
	}
	for name in ['host-tests', 'allocs-before', 'allocs-after', 'assertion-control', 'passing-log-control'] { publish(area + name + '.log', out + 'seekextent-' + name + '.log')! }
	println('Generic DATA/HOLE qualification audit: PASS')
}
