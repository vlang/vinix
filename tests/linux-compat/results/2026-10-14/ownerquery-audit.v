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
	rows := log.split_into_lines().filter(it.starts_with('LINUX OWNERQUERY CASES:')); assert rows.len == 10
	mut seen := map[string]bool{}
	for row in rows {
		fields := row.fields(); assert fields.len == 7 && fields[3].starts_with('ordinary=') && fields[4].starts_with('kind=') && fields[5].starts_with('calls=') && fields[6].starts_with('failures=')
		group := fields[3].all_after('='); kind := fields[4].all_after('=').int(); key := group + '-' + kind.str()
		assert group in ['0', '1'] && kind in [0, 1, 2, 3, 4] && key !in seen; seen[key] = true
		assert fields[5].all_after('=').int() == [405, 135, 135, 225, 315]![kind]
		assert fields[6].all_after('=').int() == if passing { 0 } else { [135, 105, 120, 150, 135]![kind] }
	}
	if passing { assert !log.contains('LINUX OWNERQUERY DETAIL:') && !log.contains('LINUX OWNERQUERY FAIL:') }
	else { assert log.contains('LINUX OWNERQUERY DETAIL:') && log.contains('LINUX OWNERQUERY FAIL:') && !log.contains('LINUX OWNERQUERY: PASS') }
	if reference { assert passing && log.contains('LINUX OWNERQUERY REFERENCE: PASS') && log.contains('Linux version 6.12.51-0-virt') && !log.contains('Kernel panic') && !log.contains('LINUX OWNERQUERY STORAGE:') }
	else if passing { assert log.split_into_lines().filter(it.trim_space() == 'LINUX OWNERQUERY: PASS').len == 1 && !log.contains('LINUX OWNERQUERY REFERENCE: PASS') }
}
fn failure(log string, arch string) { assert log.contains('LINUX OWNERQUERY DETAIL:'), 'ownerquery baseline failure markers required'; semantics(log, false, false, arch) }
fn storage(log string, arch string) {
	mut slabs := [2]int{}; mut pages := [2]int{}; mut seen := map[string]bool{}
	for row in log.split_into_lines() {
		if !row.starts_with('LINUX OWNERQUERY SLAB:') && !row.starts_with('LINUX OWNERQUERY STORAGE:') { continue }
		fields := row.fields(); assert fields.len == 7; group := fields[3].all_after('=').int(); assert group in [0, 1]
		pair := fields[5].all_after('=').split('/'); assert pair.len == 2 && pair[0] == pair[1] && pair.all(it != '' && it.bytes().all(it.is_digit()))
		if fields[2] == 'SLAB:' { key := fields[3] + '-' + fields[4]; assert key !in seen && fields[6] == 'cycles=200'; seen[key] = true; slabs[group]++ }
		else { assert fields[4] == 'cycles=200' && fields[6] == 'PASS' && pair[0].int() == if arch == 'aarch64' { 72 } else { 185 }; pages[group]++ }
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
	for label, path in {'kernel': state + '/linux', 'probe': state + '/probe', 'wrapper_source': state + '/source/ownerqueryreferenceinit/core.v', 'wrapper_c': state + '/fixture.c', 'wrapper_elf': state + '/init', 'initramfs': state + '/initramfs.cpio', 'serial': state + '/serial.log', 'serial_adapter_c': state + '/serial.c', 'controller_source': '/Users/alex/code/vinix/tests/linux-compat/ownerquery-reference.v', 'qemu': command[0]} { assert artifacts[label] == digest(path) }
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/ownerqueryreferenceinit/core.v')
	semantics(os.read_file(state + '/serial.log')!, true, true, arch); return artifacts
}

// Preserve completed superseded probes, including the Linux join/detach
// timing failure. Their source fingerprints differ from the final probe.
fn diagnostics(area string, out string, arch string, suffix string, base string) !map[string]string {
	mut hashes := map[string]string{}
	for prefix in ['verified', 'qualified', 'final'] {
		for phase in ['before', 'after', 'reference'] {
			if prefix == 'verified' && phase == 'after' { continue }
			state := area + prefix + '-' + phase + '-' + suffix
			value := object(state + '/receipt.json')!
			assert value['architecture']!.str() == arch
			mut artifacts := {'receipt': digest(state + '/receipt.json'), 'aggregate': digest(state + '.log')}
			mut capture := ''
			if phase == 'reference' {
				assert value['finished']!.bool() && value['status']!.int() == 0
				assert value['passed']!.bool() == !(prefix == 'qualified' && suffix == 'x86')
				original := value['artifacts']!.as_map_of_strings()
				for label, path in {'kernel': state + '/linux', 'probe': state + '/probe', 'wrapper_source': state + '/source/ownerqueryreferenceinit/core.v', 'wrapper_c': state + '/fixture.c', 'wrapper_elf': state + '/init', 'initramfs': state + '/initramfs.cpio', 'serial': state + '/serial.log', 'serial_adapter_c': state + '/serial.c'} { assert original[label] == digest(path); artifacts[label] = original[label] }
				capture = state + '/serial.log'
				if prefix == 'qualified' && suffix == 'x86' {
					log := os.read_file(capture)!
					assert log.contains('ordinary=0 kind=2 call=46') && log.contains('ordinary=0 kind=2 calls=135 failures=1') && log.contains('LINUX OWNERQUERY FAIL:')
				} else { semantics(os.read_file(capture)!, true, true, arch) }
			} else {
				rows := value['results']!.as_array(); assert rows.len == if phase == 'before' { 1 } else { 5 }
				for row in rows {
					entry := row.as_map(); name := entry['name']!.str()
					assert entry['exit_code']!.int() == if phase == 'before' || (prefix == 'final' && name == 'ownerquery') { 1 } else { 0 } && entry['detail']!.str() == ''
					for label, path in {'source': state + '/sources/' + name + 'fixture/core.v', 'init': state + '/' + name + '/init', 'iso': state + '/' + name + '/test.iso'} {
						key := if label == 'source' { 'source_sha256' } else if label == 'init' { 'init_sha256' } else { 'iso_sha256' }; hash := digest(path); assert entry[key]!.str() == hash; artifacts[name + '_' + label] = hash
					}
					artifacts[name + '_c'] = digest(state + '/' + name + '/fixture.c'); artifacts[name + '_serial'] = digest(state + '/' + name + '/serial.log')
				}
				capture = state + '/ownerquery/serial.log'
				if prefix == 'final' {
					// Cached task paths never satisfied the removal predicate;
					// this setup failure stopped the worker/group categories.
					log := os.read_file(capture)!
					assert log.contains('LINUX OWNERQUERY FAIL:') && !log.contains('LINUX OWNERQUERY STORAGE:')
					case_rows := log.split_into_lines().filter(it.starts_with('LINUX OWNERQUERY CASES:')); assert case_rows.len == 10
					mut seen := map[string]bool{}
					for case_row in case_rows {
						fields := case_row.fields(); assert fields.len == 7
						group := fields[3].all_after('='); kind := fields[4].all_after('=').int(); key := group + '-' + kind.str()
						assert group in ['0', '1'] && kind in [0, 1, 2, 3, 4] && key !in seen; seen[key] = true
						assert fields[5].all_after('=').int() == [405, 135, 45, 0, 315]![kind]
						assert fields[6].all_after('=').int() == if phase == 'before' { [135, 105, 30, 0, 135]![kind] } else { 0 }
					}
				} else if phase == 'before' { failure(os.read_file(capture)!, arch) } else { semantics(os.read_file(capture)!, true, false, arch) }
			}
			label := prefix + '-' + phase + '-' + arch
			publish(state + '/receipt.json', out + 'ownerquery-diagnostic-' + label + '.json')!
			publish(state + '.log', out + 'ownerquery-diagnostic-' + label + '.log')!
			publish(capture, out + 'ownerquery-diagnostic-' + label + '-native.log')!
			os.write_file(out + 'ownerquery-diagnostic-' + label + '-evidence.json', json2.encode(Evidence{architecture: arch, context: 'Completed superseded probe; diagnostic only. Qualification uses fresh task-directory snapshots and bounded observed settling after join. The qualified x86 Linux reference retains its single premature post-join expectation failure; final native profiles retain cached-path removal setup failures and passing related cases.', base_commit: base, artifacts: artifacts}, prettify: true) + '\n')!
			for key, hash in artifacts { hashes[label + '_' + key] = hash }
		}
	}
	return hashes
}


fn erase(source string, before bool) string {
	names := ['file__syscall_fcntl', 'proc__pid_number_exists', 'proc__pid_number_id', 'proc__pid_owner_number']; mut kept := []string{}; mut inside := false; mut separator := false; mut removed := 0
	for line in source.split_into_lines() {
		if inside { if line == '}' { inside = false; separator = true }; continue }
		if separator { assert line == ''; separator = false; continue }
		if line != '' && line[0] != `	` && names.any(line.contains(' ' + it + '(')) { assert line.ends_with(';') || line.ends_with('{'), line; inside = line.ends_with('{'); removed++; continue }
		kept << line
	}; assert !inside && removed == if before { 4 } else { 6 }; return kept.join('
')
}

fn main() {
	if '--negative-control' in os.args { assert false, 'audit assertions must execute'; return }
	if '--negative-pass-control' in os.args { failure(os.read_file(os.args[2])!, os.args[3]); return }
	root := '/Users/alex/code/vinix/'; area := '/Users/alex/.cache/vinix-linux-compat/ownerquery-20261014/'; out := root + 'tests/linux-compat/results/2026-10-14/'; compiler := '/Users/alex/.cache/vinix-linux-compat/procstate-20261013/compiler/v'
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'audit assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control', area + 'settled-after-arm/ownerquery/serial.log', 'aarch64'], 'ownerquery baseline failure markers required'))!
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == '905c838513a0939fb8d269786487346fbd62d7a1'
	mut inputs := object(area + 'kernel-arm/docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 63
	assert digest(area + 'linux-fcntl.c') == 'ec0082d625d58d482d94ff8f1639d27a2da63e6cf3f50580820c158ee1a48acd'
	assert digest(compiler) == 'f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39'
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total') && os.read_file(area + 'coverage-check.log')!.contains('Linux dispatch coverage: PASS')
	before_allocs := os.read_file(area + 'allocs-before.log')!; after_allocs := os.read_file(area + 'allocs-after.log')!
	for arch in ['aarch64', 'x86_64'] {
		before_count := if arch == 'aarch64' { '659 source files, 400 allocation sites (V exit 0)' } else { '655 source files, 292 allocation sites (V exit 0)' }
		after_count := if arch == 'aarch64' { '1304 source files, 400 allocation sites (V exit 0)' } else { '1315 source files, 292 allocation sites (V exit 0)' }
		assert before_allocs.contains(arch + ': ' + before_count) && after_allocs.contains(arch + ': ' + after_count)
	}
	assert before_allocs.split_into_lines().filter(it.starts_with('NEW:')) == after_allocs.split_into_lines().filter(it.starts_with('NEW:'))
	paths := ['kernel/file/file.v', 'kernel/proc/pidns.v']; review := out + 'ownerquery-lifetime-review.md'; review_text := os.read_file(review)!; assert review_text.starts_with('Independent ownerquery lifetime review: PASS')
	for path in paths { assert review_text.contains(inputs[path]) && inputs[path] == digest(root + path) }
	assert review_text.contains(digest(root + 'tests/linux-compat/ownerqueryfixture/core.v'))
	drift_values := object(area + 'preflight-drift-pins.json')!; mut drift_pins := map[string]string{}
	for key, value in drift_values { drift_pins[key] = value.str() }; assert drift_pins.len == 8
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'; assert git(tree, ['rev-parse', 'HEAD'])! == base && git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])!.split_into_lines() == paths
		for path, hash in inputs { if path.starts_with('kernel/') { assert digest(tree + path) == hash } }
		kernel_c := tree + 'kernel/obj/blob.c'; assert erase(os.read_file(area + 'before-' + suffix + '.c')!, true) == erase(os.read_file(kernel_c)!, false), 'complete C outside fcntl and precisely the replaced/new scalar PID lookup units'; assert review_text.contains(digest(kernel_c))
		preview := os.read_file(area + 'preview-' + suffix + '.c')!; assert preview.count('alloca(') == 26 && !preview.contains('memdup(') && !preview.contains('malloc(') && !preview.contains('new_array') && !preview.contains('v_fixed_index')
		before_hash := digest(area + 'baseline-' + suffix + '/kernel/bin/vinix'); after_hash := digest(tree + 'kernel/bin/vinix')
		baseline := area + 'settled-before-' + suffix; candidate := area + 'settled-after-' + suffix; reference := area + 'settled-reference-' + suffix
		before := receipt(baseline, arch, before_hash, ['ownerquery'], true)!; after := receipt(candidate, arch, after_hash, ['ownerquery', 'fcntlowner', 'fcntlsig', 'open', 'runtime'], false)!
		assert before['ownerquery_source'] == after['ownerquery_source'] && before['ownerquery_init'] == after['ownerquery_init'] && before['ownerquery_c'] == after['ownerquery_c'] && after['ownerquery_c'] == digest(area + 'preview-' + suffix + '.c')
		failure(os.read_file(baseline + '/ownerquery/serial.log')!, arch); log := os.read_file(candidate + '/ownerquery/serial.log')!; semantics(log, true, false, arch); storage(log, arch); assert review_text.contains(digest(candidate + '/ownerquery/serial.log'))
		linux := reference_receipt(reference, arch, after['ownerquery_init'])!; assert review_text.contains(linux['serial']) && review_text.contains(linux['wrapper_c']) && review_text.contains(linux['probe'])
		preflight := area + 'preflight-settled-' + suffix
		assert digest(preflight + '/init') == after['ownerquery_init'] && drift_pins[arch + '_elf'] == after['ownerquery_init']
		assert drift_pins[arch + '_native_c'] == after['ownerquery_c'] && drift_pins[arch + '_preflight_c'] == digest(preflight + '/fixture.c')
		assert drift_pins[arch + '_native_c'] != drift_pins[arch + '_preflight_c'] && review_text.contains(drift_pins[arch + '_preflight_c'])
		drift := area + 'preflight-drift-' + arch + '.log'; assert drift_pins[arch + '_drift'] == digest(drift)
		drift_text := os.read_file(drift)!; changed := drift_text.split_into_lines().filter((it.starts_with('+') && !it.starts_with('+++')) || (it.starts_with('-') && !it.starts_with('---')))
		assert drift_text.contains('v3_eprint_begin') && !changed.any(it.contains('ownerqueryfixture__')) && drift_text.split_into_lines().filter(it.starts_with('@@')).len == 1
		assert linux['kernel'] == digest('/Users/alex/.cache/vinix-linux-compat/statx-20261013/linux-inputs/vmlinuz-' + arch)
		assert os.read_file(candidate + '/runtime/serial.log')!.contains('LINUX RUNTIME PASS: atomics SIMD TLS') && os.read_file(candidate + '/runtime/serial.log')!.contains('LINUX RUNTIME PASS: JIT page sizes')
		mut artifacts := {'linux_fcntl_source': digest(area + 'linux-fcntl.c'), 'compiler': digest(compiler), 'controller': digest(area + 'run'), 'controller_source': digest(root + 'tests/linux-compat/run.v'), 'reference_controller': digest(area + 'reference'), 'audit': digest(@FILE), 'audit_executable': digest(os.executable()), 'review': digest(review), 'before_kernel': before_hash, 'after_kernel': after_hash, 'before_kernel_c': digest(area + 'before-' + suffix + '.c'), 'after_kernel_c': digest(kernel_c), 'preview': digest(area + 'preview-' + suffix + '.c')}
		for key, hash in before { artifacts['before_' + key] = hash }; for key, hash in after { artifacts['after_' + key] = hash }; for key, hash in linux { artifacts['reference_' + key] = hash }
		artifacts['reference_receipt'] = digest(reference + '/receipt.json'); artifacts['reference_aggregate'] = digest(reference + '.log')
		artifacts['preflight_c'] = drift_pins[arch + '_preflight_c']; artifacts['preflight_init'] = drift_pins[arch + '_elf']; artifacts['preflight_drift'] = drift_pins[arch + '_drift']; artifacts['preflight_drift_pins'] = digest(area + 'preflight-drift-pins.json')
		publish(drift, out + 'ownerquery-preflight-drift-' + arch + '.log')!
		for phase in ['before', 'after'] {
			state := if phase == 'after' { candidate } else { baseline }; publish(state + '.log', out + 'ownerquery-' + phase + '-' + arch + '.log')!; publish(state + '/receipt.json', out + 'ownerquery-' + phase + '-' + arch + '.json')!; publish(state + '/ownerquery/serial.log', out + 'ownerquery-' + phase + '-' + arch + '-native.log')!
			build := area + 'build-' + phase + '-' + suffix + '.log'; build_text := os.read_file(build)!; assert build_text.contains('-o bin/vinix') && !build_text.contains('Error ') && !build_text.contains('No space left on device'); artifacts['build_' + phase] = digest(build)
		}
		publish(reference + '.log', out + 'ownerquery-reference-' + arch + '.log')!; publish(reference + '/serial.log', out + 'ownerquery-reference-' + arch + '-native.log')!; publish(reference + '/receipt.json', out + 'ownerquery-reference-' + arch + '.json')!
		for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'scope-check.log', 'assertion-control.log', 'passing-log-control.log'] { artifacts[name] = digest(area + name) }
		for key, hash in diagnostics(area, out, arch, suffix, base)! { artifacts['diagnostic_' + key] = hash }
		artifacts['build_arm_disk_diagnostic'] = digest(area + 'build-after-arm-disk-diagnostic.log')
		context := 'Native musl ELF64 owner getter task kinds and one-level PID namespace mapping. Root/UID1000 cohorts each run [405,135,135,225,315] controls: live main PID/non-main TID/child PID kinds, child reap, joined worker with independent fresh task-directory membership/removal snapshots and bounded observed settling, surviving leaderless group then final member reap, and inside/outside shared-description namespace queries. Total2430 controls per architecture; baselines fail1290. Original/dup/CLOEXEC aliases on regular/pipe/UNIX-stream descriptions use native raw/libc scalar/extended getters, upper words, full-width owner pointers and proper negative raw group errno decoding. Accepted kind-mismatched targets return zero on getters; removed targets return zero and new setters ESRCH while preserving kind. Group kinds remain visible after leader reap until final member release. Setters store kernel numbers; getters translate attached requested kinds into caller namespace. Scalar owner pair updates/snapshots use Handle.l, released before table lookup. Helpers retain no target or namespace pointer; no added fields, objects or allocation sites. Native baseline/candidate probe source/C/ELF are identical; actual Linux6.12.51 passes the same ELF. Separately compiled preflight C has explicitly pinned stderr-scaffolding drift and identical resulting ELF, without C normalization. Two200-cycle cohorts cover real aliases, live non-main-thread kinds, successful updates and refused missing targets with all slabs and large pages flat. Four completed production builds, five candidate cases, eight host files, 63 source fingerprints, exact generated-C scope and independent lifetime review are bound; 26 explicit probe allocas and no hidden heap/index helpers. Failed joins, invalid post-launch TID or live task check and pre-join child failure terminate without unwinding a borrowed worker frame. Assertion and passing-as-baseline controls execute. Existing allocation allowance refusals remain. One ARM build disk-exhaustion diagnostic and all completed earlier profiles are preserved, including a Linux x86 premature post-join expectation failure and native cached-path removal setup failures. Final builds and profiles are complete, temporary data uses a new verified RAM scratch volume. Retained PID identity/recycling, exact exit/mutation races and cached task-path invalidation, SIGIO/security policy, deeper namespaces, GNU wrappers and translated/ELF32 paths plus the three broad roadmap gates remain separate.'
		os.write_file(out + 'ownerquery-evidence-' + arch + '.json', json2.encode(Evidence{architecture: arch, context: context, base_commit: base, artifacts: artifacts, source_inputs: inputs}, prettify: true) + '\n')!
	}
	assert os.read_file(area + 'build-after-arm-disk-diagnostic.log')!.contains('No space left on device')
	for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log', 'scope-check.log', 'assertion-control.log', 'passing-log-control.log', 'build-before-arm.log', 'build-before-x86.log', 'build-after-arm.log', 'build-after-x86.log', 'build-after-arm-disk-diagnostic.log', 'preflight-drift-pins.json'] { publish(area + name, out + 'ownerquery-' + name)! }
	println('Native ownerquery conformance audit: PASS')
}
