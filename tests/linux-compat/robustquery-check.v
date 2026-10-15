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
fn C.CC_SHA256_Update(voidptr,voidptr,u32) i32
fn C.CC_SHA256_Final(&u8,voidptr) i32
struct Evidence { architecture string context string base_commit string artifacts map[string]string source_inputs map[string]string }






fn body(source string,name string) string {
 rows := source.split_into_lines().filter(it.contains(' '+name+'(') && it.ends_with('{'))
 assert rows.len == 1,name
 return definition(source,'\n'+rows[0])
}







fn digest(path string) string {
	mut input := os.open(path) or { panic(err) }
	defer { input.close() }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	$if macos {
		mut state := C.CC_SHA256_CTX{}
		assert C.CC_SHA256_Init(unsafe { &state }) == 1
		for {
			n := input.read(mut buffer) or {
				if err is os.Eof { break }
				panic(err)
			}
			if n == 0 { break }
			assert C.CC_SHA256_Update(unsafe { &state }, buffer.data, u32(n)) == 1
		}
		mut result := [32]u8{}
		assert C.CC_SHA256_Final(unsafe { &result[0] }, unsafe { &state }) == 1
		return result[..].hex()
	} $else {
		mut state := sha256.new()
		for {
			n := input.read(mut buffer) or {
				if err is os.Eof { break }
				panic(err)
			}
			if n == 0 { break }
			assert state.write(buffer[..n]) or { panic(err) } == n
		}
		mut result := []u8{len: 32}
		state.checksum_into(mut result)
		return result.hex()
	}
}

fn object(path string) !map[string]json2.Any {
	return json2.decode[json2.Any](os.read_file(path)!)!.as_map()
}

fn publish(input string, output string) ! {
	data := os.read_bytes(input)!
	if os.exists(output) {
		assert os.read_bytes(output)! == data
	} else {
		os.write_file_array(output, data)!
	}
}

fn git(tree string, args []string) !string {
	mut p := os.new_process('git')
	p.set_args(['-C', tree, ...args])
	p.set_redirect_stdio_merged()
	p.run()
	output := p.stdout_slurp()
	p.wait()
	code := p.code
	p.close()
	assert code == 0, output
	return output.trim_space()
}

fn control(args []string, marker string) string {
	mut p := os.new_process(os.executable())
	p.set_args(args)
	p.set_redirect_stdio_merged()
	p.run()
	output := p.stdout_slurp()
	p.wait()
	code := p.code
	p.close()
	if code != 1 || !output.contains(marker) { panic('audit negative control did not execute') }
	return output
}

fn storage(log string, arch string, phase string) {
 mut slabs := [4]int{}; mut pages := [4]int{}; mut seen := map[string]bool{}
 for row in log.split_into_lines().filter(it.starts_with('LINUX ROBUSTQUERY SLAB:') || it.starts_with('LINUX ROBUSTQUERY STORAGE:')) {
  fields := row.fields(); assert fields.len == 8 && fields[3].starts_with('ordinary=') && fields[4].starts_with('namespace=')
  ordinary := fields[3].all_after('=').int(); namespace := fields[4].all_after('=').int(); assert ordinary in [0,1] && namespace in [0,1]
  cohort := ordinary+2*namespace; pair := fields[6].all_after('=').split('/'); assert pair.len == 2 && pair[0] == pair[1] && pair.all(it != '' && it.bytes().all(it.is_digit()))
  if fields[2] == 'SLAB:' {
   assert fields[5].starts_with('size=') && fields[7] == 'cycles=200'; key := fields[3]+fields[4]+fields[5]; assert key !in seen; seen[key] = true; slabs[cohort]++
  } else { assert fields[5] == 'cycles=200' && fields[7] == 'PASS' && pair[0].u64() > 0; pages[cohort]++ }
 }
 for cohort in 0 .. 4 {
  assert slabs[cohort] == if phase == 'before' {0} else if arch == 'aarch64' {18} else {14}
  assert pages[cohort] == if phase == 'before' {0} else {1}
 }
}

fn failure(log string, arch string) {
	assert log.contains('LINUX ROBUSTQUERY DETAIL:'), 'robustquery baseline failure markers required'
	semantics(log, 'before', arch, false)
}

fn receipt(state string, arch string, kernel string, names []string, failing bool) !map[string]string {
	value := object(state + '/receipt.json')!
	assert value['architecture']!.str() == arch && value['kernel_sha256']!.str() == kernel && digest(state + '/kernel/bin/vinix') == kernel
	rows := value['results']!.as_array()
	assert rows.len == names.len
	mut artifacts := {
		'receipt': digest(state + '/receipt.json')
	}
	artifacts['aggregate'] = digest(state + '.log')
	for index, row in rows {
		entry := row.as_map()
		name := entry['name']!.str()
		assert name == names[index] && entry['exit_code']!.int() == if failing && index == 0 {
			1
		} else {
			0
		} && entry['detail']!.str() == ''
		for label, path in {
			'source': state + '/sources/' + name + 'fixture/core.v'
			'init':   state + '/' + name + '/init'
			'iso':    state + '/' + name + '/test.iso'
		} {
			hash := digest(path)
			key := if label == 'source' {
				'source_sha256'
			} else if label == 'init' {
				'init_sha256'
			} else {
				'iso_sha256'
			}
			assert hash == entry[key]!.str()
			artifacts[name + '_' + label] = hash
		}
		assert artifacts[name + '_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/' + name + 'fixture/core.v')
		artifacts[name + '_c'] = digest(state + '/' + name + '/fixture.c')
		artifacts[name + '_serial'] = digest(state + '/' + name + '/serial.log')
		if !failing || index > 0 {
			assert os.read_file(state + '/' + name + '/serial.log')!.contains('LINUX ' + name.to_upper() + ': PASS')
		}
	}
	return artifacts
}

