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
	if code != 1 || !output.contains(marker) { panic('audit negative control did not execute') }
	return output
}
fn outcomes(log string, passing bool) {
	for ordinary in 0 .. 2 {
		assert log.contains('LINUX IOVPACKET OUTCOMES: ordinary=' + ordinary.str() + ' cases=350 failures=' + if passing { '0' } else { '140' })
	}
}
fn native_failure(log string) {
	assert log.contains('version=0 count=2 variant=3 result=1/0 expected=-1/14 bytes=41,00'), 'native failure markers required'
	assert log.contains('version=0 count=2 variant=5 result=1/0 expected=-1/14 bytes=41,00 boundary=42')
	assert log.contains('version=0 count=2 variant=6 result=-1/14 expected=-1/11')
	assert log.contains('version=0 count=2 variant=7 result=-1/14 expected=0/0')
	outcomes(log, false)
	assert log.contains('LINUX IOVPACKET FAIL: UNIX record copy faults or storage')
	assert !log.split_into_lines().any(it.trim_space() == 'LINUX IOVPACKET: PASS')
}
fn retention(log string, arch string, marker string) {
	mut seen := map[string]bool{}; mut rows := [2]int{}; mut pages := [2]int{}
	for line in log.split_into_lines() {
		if !line.starts_with('LINUX ' + marker + ' SLAB:') && !line.starts_with('LINUX ' + marker + ' STORAGE:') { continue }
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
	root := '/Users/alex/code/vinix/'; area := '/tmp/vinix-iovpacket-1013/'; out := root + 'tests/linux-compat/results/2026-10-13/'
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'audit assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control', area + 'after-arm.log'], 'native failure markers required'))!
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == 'b463fe892f479445ad56fba4815e36c770b15cef'
	inputs := object(area + 'kernel-arm/docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 63
	for path in ['kernel/resource/resource.v', 'kernel/syscall/table/linux_common.v', 'tools/linux-compat/coverage.v'] { assert digest(root + path) == inputs[path] }
	assert git('/tmp/vinix-iovposition-1013/v-snapshot', ['rev-parse', 'HEAD'])! == 'f6358ecff9cffbf2d8b03e6a09269aac7707e26c'
	assert git('/tmp/vinix-iovposition-1013/v-snapshot', ['diff', '--name-only', 'HEAD'])! == ''
	// Check the streaming system implementation against V SHA-256.
	assert digest(area + 'host-tests.log') == sha256.sum(os.read_bytes(area + 'host-tests.log')!).hex()
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total')
	assert os.read_file(area + 'geometry.log')!.contains('Mapping metadata storage admission: PASS')
	assert os.read_file(area + 'coverage-check.log')!.contains('Linux dispatch coverage: PASS')
	before_allocs := os.read_file(area + 'allocs-before.log')!; after_allocs := os.read_file(area + 'allocs-after.log')!
	assert before_allocs.split_into_lines().filter(it.starts_with('NEW:')) == after_allocs.split_into_lines().filter(it.starts_with('NEW:'))
	for arch, row in {'aarch64': '657 source files, 406 allocation sites', 'x86_64': '653 source files, 295 allocation sites'} {
		assert before_allocs.contains(arch + ': ' + row + ' (V exit 0)') && after_allocs.contains(arch + ': ' + row + ' (V exit 0)')
	}
	assert git(area + 'alloc-baseline', ['rev-parse', 'HEAD'])! == base
	assert git(area + 'alloc-baseline', ['diff', '--name-only', 'HEAD'])! == ''
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'
		assert git(tree, ['rev-parse', 'HEAD'])! == base
		assert git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])! == 'kernel/resource/resource.v\nkernel/syscall/table/linux_common.v'
		for path, hash in inputs { if path.starts_with('kernel/') { assert digest(tree + path) == hash } }
		generated := os.read_file(tree + 'kernel/obj/blob.c')!; baseline_c := os.read_file(area + 'before-' + suffix + '.c')!
		for name in ['table__linux_readv_flags', 'table__linux_writev_flags', 'table__linux_positioned_iov'] {
			assert definition(generated, name) == definition(baseline_c, name)
		}
		for name in ['readv', 'writev', 'preadv', 'pwritev', 'preadv2', 'pwritev2'] { assert definition(generated, 'table__syscall_linux_' + name) == definition(baseline_c, 'table__syscall_linux_' + name) }
		query := definition(generated, 'resource__read_keeps_boundaries')
		assert query.count('__builtin_alloca(sizeof(resource__RecordReadScratch))') == 1
		assert query.count('._object = res->_object') == 1 && query.contains('return resource__RecordReadableResource__keeps_boundaries(&(scratch->backend));')
		for forbidden in ['malloc(', 'memdup(', 'new_array', 'v_free(', 'klock__', '__ref(', '__unref('] { assert !query.contains(forbidden) }
		helper := definition(generated, 'table__linux_readv_stream')
		assert helper.count('resource__read_keeps_boundaries(') == 1 && helper.count('memory__malloc_packed_fallible(') == 1
		assert helper.count('fs__read_pinned_descriptor(') == 1 && helper.contains('vmstorage__allocation_bytes(size)')
		assert helper.contains('krandom__explicit_bzero(buffer, (size_t)(size));') && helper.contains('v_free(buffer)') && helper.contains('kbudget__release(charge)')
		assert !helper.contains('file__FD__unref(') && !helper.contains('table__LinuxIOVector__release(')
		unchanged := helper.replace('\n\tbool record = resource__read_keeps_boundaries(fd->handle->resource);', '')
			.replace('!record && (i < count)', 'i < count').replace('(copied != 0) && !record', 'copied != 0')
		assert unchanged == definition(baseline_c, 'table__linux_readv_stream')
		mut artifacts := {'compiler': digest('/tmp/vinix-iovposition-1013/v-snapshot/v'), 'controller': digest(area + 'run'), 'controller_source': digest(root + 'tests/linux-compat/run.v'),
			'kernel_generated_c': digest(tree + 'kernel/obj/blob.c'), 'kernel_before_generated_c': digest(area + 'before-' + suffix + '.c'),
			'audit': digest(@FILE), 'host_tests': digest(area + 'host-tests.log'), 'geometry': digest(area + 'geometry.log'),
			'allocs_before': digest(area + 'allocs-before.log'), 'allocs_after': digest(area + 'allocs-after.log'),
			'assertion_control': digest(area + 'assertion-control.log'), 'passing_log_control': digest(area + 'passing-log-control.log'),
			'committed_fixture_source': digest(root + 'tests/linux-compat/iovpacketfixture/core.v'), 'committed_fixture_generated_c': digest(area + 'committed-fixture.c')}
		mut all_candidate_names := []string{}
		for phase in ['before', 'after', 'completion'] {
			state := area + phase + '-' + suffix + '/'; receipt := object(state + 'receipt.json')!
			kernel_hash := digest(if phase == 'before' { area + 'before-' + suffix + '.kernel' } else { tree + 'kernel/bin/vinix' })
			assert receipt['architecture']!.str() == arch && receipt['kernel_sha256']!.str() == kernel_hash && digest(state + 'kernel/bin/vinix') == kernel_hash
			log := os.read_file(area + phase + '-' + suffix + '.log')!
			artifacts[phase + '_kernel'] = kernel_hash; artifacts[phase + '_receipt'] = digest(state + 'receipt.json'); artifacts[phase + '_log'] = digest(area + phase + '-' + suffix + '.log')
			rows := receipt['results']!.as_array()
			assert rows.len == if phase == 'before' { 1 } else if phase == 'after' { if arch == 'aarch64' { 5 } else { 4 } } else { if arch == 'aarch64' { 3 } else { 4 } }
			mut names := []string{}
			for row in rows {
				entry := row.as_map(); name := entry['name']!.str(); assert name !in names; names << name
				assert entry['exit_code']!.int() == if phase == 'before' { 1 } else { 0 }
				frozen_source := state + 'sources/' + name + 'fixture/core.v'
				assert entry['source_sha256']!.str() == digest(frozen_source)
				if name == 'iovpacket' {
					// Remove trailing blank lines for the commit while retaining the
					// exact tested source hashes. Fresh generated C must be identical.
					assert os.read_file(frozen_source)!.trim_right('\n') + '\n' == os.read_file(root + 'tests/linux-compat/iovpacketfixture/core.v')!
				} else { assert entry['source_sha256']!.str() == digest(root + 'tests/linux-compat/' + name + 'fixture/core.v') }
				assert entry['init_sha256']!.str() == digest(state + name + '/init') && entry['iso_sha256']!.str() == digest(state + name + '/test.iso')
				c := state + name + '/fixture.c'; artifacts[phase + '_' + name + '_generated_c'] = digest(c)
				if name == 'iovpacket' {
					assert digest(c) == artifacts['committed_fixture_generated_c']
					fixture := os.read_file(c)!; assert !fixture.contains('malloc(') && !fixture.contains('memdup(') && !fixture.contains('new_array') && !fixture.contains('v_fixed_index(')
					assert fixture.contains('alloca(') && fixture.contains('mprotect(') && fixture.contains('mmap(')
					if phase == 'before' { native_failure(log) } else { outcomes(log, true) }
				}
				if phase != 'before' { assert log.contains('LINUX ' + name.to_upper() + ': PASS'); assert name !in all_candidate_names; all_candidate_names << name }
			}
			if phase == 'after' {
				assert names == if arch == 'aarch64' { ['iovpacket', 'iovstream', 'iovrange', 'iovimport', 'iovpin'] } else { ['iovpacket', 'iovstream', 'iovrange', 'iovimport'] }
				// Host storage exhaustion stopped compilation/receipt publication
				// after these successful rows. Keep this aggregate failed.
				assert log.contains('No space left on device') && log.contains('failed to open file')
				assert !log.contains('Linux compatibility guest suite: PASS')
				for name in names { retention(log, arch, name.to_upper()) }
			} else if phase == 'completion' {
				assert names == if arch == 'aarch64' { ['iovflags', 'iovfd', 'runtime'] } else { ['iovpin', 'iovflags', 'iovfd', 'runtime'] }
				assert log.contains('Linux compatibility guest suite: PASS')
				assert !log.contains('No space left on device')
				for name in names { if name != 'runtime' { retention(log, arch, name.to_upper()) } }
			}
			publish(state + 'receipt.json', out + 'iovpacket-' + phase + '-' + arch + '.json')!; publish(area + phase + '-' + suffix + '.log', out + 'iovpacket-' + phase + '-' + arch + '.log')!
		}
		assert all_candidate_names == ['iovpacket', 'iovstream', 'iovrange', 'iovimport', 'iovpin', 'iovflags', 'iovfd', 'runtime']
		assert artifacts['before_iovpacket_generated_c'] == artifacts['after_iovpacket_generated_c']
		context := 'Native musl ELF64 UNIX datagram/seqpacket readv and current-position preadv2:350 checks in each root/UID1000 cohort with2/8/9/513/1024-entry immutable imports. Unchanged kernels fail140 checks per cohort. Selected records retire on inaccessible/read-only/later/page-crossing destination faults and report EFAULT even after copied prefixes. Empty queues return EAGAIN before destination copy; zero-length queued records return0 and retire only that record. Valid empty/malformed/count/length/flag imports preserve queues. Short records do not touch later invalid destinations. Fixed kernels pass all700 checks per architecture, seven other native guest cases, eight host test files and mapping geometry. Host storage exhaustion stopped the initial aggregate after five successful ARM/four successful x86 rows; its failed logs and partial receipts are preserved. Fresh completion suites pass the remaining three ARM/four x86 cases on the identical candidate kernels, without relabeling the initial aggregate. Stable two-pair/two-page retention cohorts warm32 and measure200 cycles through210 transfers each, requiring identical slab live objects and big pages. Both kernels are freshly built in isolated worktrees at b463fe892; only resource.v and linux_common.v differ. Generated C proves a synchronous borrowed stack interface query, unchanged FD/vector ownership and buffer erase/free before charge release; independent lifetime review found no blocker. Fresh allocation audits keep existing406ARM/295x86 sites and identical allowance failures; no allowance increase. Source inventory includes63 inputs, adding UNIX endpoint semantics. Assertion and passing-log rejection controls both execute. Scalar reads/recvmsg, Internet/netlink records, stream later-copy faults/queue rollback, GNU wrappers, ELF32/translated paths, allocation exhaustion, shared offsets and complete Linux application installation/compatibility remain unqualified. Previous broader performance/desktop evidence belongs to the preceding stream fix and is not relabeled as a run on this kernel.'
		os.write_file(out + 'iovpacket-' + arch + '-evidence.json', json2.encode(Evidence{arch, context, base, artifacts, inputs}, prettify: true) + '\n')!
	}
	for name in ['host-tests', 'geometry', 'allocs-before', 'allocs-after', 'assertion-control', 'passing-log-control'] { publish(area + name + '.log', out + 'iovpacket-' + name + '.log')! }
	println('UNIX record-vector qualification audit: PASS')
}
