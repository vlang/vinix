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
	rows := log.split_into_lines().filter(it.starts_with('LINUX FCNTLSIG CASES:')); assert rows.len == 10
	mut seen := map[string]bool{}
	for row in rows {
		fields := row.fields(); assert fields.len == 7 && fields[3].starts_with('ordinary=') && fields[4].starts_with('kind=') && fields[5].starts_with('calls=') && fields[6].starts_with('failures=')
		group := fields[3].all_after('='); kind := fields[4].all_after('=').int(); key := group + '-' + kind.str()
		assert group in ['0', '1'] && kind in [0, 1, 2, 3, 4] && key !in seen; seen[key] = true
		assert fields[5].all_after('=').int() == [810, 405, 243, 540, 362]![kind]
		assert passing && fields[6].all_after('=').int() == 0
	}
	if passing { assert !log.contains('LINUX FCNTLSIG DETAIL:') && !log.contains('LINUX FCNTLSIG FAIL:') }
	else { assert log.contains('LINUX FCNTLSIG DETAIL:') && log.contains('LINUX FCNTLSIG FAIL:') && !log.contains('LINUX FCNTLSIG: PASS') }
	if reference { assert passing && log.contains('LINUX FCNTLSIG REFERENCE: PASS') && log.contains('Linux version 6.12.51-0-virt') && !log.contains('Kernel panic') && !log.contains('LINUX FCNTLSIG STORAGE:') }
	else if passing { assert log.split_into_lines().filter(it.trim_space() == 'LINUX FCNTLSIG: PASS').len == 1 && !log.contains('LINUX FCNTLSIG REFERENCE: PASS') }
}
fn failure(log string, arch string) { assert log.contains('LINUX FCNTLSIG DETAIL:'), 'fcntlsig baseline failure markers required'; semantics(log, false, false, arch) }
fn storage(log string, arch string) {
	mut slabs := [2]int{}; mut pages := [2]int{}; mut seen := map[string]bool{}
	for row in log.split_into_lines() {
		if !row.starts_with('LINUX FCNTLSIG SLAB:') && !row.starts_with('LINUX FCNTLSIG STORAGE:') { continue }
		fields := row.fields(); assert fields.len == 7; group := fields[3].all_after('=').int(); assert group in [0, 1]
		pair := fields[5].all_after('=').split('/'); assert pair.len == 2 && pair[0] == pair[1] && pair.all(it != '' && it.bytes().all(it.is_digit()))
		if fields[2] == 'SLAB:' { key := fields[3] + '-' + fields[4]; assert key !in seen && fields[6] == 'cycles=200'; seen[key] = true; slabs[group]++ }
		else { assert fields[4] == 'cycles=200' && fields[6] == 'PASS' && pair[0].u64() > 0; pages[group]++ }
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
	for label, path in {'kernel': state + '/linux', 'probe': state + '/probe', 'wrapper_source': state + '/source/fcntlsigreferenceinit/core.v', 'wrapper_c': state + '/fixture.c', 'wrapper_elf': state + '/init', 'initramfs': state + '/initramfs.cpio', 'serial': state + '/serial.log', 'serial_adapter_c': state + '/serial.c', 'controller_source': '/Users/alex/code/vinix/tests/linux-compat/fcntlsig-reference.v', 'qemu': command[0]} { assert artifacts[label] == digest(path) }
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/fcntlsigreferenceinit/core.v')
	semantics(os.read_file(state + '/serial.log')!, true, true, arch); return artifacts
}
fn main() {
	if '--negative-control' in os.args { assert false, 'audit assertions must execute'; return }
	if '--negative-pass-control' in os.args { failure(os.read_file(os.args[2])!, os.args[3]); return }
	root := '/Users/alex/code/vinix/'; area := '/Users/alex/.cache/vinix-linux-compat/fcntlsig-20261014/'; out := root + 'tests/linux-compat/results/2026-10-14/'; compiler := '/Users/alex/.cache/vinix-linux-compat/procstate-20261013/compiler/v'
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'audit assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control', area + 'verified-native-arm/fcntlsig/serial.log', 'aarch64'], 'fcntlsig baseline failure markers required'))!
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == '97e2f95bdad3acbf00ec27ada5ae38c09e25c6a6'
	inputs := object(area + 'kernel-arm/docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 63
	assert digest(compiler) == 'f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39'
	assert digest(area + 'linux-fcntl.c') == 'ec0082d625d58d482d94ff8f1639d27a2da63e6cf3f50580820c158ee1a48acd'
	assert digest(area + 'linux-signal.h') == 'f6b75a1b35c5fb2b0e5994964ce75ef30bcdd0a4d412f8755c0c791d56a7eab4'
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total') && os.read_file(area + 'coverage-check.log')!.contains('Linux dispatch coverage: PASS')
	allocs := os.read_file(area + 'allocs-before.log')!; assert allocs.contains('aarch64: 659 source files, 400 allocation sites (V exit 0)') && allocs.contains('x86_64: 655 source files, 292 allocation sites (V exit 0)')
	review := out + 'fcntlsig-lifetime-review.md'; reviewed := os.read_file(review)!; assert reviewed.starts_with('Independent fcntlsig lifetime review: PASS')
	assert reviewed.contains(digest(root + 'tests/linux-compat/fcntlsigfixture/core.v'))
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'; assert git(tree, ['rev-parse', 'HEAD'])! == base && git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])! == ''
		for path, hash in inputs { if path.starts_with('kernel/') { assert digest(tree + path) == hash } }
		assert digest(root + 'kernel/file/file.v') == inputs['kernel/file/file.v']
		kernel := digest(tree + 'kernel/bin/vinix'); kernel_c := tree + 'kernel/obj/blob.c'; assert digest(area + 'baseline-' + suffix + '/kernel/bin/vinix') == kernel && os.read_file(area + 'before-' + suffix + '.c')! == os.read_file(kernel_c)! && reviewed.contains(digest(kernel_c))
		preview := os.read_file(area + 'preview-' + suffix + '.c')!; assert preview.count('alloca(') == 10 && !preview.contains('memdup(') && !preview.contains('malloc(') && !preview.contains('new_array') && !preview.contains('v_fixed_index')
		native := area + 'verified-native-' + suffix; reference := area + 'verified-reference-' + suffix; diagnostic := area + 'verified-before-' + suffix
		actual := receipt(native, arch, kernel, ['fcntlsig', 'fcntlabi', 'fcntlpath', 'open', 'runtime'], false)!; prior := receipt(diagnostic, arch, kernel, ['fcntlsig'], false)!
		assert actual['fcntlsig_source'] == prior['fcntlsig_source'] && actual['fcntlsig_init'] == prior['fcntlsig_init'] && actual['fcntlsig_c'] == prior['fcntlsig_c'] && actual['fcntlsig_c'] == digest(area + 'preview-' + suffix + '.c') && actual['fcntlsig_c'] == digest(area + 'preflight-' + suffix + '/fixture.c')
		for state in [native, diagnostic] { log := os.read_file(state + '/fcntlsig/serial.log')!; semantics(log, true, false, arch); storage(log, arch); assert reviewed.contains(digest(state + '/fcntlsig/serial.log')) }
		linux := reference_receipt(reference, arch, actual['fcntlsig_init'])!; assert reviewed.contains(linux['serial']) && reviewed.contains(linux['wrapper_c']) && reviewed.contains(linux['probe'])
		assert linux['kernel'] == digest('/Users/alex/.cache/vinix-linux-compat/statx-20261013/linux-inputs/vmlinuz-' + arch)
		assert os.read_file(native + '/runtime/serial.log')!.contains('LINUX RUNTIME PASS: atomics SIMD TLS') && os.read_file(native + '/runtime/serial.log')!.contains('LINUX RUNTIME PASS: JIT page sizes')
		mut artifacts := {'compiler': digest(compiler), 'controller': digest(area + 'run'), 'controller_source': digest(root + 'tests/linux-compat/run.v'), 'reference_controller': digest(area + 'reference'), 'audit': digest(@FILE), 'audit_executable': digest(os.executable()), 'review': digest(review), 'kernel': kernel, 'kernel_c': digest(kernel_c), 'preview': digest(area + 'preview-' + suffix + '.c'), 'linux_fcntl_source': digest(area + 'linux-fcntl.c'), 'linux_signal_source': digest(area + 'linux-signal.h'), 'initial_expectation_wrapper': digest(area + 'execute.v'), 'corrected_native_wrapper': digest(area + 'run-native.v')}
		for key, hash in actual { artifacts['native_' + key] = hash }; for key, hash in prior { artifacts['diagnostic_' + key] = hash }; for key, hash in linux { artifacts['reference_' + key] = hash }
		artifacts['reference_receipt'] = digest(reference + '/receipt.json'); artifacts['reference_aggregate'] = digest(reference + '.log')
		for label, state in {'native': native, 'diagnostic': diagnostic} { publish(state + '.log', out + 'fcntlsig-' + label + '-' + arch + '.log')!; publish(state + '/receipt.json', out + 'fcntlsig-' + label + '-' + arch + '.json')!; publish(state + '/fcntlsig/serial.log', out + 'fcntlsig-' + label + '-' + arch + '-native.log')! }
		publish(reference + '.log', out + 'fcntlsig-reference-' + arch + '.log')!; publish(reference + '/serial.log', out + 'fcntlsig-reference-' + arch + '-native.log')!; publish(reference + '/receipt.json', out + 'fcntlsig-reference-' + arch + '.json')!
		build := area + 'build-before-' + suffix + '.log'; assert os.read_file(build)!.contains('-o bin/vinix'); artifacts['build'] = digest(build)
		for name in ['host-tests.log', 'allocs-before.log', 'coverage-check.log', 'assertion-control.log', 'passing-log-control.log'] { artifacts[name] = digest(area + name) }
		context := 'Native musl ELF64 F_SETSIG/F_GETSIG conformance qualification on unchanged frozen kernel 97e2f95bd. The existing Linux dispatch wrapper already imports low32 scalar signal words; no kernel fix or baseline failure is claimed. Exact 4720 controls per architecture, [810,405,243,540,362] per credential, pass on both initial and fresh five-case native runs and actual Linux6.12.51 with identical native source/C/ELF. Six source classes, three alias forms, independent opens, O_PATH/missing sources, boundary/upper words, musl setters, ignored getter arguments, zero/eight limits and descriptor replacement preserve real signal configuration, metadata/flags/owners/cursors/bytes/AB queues. Both native sequences retain flat 18/14 slab classes and positive equal observed page counts through two200-cycle setter/refusal/alias-close cohorts. Ten explicit allocas and no hidden heap/index helpers. Kernel source/C/ELF remain exactly unchanged; no allocation/lifetime/lock-order change. Initial outer wrapper incorrectly expected inner failure and asserted after successful guest receipts; its source and complete passing diagnostic receipts remain bound. Fresh corrected five-case wrappers complete0. Two production builds, eight host files, one unchanged allocation inventory with existing allowance refusals,63 frozen inputs, pinned Linux primary source, independent lifetime review and executing assertion/passing-as-failure controls bind this evidence. Actual SIGIO/queued-signal delivery, async readiness, ownership/security policy, concurrent mutation/close, GNU wrappers and translated/ELF32 paths remain unqualified; three broad roadmap gates stay open.'
		os.write_file(out + 'fcntlsig-evidence-' + arch + '.json', json2.encode(Evidence{architecture: arch, context: context, base_commit: base, artifacts: artifacts, source_inputs: inputs}, prettify: true) + '\n')!
	}
	for name in ['host-tests.log', 'allocs-before.log', 'coverage-check.log', 'assertion-control.log', 'passing-log-control.log', 'build-before-arm.log', 'build-before-x86.log'] { publish(area + name, out + 'fcntlsig-' + name)! }
	println('Native fcntlsig conformance audit: PASS')
}