fn reference_receipt(state string, arch string, init string) !map[string]string {
	value := object(state + '/receipt.json')!
	assert value['architecture']!.str() == arch && value['passed']!.bool() && value['finished']!.bool() && value['forced']!.bool() && value['status']!.int() == 0
	artifacts := value['artifacts']!.as_map_of_strings()
	command := value['command']!.as_array().map(it.str())
	assert command.contains('-kernel') && command.contains('-initrd') && command.contains('-no-reboot')
	for label, path in {
		'kernel':            state + '/linux'
		'probe':             state + '/probe'
		'wrapper_source':    state + '/source/robustqueryreferenceinit/core.v'
		'wrapper_c':         state + '/fixture.c'
		'wrapper_elf':       state + '/init'
		'initramfs':         state + '/initramfs.cpio'
		'serial':            state + '/serial.log'
		'serial_adapter_c':  state + '/serial.c'
		'controller_source': '/Users/alex/code/vinix/tests/linux-compat/robustquery-reference.v'
		'qemu':              command[0]
	} {
		assert artifacts[label] == digest(path)
	}
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/robustqueryreferenceinit/core.v')
	semantics(os.read_file(state + '/serial.log')!, 'after', arch, true)
	return artifacts
}

fn definition(source string, marker string) string {
	start := source.index(marker) or { panic('missing complete definition: ' + marker) }
	mut depth := 0
	mut entered := false
	for position in start .. source.len {
		if source[position] == `{` {
			depth++
			entered = true
		} else if source[position] == `}` {
			depth--
			if entered && depth == 0 { return source[start..position + 1] }
		}
	}
	panic('unclosed function definition')
}

