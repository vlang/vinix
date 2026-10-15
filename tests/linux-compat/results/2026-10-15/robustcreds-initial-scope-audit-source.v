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
 for row in log.split_into_lines().filter(it.starts_with('LINUX ROBUSTCREDS SLAB:') || it.starts_with('LINUX ROBUSTCREDS STORAGE:')) {
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
	assert log.contains('LINUX ROBUSTCREDS DETAIL:'), 'robustcreds baseline failure markers required'
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
		'wrapper_source':    state + '/source/robustcredsreferenceinit/core.v'
		'wrapper_c':         state + '/fixture.c'
		'wrapper_elf':       state + '/init'
		'initramfs':         state + '/initramfs.cpio'
		'serial':            state + '/serial.log'
		'serial_adapter_c':  state + '/serial.c'
		'controller_source': '/Users/alex/code/vinix/tests/linux-compat/robustcreds-reference.v'
		'qemu':              command[0]
	} {
		assert artifacts[label] == digest(path)
	}
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/robustcredsreferenceinit/core.v')
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
		println('Native inspection credentials source/C scope: PASS')
		return
	}
	if '--negative-control' in os.args {
		assert false, 'robustcreds assertions must execute'
		return
	}
	if '--negative-pass-control' in os.args {
		failure(os.read_file(os.args[2])!, os.args[3])
		return
	}
	assert os.args.len == 2, 'Usage: robustcreds-check.v EVIDENCE-AREA (compile without -prod)'
	area := os.args[1].trim_right('/') + '/'
	states := area + 'states/'
	root := '/Users/alex/code/vinix/'
	out := root + 'tests/linux-compat/results/2026-10-15/'
	os.mkdir_all(out)!
	sdk_and_primary(area, out)!
	diagnostics(area,out)!
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'robustcreds assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control',
		states + 'p1-reference-arm/serial.log', 'aarch64'], 'robustcreds baseline failure markers required'))!
	check_source(area, root)!
	for suffix in ['arm', 'x86'] { check_c(area, suffix)! }
	os.write_file(area+'scope-check.log','arm/x86: exact whole production C differs only in inspection_capable prototype/body, inspection_allowed and get_robust_list calls, plus scalar may_inspect_realcreds_locked helper/declaration; effective ptrace override and real-ID/permitted subset selection; unchanged MAC, table/map locks, user copies, Process/Thread/map ownership, inspection refs and release; no allocation/free/pin/stack promotion or normalization\n')!
	base := os.read_file(area + 'base.txt')!.trim_space()
	assert base == '649619d3ab186043337e4ba237a42970d81a2d30'
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
	assert os.read_file(area + 'watch.log')!.split_into_lines().filter(it.starts_with('Completed ')).len == 8
	retained := object(area + 'watch-retained-inputs.json')!
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
				['robustcreds']
			} else {
				['robustcreds', 'runtime', 'robustwake']
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
		assert git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])! == 'kernel/proc/inspect.v\nkernel/userland/linux_task.v'
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
            'inspection_source_before': digest(area+'before-inspect.v'),
            'inspection_source_after': digest(area+'after-inspect.v'),
			'fixture_source':           digest(root + 'tests/linux-compat/robustcredsfixture/core.v')
			'audit_source':             digest(@FILE)
			'linux_primary_source':     digest(area + 'linux-syscalls-v6.12.c')
			'linux_primary_pin':        digest(area + 'linux-source.json')
			'private_sdk': digest(area + 'sdk-inputs.json')
			'sdk_prior_inputs': digest('/Users/alex/.cache/vinix-linux-compat/robustwake-20261015/sdk-inputs.json')
			'arm_compiler_adapter': digest(area + 'arm-cc.v')
			'arm_compiler_adapter_binary': digest(area + 'arm-cc')
			'prior_diagnostics': digest(area + 'diagnostic-pins.json')
			'scope_contract': digest(area + 'scope-check.log')
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
			state := states + 'p1-' + phase + '-' + suffix
			kernel := area + if phase == 'before' { 'baseline-' } else { 'kernel-' } + suffix + '/kernel/bin/vinix'
			names := if phase == 'before' {
				['robustcreds']
			} else {
				['robustcreds', 'runtime', 'robustwake']
			}
			captured := receipt(state, arch, digest(kernel), names, phase == 'before')!
			for key, value in captured { artifacts[phase + '_' + key] = value }
			for key in ['robustcreds_source', 'robustcreds_init', 'robustcreds_c'] {
				if phase == 'before' {
					identity[key] = captured[key]
				} else {
					assert identity[key] == captured[key]
				}
			}
			text := os.read_file(state + '/robustcreds/serial.log')!
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
				'native':    state + '/robustcreds/serial.log'
				'build':     build
			} {
				publish(path, out + 'robustcreds-' + phase + '-' + arch + '-' + label + if label == 'receipt' {
					'.json'
				} else {
					'.log'
				})!
			}
			if phase == 'after' {
				for name in names {
					if name == 'robustcreds' { continue }
					publish(state + '/' + name + '/serial.log', out + 'robustcreds-regression-' + arch + '-' + name + '.log')!
				}
			}
		}
		probe := states + 'p1-before-' + suffix + '/robustcreds'
		raw := os.read_file(probe + '/fixture.c')!
		assert raw.count('alloca(') == 14
		for token in ['malloc(', 'calloc(', 'realloc(', 'memdup(', 'array_push(', 'array_get(',
			'v_fixed_index('] {
			assert !raw.contains(token)
		}
		reference := states + 'p1-reference-' + suffix
		linux := reference_receipt(reference, arch, identity['robustcreds_init'])!
		for key, value in linux { artifacts['reference_' + key] = value }
		for label, path in {
			'receipt':   reference + '/receipt.json'
			'aggregate': reference + '.log'
			'native':    reference + '/serial.log'
		} {
			publish(path, out + 'robustcreds-reference-' + arch + '-' + label + if label == 'receipt' {
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
		os.write_file(out + 'robustcreds-evidence-' + arch + '.json', json2.encode(Evidence{
			architecture:  arch
			context: 'Native get_robust_list READ_REALCREDS and effective-only CAP_SYS_PTRACE inspection overrides:5120 controls per architecture, original560 failures, corrected and identical-ELF Linux6.12.51 zero. Four base-root/base-UID1000 initial/one-level PID namespace cohorts, each with32 independently observed caller/target real/effective/saved UID/GID, permitted/effective capabilities and dumpability profiles. Leader and pipe-blocked worker queries, canonical/upper PID words, valid/NULL head/length outputs, process_vm read/write bytes with invalid local payloads and target echo, nondumpable self controls and missing-target precedence. Restore both target musl heads, join workers, reap caller/target and close every pipe/mapping. Four warmed200-cycle complete trial cleanup cohorts, four fresh production builds, runtime/robustwake regressions, unchanged allocation diagnostics,67 inventory/2014 SDK/15146 compiler pins and exact whole-C scalar helper scope with executing negative controls. Initial host setup and pre-ELF probe compiler refusals retained separately. User namespaces/LSM/MAC policy changes, concurrent credential/target/map changes, broad process_vm vector/fault semantics, GNU/foreign paths and three broad roadmap gates remain separate.'
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
		publish(area + name, out + 'robustcreds-' + name)!
	}
	publish(area + 'watch-retained-inputs.json', out + 'robustcreds-watch-retained-inputs.json')!
	os.write_file(area + 'audit.log', 'Native robustcreds conformance audit: PASS\n')!
	publish(area + 'audit.log', out + 'robustcreds-audit.log')!
	println('Native robustcreds conformance audit: PASS')
}







fn semantics(log string,phase string,arch string,reference bool) {
 assert phase in ['before','after'] && arch in ['aarch64','x86_64']
 rows := log.split_into_lines().filter(it.starts_with('LINUX ROBUSTCREDS PROFILE:')); assert rows.len == 128
 mut seen := map[string]bool{}
 for row in rows {
  f := row.fields(); assert f.len == 14 && f[3] in ['ordinary=0','ordinary=1'] && f[4] in ['namespace=0','namespace=1'] && f[5].starts_with('profile=')
  index := f[5].all_after('=').int(); assert index >= 0 && index < 32
  key := f[3]+f[4]+f[5]; assert key !in seen; seen[key] = true
  base := if f[3] == 'ordinary=1' {u64(1000)} else {u64(0)}
  caller := profile_words(index,base,true); target := profile_words(index,base,false)
  for offset,word in ['caller_uid','caller_gid','caller_caps','target_uid','target_gid','target_caps'] {
   value := if offset < 3 {caller} else {target}; slot := offset%3
   wanted := if slot < 2 {value[slot*3].str()+'/'+value[slot*3+1].str()+'/'+value[slot*3+2].str()} else {value[6].str()+'/'+value[7].str()}
   assert f[6+offset] == word+'='+wanted
  }
  assert f[12] == 'dump='+target[8].str()
  assert f[13] == 'allowed='+if index in [0,1,3,14,15,17,18,21,22,25,26,28,29,30] {'1'} else {'0'}
 }
 cohorts := log.split_into_lines().filter(it.starts_with('LINUX ROBUSTCREDS COHORT:')); assert cohorts.len == 4; seen.clear()
 for row in cohorts {
  f := row.fields(); assert f.len == 12 && f[3] in ['ordinary=0','ordinary=1'] && f[4] in ['namespace=0','namespace=1']
  key := f[3]+f[4]; assert key !in seen; seen[key] = true
  assert f[5].starts_with('self=') && f[5].all_after('=').int() > 1
  if f[4] == 'namespace=1' {assert f[5] == 'self=2'}
  assert f[6] == 'page='+if arch == 'aarch64' && !reference {'16384'} else {'4096'}
  assert f[7..] == ['profiles=32','targets=32','workers=32','callers=32','cleaned=96']
 }
 mut local := map[string]string{}
 for label in ['CASES:','FINAL:'] {
  cases := log.split_into_lines().filter(it.starts_with('LINUX ROBUSTCREDS '+label)); assert cases.len == 24; seen.clear(); mut calls := 0; mut failures := 0
  for row in cases {
   f := row.fields(); assert f.len == 8 && f[3] in ['ordinary=0','ordinary=1'] && f[4] in ['namespace=0','namespace=1'] && f[5] in ['kind=0','kind=1','kind=2','kind=3','kind=4','kind=5']
   key := f[3]+f[4]+f[5]; assert key !in seen; seen[key] = true; kind := f[5].all_after('=').int()
   assert f[6].starts_with('calls=') && f[7].starts_with('failures=')
   n := f[6].all_after('=').int(); bad := f[7].all_after('=').int()
   assert n == [192,192,64,64,384,384]![kind] && bad == if phase == 'before' {[60,60,10,10,0,0]![kind]} else {0}
   if label == 'CASES:' {local[key] = f[6]+f[7]} else {assert local[key] == f[6]+f[7]}; calls += n; failures += bad
  }
  assert calls == 5120 && failures == if phase == 'before' {560} else {0}
 }
 if phase == 'before' {assert log.contains('LINUX ROBUSTCREDS DETAIL:') && log.contains('LINUX ROBUSTCREDS FAIL:') && !log.contains('LINUX ROBUSTCREDS: PASS')}
 else {assert !log.contains('LINUX ROBUSTCREDS DETAIL:') && !log.contains('LINUX ROBUSTCREDS FAIL:')}
 if reference {assert log.contains('Linux version 6.12.51-0-virt') && log.contains('LINUX ROBUSTCREDS REFERENCE: PASS') && !log.contains('LINUX ROBUSTCREDS STORAGE:')}
 else if phase == 'after' {assert log.count('LINUX ROBUSTCREDS: PASS') == 1}
 assert !log.contains('Kernel panic') && !log.contains('setup stage=')
}
fn profile_words(index int,base u64,caller bool) [9]u64 {
 mut words := [base,base,base,base,base,base,u64(0),0,1]!
 if caller {
  match index {
   1,29 {words[1] = 2000}
   2 {words[0] = 2000}
   3 {words[4] = 2000}
   4 {words[3] = 2000}
   27 {words[0] = 2000}
   28 {words[1] = 2000}
   30 {words[1] = 2000; words[4] = 2000}
   31 {words[0] = 2000; words[3] = 2000}
   else {}
  }
  if index in [13,14,15,20,21,22,23,24,25,26,27,28] {words[6] = u64(1)<<19}
  if index in [14,15,21,25,26] {words[7] = words[6]}
  if index in [17,18] {words[6] = u64(1)<<10}
  if index == 18 {words[7] = words[6]}; if index == 19 {words[6] = u64(1)<<13}; words[8] = 0
 } else {
  match index {
   5 {words[0] = 2000} 6 {words[1] = 2000} 7 {words[2] = 2000}
   8 {words[3] = 2000} 9 {words[4] = 2000} 10 {words[5] = 2000}
   11,15,23,25 {for position in 0 .. 3 {words[position] = 2000}}
   24,26 {for position in 3 .. 6 {words[position] = 2000}}
   else {}
  }
  if index in [12,13,14,15] {words[8] = 0}; if index in [16,17,18,19,20,21] {words[6] = u64(1)<<10}
 }
 return words
}
fn check_source(area string,root string) ! {
 before := os.read_file(area+'before-linux_task.v')!; after := os.read_file(area+'after-linux_task.v')!
 old := 'proc.may_inspect_locked(target.process)'; replacement := 'proc.may_inspect_realcreds_locked(target.process)'
 assert before.count(old) == 1 && before.replace(old,replacement) == after
 original := os.read_file(area+'before-inspect.v')!; final := os.read_file(area+'after-inspect.v')!
 mut wanted := original.replace('fn inspection_capable(caller &Process, target &Process, permitted bool)','fn inspection_capable(caller &Process, target &Process)')
 wanted = wanted.replace('\tmask := if permitted { caller.caps.permitted } else { caller.caps.effective }\n\treturn mask & (u64(1) << cap_sys_ptrace) != 0','\t// REALCREDS selects permitted capabilities for the subset check below;\n\t// an active CAP_SYS_PTRACE override always requires the effective set.\n\treturn caller.caps.effective & (u64(1) << cap_sys_ptrace) != 0')
 wanted = wanted.replace('inspection_capable(caller, target, real_creds)','inspection_capable(caller, target)')
 helper := definition(final,'pub fn may_inspect_realcreds_locked(')
 assert helper == 'pub fn may_inspect_realcreds_locked(target &Process) bool {\n\tif target == unsafe { nil } {\n\t\treturn false\n\t}\n\tcurrent := current_thread().process\n\treturn inspection_allowed(current, target, true)\n}'
 addition := '// get_robust_list uses READ_REALCREDS, as process_vm_* does. The caller holds\n// the process table lock through the credential check and scalar snapshot.\n'+helper+'\n\n'
 assert final.count(addition) == 1 && wanted == final.replace(addition,'')
 for suffix in ['arm','x86'] {for path in ['kernel/userland/linux_task.v','kernel/proc/inspect.v'] {assert digest(root+path) == digest(area+'kernel-'+suffix+'/'+path) && digest(root+path) == digest(area+'after-'+os.file_name(path))}}
}
fn check_c(area string,suffix string) ! {
 before := os.read_file(area+'before-'+suffix+'.c')!; after := os.read_file(area+'after-'+suffix+'.c')!
 old_capable := body(before,'proc__inspection_capable'); new_capable := body(after,'proc__inspection_capable')
 old_select := '\tu64 __if_val_0 = {0};\n\tif (permitted) {\n\t\t__if_val_0 = caller->caps.permitted;\n\t} else {\n\t\t__if_val_0 = caller->caps.effective;\n\t}\n\tu64 mask = __if_val_0;\n'
 assert old_capable.count(old_select) == 1 && old_capable.count('(mask &') == 1
 assert old_capable.replace(', bool permitted)',')').replace(old_select,'').replace('(mask &','(caller->caps.effective &') == new_capable
 old_allowed := body(before,'proc__inspection_allowed'); new_allowed := body(after,'proc__inspection_allowed')
 assert old_allowed.replace('proc__inspection_capable(caller, target, real_creds)','proc__inspection_capable(caller, target)') == new_allowed
 old_get := body(before,'userland__syscall_get_robust_list'); new_get := body(after,'userland__syscall_get_robust_list')
 assert old_get.replace('proc__may_inspect_locked(target->process)','proc__may_inspect_realcreds_locked(target->process)') == new_get
 helper := body(after,'proc__may_inspect_realcreds_locked')
 assert helper == body(before,'proc__may_inspect_locked').replace('proc__may_inspect_locked','proc__may_inspect_realcreds_locked').replace('current, target, false','current, target, true')
 previous := 'bool proc__inspection_capable(proc__Process* caller, proc__Process* target, bool permitted);'
 replacement := 'bool proc__inspection_capable(proc__Process* caller, proc__Process* target);'
 declaration := 'bool proc__may_inspect_realcreds_locked(proc__Process* target);\n'
 assert before.count(previous) == 1 && after.count(declaration) == 1
 assert before.replace(old_capable,'').replace(old_allowed,'').replace(old_get,'').replace(previous,replacement) == after.replace(new_capable,'').replace(new_allowed,'').replace(new_get,'').replace(helper+'\n','').replace(declaration,''),'Exact whole-C inspection helper/call scope without normalization'
 for token in ['malloc(','calloc(','realloc(','memdup(','array__','free(','alloca(','vinix_stack_alloc(','pin_process(','unpin_process(','copy_from_user(','copy_to_user('] {
  assert old_capable.count(token) == new_capable.count(token) && old_allowed.count(token) == new_allowed.count(token) && old_get.count(token) == new_get.count(token) && helper.count(token) == 0,token
 }
}
fn sdk_and_primary(area string,out string) ! {
 sdk := object(area+'sdk-inputs.json')!; prior := object('/Users/alex/.cache/vinix-linux-compat/robustwake-20261015/sdk-inputs.json')!; assert sdk.len == 2014 && prior.len == sdk.len
 mut found := map[string]bool{}
 for path in os.walk_ext(area+'sdk','') {assert os.inode(path).typ == .regular; local := path.all_after(area+'sdk/'); assert local in sdk && local !in found; found[local] = true}
 assert found.len == sdk.len
 for path,hash in sdk {assert hash.str() == prior[path]!.str() && digest(area+'sdk/'+path) == hash.str(),path}
 for state in ['p1-before-arm/robustcreds','p1-after-arm/robustcreds','p1-after-arm/runtime','p1-after-arm/robustwake','p1-reference-arm'] {for file in ['fixture.o','serial.o','init'] {
  driver := object(area+'states/'+state+'/'+file+'.compiler.json')!; assert driver['status']!.str() == '0' && driver['output']!.str() == ''
  assert driver['arguments']!.str().contains('--gcc-install-dir='+area.trim_right('/')+'/sdk/usr/lib/gcc/aarch64-alpine-linux-musl/14.2.0') && driver['arguments']!.str().contains('--target=aarch64-linux-musl') && driver['arguments']!.str().contains('--sysroot='+area.trim_right('/')+'/sdk')
 }}
 for name in ['sdk-inputs.json','linux-source.json'] {publish(area+name,out+'robustcreds-'+name)!}
}
fn diagnostics(area string,out string) ! {
 mut pins := map[string]string{}
 source_pins := object(area+'linux-source.json')!; assert source_pins.len == 3
 for name,path in {'syscalls':'kernel/futex/syscalls.c','ptrace':'kernel/ptrace.c','commoncap':'security/commoncap.c'} {
  file := area+'linux-'+name+'-v6.12.c'; assert source_pins[name]!.str() == digest(file)+' https://kernel.googlesource.com/pub/scm/linux/kernel/git/torvalds/linux/+/refs/tags/v6.12/'+path+'?format=TEXT'
  pins[file] = digest(file); pins[area+'linux-'+name+'-download.log'] = digest(area+'linux-'+name+'-download.log')
 }
 assert os.read_file(area+'linux-syscalls-v6.12.c')!.contains('ptrace_may_access(p, PTRACE_MODE_READ_REALCREDS)')
 assert os.read_file(area+'linux-ptrace-v6.12.c')!.contains('caller_uid = cred->uid;') && os.read_file(area+'linux-commoncap-v6.12.c')!.contains('caller_caps = &cred->cap_permitted;') && os.read_file(area+'linux-commoncap-v6.12.c')!.contains('return cap_raised(cred->cap_effective, cap) ? 0 : -EPERM;')
 assert os.read_file(area+'preflight-initial-refusal.log')!.contains("fatal error: 'linux/capability.h' file not found") && !os.exists(area+'states/preflight-arm/init')
 first := os.read_file(area+'initial-probe.v')!; final := os.read_file('/Users/alex/code/vinix/tests/linux-compat/robustcredsfixture/core.v')!
 mut corrected := first.replace('#include <linux/capability.h>\n','').replace('@[typedef]\nstruct C.__user_cap_header_struct','struct CapHeader').replace('@[typedef]\nstruct C.__user_cap_data_struct','struct CapData').replace('C.__user_cap_header_struct','CapHeader').replace('C.__user_cap_data_struct','CapData')
 corrected = corrected.replace('fn profile(index i32,base u32,caller bool) Credentials {','fn profile(index i32,base u32,caller bool) Credentials {\n unsafe {').replace(' return result\n}\nfn observe',' return result\n }\n}\nfn observe'); assert corrected == final
 assert os.read_file(area+'states/preflight-arm/fixture.c')!.contains('v_fixed_index(')
 assert os.read_file(area+'preflight-p2.log')!.contains('Probe compiler preflight: PASS') && digest(area+'states/preflight-p2-arm/fixture.c') == digest(area+'states/p1-before-arm/robustcreds/fixture.c')
 for name in ['preflight-arm','preflight-p2-arm'] {for file in os.walk_ext(area+'states/'+name,'') {if os.inode(file).typ == .regular {pins[file] = digest(file)}}}
 for name in ['setup.v','setup.log','setup-initial-refusal.log','initial-probe.v','finish.v','finish.log','fix-preflight.v','preflight.v','preflight-p2.v','preflight-initial-refusal.log','preflight-p2.log','pipeline.v','pipeline','pipeline-producer.log','watch.v','watch','manage.v','manage','fetch.v','fetch.log','create-audit.v','contracts.txt'] {pins[area+name] = digest(area+name)}
 for name in ['initial-probe.v','setup-initial-refusal.log','preflight-initial-refusal.log','preflight-p2.log','fetch.log'] {publish(area+name,out+'robustcreds-'+name)!}
 data := json2.encode(pins,prettify:true)+'\n'; if os.exists(area+'diagnostic-pins.json') {assert os.read_file(area+'diagnostic-pins.json')! == data} else {os.write_file(area+'diagnostic-pins.json',data)!}
 publish(area+'diagnostic-pins.json',out+'robustcreds-diagnostic-pins.json')!
}
