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
	mut p := os.new_process('git'); p.set_args(command); p.set_redirect_stdio_merged(); p.run()
	output := p.stdout_slurp(); p.wait(); code := p.code; p.close()
	assert code == 0, output; return output.trim_space()
}
fn control(args []string, marker string) string {
	mut p := os.new_process(os.executable()); p.set_args(args); p.set_redirect_stdio_merged(); p.run()
	output := p.stdout_slurp(); p.wait(); code := p.code; p.close()
	if code != 1 || !output.contains(marker) { panic('audit negative control did not execute') }; return output
}
fn semantics(log string, passing bool, reference bool, arch string) {
	assert arch in ['aarch64', 'x86_64']
	initial := log.split_into_lines().filter(it.starts_with('LINUX FCNTLSYNC INITIAL:')); assert initial.len == 2
	assert initial.map(it.trim_space()).sorted() == ['LINUX FCNTLSYNC INITIAL: ordinary=0 descriptors=35 PASS', 'LINUX FCNTLSYNC INITIAL: ordinary=1 descriptors=35 PASS']
	rows := log.split_into_lines().filter(it.starts_with('LINUX FCNTLSYNC CASES:')); assert rows.len == 8
	mut seen := map[string]bool{}
	for row in rows {
		fields := row.fields(); assert fields.len == 7 && fields[3].starts_with('ordinary=') && fields[4].starts_with('kind=') && fields[5].starts_with('calls=') && fields[6].starts_with('failures='); group := fields[3].all_after('='); kind := fields[4].all_after('=').int(); key := group + '-' + kind.str()
		assert group in ['0', '1'] && kind in [0, 1, 2, 3] && key !in seen; seen[key] = true
		assert fields[5].all_after('=').int() == [864, 320, 296, 256]![kind]
		assert fields[6].all_after('=').int() == if passing { 0 } else { [588, 0, 147, 132]![kind] }
	}
	if passing { assert !log.contains('LINUX FCNTLSYNC DETAIL:') && !log.contains('LINUX FCNTLSYNC FAIL:') }
	else { assert log.contains('LINUX FCNTLSYNC DETAIL:') && log.contains('LINUX FCNTLSYNC FAIL:') && !log.contains('LINUX FCNTLSYNC: PASS') }
	if reference { assert passing && log.contains('LINUX FCNTLSYNC REFERENCE: PASS') && log.contains('Linux version 6.12.51-0-virt') && !log.contains('Kernel panic') && !log.contains('LINUX FCNTLSYNC STORAGE:') }
	else if passing { assert log.split_into_lines().filter(it.trim_space() == 'LINUX FCNTLSYNC: PASS').len == 1 && !log.contains('LINUX FCNTLSYNC REFERENCE: PASS') }
}
fn failure(log string, arch string) { assert log.contains('LINUX FCNTLSYNC DETAIL:'), 'fcntlsync baseline failure markers required'; semantics(log, false, false, arch) }
fn storage(log string, arch string) {
	mut slabs := [2]int{}; mut pages := [2]int{}; mut seen := map[string]bool{}
	for row in log.split_into_lines() {
		if !row.starts_with('LINUX FCNTLSYNC SLAB:') && !row.starts_with('LINUX FCNTLSYNC STORAGE:') { continue }
		fields := row.fields(); assert fields.len == 7; group := fields[3].all_after('=').int(); assert group in [0, 1]
		pair := fields[5].all_after('=').split('/'); assert pair.len == 2 && pair[0] == pair[1] && pair.all(it != '' && it.bytes().all(it.is_digit()))
		if fields[2] == 'SLAB:' { key := fields[3] + '-' + fields[4]; assert key !in seen && fields[6] == 'cycles=200'; seen[key] = true; slabs[group]++ }
		else { assert fields[4] == 'cycles=200' && fields[6] == 'PASS' && pair[0].int() == if arch == 'aarch64' { 68 } else { 177 }; pages[group]++ }
	}
	for group in 0 .. 2 { assert slabs[group] == if arch == 'aarch64' { 18 } else { 14 }; assert pages[group] == 1 }
}
fn receipt(state string, arch string, kernel string, names []string, failing bool) !map[string]string {
	value := object(state + '/receipt.json')!; assert value['architecture']!.str() == arch && value['kernel_sha256']!.str() == kernel && digest(state + '/kernel/bin/vinix') == kernel
	rows := value['results']!.as_array(); assert rows.len == names.len
	mut artifacts := {'receipt': digest(state + '/receipt.json'), 'aggregate': digest(state + '.log')}
	for index, row in rows {
		entry := row.as_map(); name := entry['name']!.str(); assert name == names[index] && entry['exit_code']!.int() == if failing { 1 } else { 0 } && entry['detail']!.str() == ''
		for label, path in {'source': state + '/sources/' + name + 'fixture/core.v', 'init': state + '/' + name + '/init', 'iso': state + '/' + name + '/test.iso'} {
			hash := digest(path); key := if label == 'source' { 'source_sha256' } else if label == 'init' { 'init_sha256' } else { 'iso_sha256' }; assert hash == entry[key]!.str(); artifacts[name + '_' + label] = hash
		}
		maintained := '/Users/alex/code/vinix/tests/linux-compat/' + name + 'fixture/core.v'
		assert artifacts[name + '_source'] == digest(maintained)
		artifacts[name + '_c'] = digest(state + '/' + name + '/fixture.c'); artifacts[name + '_serial'] = digest(state + '/' + name + '/serial.log')
		if !failing { assert os.read_file(state + '/' + name + '/serial.log')!.contains('LINUX ' + name.to_upper() + ': PASS') }
	}
	return artifacts
}
fn scope(before string, after string, arch string) {
	assert arch in ['aarch64', 'x86_64']
		old := '#define resource__file_settable_flags_mask ((((02000) | (04000)) | (010000)) | (04010000))'
		new := '#define resource__file_settable_flags_mask ((02000) | (04000))'
		assert before.count(old) == 1 && after.count(new) == 1
		assert after.replace(new, old) == before, 'whole C changes only the status mask macro'
}
fn composition(state string, arch string, out string) !map[string]string {
	area := '/Users/alex/.cache/vinix-linux-compat/fcntlsync-20261013'; suffix := if arch == 'aarch64' { 'arm' } else { 'x86' }
	value := object(state + '/receipt.json')!; proof := value['artifacts']!.as_map_of_strings(); origins := value['provenance']!.as_map_of_strings()
	assert proof['composer_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/results/2026-10-13/fcntlsync-compose.v') && origins.len == 5
	mut artifacts := {'composer': proof['composer_source'], 'compose_log': digest(area + '/compose.log')}
	for name in ['fcntlsync', 'fcntlabi', 'fcntlpath', 'open', 'runtime'] {
		expected := area + '/' + if name == 'fcntlsync' { 'new-after-' + suffix } else if arch == 'aarch64' && name == 'fcntlpath' { 'initial-mask-new-after-arm' } else { 'initial-after-' + suffix }
		assert origins[name] == expected
		original := object(expected + '/receipt.json')!; assert original['architecture']!.str() == arch && original['kernel_sha256']!.str() == value['kernel_sha256']!.str() && digest(expected + '/kernel/bin/vinix') == value['kernel_sha256']!.str()
		rows := original['results']!.as_array().filter(it.as_map()['name']!.str() == name); assert rows.len == 1 && rows[0].as_map()['exit_code']!.int() == 0 && rows[0].as_map()['detail']!.str() == ''
		for file in ['init', 'test.iso', 'fixture.c', 'serial.log', 'serial.c'] { assert digest(state + '/' + name + '/' + file) == digest(expected + '/' + name + '/' + file) }
		assert digest(state + '/sources/' + name + 'fixture/core.v') == digest(expected + '/sources/' + name + 'fixture/core.v')
		artifacts[name + '_origin_receipt'] = digest(expected + '/receipt.json'); artifacts[name + '_origin_aggregate'] = digest(expected + '.log')
	}
	for label in ['original', 'fresh'] {
		origin := area + '/' + if label == 'original' { 'initial-after-' + suffix } else { 'new-after-' + suffix }
		assert proof[label + '_receipt'] == digest(origin + '/receipt.json') && proof[label + '_aggregate'] == digest(origin + '.log')
		publish(origin + '/receipt.json', out + 'fcntlsync-' + label + '-' + arch + '.json')!; publish(origin + '.log', out + 'fcntlsync-' + label + '-' + arch + '.log')!
	}
	if arch == 'aarch64' { origin := area + '/initial-mask-new-after-arm'; publish(origin + '/receipt.json', out + 'fcntlsync-retry-aarch64.json')!; publish(origin + '.log', out + 'fcntlsync-retry-aarch64.log')! }
	return artifacts
}
fn reference_receipt(state string, arch string, init string) !map[string]string {
	value := object(state + '/receipt.json')!; assert value['architecture']!.str() == arch && value['passed']!.bool() && value['finished']!.bool() && value['forced']!.bool() && value['status']!.int() == 0
	artifacts := value['artifacts']!.as_map_of_strings()
	command := value['command']!.as_array().map(it.str()); assert command.contains('-kernel') && command.contains('-initrd') && command.contains('-no-reboot')
	for label, path in {'kernel': state + '/linux', 'probe': state + '/probe', 'wrapper_source': state + '/source/fcntlsyncreferenceinit/core.v', 'wrapper_c': state + '/fixture.c', 'wrapper_elf': state + '/init', 'initramfs': state + '/initramfs.cpio', 'serial': state + '/serial.log', 'serial_adapter_c': state + '/serial.c', 'controller_source': '/Users/alex/code/vinix/tests/linux-compat/fcntlsync-reference.v', 'qemu': command[0]} { assert artifacts[label] == digest(path) }
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/fcntlsyncreferenceinit/core.v')
	semantics(os.read_file(state + '/serial.log')!, true, true, arch); return artifacts
}
fn main() {
	if '--negative-control' in os.args { assert false, 'audit assertions must execute'; return }
	if '--negative-pass-control' in os.args { failure(os.read_file(os.args[2])!, os.args[3]); return }
	root := '/Users/alex/code/vinix/'; area := '/Users/alex/.cache/vinix-linux-compat/fcntlsync-20261013/'; out := root + 'tests/linux-compat/results/2026-10-13/'; compiler := '/Users/alex/.cache/vinix-linux-compat/procstate-20261013/compiler/v'
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'audit assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control', area + 'final-after-arm/fcntlsync/serial.log', 'aarch64'], 'fcntlsync baseline failure markers required'))!
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == '73f513e79eb61d5a67c094801da5ef922d19e1d0'
	inputs := object(area + 'kernel-arm/docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 63
	assert digest(compiler) == 'f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39'
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total') && os.read_file(area + 'coverage-check.log')!.contains('Linux dispatch coverage: PASS')
	before_allocs := os.read_file(area + 'allocs-before.log')!; after_allocs := os.read_file(area + 'allocs-after.log')!
	for arch in ['aarch64', 'x86_64'] { count := arch + ': ' + if arch == 'aarch64' { '659 source files, 400 allocation sites (V exit 0)' } else { '655 source files, 292 allocation sites (V exit 0)' }; assert before_allocs.contains(count) && after_allocs.contains(count) }
	assert before_allocs.split_into_lines().filter(it.starts_with('NEW:')) == after_allocs.split_into_lines().filter(it.starts_with('NEW:'))
	paths := ['kernel/resource/resource.v']; review := out + 'fcntlsync-lifetime-review.md'; review_text := os.read_file(review)!; assert review_text.starts_with('Independent fcntlsync lifetime review: PASS')
	for path in paths { assert review_text.contains(inputs[path]) && inputs[path] == digest(root + path) }; assert review_text.contains(digest(root + 'tests/linux-compat/fcntlsyncfixture/core.v'))
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'; assert git(tree, ['rev-parse', 'HEAD'])! == base && git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])!.split_into_lines() == paths
		for source_path, hash in inputs { if source_path.starts_with('kernel/') { assert digest(tree + source_path) == hash } }
		kernel_c := tree + 'kernel/obj/blob.c'; scope(os.read_file(area + 'before-' + suffix + '.c')!, os.read_file(kernel_c)!, arch); assert review_text.contains(digest(kernel_c))
		preview := os.read_file(area + 'preview-' + suffix + '.c')!; assert preview.count('alloca(') == 7 && !preview.contains('memdup(') && !preview.contains('malloc(') && !preview.contains('new_array') && !preview.contains('v_fixed_index')
		before_hash := digest(area + 'baseline-' + suffix + '/kernel/bin/vinix'); after_hash := digest(tree + 'kernel/bin/vinix')
		baseline := area + 'final-before-' + suffix; candidate := area + 'final-after-' + suffix; reference := area + 'final-reference-' + suffix
		before := receipt(baseline, arch, before_hash, ['fcntlsync'], true)!; after := receipt(candidate, arch, after_hash, ['fcntlsync', 'fcntlabi', 'fcntlpath', 'open', 'runtime'], false)!
		assert before['fcntlsync_source'] == after['fcntlsync_source'] && before['fcntlsync_init'] == after['fcntlsync_init'] && before['fcntlsync_c'] == after['fcntlsync_c'] && after['fcntlsync_c'] == digest(area + 'preview-' + suffix + '.c')
		failure(os.read_file(baseline + '/fcntlsync/serial.log')!, arch); log := os.read_file(candidate + '/fcntlsync/serial.log')!; semantics(log, true, false, arch); storage(log, arch); assert review_text.contains(digest(candidate + '/fcntlsync/serial.log'))
		linux := reference_receipt(reference, arch, after['fcntlsync_init'])!; assert review_text.contains(linux['serial']) && review_text.contains(linux['wrapper_c']) && review_text.contains(linux['probe'])
		assert linux['kernel'] == digest('/Users/alex/.cache/vinix-linux-compat/statx-20261013/linux-inputs/vmlinuz-' + arch)
		assert os.read_file(candidate + '/runtime/serial.log')!.contains('LINUX RUNTIME PASS: atomics SIMD TLS') && os.read_file(candidate + '/runtime/serial.log')!.contains('LINUX RUNTIME PASS: JIT page sizes')
		mut artifacts := {'compiler': digest(compiler), 'controller': digest(area + 'run'), 'controller_source': digest(root + 'tests/linux-compat/run.v'), 'reference_controller': digest(area + 'reference'), 'audit': digest(@FILE), 'audit_executable': digest(os.executable()), 'review': digest(review), 'before_kernel': before_hash, 'after_kernel': after_hash, 'before_kernel_c': digest(area + 'before-' + suffix + '.c'), 'after_kernel_c': digest(kernel_c), 'preview': digest(area + 'preview-' + suffix + '.c')}
		for key, hash in composition(candidate, arch, out)! { artifacts['composition_' + key] = hash }
		for key, hash in before { artifacts['before_' + key] = hash }; for key, hash in after { artifacts['after_' + key] = hash }; for key, hash in linux { artifacts['reference_' + key] = hash }
		artifacts['reference_receipt'] = digest(reference + '/receipt.json'); artifacts['reference_aggregate'] = digest(reference + '.log'); artifacts['reference_url'] = digest('/Users/alex/.cache/vinix-linux-compat/statx-20261013/linux-inputs/url-' + arch + '.txt')
		for phase in ['before', 'after'] {
			state := area + 'final-' + phase + '-' + suffix; publish(state + '.log', out + 'fcntlsync-' + phase + '-' + arch + '.log')!; publish(state + '/receipt.json', out + 'fcntlsync-' + phase + '-' + arch + '.json')!
			publish(state + '/fcntlsync/serial.log', out + 'fcntlsync-' + phase + '-' + arch + '-native.log')!
			build := area + 'build-' + phase + '-' + suffix + '.log'; build_text := os.read_file(build)!; assert build_text.contains('-o bin/vinix') && !build_text.contains('Error ') && !build_text.contains('No space left on device'); artifacts['build_' + phase] = digest(build)
		}
		publish(reference + '.log', out + 'fcntlsync-reference-' + arch + '.log')!; publish(reference + '/serial.log', out + 'fcntlsync-reference-' + arch + '-native.log')!; publish(reference + '/receipt.json', out + 'fcntlsync-reference-' + arch + '.json')!
		for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'scope-check.log', 'assertion-control.log', 'passing-log-control.log'] { artifacts[name] = digest(area + name) }
		context := 'Native musl ELF64 F_SETFL synchronization preservation: 3472 controls per architecture, root and UID/GID 1000. Nine regular/directory/unlinked/pipe description classes with original/dup/CLOEXEC forms, six O_PATH aliases and held 64/65. Explicit initial sync/access checks for all 35 held descriptions. Eight flag combinations and independent fd/command/argument upper words preserve open-time O_SYNC/O_DSYNC/access/descriptor flags; append/nonblock changes share across aliases but not separate opens. Exact EBADF for bad descriptors/O_PATH; zero/eight soft limits and close/replacement 66 retain state. All held metadata/cursors, file bytes and AB remain intact. Baselines fail 1734; strengthened candidate and Linux 6.12.51 references pass byte-identical native C/ELF. Two 200-cycle cohorts retain all 18 ARM/14 x86 slabs and 68/177 pages flat. Five guest cases composed with exact successful-case provenance on identical kernel bytes: fresh strengthened fcntlsync, successful fcntlabi/open/runtime and fcntlpath (ARM retry after failed ENOSPC ISO setup). Provisional sync and initial O_PATH access-mask probes remain excluded diagnostics. No repeated successful unrelated cases. Eight host files pass; allocation sites/allowance refusals unchanged. Complete kernel C changes only one mutable-mask macro. All 63 isolated inputs and compiler/controller/source/C/kernel/ELF/ISO/reference/build/audit/composer/review hashes bound; assertion/passing-as-baseline controls execute. Historical completed artifacts losslessly compressed with verified SHA manifests. Other F_SETFL semantics, physical durability, concurrency, GNU wrappers and foreign ABIs remain separate; three broad section 15 gates stay open.'
		os.write_file(out + 'fcntlsync-evidence-' + arch + '.json', json2.encode(Evidence{architecture: arch, context: context, base_commit: base, artifacts: artifacts, source_inputs: inputs}, prettify: true) + '\n')!
	}
	for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'scope-check.log', 'assertion-control.log', 'passing-log-control.log', 'build-before-arm.log', 'build-before-x86.log', 'build-after-arm.log', 'build-after-x86.log'] { publish(area + name, out + 'fcntlsync-' + name)! }
	println('Native fcntlsync conformance audit: PASS')
}
