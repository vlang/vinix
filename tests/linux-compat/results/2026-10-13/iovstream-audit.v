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
fn digest(path string) string { return sha256.sum(os.read_bytes(path) or { panic(err) }).hex() }
fn stream_digest(path string) !string {
	mut input := os.open(path)!; defer { input.close() }
	mut buffer := []u8{len: 1024 * 1024}
	$if macos {
		// The system SHA-256 implementation keeps multi-GiB archive checks
		// bounded in memory. Compare it with V SHA-256 on small inputs below.
		mut state := C.CC_SHA256_CTX{}
		assert C.CC_SHA256_Init(unsafe { &state }) == 1
		for {
			n := input.read(mut buffer) or { if err is os.Eof { break }; return err }
			if n == 0 { break }
			assert C.CC_SHA256_Update(unsafe { &state }, buffer.data, u32(n)) == 1
		}
		mut result := []u8{len: 32}
		assert C.CC_SHA256_Final(result.data, unsafe { &state }) == 1
		return result.hex()
	} $else {
		mut state := sha256.new()
		for {
			n := input.read(mut buffer) or { if err is os.Eof { break }; return err }
			if n == 0 { break }; assert state.write(buffer[..n])! == n
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
	assert code == 0; return output.trim_space()
}
fn definition(source string, name string) string {
	lines := source.split_into_lines().filter(it.contains(' ' + name + '(') && it.ends_with(' {'))
	assert lines.len == 1; return source.all_after(lines[0]).all_before('\n}\n')
}
fn control(args []string, marker string) {
	mut p := os.new_process(os.executable()); p.set_args(args); p.set_redirect_stdio(); p.run()
	output := p.stdout_slurp() + p.stderr_slurp(); p.wait(); code := p.code; p.close()
	if code != 1 || !output.contains(marker) { panic('audit negative control did not execute') }
}
fn outcomes(log string, passing bool) {
	for ordinary in 0 .. 2 {
		assert log.contains('LINUX IOVSTREAM OUTCOMES: ordinary=' + ordinary.str() + ' cases=220 failures=' + if passing { '0' } else { '80' })
	}
}
fn native_failure(log string) {
	assert log.contains('kind=0 version=0 count=2 variant=1 early=0 result=4/0 expected=2/0'), 'native failure markers required'
	assert log.contains('kind=2 version=0 count=2 variant=0 early=1 result=2/0 expected=2/0 bytes=41,58,00,00')
	assert log.contains('kind=3 version=1 count=1024 result=524288/0 expected=1048576/0')
	outcomes(log, false)
	assert log.contains('LINUX IOVSTREAM FAIL: record boundaries, available data or storage')
	assert !log.split_into_lines().any(it.trim_space() == 'LINUX IOVSTREAM: PASS')
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
fn performance(root string, area string, out string, base string, inputs map[string]string) ! {
	previous := '/tmp/vinix-iovposition-1013/'
	prior := object(out + 'iovposition-performance-evidence.json')!['artifacts']!.as_map_of_strings()
	assert stream_digest(area + 'before-arm.kernel')! == digest(area + 'before-arm.kernel')
	assert stream_digest(area + 'host-tests.log')! == digest(area + 'host-tests.log')
	mut artifacts := {'controller': digest(previous + 'perf'), 'controller_source': digest(previous + 'perf.v'),
		'desktop': digest(previous + 'vinix-desktop'), 'cached_initramfs': stream_digest(root + 'build-support/init-aarch64/initramfs-desktop.tar')!,
		'before_kernel': digest(area + 'before-arm.kernel'), 'after_kernel': digest(area + 'kernel-arm/kernel/bin/vinix'),
		'auditor': digest(@FILE), 'previous_image_evidence': digest(out + 'iovposition-performance-evidence.json')}
	for key in ['controller', 'controller_source', 'desktop', 'cached_initramfs'] { assert artifacts[key] == prior[key] }
	assert artifacts['controller_source'] == digest(out + 'iovposition-performance.v')
	for prefix in ['perf-before', 'perf-after', 'desktop-after'] {
		log := os.read_file(area + prefix + '.log')!; serial := os.read_file(area + prefix + '/serial.log')!
		assert log.contains(serial) && serial.contains('VINIX DESKTOP PERF: DONE')
		assert !serial.contains('PERF-ERROR') && !serial.contains('KERNEL PANIC') && !serial.contains('FATAL EXCEPTION')
		rows := json2.decode[json2.Any](os.read_file(area + prefix + '.json')!)!.as_array()
		if prefix.starts_with('perf') {
			ops := rows.filter(it.as_map()['report'] or { json2.Any('') }.str() == 'PERF-OPS')
			churn := rows.filter(it.as_map()['report'] or { json2.Any('') }.str() == 'PERF-CHURN')
			cache := rows.filter(it.as_map()['report'] or { json2.Any('') }.str() == 'PERF-CACHE')
			assert ops.len == 36 && churn.len == 4 && cache.len == 1
			for row in ops { entry := row.as_map(); assert entry['count']!.str() == '200' && entry['bytes_per_op']!.str() == '0' }
			for row in churn {
				entry := row.as_map(); assert entry['runs']!.str() == '300'
				if prefix == 'perf-before' && entry['program']!.str() == '/usr/bin/curl --version' {
					assert entry['retained_kb']!.str() == '16' && entry['per_run_bytes']!.str() == '54'
				} else { assert entry['retained_kb']!.str() == '0' && entry['per_run_bytes']!.str() == '0' }
			}

			slab_rows := serial.split_into_lines().filter(it.starts_with('PERF-SLAB '))
			if prefix == 'perf-before' {
				assert slab_rows.len == 1 && slab_rows[0].contains('program="/usr/bin/curl --version" class=size-32 objects=+0 pages=+1')
			} else { assert slab_rows.len == 0 }
			assert cache[0].as_map()['written_mb']!.str() == '32'
		} else {
			assert rows.len == 3
			for i, scenario in ['idle', 'apps', 'drag'] {
				entry := rows[i].as_map(); assert entry['scenario']!.str() == scenario && entry['round']!.int() == 1
				assert entry['seconds']!.str() == '5.0' && entry['processes']!.str().int() >= if scenario == 'apps' { 7 } else { 2 }
				artifacts[scenario + '_screenshot'] = digest(area + 'desktop-after-shots/new-' + scenario + '-1.ppm')
			}
		}
		artifacts[prefix + '_json'] = digest(area + prefix + '.json'); artifacts[prefix + '_log'] = digest(area + prefix + '.log'); artifacts[prefix + '_serial'] = digest(area + prefix + '/serial.log')
		publish(area + prefix + '.json', out + 'iovstream-' + prefix + '.json')!; publish(area + prefix + '.log', out + 'iovstream-' + prefix + '.log')!
	}
	artifacts['candidate_apps_png'] = digest(area + 'desktop-apps.png'); publish(area + 'desktop-apps.png', out + 'iovstream-desktop-apps.png')!
	context := 'AArch64 QEMU paired retention comparison on the valid vector-stream fix using identical cached desktop archive, extracted13MiB desktop and preserved V controller. All36 200-operation rows retain zero bytes before/after. All4 candidate300-process churn rows retain zero bytes/pages/live objects. Baseline curl records16KiB retained slab capacity (one size32 page with zero additional live objects, reported54bytes/run); the other3 baseline rows remain flat. This capacity difference is preserved and does not establish a causal performance improvement. The32MiB cache workload records expected cache growth. Candidate idle/apps/drag each pass one5-second sample; the7-process apps screenshot was inspected. These startup/retention checks do not qualify Linux installation/lifecycle, foreign ABI/ELF32, x86 desktop performance, physical hardware or a benchmark threshold. Shared caches were preserved and only disposable VM state cleaned. Archive hashing uses system SHA-256 on macOS (checked against V SHA-256 on small artifacts), with a portable V fallback.'
	os.write_file(out + 'iovstream-performance-evidence.json', json2.encode(Evidence{'aarch64', context, base, artifacts, inputs}, prettify: true) + '\n')!
}
fn main() {
	if '--negative-control' in os.args { assert false, 'audit assertions must execute'; return }
	if '--negative-pass-control' in os.args { native_failure(os.read_file(os.args[2])!); return }
	control(['--negative-control'], 'audit assertions must execute')
	root := '/Users/alex/code/vinix/'; area := '/tmp/vinix-iovstream-1013/'; out := root + 'tests/linux-compat/results/2026-10-13/'
	control(['--negative-pass-control', area + 'after-final-arm.log'], 'native failure markers required')
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == 'bced1c4ec72cbdca89df5b398a101161ed7003f2'
	// Fingerprint the isolated candidate, excluding concurrent edits to
	// unrelated source files in the shared checkout.
	inputs := object(area + 'kernel-arm/docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 62
	assert digest(root + 'kernel/syscall/table/linux_common.v') == inputs['kernel/syscall/table/linux_common.v']
	assert git('/tmp/vinix-iovposition-1013/v-snapshot', ['rev-parse', 'HEAD'])! == 'f6358ecff9cffbf2d8b03e6a09269aac7707e26c'
	assert git('/tmp/vinix-iovposition-1013/v-snapshot', ['diff', '--name-only', 'HEAD'])! == ''
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total')
	assert os.read_file(area + 'geometry.log')!.contains('Mapping metadata storage admission: PASS')
	assert os.read_file(area + 'coverage-check.log')!.contains('Linux dispatch coverage: PASS')
	before_allocs := os.read_file(area + 'allocs-before.log')!; after_allocs := os.read_file(area + 'allocs-after.log')!
	assert before_allocs.split_into_lines().filter(it.starts_with('NEW:')) == after_allocs.split_into_lines().filter(it.starts_with('NEW:'))
	for arch, row in {'aarch64': '655 source files, 406 allocation sites', 'x86_64': '651 source files, 295 allocation sites'} {
		assert before_allocs.contains(arch + ': ' + row + ' (V exit 0)') && after_allocs.contains(arch + ': ' + row + ' (V exit 0)')
	}
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'
		assert git(tree, ['rev-parse', 'HEAD'])! == base
		assert git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])! == 'kernel/syscall/table/linux_common.v'
		for path, hash in inputs { if path.starts_with('kernel/') { assert digest(tree + path) == hash } }
		generated := os.read_file(tree + 'kernel/obj/blob.c')!; baseline_c := os.read_file(area + 'before-' + suffix + '.c')!
		assert definition(generated, 'table__linux_positioned_iov') == definition(baseline_c, 'table__linux_positioned_iov')
		// The isolated copy retained two concurrently added cleanup wipes
		// in existing writev/sendfile. They are independently owned hunks;
		// compare writev without its nine emitted erase-before-free sites.
		write_body := definition(generated, 'table__linux_writev_flags')
		wipe := 'krandom__explicit_bzero((void*)(buffer), (size_t)(size));'
		assert write_body.split_into_lines().filter(it.trim_space() == wipe).len == 9
		assert write_body.split_into_lines().filter(it.trim_space() != wipe).join('\n').trim_space() == definition(baseline_c, 'table__linux_writev_flags').trim_space()
		body := definition(generated, 'table__linux_readv_flags')
		assert body.count('file__fd_from_fdnum(') == 1 && body.contains('file__FD__unref(')
		assert body.count('table__import_linux_iov(') == 1 && body.contains('table__LinuxIOVector__release(')
		assert body.count('table__linux_readv_stream(') == 1
		helper := definition(generated, 'table__linux_readv_stream')
		assert helper.count('memory__malloc_packed_fallible(') == 1 && helper.count('fs__read_pinned_descriptor(') == 1
		assert helper.contains('vmstorage__allocation_bytes(size)') && helper.contains('proc__reserve_kernel(')
		assert helper.contains('v_free(buffer)') && helper.contains('kbudget__release(charge)')
		assert !helper.contains('file__FD__unref(') && !helper.contains('table__LinuxIOVector__release(')
		assert !helper.contains('memdup(') && !helper.contains('new_array') && !helper.contains('v_fixed_index(')
		for name in ['readv', 'writev', 'preadv', 'pwritev', 'preadv2', 'pwritev2'] { assert definition(generated, 'table__syscall_linux_' + name) == definition(baseline_c, 'table__syscall_linux_' + name) }
		mut artifacts := {'compiler': digest('/tmp/vinix-iovposition-1013/v-snapshot/v'), 'controller': digest(area + 'run'),
			'kernel_generated_c': digest(tree + 'kernel/obj/blob.c'), 'kernel_before_generated_c': digest(area + 'before-' + suffix + '.c'),
			'audit': digest(@FILE), 'host-tests': digest(area + 'host-tests.log'), 'geometry': digest(area + 'geometry.log'),
			'allocs-before': digest(area + 'allocs-before.log'), 'allocs-after': digest(area + 'allocs-after.log'), 'previous_native_evidence': digest(out + 'iovfd-' + arch + '-evidence.json')}
		for phase in ['before', 'after'] {
			state := area + phase + '-final-' + suffix + '/'; receipt := object(state + 'receipt.json')!
			kernel_hash := digest(if phase == 'before' { area + 'before-' + suffix + '.kernel' } else { tree + 'kernel/bin/vinix' })
			assert receipt['architecture']!.str() == arch && receipt['kernel_sha256']!.str() == kernel_hash && digest(state + 'kernel/bin/vinix') == kernel_hash
			log := os.read_file(area + phase + '-final-' + suffix + '.log')!
			if phase == 'before' {
				prior := object(out + 'iovfd-' + arch + '-evidence.json')!['artifacts']!.as_map_of_strings()
				assert kernel_hash == prior['after_kernel'] && digest(area + 'before-' + suffix + '.c') == prior['kernel_generated_c']
			}
			artifacts[phase + '_kernel'] = kernel_hash; artifacts[phase + '_receipt'] = digest(state + 'receipt.json'); artifacts[phase + '_log'] = digest(area + phase + '-final-' + suffix + '.log')
			rows := receipt['results']!.as_array(); assert rows.len == 1
			mut names := []string{}
			for row in rows {
				entry := row.as_map(); name := entry['name']!.str(); assert name !in names; names << name
				assert entry['exit_code']!.int() == if phase == 'before' && name == 'iovstream' { 1 } else { 0 }
				assert entry['source_sha256']!.str() == digest(state + 'sources/' + name + 'fixture/core.v') && entry['source_sha256']!.str() == digest(root + 'tests/linux-compat/' + name + 'fixture/core.v')
				assert entry['init_sha256']!.str() == digest(state + name + '/init') && entry['iso_sha256']!.str() == digest(state + name + '/test.iso')
				c := state + name + '/fixture.c'; artifacts[phase + '_' + name + '_generated_c'] = digest(c)
				if name == 'iovstream' {
					fixture := os.read_file(c)!; assert !fixture.contains('malloc(') && !fixture.contains('memdup(') && !fixture.contains('new_array') && !fixture.contains('v_fixed_index(')
					assert fixture.contains('alloca(') && fixture.contains('pthread_join(') && fixture.contains('mmap(')
					if phase == 'before' { native_failure(log) } else { outcomes(log, true); retention(log, arch, 'IOVSTREAM') }
				}
				if phase == 'after' { assert log.contains('LINUX ' + name.to_upper() + ': PASS') }
			}
			if phase == 'after' {
				assert names == ['iovstream']
				assert log.contains('Linux compatibility guest suite: PASS')
			}
			publish(state + 'receipt.json', out + 'iovstream-' + phase + '-' + arch + '.json')!; publish(area + phase + '-final-' + suffix + '.log', out + 'iovstream-' + phase + '-' + arch + '.log')!
		}
		assert artifacts['before_iovstream_generated_c'] == artifacts['after_iovstream_generated_c']
		// The initial candidate suite remains failed: its stream retention
		// stress exhausted the independent socket-object budget. Eleven other
		// cases passed. Qualify those rows separately from the corrected rerun.
		regression_state := area + 'after-' + suffix + '/'
		regression := object(regression_state + 'receipt.json')!
		assert regression['kernel_sha256']!.str() == artifacts['after_kernel']
		regression_log := os.read_file(area + 'after-' + suffix + '.log')!
		regression_rows := regression['results']!.as_array(); assert regression_rows.len == 12
		mut regression_names := []string{}
		for row in regression_rows {
			entry := row.as_map(); name := entry['name']!.str(); regression_names << name
			assert entry['exit_code']!.int() == if name == 'iovstream' { 1 } else { 0 }
			assert entry['source_sha256']!.str() == digest(regression_state + 'sources/' + name + 'fixture/core.v')
			assert entry['init_sha256']!.str() == digest(regression_state + name + '/init') && entry['iso_sha256']!.str() == digest(regression_state + name + '/test.iso')
			if name != 'iovstream' { assert entry['source_sha256']!.str() == digest(root + 'tests/linux-compat/' + name + 'fixture/core.v'); assert regression_log.contains('LINUX ' + name.to_upper() + ': PASS') }
			artifacts['regression_' + name + '_generated_c'] = digest(regression_state + name + '/fixture.c')
		}
		assert regression_names == ['iovstream', 'iovfd', 'iovflags', 'iovposition', 'iovoffset', 'iovrange', 'iovimport', 'iovpin', 'pathio', 'readerror', 'pipezero', 'runtime']
		for marker in ['IOVFD', 'IOVFLAGS', 'IOVPOSITION', 'IOVOFFSET', 'IOVRANGE', 'IOVIMPORT', 'IOVPIN'] { retention(regression_log, arch, marker) }
		baseline_import_state := area + 'before-' + suffix + '/'
		baseline_import := object(baseline_import_state + 'receipt.json')!['results']!.as_array()[1].as_map()
		assert baseline_import['name']!.str() == 'iovimport' && baseline_import['exit_code']!.int() == 0
		assert baseline_import['source_sha256']!.str() == digest(root + 'tests/linux-compat/iovimportfixture/core.v')
		assert digest(baseline_import_state + 'iovimport/fixture.c') == artifacts['regression_iovimport_generated_c']
		artifacts['baseline_import_receipt'] = digest(baseline_import_state + 'receipt.json'); artifacts['baseline_import_log'] = digest(area + 'before-' + suffix + '.log')
		publish(baseline_import_state + 'receipt.json', out + 'iovstream-baseline-import-' + arch + '.json')!; publish(area + 'before-' + suffix + '.log', out + 'iovstream-baseline-import-' + arch + '.log')!
		artifacts['initial_candidate_receipt'] = digest(regression_state + 'receipt.json'); artifacts['initial_candidate_log'] = digest(area + 'after-' + suffix + '.log')
		publish(regression_state + 'receipt.json', out + 'iovstream-regressions-' + arch + '.json')!; publish(area + 'after-' + suffix + '.log', out + 'iovstream-regressions-' + arch + '.log')!
		diagnostic := area + 'retention-diagnostic-' + suffix
		diagnostic_log := os.read_file(diagnostic + '.log')!
		assert diagnostic_log.contains('socket 4096 33554432') && diagnostic_log.contains('LastDenied: objects') && diagnostic_log.contains('LastDeniedKind: socket')
		assert object(diagnostic + '/receipt.json')!['results']!.as_array()[0].as_map()['exit_code']!.int() == 1
		artifacts['retention_diagnostic_log'] = digest(diagnostic + '.log'); artifacts['retention_diagnostic_receipt'] = digest(diagnostic + '/receipt.json')
		publish(diagnostic + '.log', out + 'iovstream-retention-diagnostic-' + arch + '.log')!; publish(diagnostic + '/receipt.json', out + 'iovstream-retention-diagnostic-' + arch + '.json')!
		rejected := area + 'rejected-compile-' + suffix
		assert os.read_file(rejected + '.log')!.contains("undeclared function 'v_fixed_index'") || os.read_file(rejected + '.log')!.contains("implicit declaration of function 'v_fixed_index'")
		assert object(rejected + '/receipt.json')!['results']!.as_array()[0].as_map()['exit_code']!.int() == 1
		artifacts['rejected_compilation_log'] = digest(rejected + '.log'); artifacts['rejected_compilation_receipt'] = digest(rejected + '/receipt.json')
		publish(rejected + '.log', out + 'iovstream-rejected-compile-' + arch + '.log')!; publish(rejected + '/receipt.json', out + 'iovstream-rejected-compile-' + arch + '.json')!
		context := 'Native musl ELF64 root/UID1000 valid pipe and UNIX stream/datagram/seqpacket receives: 220 checks per cohort across readv and current-position preadv2, stack/heap headers, complete/truncated records, next-message preservation, blocking available data and1MiB records. Unchanged kernels fail80 checks per cohort; fixed kernels pass all440 per architecture and two200-cycle cohorts retain flat slab/big-page storage with stable endpoint identities, including EAGAIN callback cleanup. Eleven other guest cases and eight host tests pass. The initial candidate aggregate receipt stays failed: its old retention stress exhausted the4096 socket-object limit before closed endpoints retired. Diagnostic denial counters confirm this; the corrected stream-only rerun passes with identical fixture C on both kernels. The updated import checkpoint passes both unchanged kernels. Buffer ownership was independently reviewed: one geometry-admitted fallible allocation, synchronous borrow, erase/free before charge release; FD/vector stay owned by the consuming syscall. Existing allocation allowance failures remain406ARM/295x86 without new sites. Baseline binaries/C match preceding descriptor-width evidence. A first bare fixture compilation was rejected and corrected before runtime qualification. First inaccessible destination queue preservation is a retained Vinix precheck, not Linux datagram error conformance: Linux frees that packet. Later destination-page faults, within-iovec partial-copy counts, queue rollback, GNU/foreign ABIs, Internet/netlink/character-device paths, shared regular-file offsets, allocator exhaustion and full Linux application qualification remain separate.'
		os.write_file(out + 'iovstream-' + arch + '-evidence.json', json2.encode(Evidence{arch, context, base, artifacts, inputs}, prettify: true) + '\n')!
	}
	for name in ['host-tests', 'geometry', 'allocs-before', 'allocs-after'] { publish(area + name + '.log', out + 'iovstream-' + name + '.log')! }
	if '--native-only' in os.args { println('Vector-stream native qualification audit: PASS'); return }
	performance(root, area, out, base, inputs)!
	println('Vector-stream qualification audit: PASS')
}
