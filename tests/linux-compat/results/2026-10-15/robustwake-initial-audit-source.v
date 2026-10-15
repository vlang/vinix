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
 for row in log.split_into_lines().filter(it.starts_with('LINUX ROBUSTWAKE SLAB:') || it.starts_with('LINUX ROBUSTWAKE STORAGE:')) {
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
	assert log.contains('LINUX ROBUSTWAKE DETAIL:'), 'robustwake baseline failure markers required'
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
		'wrapper_source':    state + '/source/robustwakereferenceinit/core.v'
		'wrapper_c':         state + '/fixture.c'
		'wrapper_elf':       state + '/init'
		'initramfs':         state + '/initramfs.cpio'
		'serial':            state + '/serial.log'
		'serial_adapter_c':  state + '/serial.c'
		'controller_source': '/Users/alex/code/vinix/tests/linux-compat/robustwake-reference.v'
		'qemu':              command[0]
	} {
		assert artifacts[label] == digest(path)
	}
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/robustwakereferenceinit/core.v')
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
		println('Native robust-futex exit wake source/C scope: PASS')
		return
	}
	if '--negative-control' in os.args {
		assert false, 'robustwake assertions must execute'
		return
	}
	if '--negative-pass-control' in os.args {
		failure(os.read_file(os.args[2])!, os.args[3])
		return
	}
	assert os.args.len == 2, 'Usage: robustwake-check.v EVIDENCE-AREA (compile without -prod)'
	area := os.args[1].trim_right('/') + '/'
	states := area + 'states/'
	root := '/Users/alex/code/vinix/'
	out := root + 'tests/linux-compat/results/2026-10-15/'
	os.mkdir_all(out)!
	sdk_and_primary(area, out)!
	diagnostics(area,out)!
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'robustwake assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control',
		states + 'p3-reference-arm/serial.log', 'aarch64'], 'robustwake baseline failure markers required'))!
	check_source(area, root)!
	for suffix in ['arm', 'x86'] { check_c(area, suffix)! }
	os.write_file(area+'scope-check.log','arm/x86: exact whole production C differs only in release_robust_list calls, abandon_robust_futex prototype/body: PI and pending flags, ownerless pending non-PI wake, bounded ordinary wake1; existing user reads/writes, traversal, offsets, PI-state release, process/map ownership and cleanup unchanged; no allocation/free/pin/stack promotion or normalization\n')!
	base := os.read_file(area + 'base.txt')!.trim_space()
	assert base == '29d59c0e06b4cfc116777e634f74ca9ac6348ffe'
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
	assert os.read_file(area + 'linux-source.sha256')!.trim_space() == digest(area + 'linux-futex-core-v6.12.c') + ' https://kernel.googlesource.com/pub/scm/linux/kernel/git/torvalds/linux/+/refs/tags/v6.12/kernel/futex/core.c?format=TEXT'
	linux_source := os.read_file(area + 'linux-futex-core-v6.12.c')!
	assert linux_source.contains('if (pending_op && !pi && !owner)') && linux_source.contains('if (!pi && (uval & FUTEX_WAITERS))') && linux_source.contains('futex_wake(uaddr, FLAGS_SIZE_32 | FLAGS_SHARED, 1,')
	assert os.read_file(area + 'watch.log')!.split_into_lines().filter(it.starts_with('Completed ')).len == 8
	retained := object(area + 'watch-retained-inputs.json')!
	assert retained.len == 84
	for path, hash in retained {
		assert path.starts_with(states + 'p3-before-arm/') || path.starts_with(states + 'p3-before-x86/') || path.starts_with(states + 'p3-after-arm/') || path.starts_with(states+'p3-after-x86/')
		assert !path.contains('/iso-build/') && !path.ends_with('/efivars.fd')
		assert os.inode(path).typ == .regular && digest(path) == hash.str(), path
	}
	mut walked := map[string]bool{}
	mut completed := map[string]bool{}
	for suffix in ['arm', 'x86'] {
		for phase in ['before', 'after'] {
			names := if phase == 'before' {
				['robustwake']
			} else {
				['robustwake', 'runtime', 'futex']
			}
			for name in names {
				probe := states + 'p3-' + phase + '-' + suffix + '/' + name
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
			'fixture_source':           digest(root + 'tests/linux-compat/robustwakefixture/core.v')
			'audit_source':             digest(@FILE)
			'linux_primary_source':     digest(area + 'linux-futex-core-v6.12.c')
			'linux_primary_pin':        digest(area + 'linux-source.sha256')
			'private_sdk': digest(area + 'sdk-inputs.json')
			'primary_source_note': digest(area + 'primary-source-note.txt')
			'sdk_prior_inputs': digest('/Users/alex/.cache/vinix-linux-compat/waitabi-20261015/sdk-inputs.json')
			'arm_compiler_adapter': digest(area + 'arm-cc.v')
			'arm_compiler_adapter_binary': digest(area + 'arm-cc')
			'prior_diagnostics': digest(area + 'diagnostic-pins.json')
			'scope_contract': digest(area + 'scope-check.log')
            'prior_compression': digest(area+'prior-transparent-compression.json'),
            'earlier_compression': digest(area+'earlier-transparent-compression.json'),
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
			state := states + 'p3-' + phase + '-' + suffix
			kernel := area + if phase == 'before' { 'baseline-' } else { 'kernel-' } + suffix + '/kernel/bin/vinix'
			names := if phase == 'before' {
				['robustwake']
			} else {
				['robustwake', 'runtime', 'futex']
			}
			captured := receipt(state, arch, digest(kernel), names, phase == 'before')!
			for key, value in captured { artifacts[phase + '_' + key] = value }
			for key in ['robustwake_source', 'robustwake_init', 'robustwake_c'] {
				if phase == 'before' {
					identity[key] = captured[key]
				} else {
					assert identity[key] == captured[key]
				}
			}
			text := os.read_file(state + '/robustwake/serial.log')!
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
				'native':    state + '/robustwake/serial.log'
				'build':     build
			} {
				publish(path, out + 'robustwake-' + phase + '-' + arch + '-' + label + if label == 'receipt' {
					'.json'
				} else {
					'.log'
				})!
			}
			if phase == 'after' {
				for name in names {
					if name == 'robustwake' { continue }
					publish(state + '/' + name + '/serial.log', out + 'robustwake-regression-' + arch + '-' + name + '.log')!
				}
			}
		}
		probe := states + 'p3-before-' + suffix + '/robustwake'
		raw := os.read_file(probe + '/fixture.c')!
		assert raw.count('alloca(') == 10
		for token in ['malloc(', 'calloc(', 'realloc(', 'memdup(', 'array_push(', 'array_get(',
			'v_fixed_index('] {
			assert !raw.contains(token)
		}
		reference := states + 'p3-reference-' + suffix
		linux := reference_receipt(reference, arch, identity['robustwake_init'])!
		for key, value in linux { artifacts['reference_' + key] = value }
		for label, path in {
			'receipt':   reference + '/receipt.json'
			'aggregate': reference + '.log'
			'native':    reference + '/serial.log'
		} {
			publish(path, out + 'robustwake-reference-' + arch + '-' + label + if label == 'receipt' {
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
		os.write_file(out + 'robustwake-evidence-' + arch + '.json', json2.encode(Evidence{
			architecture:  arch
			context: 'Native robust futex exit wakes:608 controls per architecture, original160 failures, corrected and identical-ELF Linux6.12.51 zero. Four root/UID1000 initial/one-level PID namespace cohorts with120 raw owner-exit trials and32 real musl mutex recovery controls each. CMP_REQUEUE positive return counts establish three shared waiters plus separate private and neighboring queues before owner exit; pidfd POLLIN and wait37 establish completed cleanup. Exact remaining queue counts require one wake for pending ownerless non-PI unlocks, one for owned WAITERS-marked ordinary entries, no ordinary wake for PI tags, and unchanged other-owner/list-only cases. All four WAITERS/OWNER_DIED combinations, positive/negative offsets, pending/list/both layouts,256-byte exact payload/canary model,600 joined waiters per raw cohort and restored libc mutex payloads. Four warmed200-cycle fork/one-waiter/requeue/exit/drain/reap/join/close storage cohorts, four isolated production builds, runtime/futex regressions, unchanged allocation diagnostics,67 inventory/2014 SDK/15146 compiler pins, exact two-function/prototype whole-C scope and executing negatives. Two pre-ELF compiler refusals retained separately; final p3 source/C/ELF identity required.42 prior robustquery and75 earlier process-group artifacts transparently compressed with unchanged paths and SHA-256. Concurrent owner-word CAS/mapping/list mutation, malformed pointers/alignment, actual PI-state handover, forced sibling exit, GNU/foreign paths and the three broad roadmap gates remain separate.'
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
		publish(area + name, out + 'robustwake-' + name)!
	}
	publish(area + 'watch-retained-inputs.json', out + 'robustwake-watch-retained-inputs.json')!
	os.write_file(area + 'audit.log', 'Native robustwake conformance audit: PASS\n')!
	publish(area + 'audit.log', out + 'robustwake-audit.log')!
	println('Native robustwake conformance audit: PASS')
}

fn semantics(log string,phase string,arch string,reference bool) {
 assert phase in ['before','after'] && arch in ['aarch64','x86_64']
 topologies := log.split_into_lines().filter(it.starts_with('LINUX ROBUSTWAKE TOPOLOGY:')); assert topologies.len == 4
 mut seen := map[string]bool{}
 for row in topologies {
  f := row.fields(); assert f.len == 13 && f[3] in ['ordinary=0','ordinary=1'] && f[4] in ['namespace=0','namespace=1']
  key := f[3]+f[4]; assert key !in seen; seen[key] = true
  assert f[5].starts_with('self=') && f[6].starts_with('child=') && f[7].starts_with('tid=')
  self := f[5].all_after('=').int(); child := f[6].all_after('=').int(); assert self > 1 && child > 1 && child != self && f[7] == 'tid='+child.str()
  if f[4] == 'namespace=1' {assert self == 2}
  assert f[8] == 'uid='+if f[3] == 'ordinary=1' {'1000'} else {'0'}
  assert f[9..] == ['registered=24','queued=3','private=1','neighbor=1']
 }
 cohorts := log.split_into_lines().filter(it.starts_with('LINUX ROBUSTWAKE COHORT:')); assert cohorts.len == 4; seen.clear()
 for row in cohorts {
  f := row.fields(); assert f.len == 12 && f[3] in ['ordinary=0','ordinary=1'] && f[4] in ['namespace=0','namespace=1']
  key := f[3]+f[4]; assert key !in seen; seen[key] = true
  assert f[5].starts_with('self=') && f[5].all_after('=').int() > 1
  if f[4] == 'namespace=1' {assert f[5] == 'self=2'}
  assert f[6] == 'uid='+if f[3] == 'ordinary=1' {'1000'} else {'0'}
  assert f[7] == 'page='+if arch == 'aarch64' && !reference {'16384'} else {'4096'}
  assert f[8..] == ['raw=120','libc=32','queued=600','cleaned=600']
 }
 mut local := map[string]string{}
 for label in ['CASES:','FINAL:'] {
  rows := log.split_into_lines().filter(it.starts_with('LINUX ROBUSTWAKE '+label)); assert rows.len == 24; seen.clear()
  mut calls := 0; mut failures := 0
  for row in rows {
   f := row.fields(); assert f.len == 8 && f[3] in ['ordinary=0','ordinary=1'] && f[4] in ['namespace=0','namespace=1'] && f[5] in ['kind=0','kind=1','kind=2','kind=3','kind=4','kind=5']
   key := f[3]+f[4]+f[5]; assert key !in seen; seen[key] = true
   kind := f[5].all_after('=').int(); assert f[6].starts_with('calls=') && f[7].starts_with('failures=')
   n := f[6].all_after('=').int(); bad := f[7].all_after('=').int()
   assert n == [16,24,48,24,8,32]![kind]
   assert bad == if phase == 'before' {[16,12,12,0,0,0]![kind]} else {0}
   if label == 'CASES:' {local[key] = f[6]+f[7]} else {assert local[key] == f[6]+f[7]}
   calls += n; failures += bad
  }
  assert calls == 608 && failures == if phase == 'before' {160} else {0}
 }
 if phase == 'before' {assert log.contains('LINUX ROBUSTWAKE DETAIL:') && log.contains('LINUX ROBUSTWAKE FAIL:') && !log.contains('LINUX ROBUSTWAKE: PASS')}
 else {assert !log.contains('LINUX ROBUSTWAKE DETAIL:') && !log.contains('LINUX ROBUSTWAKE FAIL:')}
 if reference {assert log.contains('Linux version 6.12.51-0-virt') && log.contains('LINUX ROBUSTWAKE REFERENCE: PASS') && !log.contains('LINUX ROBUSTWAKE STORAGE:')}
 else if phase == 'after' {assert log.count('LINUX ROBUSTWAKE: PASS') == 1}
 assert !log.contains('Kernel panic') && !log.contains('setup stage=')
}
fn check_source(area string,root string) ! {
 before := os.read_file(area+'before-linux_task.v')!; after := os.read_file(area+'after-linux_task.v')!
 changes := {
  'abandon_robust_futex(proc.own_tid(t), u64(i64(entry & ~u64(1)) + offset))':'abandon_robust_futex(proc.own_tid(t), u64(i64(entry & ~u64(1)) + offset), entry & 1 != 0, false)'
  'abandon_robust_futex(proc.own_tid(t), u64(i64(pending & ~u64(1)) + offset))':'abandon_robust_futex(proc.own_tid(t), u64(i64(pending & ~u64(1)) + offset), pending & 1 != 0, true)'
  'fn abandon_robust_futex(tid int, address u64) {':'fn abandon_robust_futex(tid int, address u64, pi bool, pending bool) {'
  '\tif value & futex_tid_mask != u32(tid) {':'\towner := value & futex_tid_mask\n\t// A pending non-PI unlock may already have cleared its owner. Complete\n\t// the lost wake without changing the consistent user mutex word.\n\tif pending && !pi && owner == 0 {\n\t\tfutex.wake_n_key(address, 1, false)\n\t\treturn\n\t}\n\tif owner != u32(tid) {'
  '\tif value & futex_waiters != 0 {\n\t\tfutex.wake(address)':'\t// PI waiters are handled by release_pi_owner; ordinary robust wakeups\n\t// select one waiter, leaving the remaining queue for mutex handover.\n\tif !pi && value & futex_waiters != 0 {\n\t\tfutex.wake_n_key(address, 1, false)'
 }
 mut expected := before
 for old,new in changes {assert expected.count(old) == 1; expected = expected.replace(old,new)}
 assert expected == after && before != after
 assert digest(root+'kernel/userland/linux_task.v') == digest(area+'after-linux_task.v')
 for suffix in ['arm','x86'] {assert digest(area+'kernel-'+suffix+'/kernel/userland/linux_task.v') == digest(area+'after-linux_task.v')}
}
fn check_c(area string,suffix string) ! {
 before := os.read_file(area+'before-'+suffix+'.c')!; after := os.read_file(area+'after-'+suffix+'.c')!
 old := body(before,'userland__abandon_robust_futex'); new := body(after,'userland__abandon_robust_futex')
 old_owner := '\tif ((value & userland__futex_tid_mask) != (u32)(tid)) {'
 new_owner := '\tu32 owner = value & userland__futex_tid_mask;\n\tif (pending && !pi && (owner == 0)) {\n\t\tfutex__wake_n_key(address, 1, false);\n\t\treturn;\n\t}\n\tif (owner != (u32)(tid)) {'
 assert old.count(old_owner) == 1
 expected := old.replace('i64 tid, u64 address)','i64 tid, u64 address, bool pi, bool pending)').replace(old_owner,new_owner).replace('if ((value & userland__futex_waiters) != 0)','if (!pi && ((value & userland__futex_waiters) != 0))').replace('futex__wake(address);','futex__wake_n_key(address, 1, false);')
 assert expected == new
 old_release := body(before,'userland__release_robust_list'); new_release := body(after,'userland__release_robust_list')
 mut release := old_release
 for name in ['entry','pending'] {
  previous := 'userland__abandon_robust_futex(proc__own_tid(t), (u64)((i64)('+name+' & ~(u64)(1)) + offset));'
  replacement := previous[..previous.len-2]+', ('+name+' & 1) != 0, '+if name == 'entry' {'false);'} else {'true);'}
  assert release.count(previous) == 1; release = release.replace(previous,replacement)
 }
 assert release == new_release
 previous_decl := 'void userland__abandon_robust_futex(i64 tid, u64 address);'
 replacement_decl := 'void userland__abandon_robust_futex(i64 tid, u64 address, bool pi, bool pending);'
 assert before.count(previous_decl) == 1
 assert before.replace(old,'').replace(old_release,'').replace(previous_decl,replacement_decl) == after.replace(new,'').replace(new_release,''),'Exact whole-C two-function/prototype scope; no normalization'
 for token in ['malloc(','calloc(','realloc(','memdup(','array__','free(','alloca(','vinix_stack_alloc(','pin_process(','unpin_process(','copy_from_user(','copy_to_user('] {
  assert old.count(token) == new.count(token) && old_release.count(token) == new_release.count(token),token
 }
 assert old.count('futex__wake(address)') == 1 && new.count('futex__wake_n_key(address, 1, false)') == 2
}
fn sdk_and_primary(area string,out string) ! {
 sdk := object(area+'sdk-inputs.json')!; prior := object('/Users/alex/.cache/vinix-linux-compat/waitabi-20261015/sdk-inputs.json')!
 assert sdk.len == 2014 && prior.len == 2014
 mut found := map[string]bool{}
 for path in os.walk_ext(area+'sdk','') {assert os.inode(path).typ == .regular; local := path.all_after(area+'sdk/'); assert local in sdk && local !in found; found[local] = true}
 assert found.len == sdk.len
 for path,hash in sdk {assert hash.str() == prior[path]!.str() && digest(area+'sdk/'+path) == hash.str(),path}
 for state in ['p3-before-arm/robustwake','p3-after-arm/robustwake','p3-after-arm/runtime','p3-after-arm/futex','p3-reference-arm'] {
  for file in ['fixture.o','serial.o','init'] {
   driver := object(area+'states/'+state+'/'+file+'.compiler.json')!
   assert driver['status']!.str() == '0' && driver['output']!.str() == ''
   assert driver['arguments']!.str().contains('--gcc-install-dir='+area.trim_right('/')+'/sdk/usr/lib/gcc/aarch64-alpine-linux-musl/14.2.0')
   assert driver['arguments']!.str().contains('--target=aarch64-linux-musl') && driver['arguments']!.str().contains('--sysroot='+area.trim_right('/')+'/sdk')
  }
 }
 for name in ['sdk-inputs.json','linux-source.sha256','primary-source-note.txt'] {publish(area+name,out+'robustwake-'+name)!}
}
fn diagnostics(area string,out string) ! {
 mut pins := map[string]string{}
 for manifest in ['prior-transparent-compression.json','earlier-transparent-compression.json'] {
  entries := object(area+manifest)!; assert entries.len == if manifest == 'prior-transparent-compression.json' {42} else {75}
  for path,hash in entries {
   names := if manifest == 'prior-transparent-compression.json' {['robustquery']} else {['groupabi','grouptid','grouporder','groupzombie']}
   assert names.any(path.starts_with('/Users/alex/.cache/vinix-linux-compat/'+it+'-20261015/'))
   assert os.inode(path).typ == .regular && digest(path) == hash.str(),path
  }
  pins[manifest] = digest(area+manifest); publish(area+manifest,out+'robustwake-'+manifest)!
 }
 assert os.read_file(area+'compress-prior.log')!.trim_space() == 'Preserved 42 prior robustquery artifacts with transparent compression; paths and SHA-256 unchanged'
 assert os.read_file(area+'compress-earlier.log')!.trim_space() == 'Preserved 75 earlier process-group artifacts with transparent compression; paths and SHA-256 unchanged'
 first := os.read_file(area+'initial-probe.v')!; second := os.read_file(area+'second-probe.v')!
 assert first.count('unsafe{&wanted}') == 1 && second == first.replace('unsafe{&wanted}','&wanted')
 final := os.read_file('/Users/alex/code/vinix/tests/linux-compat/robustwakefixture/core.v')!
 original_flags := 'fn flags(choice i32) u32 {return [u32(0),0x40000000,0x80000000,0xc0000000]![choice]}'
 assert second.count(original_flags) == 1 && final == second.replace(original_flags,'fn flags(choice i32) u32 {return u32(choice)<<30}')
 for suffix in ['arm','x86'] {for phase in ['p1','p2'] {
  state := area+'states/'+phase+'-before-'+suffix
  rows := object(state+'/receipt.json')!['results']!.as_array(); assert rows.len == 1
  row := rows[0].as_map(); assert row['exit_code']!.int() == 1 && row['detail']!.str() == 'Command failed' && row['init_sha256']!.str() == '' && row['iso_sha256']!.str() == ''
  assert os.read_file(state+'/sources/robustwakefixture/core.v')! == if phase == 'p1' {first} else {second}
  assert !os.exists(state+'/robustwake/init') && !os.exists(state+'/robustwake/test.iso')
  text := os.read_file(state+'.log')!
  assert text.contains(if phase == 'p1' {'already inside `unsafe` block'} else {'v_fixed_index'}) && !text.contains('LINUX ROBUSTWAKE COHORT:')
  if phase == 'p2' {
   raw := os.read_file(state+'/robustwake/fixture.c')!; function := body(raw,'robustwakefixture__flags')
   corrected := body(os.read_file(area+'states/p3-before-'+suffix+'/robustwake/fixture.c')!,'robustwakefixture__flags')
   assert function.contains('v_fixed_index(choice, 4)') && !corrected.contains('v_fixed_index') && corrected.contains('(u32)(choice)') && corrected.contains('<< (30)')
   assert raw.replace(function,corrected) == os.read_file(area+'states/p3-before-'+suffix+'/robustwake/fixture.c')!
  }
  for path in os.walk_ext(state,'') {if os.inode(path).typ == .regular {pins[path] = digest(path)}}
  pins[state+'.log'] = digest(state+'.log')
  publish(state+'/receipt.json',out+'robustwake-diagnostic-'+os.file_name(state)+'-receipt.json')!
  publish(state+'.log',out+'robustwake-diagnostic-'+os.file_name(state)+'.log')!
 }}
 preflight := object(area+'preflight-compiler.json')!; assert preflight['status']!.str() == '0' && preflight['output']!.str() == ''
 assert preflight['generated_c']!.str() == digest(area+'preflight-probe.c') && digest(area+'preflight-probe.c') == digest(area+'states/p3-before-arm/robustwake/fixture.c')
 assert os.read_file(area+'pipeline-producer.log')!.contains('Probe did not compile; retain refusal:') && os.read_file(area+'retry.log')!.contains('Final probe compilation refused')
 for name in ['initial-probe.v','second-probe.v','retry.v','retry-p3.v','retry.log','preflight-probe.c','preflight-probe.o','preflight-compiler.json','preflight-and-retry.v','preflight-and-retry.log','finish-probe.v','use-existing-wake.v','compress-earlier.v','compress-earlier.log','compress-prior.log','pipeline-producer.log','manage-p3.v','manage-p3','watch-p3.v','create-audit.v','audit-contracts.txt','linux-futex-core-v6.12.base64'] {
  pins[name] = digest(area+name)
  if name.ends_with('.json') || name.ends_with('.log') || name in ['initial-probe.v','second-probe.v','compress-earlier.v'] {publish(area+name,out+'robustwake-'+name)!}
 }
 helper := '/Users/alex/.cache/vinix-linux-compat/compress-robustquery-for-wake.v'; pins[helper] = digest(helper); publish(helper,out+'robustwake-compress-prior.v')!
 data := json2.encode(pins,prettify:true)+'\n'
 if os.exists(area+'diagnostic-pins.json') {assert os.read_file(area+'diagnostic-pins.json')! == data} else {os.write_file(area+'diagnostic-pins.json',data)!}
 publish(area+'diagnostic-pins.json',out+'robustwake-diagnostic-pins.json')!
}
