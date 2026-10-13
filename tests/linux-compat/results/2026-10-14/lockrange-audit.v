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
	rows := log.split_into_lines().filter(it.starts_with('LINUX LOCKRANGE CASES:')); assert rows.len == 10
	mut seen := map[string]bool{}
	for row in rows {
		fields := row.fields(); assert fields.len == 7 && fields[3].starts_with('ordinary=') && fields[4].starts_with('kind=') && fields[5].starts_with('calls=') && fields[6].starts_with('failures=')
		group := fields[3].all_after('='); kind := fields[4].all_after('=').int(); key := group + '-' + kind.str()
		assert group in ['0', '1'] && kind in [0, 1, 2, 3, 4] && key !in seen; seen[key] = true
		assert fields[5].all_after('=').int() == if passing { [128, 64, 204, 340, 312]![kind] } else { [128, 64, 204, 340, 312]![kind] }
		assert fields[6].all_after('=').int() == if passing { 0 } else { [48, 24, 34, 70, 0]![kind] }
	}
	if passing { assert !log.contains('LINUX LOCKRANGE DETAIL:') && !log.contains('LINUX LOCKRANGE FAIL:') }
	else { assert log.contains('LINUX LOCKRANGE DETAIL:') && log.contains('LINUX LOCKRANGE FAIL:') && !log.contains('LINUX LOCKRANGE: PASS') }
	if reference { assert passing && log.contains('LINUX LOCKRANGE REFERENCE: PASS') && log.contains('Linux version 6.12.51-0-virt') && !log.contains('Kernel panic') && !log.contains('LINUX LOCKRANGE STORAGE:') }
	else if passing { assert log.split_into_lines().filter(it.trim_space() == 'LINUX LOCKRANGE: PASS').len == 1 && !log.contains('LINUX LOCKRANGE REFERENCE: PASS') }
}
fn failure(log string, arch string) { assert log.contains('LINUX LOCKRANGE DETAIL:'), 'lockrange baseline failure markers required'; semantics(log, false, false, arch) }
fn storage(log string, arch string) {
	mut slabs := [2]int{}; mut pages := [2]int{}; mut seen := map[string]bool{}
	for row in log.split_into_lines() {
		if !row.starts_with('LINUX LOCKRANGE SLAB:') && !row.starts_with('LINUX LOCKRANGE STORAGE:') { continue }
		fields := row.fields(); assert fields.len == 7; group := fields[3].all_after('=').int(); assert group in [0, 1]
		pair := fields[5].all_after('=').split('/'); assert pair.len == 2 && pair[0] == pair[1] && pair.all(it != '' && it.bytes().all(it.is_digit()))
		if fields[2] == 'SLAB:' { key := fields[3] + '-' + fields[4]; assert key !in seen && fields[6] == 'cycles=200'; seen[key] = true; slabs[group]++ }
		else { assert fields[4] == 'cycles=200' && fields[6] == 'PASS' && pair[0].int() == if arch == 'aarch64' { 63 } else { 160 }; pages[group]++ }
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
fn reference_receipt(state string, arch string, init string) !map[string]string {
	value := object(state + '/receipt.json')!; assert value['architecture']!.str() == arch && value['passed']!.bool() && value['finished']!.bool() && value['forced']!.bool() && value['status']!.int() == 0
	artifacts := value['artifacts']!.as_map_of_strings()
	command := value['command']!.as_array().map(it.str()); assert command.contains('-kernel') && command.contains('-initrd') && command.contains('-no-reboot')
	for label, path in {'kernel': state + '/linux', 'probe': state + '/probe', 'wrapper_source': state + '/source/lockrangereferenceinit/core.v', 'wrapper_c': state + '/fixture.c', 'wrapper_elf': state + '/init', 'initramfs': state + '/initramfs.cpio', 'serial': state + '/serial.log', 'serial_adapter_c': state + '/serial.c', 'controller_source': '/Users/alex/code/vinix/tests/linux-compat/lockrange-reference.v', 'qemu': command[0]} { assert artifacts[label] == digest(path) }
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/lockrangereferenceinit/core.v')
	semantics(os.read_file(state + '/serial.log')!, true, true, arch); return artifacts
}
fn erase(source string) string {
	names := ['file__normalize_lock', 'file__set_record_lock', 'file__get_record_lock', 'file__fcntl_lock']; mut kept := []string{}; mut inside := false; mut removed := 0
	for line in source.split_into_lines() {
		if inside { if line == '}' { inside = false }; continue }
		if line != '' && line[0] != `\t` && names.any(line.contains(' ' + it + '(')) { assert line.ends_with(';') || line.ends_with('{'), line; inside = line.ends_with('{'); removed++; continue }
		kept << line
	}
	assert !inside && removed == 8
	return kept.join('\n')
}
fn recovery(state string, out string) ! {
	area := '/Users/alex/.cache/vinix-linux-compat/lockrange-20261014'; value := object(state + '/receipt.json')!; proof := value['artifacts']!.as_map_of_strings(); origins := value['provenance']!.as_map_of_strings()
	assert origins.len == 5 && proof['composer_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/results/2026-10-14/lockrange-compose.v')
	assert proof['original_receipt'] == digest(area + '/verified-after-x86/receipt.json') && proof['recovery_receipt'] == digest(area + '/recovery-after-x86/receipt.json') && proof['recovery_aggregate'] == digest(area + '/recovery-after-x86.log')
	assert !os.exists(area + '/verified-after-x86.log')
	for name in ['lockrange', 'ofdlocks', 'fcntlpath', 'open', 'runtime'] {
		origin := area + '/' + if name in ['open', 'runtime'] { 'recovery-after-x86' } else { 'verified-after-x86' }; assert origins[name] == origin
		original := object(origin + '/receipt.json')!; assert original['architecture']!.str() == 'x86_64' && original['kernel_sha256']!.str() == value['kernel_sha256']!.str() && digest(origin + '/kernel/bin/vinix') == value['kernel_sha256']!.str()
		rows := original['results']!.as_array().filter(it.as_map()['name']!.str() == name); assert rows.len == 1 && rows[0].as_map()['exit_code']!.int() == 0 && rows[0].as_map()['detail']!.str() == ''
		for file in ['init', 'fixture.c', 'test.iso', 'serial.log', 'serial.c'] { assert digest(state + '/' + name + '/' + file) == digest(origin + '/' + name + '/' + file) }
		assert digest(state + '/sources/' + name + 'fixture/core.v') == digest(origin + '/sources/' + name + 'fixture/core.v')
	}
	publish(area + '/verified-after-x86/receipt.json', out + 'lockrange-original-x86_64.json')!; publish(area + '/recovery-after-x86/receipt.json', out + 'lockrange-recovery-x86_64.json')!; publish(area + '/recovery-after-x86.log', out + 'lockrange-recovery-x86_64.log')!; publish(area + '/compose.log', out + 'lockrange-compose.log')!
}

fn main() {
	if '--negative-control' in os.args { assert false, 'audit assertions must execute'; return }
	if '--negative-pass-control' in os.args { failure(os.read_file(os.args[2])!, os.args[3]); return }
	root := '/Users/alex/code/vinix/'; area := '/Users/alex/.cache/vinix-linux-compat/lockrange-20261014/'; out := root + 'tests/linux-compat/results/2026-10-14/'; compiler := '/Users/alex/.cache/vinix-linux-compat/procstate-20261013/compiler/v'
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'audit assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control', area + 'verified-after-arm/lockrange/serial.log', 'aarch64'], 'lockrange baseline failure markers required'))!
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == '8682eac81b7e53ad8113513a883ac2ba750a8b9d'
	mut inputs := object(area + 'kernel-arm/docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 63
	inputs['kernel/file/locks.v'] = digest(area + 'kernel-arm/kernel/file/locks.v')
	assert digest(compiler) == 'f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39'
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total') && os.read_file(area + 'coverage-check.log')!.contains('Linux dispatch coverage: PASS')
	before_allocs := os.read_file(area + 'allocs-before.log')!; after_allocs := os.read_file(area + 'allocs-after.log')!
	for arch in ['aarch64', 'x86_64'] { count := arch + ': ' + if arch == 'aarch64' { '659 source files, 400 allocation sites (V exit 0)' } else { '655 source files, 292 allocation sites (V exit 0)' }; assert before_allocs.contains(count) && after_allocs.contains(count) }
	assert before_allocs.split_into_lines().filter(it.starts_with('NEW:')) == after_allocs.split_into_lines().filter(it.starts_with('NEW:'))
	paths := ['kernel/file/locks.v']; review := out + 'lockrange-lifetime-review.md'; review_text := os.read_file(review)!; assert review_text.starts_with('Independent lockrange lifetime review: PASS')
	for path in paths { assert review_text.contains(inputs[path]) && inputs[path] == digest(root + path) }
	assert review_text.contains(digest(root + 'tests/linux-compat/lockrangefixture/core.v'))
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'; assert git(tree, ['rev-parse', 'HEAD'])! == base && git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])!.split_into_lines() == paths
		for path, hash in inputs { if path.starts_with('kernel/') { assert digest(tree + path) == hash } }
		kernel_c := tree + 'kernel/obj/blob.c'; assert erase(os.read_file(area + 'before-' + suffix + '.c')!) == erase(os.read_file(kernel_c)!), 'complete C outside exactly four reviewed record-lock functions/prototypes'; assert review_text.contains(digest(kernel_c))
		preview := os.read_file(area + 'preview-' + suffix + '.c')!; assert preview.count('alloca(') == 10 && !preview.contains('memdup(') && !preview.contains('malloc(') && !preview.contains('new_array') && !preview.contains('v_fixed_index')
		before_hash := digest(area + 'baseline-' + suffix + '/kernel/bin/vinix'); after_hash := digest(tree + 'kernel/bin/vinix')
		baseline := area + 'verified-before-' + suffix; candidate := area + if arch == 'x86_64' { 'qualified-after-x86' } else { 'verified-after-arm' }; reference := area + 'verified-reference-' + suffix
		before := receipt(baseline, arch, before_hash, ['lockrange'], true)!; after := receipt(candidate, arch, after_hash, ['lockrange', 'ofdlocks', 'fcntlpath', 'open', 'runtime'], false)!
		assert before['lockrange_source'] == after['lockrange_source'] && before['lockrange_init'] == after['lockrange_init'] && before['lockrange_c'] == after['lockrange_c'] && after['lockrange_c'] == digest(area + 'preview-' + suffix + '.c')
		failure(os.read_file(baseline + '/lockrange/serial.log')!, arch); log := os.read_file(candidate + '/lockrange/serial.log')!; semantics(log, true, false, arch); storage(log, arch); assert review_text.contains(digest(candidate + '/lockrange/serial.log'))
		linux := reference_receipt(reference, arch, after['lockrange_init'])!; assert review_text.contains(linux['serial']) && review_text.contains(linux['wrapper_c']) && review_text.contains(linux['probe'])
		assert linux['kernel'] == digest('/Users/alex/.cache/vinix-linux-compat/statx-20261013/linux-inputs/vmlinuz-' + arch)
		assert os.read_file(candidate + '/runtime/serial.log')!.contains('LINUX RUNTIME PASS: atomics SIMD TLS') && os.read_file(candidate + '/runtime/serial.log')!.contains('LINUX RUNTIME PASS: JIT page sizes')
		if arch == 'x86_64' { recovery(candidate, out)! }
		mut artifacts := {'compiler': digest(compiler), 'controller': digest(area + 'run'), 'controller_source': digest(root + 'tests/linux-compat/run.v'), 'reference_controller': digest(area + 'reference'), 'audit': digest(@FILE), 'audit_executable': digest(os.executable()), 'review': digest(review), 'before_kernel': before_hash, 'after_kernel': after_hash, 'before_kernel_c': digest(area + 'before-' + suffix + '.c'), 'after_kernel_c': digest(kernel_c), 'preview': digest(area + 'preview-' + suffix + '.c')}
		for key, hash in before { artifacts['before_' + key] = hash }; for key, hash in after { artifacts['after_' + key] = hash }; for key, hash in linux { artifacts['reference_' + key] = hash }
		artifacts['reference_receipt'] = digest(reference + '/receipt.json'); artifacts['reference_aggregate'] = digest(reference + '.log')
		for phase in ['before', 'after'] {
			state := if phase == 'after' { candidate } else { baseline }; publish(state + '.log', out + 'lockrange-' + phase + '-' + arch + '.log')!; publish(state + '/receipt.json', out + 'lockrange-' + phase + '-' + arch + '.json')!; publish(state + '/lockrange/serial.log', out + 'lockrange-' + phase + '-' + arch + '-native.log')!
			build := area + 'build-' + phase + '-' + suffix + '.log'; build_text := os.read_file(build)!; assert build_text.contains('-o bin/vinix') && !build_text.contains('Error ') && !build_text.contains('No space left on device'); artifacts['build_' + phase] = digest(build)
		}
		publish(reference + '.log', out + 'lockrange-reference-' + arch + '.log')!; publish(reference + '/serial.log', out + 'lockrange-reference-' + arch + '-native.log')!; publish(reference + '/receipt.json', out + 'lockrange-reference-' + arch + '.json')!
		for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'scope-check.log', 'assertion-control.log', 'passing-log-control.log'] { artifacts[name] = digest(area + name) }
		context := 'Native musl ELF64 signed record-lock ranges:2096 controls per architecture, root/UID1000. All six POSIX/OFD query/nonblocking/blocking commands, libc/raw native upper words and full-width flock pointers. Sixteen accepted endpoint/negative/CUR/END/unbounded cases and ten invalid ranges per command/form; invalid kind/PID/access/whence combinations follow actual Linux precedence. Finite extents ending at INT64_MAX map to the existing zero-length sentinel; byte before maximum remains finite. Whole headers, accepted locks or error-path seeds, bytes/size/mode/ownership/descriptor flags and shared cursors verified. Maximum-byte splits/gaps/bridges/downgrades/alias retention/final release pass. Both baselines reproduce 352 failures; candidates and Linux 6.12.51 pass identical source/C/ELF. Two 200-cycle cohorts keep 18 ARM/14 x86 slabs and 63/160 pages flat through maximum-byte OFD/POSIX lock and close operations. One scalar normalized LockRange imported after POSIX query-kind guard and before appropriate type/access/PID checks; copied by value to existing retained-handle helpers. No owner/table/allocation/reclamation/lock-order changes or added allocation sites; existing allowance refusals remain. Whole kernel C byte-identical outside exactly four reviewed bodies/prototypes, no blank normalization/helper removal. Ten explicit probe allocas, no hidden heap/index helpers. Five final guest cases (lockrange, ofdlocks, fcntlpath, open, runtime): ordinary ARM controller run; x86 composition of three original passing cases and two recovered cases after host ENOSPC image setup and absent outer aggregate, with exact provenance, eight host files, scope/coverage/builds, all 64 dispatch/lock inputs and independent review bound; assertion/passing-as-baseline controls execute. Prior completed artifacts losslessly compressed with verified SHA manifests. Concurrent CUR/END changes, arbitrary persistent populations, nonregular/disk/network/overlay filesystems, POSIX deadlocks/close races, fairness/pressure/cancellation and GNU/translated/ELF32 paths remain separate; three broad roadmap gates stay open.'
		os.write_file(out + 'lockrange-evidence-' + arch + '.json', json2.encode(Evidence{architecture: arch, context: context, base_commit: base, artifacts: artifacts, source_inputs: inputs}, prettify: true) + '\n')!
	}
	for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'scope-check.log', 'assertion-control.log', 'passing-log-control.log', 'build-before-arm.log', 'build-before-x86.log', 'build-after-arm.log', 'build-after-x86.log'] { publish(area + name, out + 'lockrange-' + name)! }
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		for prefix in ['final', 'new', 'retry'] { path := area + prefix + '-after-' + suffix; if os.is_file(path + '/receipt.json') { publish(path + '/receipt.json', out + 'lockrange-diagnostic-' + prefix + '-' + arch + '.json')! }; if os.is_file(path + '.log') { publish(path + '.log', out + 'lockrange-diagnostic-' + prefix + '-' + arch + '.log')! } }
	}
	println('Native lockrange conformance audit: PASS')
}
