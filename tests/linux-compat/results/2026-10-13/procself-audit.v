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
	lines := source.split_into_lines().filter(!it.starts_with(' ') && !it.starts_with('	') && it.contains(' ' + name + '(') && it.ends_with(' {'))
	assert lines.len == 1; return source.all_after(lines[0]).all_before('\n}\n')
}
fn control(args []string, marker string) string {
	mut p := os.new_process(os.executable()); p.set_args(args); p.set_redirect_stdio(); p.run()
	output := p.stdout_slurp() + p.stderr_slurp(); p.wait(); code := p.code; p.close()
	if code != 1 || !output.contains(marker) { panic('audit negative control did not execute') }; return output
}
fn canonical_discard(source string) string {
	mut output := strings.new_builder(source.len); mut names := map[string]string{}; mut position := 0
	for position < source.len {
		start := position
		if source[position].is_letter() || source[position] == `_` {
			position++
			for position < source.len && (source[position].is_alnum() || source[position] == `_`) { position++ }
			token := source[start..position]
			if token.starts_with('__discard_') && token.len > 10 && token[10..].bytes().all(it.is_digit() || it == `_`) {
				if token !in names { names[token] = '_return' + names.len.str() }
				output.write_string(names[token])
			} else { output.write_string(token) }
		} else { output.write_u8(source[position]); position++ }
	}
	return output.str()
}
fn rebind_literals(source string, names map[string]string) string {
	mut result := strings.new_builder(source.len); mut position := 0
	for position < source.len {
		start := position; byte := source[position]
		if byte == `"` || byte == `'` {
			position++
			for position < source.len {
				if source[position] == `\\` { position += 2; continue }
				if source[position] == byte { position++; break }; position++
			}
			assert position <= source.len; result.write_string(source[start..position])
		} else if byte.is_letter() || byte == `_` {
			position++; for position < source.len && (source[position].is_alnum() || source[position] == `_`) { position++ }
			token := source[start..position]; result.write_string(if token in names { names[token] } else { token })
		} else { result.write_u8(byte); position++ }
	}
	return result.str()
}
fn restore_generated(generated string, baseline string) {
	// Removing the first use of /proc/ moves that interned constant to its
	// next use. Bind symbols by exact bytes and restore declaration order.
	old_pool := baseline.split_into_lines().filter(it.starts_with('static const string _str_'))
	new_pool := generated.split_into_lines().filter(it.starts_with('static const string _str_'))
	proc_literal := old_pool.filter(it.ends_with(' = {"/proc/", 6, 1};')); assert proc_literal.len == 1 && old_pool.len == new_pool.len
	mut old_by_value := map[string]string{}; mut names := map[string]string{}
	for row in old_pool {
		value := row.all_after(' = '); assert value !in old_by_value
		old_by_value[value] = row.all_after('static const string ').all_before(' = ')
	}
	mut seen := map[string]bool{}
	for row in new_pool {
		value := row.all_after(' = '); assert value in old_by_value && value !in seen; seen[value] = true
		names[row.all_after('static const string ').all_before(' = ')] = old_by_value[value]
	}
	mut restored := rebind_literals(generated, names)
	mapped_pool := rebind_literals(new_pool.join('\n'), names)
	assert restored.count(mapped_pool) == 1 && baseline.count(old_pool.join('\n')) == 1
	restored = restored.replace(mapped_pool, old_pool.join('\n'))
	current := definition(restored, 'fs__procfs_dynamic_link_target')
	previous := definition(baseline, 'fs__procfs_dynamic_link_target')
	call := '\n\tlib__Text__add(text, ' + proc_literal[0].all_after('static const string ').all_before(' = ') + ');'
	assert previous.count(call) == 1 && previous.replace(call, '') == current
	assert current.contains('lib__finish_text') && current.contains('proc__pid_in') && current.contains('proc__tid_in')
	assert restored.count(current) == 1
	restored = restored.replace(current, previous)
	if restored != baseline { os.write_file('/Users/alex/.cache/vinix-linux-compat/procself-20261013/scope-restored.c', restored) or { panic(err) } }
	matched := canonical_discard(restored) == canonical_discard(baseline)
	assert matched, 'only dynamic target formatting, exact constant-pool rebinding and unused-loop source offsets may change whole kernel C'
}
fn failure(log string) {
	assert log.contains('cases=270 failures=90 status=1'), 'relative procfs baseline markers required'
	rows := log.split_into_lines().filter(it.starts_with('LINUX PROCSELF OUTCOMES:'))
	assert rows.len == 6 && rows.all(it.contains('cases=270 failures=90 status=1'))
	assert log.contains('LINUX PROCSELF CHROOT: no-/proc relative-self/thread-self-status FAIL')
	assert log.contains('LINUX PROCSELF FAIL: relative target, reader identity, resolution or storage')
	assert !log.split_into_lines().any(it.trim_space() == 'LINUX PROCSELF: PASS')
}
fn success(log string, arch string) {
	rows := log.split_into_lines().filter(it.starts_with('LINUX PROCSELF OUTCOMES:'))
	assert rows.len == 6 && rows.all(it.contains('cases=270 failures=0 status=1'))
	mut cohorts := map[string]bool{}
	for row in rows {
		fields := row.fields(); assert fields.len == 10
		group := fields[3].all_after('='); slot := fields[4].all_after('=')
		assert group in ['0', '1'] && slot in ['0', '1', '2'] && group + '-' + slot !in cohorts
		cohorts[group + '-' + slot] = true
		assert (fields[5].all_after('=') == fields[6].all_after('=')) == (slot == '0')
	}
	mut slab_keys := map[string]bool{}; mut counts := [2]int{}; mut pages := [2]int{}
	for line in log.split_into_lines() {
		if !line.starts_with('LINUX PROCSELF SLAB:') && !line.starts_with('LINUX PROCSELF STORAGE:') { continue }
		fields := line.fields(); assert fields.len == 7
		group := fields[3].all_after('=').int(); assert group in [0, 1]
		pair := fields[5].all_after('=').split('/'); assert pair.len == 2 && pair.all(it != '' && it.bytes().all(it.is_digit())) && pair[0] == pair[1]
		if fields[2] == 'SLAB:' {
			key := fields[3] + '-' + fields[4]; assert key !in slab_keys && fields[6] == 'cycles=200'
			slab_keys[key] = true; counts[group]++
		} else {
			assert fields[4] == 'cycles=200' && fields[6] == 'PASS'
			assert pair[0].u64() == if arch == 'aarch64' { u64(63) } else { u64(160) }; pages[group]++
		}
	}
	for group in 0 .. 2 { assert counts[group] == if arch == 'aarch64' { 18 } else { 14 }; assert pages[group] == 1 }
	assert log.contains('LINUX PROCSELF CHROOT: no-/proc relative-self/thread-self-status PASS') && log.split_into_lines().filter(it.trim_space() == 'LINUX PROCSELF: PASS').len == 1
}
fn receipt(state string, arch string, kernel_hash string, names []string, failing bool) !map[string]string {
	value := object(state + '/receipt.json')!; assert value['architecture']!.str() == arch && value['kernel_sha256']!.str() == kernel_hash
	assert digest(state + '/kernel/bin/vinix') == kernel_hash
	rows := value['results']!.as_array(); assert rows.len == names.len
	mut artifacts := {'receipt': digest(state + '/receipt.json'), 'aggregate': digest(state + '.log')}
	for index, row in rows {
		entry := row.as_map(); name := entry['name']!.str(); assert name == names[index]
		assert entry['exit_code']!.int() == if failing { 1 } else { 0 } && entry['detail']!.str() == ''
		for label, path in {'source': state + '/sources/' + name + 'fixture/core.v', 'init': state + '/' + name + '/init', 'iso': state + '/' + name + '/test.iso'} {
			hash := digest(path); assert hash == entry[if label == 'source' { 'source_sha256' } else if label == 'init' { 'init_sha256' } else { 'iso_sha256' }]!.str()
			artifacts[name + '_' + label] = hash
		}
		artifacts[name + '_c'] = digest(state + '/' + name + '/fixture.c')
		artifacts[name + '_serial'] = digest(state + '/' + name + '/serial.log')
		if !failing {
			assert artifacts[name + '_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/' + name + 'fixture/core.v')
			assert os.read_file(state + '/' + name + '/serial.log')!.contains('LINUX ' + name.to_upper() + ': PASS')
		}
	}
	return artifacts
}
fn main() {
	if '--negative-control' in os.args { assert false, 'audit assertions must execute'; return }
	if '--negative-pass-control' in os.args { failure(os.read_file(os.args[2])!); return }
	root := '/Users/alex/code/vinix/'; area := '/Users/alex/.cache/vinix-linux-compat/procself-20261013/'; compiler := '/Users/alex/.cache/vinix-linux-compat/compiler-f6358ec/'
	out := root + 'tests/linux-compat/results/2026-10-13/'
	if '--kernel-control' in os.args {
		for suffix in ['arm', 'x86'] { restore_generated(os.read_file(area + 'kernel-' + suffix + '/kernel/obj/blob.c')!, os.read_file(area + 'before-' + suffix + '.c')!) }
		println('Relative procfs kernel scope: PASS'); return
	}
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'audit assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control', area + 'after-arm/procself/serial.log'], 'relative procfs baseline markers required'))!
	base := os.read_file(area + 'base.txt')!.trim_space(); assert base == '7da8032f9ea39d0d6dacd0c609aebd77f13ff8ed'
	inputs := object(area + 'kernel-arm/docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings(); assert inputs.len == 63 && inputs['kernel/fs/procfs.v'] == digest(root + 'kernel/fs/procfs.v')
	assert git(compiler, ['rev-parse', 'HEAD'])! == 'f6358ecff9cffbf2d8b03e6a09269aac7707e26c' && git(compiler, ['diff', '--name-only', 'HEAD'])! == ''
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total') && os.read_file(area + 'coverage-check.log')!.contains('Linux dispatch coverage: PASS')
	before_allocs := os.read_file(area + 'allocs-before.log')!; after_allocs := os.read_file(area + 'allocs-after.log')!
	assert before_allocs.split_into_lines().filter(it.starts_with('NEW:')) == after_allocs.split_into_lines().filter(it.starts_with('NEW:'))
	for arch, row in {'aarch64': '657 source files, 406 allocation sites', 'x86_64': '653 source files, 295 allocation sites'} { assert before_allocs.contains(arch + ': ' + row + ' (V exit 0)') && after_allocs.contains(arch + ': ' + row + ' (V exit 0)') }
	assert git(area + 'audit-baseline', ['diff', '--name-only', 'HEAD'])! == '' && git(area + 'audit-baseline', ['rev-parse', 'HEAD'])! == base
	for path in ['tests/linux-compat/readlinkabifixture/core.v', 'tests/linux-compat/readlinkemptyfixture/core.v'] {
		original := git(root, ['show', base + ':' + path])! + '\n'
		assert original.count("c'/proc/%d'") == 1 && original.replace("c'/proc/%d'", "c'%d'") == os.read_file(root + path)!
	}
	mount_source := git(root, ['show', base + ':tests/procfs-mount/mountfixture/core.v'])! + '\n'
	assert mount_source.replace("length == 7 && C.memcmp(&link[0], c'/proc/1', 7)", "length == 1 && C.memcmp(&link[0], c'1', 1)").replace("== 7 && C.memcmp(&link[0], c'/proc/1', 7)", "== 1 && C.memcmp(&link[0], c'1', 1)") == os.read_file(root + 'tests/procfs-mount/mountfixture/core.v')!
	review := root + 'tests/linux-compat/results/2026-10-13/procself-lifetime-review.md'
	review_text := os.read_file(review)!; assert review_text.starts_with('Independent relative procfs link lifetime review: PASS')
	for path in [root + 'kernel/fs/procfs.v', root + 'tests/linux-compat/procselffixture/core.v', area + 'preview-arm.c', area + 'preview-x86.c'] { assert review_text.contains(digest(path)) }
	for arch, suffix in {'aarch64': 'arm', 'x86_64': 'x86'} {
		tree := area + 'kernel-' + suffix + '/'
		assert git(tree, ['rev-parse', 'HEAD'])! == base && git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])! == 'kernel/fs/procfs.v'
		for path, hash in inputs { if path.starts_with('kernel/') { assert digest(tree + path) == hash } }
		restore_generated(os.read_file(tree + 'kernel/obj/blob.c')!, os.read_file(area + 'before-' + suffix + '.c')!)
		assert review_text.contains(digest(tree + 'kernel/obj/blob.c')) && review_text.contains(digest(area + 'after-' + suffix + '/procself/serial.log'))
		mut artifacts := {'compiler': digest(compiler + 'v'), 'controller': digest(area + 'run'), 'controller_source': digest(root + 'tests/linux-compat/run.v'), 'audit': digest(@FILE),
			'host_tests': digest(area + 'host-tests.log'), 'allocs_before': digest(area + 'allocs-before.log'), 'allocs_after': digest(area + 'allocs-after.log'), 'allocs_overlap': digest(area + 'allocs-overlap.log'),
			'assertion_control': digest(area + 'assertion-control.log'), 'passing_log_control': digest(area + 'passing-log-control.log'), 'coverage_check': digest(area + 'coverage-check.log'),
			'lifetime_review': digest(review), 'kernel_c': digest(tree + 'kernel/obj/blob.c'), 'kernel_before_c': digest(area + 'before-' + suffix + '.c'), 'preview_c': digest(area + 'preview-' + suffix + '.c')}
		for phase in ['before', 'after'] {
			build := area + 'build-' + phase + '-' + suffix + '.log'; build_log := os.read_file(build)!
			assert build_log.contains('-o bin/vinix') && !build_log.contains('Error ') && !build_log.contains('No space left on device'); artifacts['build_' + phase] = digest(build)
			state := area + if phase == 'before' { 'final-before-' + suffix } else { 'after-' + suffix }
			kernel_hash := digest(if phase == 'before' { area + 'before-' + suffix + '.kernel' } else { tree + 'kernel/bin/vinix' }); artifacts[phase + '_kernel'] = kernel_hash
			data := receipt(state, arch, kernel_hash, if phase == 'before' { ['procself'] } else { ['procself', 'readlinkabi', 'readlinkempty', 'open', 'namespace', 'runtime'] }, phase == 'before')!
			for key, value in data { artifacts[phase + '_' + key] = value }
			assert data['procself_source'] == digest(root + 'tests/linux-compat/procselffixture/core.v') && data['procself_c'] == digest(area + 'preview-' + suffix + '.c')
			log := os.read_file(state + '/procself/serial.log')!; if phase == 'before' { failure(log) } else { success(log, arch); assert os.read_file(state + '.log')!.contains('Linux compatibility guest suite: PASS') }
			publish(state + '.log', out + 'procself-' + phase + '-' + arch + '.log')!; publish(state + '/receipt.json', out + 'procself-' + phase + '-' + arch + '.json')!
		}
		// Preserve initial wider status-file assertions and completed failures.
		initial := area + 'before-' + suffix; data := receipt(initial, arch, artifacts['before_kernel'], ['procself'], true)!
		for key, value in data { artifacts['initial_before_' + key] = value }
		publish(initial + '.log', out + 'procself-initial-before-' + arch + '.log')!; publish(initial + '/receipt.json', out + 'procself-initial-before-' + arch + '.json')!
		original_v := os.read_file(initial + '/sources/procselffixture/core.v')!; final_v := os.read_file(root + 'tests/linux-compat/procselffixture/core.v')!
		publish(initial + '/sources/procselffixture/core.v', out + 'procself-initial-fixture.v.txt')!
		assert digest(out + 'procself-initial-fixture.v.txt') == data['procself_source']
		for name in ['probe', 'matrix', 'cycle', 'storage', 'worker', 'prepare', 'cleanup', 'chroot_test', 'run'] { assert definition(original_v, name) == definition(final_v, name) }
		for phase in ['mount', 'mount-before', 'mount-reuse'] {
			state := area + phase + '-' + suffix; value := object(state + '/inputs.json')!
			assert value['selected_kernel_sha256']!.str() == artifacts[if phase == 'mount-before' { 'before_kernel' } else { 'after_kernel' }]
			assert value['source_sha256']!.as_map_of_strings()['core.v'] == digest(root + 'tests/procfs-mount/mountfixture/core.v') && value['fixture_elf_sha256']!.str() == digest(state + '/init') && value['iso_sha256']!.str() == digest(state + '/test.iso')
			log := os.read_file(state + '/serial.log')!
			if phase == 'mount-reuse' { assert value['native_guest_returncode']!.int() == 0 && log.contains('PROC MOUNT GUEST: PASS') && log.contains('PROC MOUNT PASS: inactive view reuse rejects self edges before retarget, concurrently') }
			else { assert value['native_guest_returncode']!.int() == 1 && log.contains('PROC MOUNT FAIL: line=80 errno=16') }
			for label, path in {'log': state + '.log', 'inputs': state + '/inputs.json', 'c': state + '/fixture.c', 'init': state + '/init', 'iso': state + '/test.iso', 'serial': state + '/serial.log'} { artifacts[phase + '_' + label] = digest(path) }
			publish(state + '.log', out + 'procself-' + phase + '-' + arch + '.log')!; publish(state + '/inputs.json', out + 'procself-' + phase + '-' + arch + '.json')!
		}
		if suffix == 'arm' {
			initial_after := receipt(area + 'initial-after-arm', arch, artifacts['after_kernel'], ['procself'], true)!
			for key, value in initial_after { artifacts['initial_after_' + key] = value }
			log := os.read_file(area + 'initial-after-arm/procself/serial.log')!; assert log.split_into_lines().filter(it.starts_with('LINUX PROCSELF OUTCOMES:')).all(it.contains('failures=0')) && log.contains('status=0') && log.contains('LINUX PROCSELF CHROOT: no-/proc relative-self/thread-self-status PASS')
			publish(area + 'initial-after-arm.log', out + 'procself-initial-after-aarch64.log')!; publish(area + 'initial-after-arm/receipt.json', out + 'procself-initial-after-aarch64.json')!
		} else {
			assert !os.exists(area + 'initial-after-x86/receipt.json')
			for label, path in {'aggregate': area + 'initial-after-x86.log', 'source': area + 'initial-after-x86/sources/procselffixture/core.v', 'c': area + 'initial-after-x86/procself/fixture.c'} { artifacts['initial_after_partial_' + label] = digest(path) }
			publish(area + 'initial-after-x86.log', out + 'procself-initial-after-x86_64-partial.log')!
		}
		context := 'Native musl ELF64 procfs relative self/thread-self targets: 1620 root/UID1000 raw/musl checks per architecture across inherited O_PATH links/dirfds, pathname and empty-path APIs, three proc mounts, main/fork/pthread readers, short/full copies and destination faults. Exact current PID/task/TID bytes, no NUL/canaries and numeric target inode/dev/mode/Tgid checks; chroot resolution works without /proc. Original task-status Pid assertions exposed a distinct leader-PID reporting bug; final target qualification excludes that field and preserves initial failed artifacts. Baselines fail90/reader and chroot resolution; candidates pass with 200 cycles of120 probes plus6 status checks (12 file opens) after32 warmups, flat live slabs and63ARM/160x86 big pages. All six related compatibility guests and eight host tests pass. Namespace inactive-root reuse passes both architectures; full mount suites fail existing16KiB retention bound at line80 on baseline and candidate, published without relaxation. Whole kernel C matches after restoring one dynamic-target formatter, exact literal-pool binding/order and unused-loop source offsets; namespace borrowing/Text/free ownership unchanged, independent generated-lifetime review passes. Source inputs/compiled sources/ELFs/ISOs/kernel/logs/receipts are pinned, both assertion controls run, existing406ARM/295x86 allocation audit failures and NEW rows unchanged. Linux task status identity, symlink atime, restrictive policy, close/unlink/exec races, copy boundaries, full mount retention, glibc/translated/ELF32 and installation/sandbox/portal qualification remain separate.'
		os.write_file(out + 'procself-evidence-' + arch + '.json', json2.encode(Evidence{architecture: arch, context: context, base_commit: base, artifacts: artifacts, source_inputs: inputs}, prettify: true) + '\n')!
	}
	for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'allocs-overlap.log', 'coverage-check.log', 'assertion-control.log', 'passing-log-control.log', 'build-before-arm.log', 'build-before-x86.log', 'build-after-arm.log', 'build-after-x86.log'] { publish(area + name, out + 'procself-' + name)! }
	println('Relative procfs link qualification audit: PASS')
}