fn main() {
	if '--scope-only' in os.args {
		area := os.args[2].trim_right('/')+'/'
		check_source(area,'/Users/alex/code/vinix/')!
		for suffix in ['arm','x86'] {check_c(area,suffix)!}
		println('Native robust-list query source/C scope: PASS')
		return
	}
	if '--negative-control' in os.args {
		assert false, 'robustquery assertions must execute'
		return
	}
	if '--negative-pass-control' in os.args {
		failure(os.read_file(os.args[2])!, os.args[3])
		return
	}
	assert os.args.len == 2, 'Usage: robustquery-check.v EVIDENCE-AREA (compile without -prod)'
	area := os.args[1].trim_right('/') + '/'
	states := area + 'states/'
	root := '/Users/alex/code/vinix/'
	out := root + 'tests/linux-compat/results/2026-10-15/'
	os.mkdir_all(out)!
	sdk_and_primary(area, out)!
	diagnostics(area,out)!
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'robustquery assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control',
		states + 'p4-reference-arm/serial.log', 'aarch64'], 'robustquery baseline failure markers required'))!
	check_source(area, root)!
	for suffix in ['arm', 'x86'] { check_c(area, suffix)! }
	os.write_file(area+'scope-check.log','arm/x86: exact whole production C differs only in get_robust_list prototype/body: signed32 PID import, length-before-head order, per-scalar full range and writable endpoints; existing lookup/credential locking, copying and error behavior retained; no allocation/free/pin/stack promotion or normalization\n')!
	base := os.read_file(area + 'base.txt')!.trim_space()
	assert base == '5f06416c1c05afbfa4ae4ae48222b4b298e26c97'
	compiler_root := '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/'
	pins := object(compiler_root + 'compiler-inputs.json')!
	assert pins.len == 15146
	assert pins['v']!.str() == '9e506a9fbd95e2e7c227cc144da023b57a288d0974ea902f1d12270e28bc416b'
	for path, hash in pins {
		assert digest(compiler_root + 'compiler/' + path) == hash.str(), path
	}
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total')
	assert os.read_file(area + 'coverage-check.log')!.count('Linux dispatch coverage: PASS') == 4
	before_alloc := os.read_file(area + 'allocs-before.log')!
	after_alloc := os.read_file(area + 'allocs-after.log')!
	assert before_alloc == after_alloc, 'Allocation diagnostics must remain byte-identical'
	for arch, count in {
		'aarch64': '398'
		'x86_64':  '290'
	} {
		assert before_alloc.split_into_lines().filter(it.starts_with(arch + ':')).len == 1
		assert before_alloc.contains(count + ' allocation sites (V exit 0)') && before_alloc.contains('NEW:')
	}
	assert os.read_file(area + 'coverage-before-check.log')!.count('Linux dispatch coverage: PASS') == 4
	assert os.read_file(area + 'linux-source.sha256')!.trim_space() == digest(area + 'linux-futex-syscalls-v6.12.c') + ' https://kernel.googlesource.com/pub/scm/linux/kernel/git/torvalds/linux/+/refs/tags/v6.12/kernel/futex/syscalls.c?format=TEXT'
	linux_source := os.read_file(area + 'linux-futex-syscalls-v6.12.c')!
	assert linux_source.contains('SYSCALL_DEFINE3(get_robust_list, int, pid,') && linux_source.contains('if (put_user(sizeof(*head), len_ptr))') && linux_source.contains('return put_user(head, head_ptr);')
	assert os.read_file(area + 'watch.log')!.split_into_lines().filter(it.starts_with('Completed ')).len == 8
	retained := object(area + 'watch-retained-inputs.json')!
	assert retained.len == 84
	for path, hash in retained {
		assert path.starts_with(states + 'p4-before-arm/') || path.starts_with(states + 'p4-before-x86/') || path.starts_with(states + 'p4-after-arm/') || path.starts_with(states+'p4-after-x86/')
		assert !path.contains('/iso-build/') && !path.ends_with('/efivars.fd')
		assert os.inode(path).typ == .regular && digest(path) == hash.str(), path
	}
	mut walked := map[string]bool{}
	mut completed := map[string]bool{}
	for suffix in ['arm', 'x86'] {
		for phase in ['before', 'after'] {
			names := if phase == 'before' {
				['robustquery']
			} else {
				['robustquery', 'runtime', 'futex']
			}
			for name in names {
				probe := states + 'p4-' + phase + '-' + suffix + '/' + name
				completed['Completed ' + probe + ': captured files byte-identical; disposable boot staging retired'] = true
				assert !os.exists(probe + '/iso-build') && !os.exists(probe + '/efivars.fd')
				mut count := 0
				for path in os.walk_ext(probe, '') {
					if os.inode(path).typ != .regular { continue }
					assert path in retained && path !in walked
					walked[path] = true
					count++
				}
				assert count == if suffix == 'arm' { 12 } else { 9 }
			}
		}
	}
	assert walked.len == retained.len
	for row in os.read_file(area + 'watch.log')!.split_into_lines() {
		assert row in completed
		completed.delete(row)
	}
	assert completed.len == 0
	for arch, suffix in {
		'aarch64': 'arm'
		'x86_64':  'x86'
	} {
		tree := area + 'kernel-' + suffix + '/'
		assert git(tree, ['rev-parse', 'HEAD'])! == base
		assert git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])! == 'kernel/userland/linux_task.v'
		// Bind the changed wait source to the committed base and both productions.
		assert git(tree,['show',base+':kernel/userland/linux_task.v'])!.trim_space() == os.read_file(area+'before-linux_task.v')!.trim_space()
		inputs := object(tree + 'docs/linux-syscall-coverage.json')!['inputs']!.as_map_of_strings()
		assert inputs.len == 67
		before_inputs := object(area + 'coverage-before-' + suffix + '.json')!['inputs']!.as_map_of_strings()
		assert before_inputs.len == 67
		for path, hash in inputs {
			assert digest(tree + path) == hash, path
			if path in ['kernel/userland/linux_task.v'] {
				assert before_inputs[path] == digest(area+'before-'+os.file_name(path))
				assert git(tree,['show',base+':'+path])!.trim_space() == os.read_file(area+'before-'+os.file_name(path))!.trim_space()
			} else { assert before_inputs[path] == hash }
		}
		mut artifacts := {
			'compiler':                 digest(compiler_root + 'compiler/v')
			'compiler_inputs':          digest(compiler_root + 'compiler-inputs.json')
			'kernel_source':            digest(root + 'kernel/userland/linux_task.v')
			'kernel_source_before':     digest(area + 'before-linux_task.v')
			'fixture_source':           digest(root + 'tests/linux-compat/robustqueryfixture/core.v')
			'audit_source':             digest(@FILE)
			'linux_primary_source':     digest(area + 'linux-futex-syscalls-v6.12.c')
			'linux_primary_pin':        digest(area + 'linux-source.sha256')
			'private_sdk': digest(area + 'sdk-inputs.json')
			'primary_source_note': digest(area + 'primary-source-note.txt')
			'sdk_prior_inputs': digest('/Users/alex/.cache/vinix-linux-compat/waitabi-20261015/sdk-inputs.json')
			'arm_compiler_adapter': digest(area + 'arm-cc.v')
			'arm_compiler_adapter_binary': digest(area + 'arm-cc')
			'prior_diagnostics': digest(area + 'diagnostic-pins.json')
			'scope_contract': digest(area + 'scope-check.log')
            'prior_output_only_builds': digest(area+'output-only-inputs.json')
            'prior_compression': digest(area+'prior-transparent-compression.json'),
            'prior_kernel_compression': digest(area+'prior-kernel-compression.json'),
			'native_controller':        digest(area + 'run')
			'native_controller_source': digest(root + 'tests/linux-compat/run.v')
			'reference_controller':     digest(area + 'reference')
			'watch_pins':               digest(area + 'watch-retained-inputs.json')
			'watch_log':                digest(area + 'watch.log')
		}
		for name in ['manage.v', 'manage', 'watch.v', 'watch', 'coverage-before-check.log', 'coverage-before-arm.json', 'coverage-before-x86.json'] {
			artifacts[name] = digest(area + name)
		}
		mut identity := map[string]string{}
		for phase in ['before', 'after'] {
			state := states + 'p4-' + phase + '-' + suffix
			kernel := area + if phase == 'before' { 'baseline-' } else { 'kernel-' } + suffix + '/kernel/bin/vinix'
			names := if phase == 'before' {
				['robustquery']
			} else {
				['robustquery', 'runtime', 'futex']
			}
			captured := receipt(state, arch, digest(kernel), names, phase == 'before')!
			for key, value in captured { artifacts[phase + '_' + key] = value }
			for key in ['robustquery_source', 'robustquery_init', 'robustquery_c'] {
				if phase == 'before' {
					identity[key] = captured[key]
				} else {
					assert identity[key] == captured[key]
				}
			}
			text := os.read_file(state + '/robustquery/serial.log')!
			semantics(text, phase, arch, false)
			storage(text, arch, phase)
			build := area + 'build-' + phase + '-' + suffix + '.log'
			text_build := os.read_file(build)!
			assert text_build.contains('-o bin/vinix') && !text_build.contains('Nothing to be done') && !text_build.contains('Error ')
			producer := area + if phase == 'before' { 'initial-build-' + suffix + '-before.log' } else { 'final-build-' + suffix + '-after-producer.log' }
			assert os.read_file(producer)!.trim_space() == suffix + ' ' + phase + ' production build: PASS'
			artifacts[phase + '_build_producer'] = digest(producer)
			artifacts[phase + '_kernel'] = digest(kernel)
			artifacts[phase + '_kernel_c'] = digest(area + phase + '-' + suffix + '.c')
			artifacts[phase + '_build'] = digest(build)
			for label, path in {
				'receipt':   state + '/receipt.json'
				'aggregate': state + '.log'
				'native':    state + '/robustquery/serial.log'
				'build':     build
			} {
				publish(path, out + 'robustquery-' + phase + '-' + arch + '-' + label + if label == 'receipt' {
					'.json'
				} else {
					'.log'
				})!
			}
			if phase == 'after' {
				for name in names {
					if name == 'robustquery' { continue }
					publish(state + '/' + name + '/serial.log', out + 'robustquery-regression-' + arch + '-' + name + '.log')!
				}
			}
		}
		probe := states + 'p4-before-' + suffix + '/robustquery'
		raw := os.read_file(probe + '/fixture.c')!
		assert raw.count('alloca(') == 6
		for token in ['malloc(', 'calloc(', 'realloc(', 'memdup(', 'array_push(', 'array_get(',
			'v_fixed_index('] {
			assert !raw.contains(token)
		}
		reference := states + 'p4-reference-' + suffix
		linux := reference_receipt(reference, arch, identity['robustquery_init'])!
		for key, value in linux { artifacts['reference_' + key] = value }
		for label, path in {
			'receipt':   reference + '/receipt.json'
			'aggregate': reference + '.log'
			'native':    reference + '/serial.log'
		} {
			publish(path, out + 'robustquery-reference-' + arch + '-' + label + if label == 'receipt' {
				'.json'
			} else {
				'.log'
			})!
			artifacts['reference_' + label] = digest(path)
		}
		for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log',
			'scope-check.log', 'assertion-control.log', 'passing-log-control.log'] {
			artifacts[name] = digest(area + name)
		}
		os.write_file(out + 'robustquery-evidence-' + arch + '.json', json2.encode(Evidence{
			architecture:  arch
			context: 'Native get_robust_list low32 PID import and length-before-head scalar output:6048 controls per architecture, original5236 failures, corrected and identical-ELF Linux6.12.51 zero. Four root/UID1000 initial/one-level PID namespace cohorts, self/leader/live-worker targets, two raw syscall word forms, four independent registered head values, unaligned and valid cross-page outputs,15 overlap offsets, NULL/unmapped/wrapping/read-only/PROT_NONE and seven stable split-page fault cuts in either/both outputs, retired/negative/missing targets and untouched guards. Registered musl head values restored in both threads before join. Four warmed200-call storage cohorts with pipe-blocked workers, six production builds (two output-only images retained without boot qualification), runtime/futex regressions, unchanged allocation diagnostics,67 inventory/2014 SDK/15146 compiler pins, exact whole-C scope and executing audit negatives. Initial p1 compiler refusals, valid p2 baseline/Linux runs, p3 x86 size48 storage variation with millisecond polling (all semantic controls and regressions passed), primary-fetch/coordinator/generator refusals retained separately; final p4 source/C/ELF identity required.36 prior retained artifacts and65 prior kernel images transparently compressed with paths and SHA-256 unchanged. Concurrent mapping/registration/target teardown, new permission policy, robust-owner-death handling, GNU/foreign paths and complete libc/installation/translation gates remain separate.'
			base_commit:   base
			artifacts:     artifacts
			source_inputs: inputs
		},
			prettify: true
		) + '\n')!
	}
	for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log',
		'scope-check.log', 'assertion-control.log', 'passing-log-control.log', 'watch.log',
		'coverage-before-check.log'] {
		publish(area + name, out + 'robustquery-' + name)!
	}
	publish(area + 'watch-retained-inputs.json', out + 'robustquery-watch-retained-inputs.json')!
	os.write_file(area + 'audit.log', 'Native robustquery conformance audit: PASS\n')!
	publish(area + 'audit.log', out + 'robustquery-audit.log')!
	println('Native robustquery conformance audit: PASS')
}

