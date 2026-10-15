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
 rows := source.split_into_lines().filter(!it.starts_with('	') && !it.starts_with(' ') && it.contains(' '+name+'(') && it.ends_with('{'))
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
 for row in log.split_into_lines().filter(it.starts_with('LINUX TIDWAKE SLAB:') || it.starts_with('LINUX TIDWAKE STORAGE:')) {
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
	assert log.contains('LINUX TIDWAKE DETAIL:'), 'tidwake baseline failure markers required'
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
		'wrapper_source':    state + '/source/tidwakereferenceinit/core.v'
		'wrapper_c':         state + '/fixture.c'
		'wrapper_elf':       state + '/init'
		'initramfs':         state + '/initramfs.cpio'
		'serial':            state + '/serial.log'
		'serial_adapter_c':  state + '/serial.c'
		'controller_source': '/Users/alex/code/vinix/tests/linux-compat/tidwake-reference.v'
		'qemu':              command[0]
	} {
		assert artifacts[label] == digest(path)
	}
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/tidwakereferenceinit/core.v')
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
		println('Native clear-child-tid source/C scope: PASS')
		return
	}
	if '--negative-control' in os.args {
		assert false, 'tidwake assertions must execute'
		return
	}
	if '--negative-pass-control' in os.args {
		failure(os.read_file(os.args[2])!, os.args[3])
		return
	}
	assert os.args.len == 2, 'Usage: tidwake-check.v EVIDENCE-AREA (compile without -prod)'
	area := os.args[1].trim_right('/') + '/'
	states := area + 'states/'
	root := '/Users/alex/code/vinix/'
	out := root + 'tests/linux-compat/results/2026-10-15/'
	os.mkdir_all(out)!
	sdk_and_primary(area, out)!
	diagnostics(area,out)!
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'tidwake assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control',
		states + 'p1-reference-arm/serial.log', 'aarch64'], 'tidwake baseline failure markers required'))!
	check_source(area, root)!
	for suffix in ['arm', 'x86'] { check_c(area, suffix)! }
	os.write_file(area+'scope-check.log','arm/x86: exact whole production C differs only in clear_child_tid shared-key maximum1 wake call plus exact dead futex__wake/futex__wake_key wrappers and declarations removed by reachability; unchanged pointer retirement, scalar store/error path, locks, ownership, Process/Thread/map refs and release; no allocation/free/pin/stack promotion or normalization\n')!
	base := os.read_file(area + 'base.txt')!.trim_space()
	assert base == '3d8363a1a0c70075cf470610321c77c10fbfd411'
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
	assert os.read_file(area + 'watch-v2.log')!.split_into_lines().filter(it.starts_with('Completed ')).len == 8
	retained := object(area + 'watch-v2-retained-inputs.json')!
	assert retained.len == 84
	for path, hash in retained {
		assert path.starts_with(states + 'p1-before-arm/') || path.starts_with(states + 'p1-before-x86/') || path.starts_with(states + 'p1-after-arm/') || path.starts_with(states+'p1-after-x86/')
		assert !path.contains('/iso-build/') && !path.ends_with('/efivars.fd')
		assert os.inode(path).typ == .regular && digest(path) == hash.str(), path
	}
	mut walked := map[string]bool{}
	mut completed := map[string]bool{}
	for suffix in ['arm', 'x86'] {
		for phase in ['before', 'after'] {
			names := if phase == 'before' {
				['tidwake']
			} else {
				['tidwake', 'runtime', 'robustwake']
			}
			for name in names {
				probe := states + 'p1-' + phase + '-' + suffix + '/' + name
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
	for row in os.read_file(area + 'watch-v2.log')!.split_into_lines() {
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
			'fixture_source':           digest(root + 'tests/linux-compat/tidwakefixture/core.v')
			'audit_source':             digest(@FILE)
			'linux_primary_source':     digest(area + 'linux-fork-v6.12.c')
			'linux_primary_pin':        digest(area + 'linux-source.sha256')
			'private_sdk': digest(area + 'sdk-inputs.json')
			'sdk_prior_inputs': digest('/Users/alex/.cache/vinix-linux-compat/robustcreds-20261015/sdk-inputs.json')
			'arm_compiler_adapter': digest(area + 'arm-cc.v')
			'arm_compiler_adapter_binary': digest(area + 'arm-cc')
			'prior_diagnostics': digest(area + 'diagnostic-pins.json')
			'scope_contract': digest(area + 'scope-check.log')
			'native_controller':        digest(area + 'run')
			'native_controller_source': digest(root + 'tests/linux-compat/run.v')
			'reference_controller':     digest(area + 'reference')
			'watch_pins':               digest(area + 'watch-v2-retained-inputs.json')
			'watch_log':                digest(area + 'watch-v2.log')
		}
		for name in ['manage.v', 'manage', 'watch-v2.v', 'watch-v2', 'coverage-before-check.log', 'coverage-before-arm.json', 'coverage-before-x86.json'] {
			artifacts[name] = digest(area + name)
		}
		mut identity := map[string]string{}
		for phase in ['before', 'after'] {
			state := states + 'p1-' + phase + '-' + suffix
			kernel := area + if phase == 'before' { 'baseline-' } else { 'kernel-' } + suffix + '/kernel/bin/vinix'
			names := if phase == 'before' {
				['tidwake']
			} else {
				['tidwake', 'runtime', 'robustwake']
			}
			captured := receipt(state, arch, digest(kernel), names, phase == 'before')!
			for key, value in captured { artifacts[phase + '_' + key] = value }
			for key in ['tidwake_source', 'tidwake_init', 'tidwake_c'] {
				if phase == 'before' {
					identity[key] = captured[key]
				} else {
					assert identity[key] == captured[key]
				}
			}
			text := os.read_file(state + '/tidwake/serial.log')!
			semantics(text, phase, arch, false)
			storage(text, arch, phase)
			build := area + 'build-' + phase + '-' + suffix + '.log'
			text_build := os.read_file(build)!
			assert text_build.contains('-o bin/vinix') && !text_build.contains('Nothing to be done') && !text_build.contains('Error ')
			producer := area + if phase == 'before' { 'initial-build-' + suffix + '-before.log' } else { 'build-' + suffix + '-after-producer.log' }
			assert os.read_file(producer)!.trim_space() == suffix + ' ' + phase + ' production build: PASS'
			artifacts[phase + '_build_producer'] = digest(producer)
			artifacts[phase + '_kernel'] = digest(kernel)
			artifacts[phase + '_kernel_c'] = digest(area + phase + '-' + suffix + '.c')
			artifacts[phase + '_build'] = digest(build)
			for label, path in {
				'receipt':   state + '/receipt.json'
				'aggregate': state + '.log'
				'native':    state + '/tidwake/serial.log'
				'build':     build
			} {
				publish(path, out + 'tidwake-' + phase + '-' + arch + '-' + label + if label == 'receipt' {
					'.json'
				} else {
					'.log'
				})!
			}
			if phase == 'after' {
				for name in names {
					if name == 'tidwake' { continue }
					publish(state + '/' + name + '/serial.log', out + 'tidwake-regression-' + arch + '-' + name + '.log')!
				}
			}
		}
		probe := states + 'p1-before-' + suffix + '/tidwake'
		raw := os.read_file(probe + '/fixture.c')!
		assert raw.count('alloca(') == 12
		for token in ['malloc(', 'calloc(', 'realloc(', 'memdup(', 'array_push(', 'array_get(',
			'v_fixed_index('] {
			assert !raw.contains(token)
		}
		reference := states + 'p1-reference-' + suffix
		linux := reference_receipt(reference, arch, identity['tidwake_init'])!
		for key, value in linux { artifacts['reference_' + key] = value }
		for label, path in {
			'receipt':   reference + '/receipt.json'
			'aggregate': reference + '.log'
			'native':    reference + '/serial.log'
		} {
			publish(path, out + 'tidwake-reference-' + arch + '-' + label + if label == 'receipt' {
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
		os.write_file(out + 'tidwake-evidence-' + arch + '.json', json2.encode(Evidence{
			architecture:  arch
			context: 'Native clear-child-tid selective shared wakes:384 controls per architecture, originals128 failures, corrected and identical-ELF Linux6.12.51 zero. Four root/UID1000 initial/one-level PID namespace cohorts check five registration classes: direct, replacement, disabled, alias and disable/re-enable; four initial words, two offsets including native page tail, one/three shared waiters, private and abandoned-address isolation, complete two-page canaries, registration TID returns, observed worker ESRCH while its leader remains alive, and real musl joins/payloads. Raw worker exit deliberately bypasses libc teardown after replacing its clear-tid pointer; no libc join of that worker is attempted, and leader exit/reap retires its complete image. Four80-warmup/200-cycle complete trial cleanup cohorts, four fresh production builds, runtime/robustwake regressions, unchanged allocation diagnostics,67 inventory/2014 SDK/15146 compiler pins, fifteen final ARM command receipts and exact one-call plus dead-wrapper whole-C scope with executing negative controls. Pre-ELF syntax refusal and initial source-fetch429 and first whole-C scope and staging-watcher allowlist refusals retained separately. Faulting/unaligned registrations, last-map-user behavior, clone child_tid flags, exec/forced sibling exit, concurrent mapping/registration changes, GNU/foreign paths and three broad roadmap gates remain separate.'
			base_commit:   base
			artifacts:     artifacts
			source_inputs: inputs
		},
			prettify: true
		) + '\n')!
	}
	for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log',
		'scope-check.log', 'assertion-control.log', 'passing-log-control.log', 'watch-v2.log',
		'coverage-before-check.log'] {
		publish(area + name, out + 'tidwake-' + name)!
	}
	publish(area + 'watch-v2-retained-inputs.json', out + 'tidwake-watch-v2-retained-inputs.json')!
	os.write_file(area + 'audit.log', 'Native tidwake conformance audit: PASS\n')!
	publish(area + 'audit.log', out + 'tidwake-audit.log')!
	println('Native tidwake conformance audit: PASS')
}














fn semantics(log string,phase string,arch string,reference bool) {
 assert phase in ['before','after'] && arch in ['aarch64','x86_64']
 topology := log.split_into_lines().filter(it.starts_with('LINUX TIDWAKE TOPOLOGY:')); assert topology.len == 4
 mut seen := map[string]bool{}
 for row in topology {
  f := row.fields(); assert f.len == 14 && f[3] in ['ordinary=0','ordinary=1'] && f[4] in ['namespace=0','namespace=1']
  key := f[3]+f[4]; assert key !in seen; seen[key] = true
  assert f[5].starts_with('self=') && f[6].starts_with('child=') && f[7].starts_with('worker=')
  self := f[5].all_after('=').int(); child := f[6].all_after('=').int(); worker := f[7].all_after('=').int(); assert self > 1 && child > 1 && worker > 1 && self != child && child != worker && worker != self
  if f[4] == 'namespace=1' {assert self == 2}
  assert f[8] == 'uid='+if f[3] == 'ordinary=1' {'1000'} else {'0'}
  assert f[9..] == ['alive_leader=1','observed_ESRCH=1','queued=3','private=1','abandoned=1']
 }
 cohorts := log.split_into_lines().filter(it.starts_with('LINUX TIDWAKE COHORT:')); assert cohorts.len == 4; seen.clear()
 for row in cohorts {
  f := row.fields(); assert f.len == 12 && f[3] in ['ordinary=0','ordinary=1'] && f[4] in ['namespace=0','namespace=1']
  key := f[3]+f[4]; assert key !in seen; seen[key] = true
  assert f[5].starts_with('self=') && f[5].all_after('=').int() > 1
  if f[4] == 'namespace=1' {assert f[5] == 'self=2'}
  assert f[6] == 'uid='+if f[3] == 'ordinary=1' {'1000'} else {'0'}
  assert f[7] == 'page='+if arch == 'aarch64' && !reference {'16384'} else {'4096'}
  assert f[8..] == ['raw=80','libc=16','classes=5','leader_alive=1']
 }
 mut local := map[string]string{}
 for label in ['CASES:','FINAL:'] {
  rows := log.split_into_lines().filter(it.starts_with('LINUX TIDWAKE '+label)); assert rows.len == 24; seen.clear(); mut calls := 0; mut failures := 0
  for row in rows {
   f := row.fields(); assert f.len == 8 && f[3] in ['ordinary=0','ordinary=1'] && f[4] in ['namespace=0','namespace=1'] && f[5] in ['kind=0','kind=1','kind=2','kind=3','kind=4','kind=5']
   key := f[3]+f[4]+f[5]; assert key !in seen; seen[key] = true; kind := f[5].all_after('=').int()
   assert f[6] == 'calls=16' && f[7].starts_with('failures='); bad := f[7].all_after('=').int()
   assert bad == if phase == 'before' {[8,8,0,8,8,0]![kind]} else {0}
   if label == 'CASES:' {local[key] = f[6]+f[7]} else {assert local[key] == f[6]+f[7]}; calls += 16; failures += bad
  }
  assert calls == 384 && failures == if phase == 'before' {128} else {0}
 }
 if phase == 'before' {assert log.contains('LINUX TIDWAKE DETAIL:') && log.contains('LINUX TIDWAKE FAIL:') && !log.contains('LINUX TIDWAKE: PASS')}
 else {assert !log.contains('LINUX TIDWAKE DETAIL:') && !log.contains('LINUX TIDWAKE FAIL:')}
 if reference {assert log.contains('Linux version 6.12.51-0-virt') && log.contains('LINUX TIDWAKE REFERENCE: PASS') && !log.contains('LINUX TIDWAKE STORAGE:')}
 else if phase == 'after' {assert log.count('LINUX TIDWAKE: PASS') == 1}
 assert !log.contains('Kernel panic') && !log.contains('setup stage=')
}
fn check_source(area string,root string) ! {
 before := os.read_file(area+'before-linux_task.v')!; after := os.read_file(area+'after-linux_task.v')!
 old := '\tfutex.wake(address)'
 replacement := "\t// Linux's exit notification selects one shared-key waiter. Other waiters\n\t// remain queued for their own synchronization or a later explicit wake.\n\tfutex.wake_n_key(address, 1, false)"
 assert before.count(old) == 1 && before.replace(old,replacement) == after
 base := os.read_file(area+'base.txt')!.trim_space()
 for suffix in ['arm','x86'] {
  tree := area+'kernel-'+suffix
  assert git(tree,['show',base+':kernel/userland/linux_task.v'])!.trim_space() == before.trim_space()
  assert digest(tree+'/kernel/userland/linux_task.v') == digest(area+'after-linux_task.v') && digest(root+'kernel/userland/linux_task.v') == digest(area+'after-linux_task.v')
 }
}
fn check_c(area string,suffix string) ! {
 before := os.read_file(area+'before-'+suffix+'.c')!; after := os.read_file(area+'after-'+suffix+'.c')!
 old := body(before,'userland__clear_child_tid'); new := body(after,'userland__clear_child_tid')
 assert old.count('futex__wake(address);') == 1 && old.replace('futex__wake(address);','futex__wake_n_key(address, 1, false);') == new
 mut expected := before.replace(old,new)
 wrappers := {
  'futex__wake':'\nu64 futex__wake(u64 virt) {\n\treturn futex__wake_key(virt, false);\n}'
  'futex__wake_key':'\nu64 futex__wake_key(u64 virt, bool private) {\n\treturn futex__wake_mask_key(virt, 0x7fffffff, private, (u32)(0xffffffff));\n}'
 }
 for name,exact in wrappers {
  wrapper := body(before,name); assert wrapper == exact && !after.contains(name+'(')
  assert expected.count(wrapper+'\n') == 1; expected = expected.replace(wrapper+'\n','')
 }
 for declaration in ['u64 futex__wake(u64 virt);\n','u64 futex__wake_key(u64 virt, bool private);\n'] {assert expected.count(declaration) == 1; expected = expected.replace(declaration,'')}
 matches := expected == after
 assert matches,'Exact whole production C: one wake call and exact dead-wrapper/declaration removal; no normalization'
 for token in ['malloc(','calloc(','realloc(','memdup(','array__','free(','alloca(','vinix_stack_alloc(','pin_process(','unpin_process(','copy_from_user(','copy_to_user('] {assert old.count(token) == new.count(token),token}
}
fn sdk_and_primary(area string,out string) ! {
 sdk := object(area+'sdk-inputs.json')!; prior := object('/Users/alex/.cache/vinix-linux-compat/robustcreds-20261015/sdk-inputs.json')!; assert sdk.len == 2014 && prior.len == sdk.len
 mut found := map[string]bool{}
 for path in os.walk_ext(area+'sdk','') {assert os.inode(path).typ == .regular; local := path.all_after(area+'sdk/'); assert local in sdk && local !in found; found[local] = true}; assert found.len == sdk.len
 for path,hash in sdk {assert hash.str() == prior[path]!.str() && digest(area+'sdk/'+path) == hash.str(),path}
 for state in ['p1-before-arm/tidwake','p1-after-arm/tidwake','p1-after-arm/runtime','p1-after-arm/robustwake','p1-reference-arm'] {for file in ['fixture.o','serial.o','init'] {
  driver := object(area+'states/'+state+'/'+file+'.compiler.json')!; assert driver['status']!.str() == '0' && driver['output']!.str() == ''
  assert driver['arguments']!.str().contains('--gcc-install-dir='+area.trim_right('/')+'/sdk/usr/lib/gcc/aarch64-alpine-linux-musl/14.2.0') && driver['arguments']!.str().contains('--target=aarch64-linux-musl') && driver['arguments']!.str().contains('--sysroot='+area.trim_right('/')+'/sdk')
 }}
 primary := os.read_file(area+'linux-fork-v6.12.c')!
 assert primary.contains('put_user(0, tsk->clear_child_tid);') && primary.contains('do_futex(tsk->clear_child_tid, FUTEX_WAKE,\n\t\t\t\t\t1, NULL, NULL, 0, 0);')
 assert os.read_file(area+'linux-source.sha256')! == digest(area+'linux-fork-v6.12.c')+' https://kernel.googlesource.com/pub/scm/linux/kernel/git/torvalds/linux/+/refs/tags/v6.12/kernel/fork.c?format=TEXT\n'
 for name in ['sdk-inputs.json','linux-source.sha256'] {publish(area+name,out+'tidwake-'+name)!}
}
fn diagnostics(area string,out string) ! {
 mut pins := map[string]string{}
 first := os.read_file(area+'initial-probe.v')!; final := os.read_file('/Users/alex/code/vinix/tests/linux-compat/tidwakefixture/core.v')!
 old := '*C.__errno_location() = 0; result := C.syscall(C.SYS_tgkill'
 assert first.count(old) == 1 && first.replace(old,'mut error_slot := C.__errno_location(); *error_slot = 0; result := C.syscall(C.SYS_tgkill') == final
 assert os.read_file(area+'helper-preflight.log')!.contains('cannot dereference a function call on the left side of an assignment') && !os.exists(area+'states/preflight-arm/init')
 assert os.read_file(area+'pipeline-producer.log')!.contains('cannot dereference a function call on the left side of an assignment')
 assert os.read_file(area+'helper-preflight-jobs.log')!.contains('Probe compiler preflight: PASS') && digest(area+'states/preflight-p2-arm/fixture.c') == digest(area+'states/p1-before-arm/tidwake/fixture.c')
 assert os.read_file(area+'fetch.log')!.contains('requested URL returned error: 429') && os.read_file(area+'fetch-fork.log')!.trim_space() == 'Tagged Linux clear-child-tid source: PASS'
 refusal := object(area+'initial-scope-refusal.json')!; assert refusal['raw_output']!.str() == area+'scope-only.log' && refusal['raw_sha256']!.str() == digest(area+'scope-only.log') && refusal['audit_source_sha256']!.str() == digest(area+'initial-scope-audit-source.v')
 assert refusal['first_line']!.str().contains("assert before.replace(old,'') == after.replace(new,'')")
 for name in ['retain-scope-refusal.v','initial-scope-audit-source.v','scope-only.log','initial-scope-refusal.json'] {pins[area+name] = digest(area+name)}
 publish(area+'initial-scope-refusal.json',out+'tidwake-initial-scope-refusal.json')!
 assert os.read_file(area+'helper-watch.log')!.contains("assert fixture in ['tidwake','futex','runtime']")
 initial_watch := object(area+'initial-watch-retained-inputs.json')!; assert initial_watch.len == 45
 assert os.read_file(area+'initial-watch.log')!.count('Completed ') == 4
 for path,hash in initial_watch {assert digest(path) == hash.str()}
 assert os.read_file(area+'watch-v2-producer.log')!.count('Retired completed boot staging:') == 8 && !os.read_file(area+'watch-v2-producer.log')!.contains('FAIL:')
 for name in ['helper-watch.log','watch-producer.log','initial-watch.log','initial-watch-retained-inputs.json','retry-watch.v','retry-watch.log','watch-v2.v','watch-v2','watch-v2-producer.log'] {pins[area+name] = digest(area+name)}
 publish(area+'helper-watch.log',out+'tidwake-initial-watch-refusal.log')!
 for name in ['preflight-arm','preflight-p2-arm'] {for file in os.walk_ext(area+'states/'+name,'') {if os.inode(file).typ == .regular {pins[file] = digest(file)}}}
 for name in ['setup.v','finish.v','finish','prepare-pipeline.v','pipeline.v','pipeline','pipeline-producer.log','pipeline-p2.v','pipeline-p2','pipeline-p2-producer.log','retry-preflight.v','retry-preflight.log','preflight.v','preflight','preflight-producer.log','preflight-jobs.v','preflight-jobs','preflight-p2-producer.log','helper-preflight.log','helper-preflight-jobs.log','initial-probe.v','fetch.v','fetch.log','fetch-fork.v','fetch-fork.log','linux-fork-v6.12.c','linux-fork-v6.12.base64','create-audit.v','contracts.txt','manage.v','manage','watch.v','watch','native-arm-before-producer.log','native-x86-before-producer.log','native-arm-after-producer.log','native-x86-after-producer.log','reference-arm-producer.log','reference-x86-producer.log'] {pins[area+name] = digest(area+name)}
 for name in ['initial-probe.v','helper-preflight.log','helper-preflight-jobs.log','pipeline-producer.log','fetch.log','fetch-fork.log'] {publish(area+name,out+'tidwake-'+name)!}
 data := json2.encode(pins,prettify:true)+'\n'; if os.exists(area+'diagnostic-pins.json') {assert os.read_file(area+'diagnostic-pins.json')! == data} else {os.write_file(area+'diagnostic-pins.json',data)!}
 publish(area+'diagnostic-pins.json',out+'tidwake-diagnostic-pins.json')!
}