fn semantics(log string,phase string,arch string,reference bool) {
 assert phase in ['before','after'] && arch in ['aarch64','x86_64']
 cohorts := log.split_into_lines().filter(it.starts_with('LINUX ROBUSTQUERY COHORT:')); assert cohorts.len == 4
 mut seen := map[string]bool{}
 for row in cohorts {
  f := row.fields(); assert f.len == 12 && f[3] in ['ordinary=0','ordinary=1'] && f[4] in ['namespace=0','namespace=1']
  key := f[3]+f[4]; assert key !in seen; seen[key] = true
  assert f[5].starts_with('self=') && f[6].starts_with('thread=')
  self := f[5].all_after('=').int(); tid := f[6].all_after('=').int(); assert self > 1 && tid > 0 && tid != self
  if f[4] == 'namespace=1' {assert self == 2 && tid == 3}
  assert f[7] == 'uid='+if f[3] == 'ordinary=1' {'1000'} else {'0'}
  assert f[8] == 'page='+if arch == 'aarch64' && !reference {'16384'} else {'4096'}
  assert f[9] == 'profiles=4' && f[10] == 'targets=3' && f[11] == 'forms=2'
 }
 mut cases := map[string]string{}
 for label in ['CASES:','FINAL:'] {
  rows := log.split_into_lines().filter(it.starts_with('LINUX ROBUSTQUERY '+label)); assert rows.len == 24
  seen.clear(); mut calls := 0; mut failures := 0
  for row in rows {
   f := row.fields(); assert f.len == 8 && f[3] in ['ordinary=0','ordinary=1'] && f[4] in ['namespace=0','namespace=1'] && f[5] in ['kind=0','kind=1','kind=2','kind=3','kind=4','kind=5']
   key := f[3]+f[4]+f[5]; assert key !in seen; seen[key] = true
   kind := f[5].all_after('=').int(); assert f[6].starts_with('calls=') && f[7].starts_with('failures=')
   n := f[6].all_after('=').int(); bad := f[7].all_after('=').int()
   assert n == [264,360,288,288,288,24]![kind]
   assert bad == if phase == 'before' {[132,337,276,288,276,0]![kind]} else {0}
   if label == 'CASES:' {cases[key] = f[6]+f[7]} else {assert cases[key] == f[6]+f[7]}
   calls += n; failures += bad
  }
  assert calls == 6048 && failures == if phase == 'before' {5236} else {0}
 }
 if phase == 'before' {assert log.contains('LINUX ROBUSTQUERY DETAIL:') && log.contains('LINUX ROBUSTQUERY FAIL:') && !log.contains('LINUX ROBUSTQUERY: PASS')}
 else {assert !log.contains('LINUX ROBUSTQUERY DETAIL:') && !log.contains('LINUX ROBUSTQUERY FAIL:')}
 if reference {assert log.contains('Linux version 6.12.51-0-virt') && log.contains('LINUX ROBUSTQUERY REFERENCE: PASS') && !log.contains('LINUX ROBUSTQUERY STORAGE:')}
 else if phase == 'after' {assert log.count('LINUX ROBUSTQUERY: PASS') == 1}
 assert !log.contains('Kernel panic') && !log.contains('setup stage=')
}
fn check_source(area string,root string) ! {
 before := os.read_file(area+'before-linux_task.v')!; after := os.read_file(area+'after-linux_task.v')!
 previous := os.read_file(area+'source-previous.txt')!; replacement := os.read_file(area+'source-replacement.txt')!
 signature := os.read_file(area+'signature-previous.txt')!; new_signature := os.read_file(area+'signature-replacement.txt')!
 assert previous.contains('if head_ptr == 0 || len_ptr == 0') && previous.contains('copy_to_user(head_ptr')
 assert replacement.contains('usercopy.user_range(len_ptr, sizeof(u64))') && replacement.contains('usercopy.writable(len_ptr + 7)') && replacement.contains('usercopy.writable(head_ptr + 7)')
 assert replacement.index('copy_to_user(len_ptr') or {panic('no length')} < replacement.index('copy_to_user(head_ptr') or {panic('no head')}
 assert new_signature == signature.replace('tid int','tid_word u64')+'\n\t// pid_t is imported from the low 32 register bits on both native ABIs.\n\ttid := int(i32(tid_word))'
 assert before.count(previous) == 1 && before.count(signature) == 1
 assert after == before.replace(previous,replacement).replace(signature,new_signature)
 assert os.read_file(area+'output-only-linux_task.v')! == before.replace(previous,replacement)
 assert digest(root+'kernel/userland/linux_task.v') == digest(area+'after-linux_task.v')
 for suffix in ['arm','x86'] {assert digest(area+'kernel-'+suffix+'/kernel/userland/linux_task.v') == digest(area+'after-linux_task.v')}
}
fn check_c(area string,suffix string) ! {
 before := os.read_file(area+'before-'+suffix+'.c')!; after := os.read_file(area+'after-'+suffix+'.c')!
 old := body(before,'userland__syscall_get_robust_list'); new := body(after,'userland__syscall_get_robust_list')
 null_branch := '\tif ((head_ptr == 0) || (len_ptr == 0)) {\n\t\treturn (multi_return_u64_u64){errno__err, errno__efault};\n\t}\n'
 first := 'if (!usercopy__copy_to_user(head_ptr, (void*)(&head), sizeof(u64))) {'
 second := 'if (!usercopy__copy_to_user(len_ptr, (void*)(&len), sizeof(u64))) {'
 length := 'if (!usercopy__user_range(len_ptr, sizeof(u64)) || !usercopy__writable(len_ptr) || !usercopy__writable(len_ptr + 7) || !usercopy__copy_to_user(len_ptr, (void*)(&len), sizeof(u64))) {'
 head := 'if (!usercopy__user_range(head_ptr, sizeof(u64)) || !usercopy__writable(head_ptr) || !usercopy__writable(head_ptr + 7) || !usercopy__copy_to_user(head_ptr, (void*)(&head), sizeof(u64))) {'
 assert old.count(null_branch) == 1 && old.count(first) == 1 && old.count(second) == 1
 output := old.replace(null_branch,'').replace(first,length).replace(second,head)
 expected := output.replace('i64 tid,','u64 tid_word,').replace('{\n\tu64 head =','{\n\ti64 tid = (i64)((i32)(tid_word));\n\tu64 head =')
 assert new == expected && old != new
 old_decl := 'multi_return_u64_u64 userland__syscall_get_robust_list(void* _0, i64 tid, u64 head_ptr, u64 len_ptr);'
 new_decl := old_decl.replace('i64 tid,','u64 tid_word,')
 assert before.count(old_decl) == 1 && before.replace(old,'').replace(old_decl,new_decl) == after.replace(new,''),'Exact whole-C scope, no normalization'
 output_c := os.read_file(area+'output-only-'+suffix+'.c')!
 assert body(output_c,'userland__syscall_get_robust_list') == output && before.replace(old,output) == output_c
 for token in ['malloc(','calloc(','realloc(','memdup(','array__','free(','alloca(','vinix_stack_alloc(','pin_process(','unpin_process(','copy_to_user('] {assert old.count(token) == new.count(token),token}
 assert old.count('usercopy__user_range(') == 0 && new.count('usercopy__user_range(') == 2 && new.count('usercopy__writable(') == 4
}
fn sdk_and_primary(area string,out string) ! {
 sdk := object(area+'sdk-inputs.json')!; prior := object('/Users/alex/.cache/vinix-linux-compat/waitabi-20261015/sdk-inputs.json')!
 assert sdk.len == 2014 && prior.len == 2014
 mut found := map[string]bool{}
 for path in os.walk_ext(area+'sdk','') {assert os.inode(path).typ == .regular; local := path.all_after(area+'sdk/'); assert local in sdk && local !in found; found[local] = true}
 assert found.len == sdk.len
 for path,hash in sdk {assert hash.str() == prior[path]!.str() && digest(area+'sdk/'+path) == hash.str(),path}
 for state in ['p4-before-arm/robustquery','p4-after-arm/robustquery','p4-after-arm/runtime','p4-after-arm/futex','p4-reference-arm'] {
  for file in ['fixture.o','serial.o','init'] {
   driver := object(area+'states/'+state+'/'+file+'.compiler.json')!
   assert driver['status']!.str() == '0' && driver['output']!.str() == ''
   assert driver['arguments']!.str().contains('--gcc-install-dir='+area.trim_right('/')+'/sdk/usr/lib/gcc/aarch64-alpine-linux-musl/14.2.0')
   assert driver['arguments']!.str().contains('--target=aarch64-linux-musl') && driver['arguments']!.str().contains('--sysroot='+area.trim_right('/')+'/sdk')
  }
 }
 for name in ['sdk-inputs.json','linux-source.sha256','primary-source-note.txt'] {publish(area+name,out+'robustquery-'+name)!}
}
fn diagnostics(area string,out string) ! {
 mut pins := map[string]string{}
 for manifest in ['prior-transparent-compression.json','prior-kernel-compression.json'] {
  entries := object(area+manifest)!; assert entries.len == if manifest == 'prior-transparent-compression.json' {36} else {65}
  for path,hash in entries {
   assert ['waitabi','waitempty','waituid','waitevent','waitusage','waitconsume','waitstatus'].any(path.starts_with('/Users/alex/.cache/vinix-linux-compat/'+it+'-20261015/'))
   assert os.inode(path).typ == .regular && digest(path) == hash.str(),path
  }
  pins[manifest] = digest(area+manifest); publish(area+manifest,out+'robustquery-'+manifest)!
 }
 assert os.read_file(area+'compress-prior.log')!.trim_space() == 'Preserved 36 retained artifacts with transparent compression; paths and SHA-256 unchanged'
 assert os.read_file(area+'compress-prior-kernels.log')!.trim_space() == 'Preserved 65 retained kernel images with transparent compression; paths and SHA-256 unchanged'
 assert os.read_file(area+'initial-primary-fetch-refusal.log')!.contains('curl: (56) The requested URL returned error: 429')
 assert os.read_file(area+'pipeline-producer.log')!.contains('failed to execute "'+area.trim_right('/')+'/preflight"')
 assert os.read_file(area+'pipeline-ready-producer.log')!.contains('Probe did not compile; retain refusal:')
 initial := os.read_file(area+'initial-probe.v')!
 fixed := initial.replace('*C.__errno_location() = 0','mut code := C.__errno_location(); *code = 0').replace('mut thread := C.pthread_t{}','mut pthread := C.pthread_t{}').replace('C.pthread_create(&thread,','C.pthread_create(&pthread,').replace('C.pthread_join(thread,','C.pthread_join(pthread,')
 p3 := os.read_file(area+'p3-probe.v')!
 assert p3 == fixed.replace('wait4 scalar status stores, stable guard faults or unused-output controls','robust-list PID import, ordered scalar output or retained storage')
 final := os.read_file('/Users/alex/code/vinix/tests/linux-compat/robustqueryfixture/core.v')!
 for name in ['get','register','saved_head','head_value','target','difference','bad','record','trial','missing','cycle','storage','snapshot','run'] {assert body_v(final,name) == body_v(p3,name),name}
 assert !body_v(final,'worker_entry').contains('C.usleep(') && !final.contains('C.__atomic_')
 assert body_v(final,'worker_entry').contains('C.read(worker.input,&command,1)') && body_v(final,'await_ready').contains('C.read(worker.ack,')
 for suffix in ['arm','x86'] {
  first := area+'states/p1-before-'+suffix
  r := object(first+'/receipt.json')!['results']!.as_array(); assert r.len == 1
  first_row := r[0].as_map(); assert first_row['exit_code']!.int() == 1 && first_row['detail']!.str() == 'Command failed' && first_row['init_sha256']!.str() == '' && first_row['iso_sha256']!.str() == ''
  assert os.read_file(first+'/sources/robustqueryfixture/core.v')! == initial && !os.exists(first+'/robustquery/init')
  text := os.read_file(first+'.log')!; assert text.contains('cannot dereference a function call on the left side of an assignment') && text.contains('invalid use of reserved type `thread`') && !text.contains('LINUX ROBUSTQUERY COHORT:')
  second := area+'states/p2-before-'+suffix
  assert os.read_file(second+'/sources/robustqueryfixture/core.v')! == fixed
  entries := object(second+'/receipt.json')!['results']!.as_array(); assert entries.len == 1
  entry := entries[0].as_map(); assert entry['exit_code']!.int() == 1 && entry['detail']!.str() == ''
  assert entry['source_sha256']!.str() == digest(second+'/sources/robustqueryfixture/core.v') && entry['init_sha256']!.str() == digest(second+'/robustquery/init') && entry['iso_sha256']!.str() == digest(second+'/robustquery/test.iso')
  semantics(os.read_file(second+'/robustquery/serial.log')!,'before',if suffix == 'arm' {'aarch64'} else {'x86_64'},false)
  reference_receipt(area+'states/p2-reference-'+suffix,if suffix == 'arm' {'aarch64'} else {'x86_64'},digest(second+'/robustquery/init'))!
  assert digest(second+'/robustquery/fixture.c') != digest(area+'states/p3-before-'+suffix+'/robustquery/fixture.c')
  p2c := os.read_file(second+'/robustquery/fixture.c')!; p3c := os.read_file(area+'states/p3-before-'+suffix+'/robustquery/fixture.c')!
  assert p3c == p2c.replace('wait4 scalar status stores, stable guard faults or unused-output controls','robust-list PID import, ordered scalar output or retained storage')
  for state in [first,second,area+'states/p2-reference-'+suffix] {
   for path in os.walk_ext(state,'') {if os.inode(path).typ == .regular {pins[path] = digest(path)}}
   pins[state+'.log'] = digest(state+'.log')
   publish(state+'/receipt.json',out+'robustquery-diagnostic-'+os.file_name(state)+'-receipt.json')!
   publish(state+'.log',out+'robustquery-diagnostic-'+os.file_name(state)+'.log')!
  }
  for name in ['output-only-'+suffix+'.c','output-only-'+suffix+'.elf','build-output-only-'+suffix+'.log'] {assert object(area+'output-only-inputs.json')![name]!.str() == digest(area+name); pins[name] = digest(area+name)}
  assert os.read_file(area+'build-output-only-'+suffix+'.log')!.contains('-o bin/vinix')
  arch := if suffix == 'arm' {'aarch64'} else {'x86_64'}
  for phase in ['before','after'] {
   state := area+'states/p3-'+phase+'-'+suffix
   names := if phase == 'before' {['robustquery']} else {['robustquery','runtime','futex']}
   rows := object(state+'/receipt.json')!['results']!.as_array(); assert rows.len == names.len
   for index,row_any in rows {
    row := row_any.as_map(); name := row['name']!.str(); assert name == names[index] && row['detail']!.str() == ''
    assert row['exit_code']!.int() == if phase == 'before' || (suffix == 'x86' && name == 'robustquery') {1} else {0}
    assert row['source_sha256']!.str() == digest(state+'/sources/'+name+'fixture/core.v') && row['init_sha256']!.str() == digest(state+'/'+name+'/init') && row['iso_sha256']!.str() == digest(state+'/'+name+'/test.iso')
    if name != 'robustquery' {assert os.read_file(state+'/'+name+'/serial.log')!.contains('LINUX '+name.to_upper()+': PASS')}
   }
   serial := os.read_file(state+'/robustquery/serial.log')!
   if phase == 'before' || suffix == 'arm' {semantics(serial,phase,arch,false); storage(serial,arch,phase)} else {p3_storage_refusal(serial)}
   for path in os.walk_ext(state,'') {if os.inode(path).typ == .regular {pins[path] = digest(path)}}
   pins[state+'.log'] = digest(state+'.log')
   publish(state+'/receipt.json',out+'robustquery-diagnostic-'+os.file_name(state)+'-receipt.json')!
   publish(state+'.log',out+'robustquery-diagnostic-'+os.file_name(state)+'.log')!
  }
  p3_probe := area+'states/p3-before-'+suffix+'/robustquery/init'
  assert digest(p3_probe) == digest(area+'states/p3-after-'+suffix+'/robustquery/init')
  reference_receipt(area+'states/p3-reference-'+suffix,arch,digest(p3_probe))!
  for path in os.walk_ext(area+'states/p3-reference-'+suffix,'') {if os.inode(path).typ == .regular {pins[path] = digest(path)}}
  pins[area+'states/p3-reference-'+suffix+'.log'] = digest(area+'states/p3-reference-'+suffix+'.log')
  publish(area+'states/p3-reference-'+suffix+'/receipt.json',out+'robustquery-diagnostic-p3-reference-'+suffix+'-receipt.json')!
  publish(area+'states/p3-reference-'+suffix+'.log',out+'robustquery-diagnostic-p3-reference-'+suffix+'.log')!
 }
 initial_helper := os.read_file(area+'initial-finish-probe.v')!; fixed_helper := os.read_file(area+'finish-probe.v')!
 assert fixed_helper == initial_helper.replace("or {panic(err)}","or {panic('missing snapshot definition')}")
 assert os.read_file(area+'initial-contract-compile-refusal.log')!.contains('error: redefinition of `row`')
 assert os.read_file(area+'initial-create-audit-refusal.log')!.contains('V panic: unclosed definition')
 for name in ['initial-contract-auditor.v','initial-contract-compile-refusal.log'] {pins[name] = digest(area+name); publish(area+name,out+'robustquery-'+name)!}
 for name in ['initial-probe.v','initial-finish-probe.v','finish-probe.v','initial-primary-fetch-refusal.log','pipeline-producer.log','pipeline-ready-producer.log','compress-prior.v','compress-prior.log','compress-prior-kernels.v','compress-prior-kernels.log','output-only-inputs.json','source-previous.txt','source-replacement.txt','signature-previous.txt','signature-replacement.txt','primary.v','primary.log','linux-primary-futex-v6.12.base64','create-audit.v','audit-contracts.txt','finalize-kernel.v','start-final.v','continue-final.v','retry.v','manage-p2.v','manage-p2','manage-p3.v','manage-p3','watch-p2.v','watch-p3.v','start-final.log','continue-final.log','p2-watch-retained-inputs.json','p2-watch.log','p3-probe.v','start-p4.v','start-p4.log','watch-p3-diagnostic.v','p3-watch-retained-inputs.json','p3-watch.log','p3-watch-producer.log','initial-create-audit.v','initial-create-audit-refusal.log','manage-p4.v','manage-p4','watch-p4.v'] {
  pins[name] = digest(area+name)
  if name.ends_with('.json') || name.ends_with('.log') || name in ['initial-probe.v','initial-finish-probe.v','compress-prior.v','compress-prior-kernels.v','source-previous.txt','source-replacement.txt','signature-previous.txt','signature-replacement.txt'] {publish(area+name,out+'robustquery-'+name)!}
 }
 data := json2.encode(pins,prettify:true)+'\n'
 if os.exists(area+'diagnostic-pins.json') {assert os.read_file(area+'diagnostic-pins.json')! == data} else {os.write_file(area+'diagnostic-pins.json',data)!}
 publish(area+'diagnostic-pins.json',out+'robustquery-diagnostic-pins.json')!
}
fn body_v(source string,name string) string {
 start := source.index('fn '+name+'(') or {panic('missing V definition')}
 tail := source[start..]; end := tail.index('\nfn ') or {tail.len}
 return tail[..end].trim_space()
}
fn p3_storage_refusal(log string) {
 // Semantic counts are independently required even though storage rejected this boot.
 corrected := log.replace('LINUX ROBUSTQUERY FAIL: robust-list PID import, ordered scalar output or retained storage','LINUX ROBUSTQUERY: PASS')
 semantics(corrected,'after','x86_64',false)
 mut differences := 0; mut summaries := 0
 for row in log.split_into_lines().filter(it.starts_with('LINUX ROBUSTQUERY SLAB:')) {
  f := row.fields(); assert f.len == 8; pair := f[6].all_after('=').split('/'); assert pair.len == 2
  if pair[0] != pair[1] {
   assert f[3] == 'ordinary=0' && f[5] == 'size=48'
   assert pair[1].int()-pair[0].int() == if f[4] == 'namespace=0' {1} else {-1}; differences++
  }
 }
 assert differences == 2
 for row in log.split_into_lines().filter(it.starts_with('LINUX ROBUSTQUERY STORAGE:')) {
  f := row.fields(); assert f.len == 8; pair := f[6].all_after('=').split('/'); assert pair.len == 2 && pair[0] == pair[1]
  assert f[7] == if f[3] == 'ordinary=0' {'FAIL'} else {'PASS'}; summaries++
 }; assert summaries == 4 && !log.contains('LINUX ROBUSTQUERY: PASS')
}
