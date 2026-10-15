// Compile without -prod: both deliberately failing controls must execute.
import crypto.sha256
import encoding.base64
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
 for row in log.split_into_lines().filter(it.starts_with('LINUX TIDFAULT SLAB:') || it.starts_with('LINUX TIDFAULT STORAGE:')) {
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
	assert log.contains('LINUX TIDFAULT DETAIL:'), 'tidfault baseline failure markers required'
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
		'wrapper_source':    state + '/source/tidfaultreferenceinit/core.v'
		'wrapper_c':         state + '/fixture.c'
		'wrapper_elf':       state + '/init'
		'initramfs':         state + '/initramfs.cpio'
		'serial':            state + '/serial.log'
		'serial_adapter_c':  state + '/serial.c'
		'controller_source': '/Users/alex/code/vinix/tests/linux-compat/tidfault-reference.v'
		'qemu':              command[0]
	} {
		assert artifacts[label] == digest(path)
	}
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/tidfaultreferenceinit/core.v')
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
		println('Native clear-child-tid fault source/C scope: PASS')
		return
	}
	if '--negative-control' in os.args {
		assert false, 'tidfault assertions must execute'
		return
	}
	if '--negative-pass-control' in os.args {
		failure(os.read_file(os.args[2])!, os.args[3])
		return
	}
	assert os.args.len == 2, 'Usage: tidfault-check.v EVIDENCE-AREA (compile without -prod)'
	area := os.args[1].trim_right('/') + '/'
	states := area + 'states/'
	root := '/Users/alex/code/vinix/'
	out := root + 'tests/linux-compat/results/2026-10-15/'
	os.mkdir_all(out)!
	sdk_and_primary(area, out)!
	diagnostics(area,out)!
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'tidfault assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control',
		states + 'p1-reference-arm/serial.log', 'aarch64'], 'tidfault baseline failure markers required'))!
	check_source(area, root)!
	for suffix in ['arm', 'x86'] { check_c(area, suffix)! }
	os.write_file(area+'scope-check.log','arm/x86: exact whole production C differs only in clear_child_tid failed-store admission and two synchronous stack mapping-capability receivers replacing measured 16-byte memdup boxes; first correction changes only clear_child_tid. Successful-store path, pointer retirement, locks, owners, refs, release and wake count unchanged. New scalar Option temporaries and borrowed interface stack values; no new allocation/free/pin/stack promotion or normalization\n')!
	base := os.read_file(area + 'base.txt')!.trim_space()
	assert base == 'c39a5ef38d7652f276619cf9073970ca1969e342'
	compiler_root := '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/'
	pins := object(compiler_root + 'compiler-inputs.json')!
	assert pins.len == 15146
	assert pins['v']!.str() == '9e506a9fbd95e2e7c227cc144da023b57a288d0974ea902f1d12270e28bc416b'
	for path, hash in pins {
		assert digest(compiler_root + 'compiler/' + path) == hash.str(), path
	}
	assert os.read_file(area + 'host-tests.log')!.contains('8 passed, 8 total')
	assert os.read_file(area + 'p2-coverage-check.log')!.count('Linux dispatch coverage: PASS') == 4
	before_alloc := os.read_file(area + 'allocs-before.log')!
	after_alloc := os.read_file(area + 'p2-allocs-after.log')!
	assert before_alloc == after_alloc, 'Allocation diagnostics must remain byte-identical'
	for arch, count in {
		'aarch64': '398'
		'x86_64':  '290'
	} {
		assert before_alloc.split_into_lines().filter(it.starts_with(arch + ':')).len == 1
		assert before_alloc.contains(count + ' allocation sites (V exit 0)') && before_alloc.contains('NEW:')
	}
	assert os.read_file(area + 'coverage-before-check.log')!.count('Linux dispatch coverage: PASS') == 4
	assert os.read_file(area + 'watch-final.log')!.split_into_lines().filter(it.starts_with('Completed ')).len == 8
	retained := object(area + 'watch-final-retained-inputs.json')!
	assert retained.len == 84
	for path, hash in retained {
		assert path.starts_with(states + 'p1-before-arm/') || path.starts_with(states + 'p1-before-x86/') || path.starts_with(states + 'p2-after-arm/') || path.starts_with(states+'p2-after-x86/')
		assert !path.contains('/iso-build/') && !path.ends_with('/efivars.fd')
		assert os.inode(path).typ == .regular && digest(path) == hash.str(), path
	}
	mut walked := map[string]bool{}
	mut completed := map[string]bool{}
	for suffix in ['arm', 'x86'] {
		for phase in ['before', 'after'] {
			names := if phase == 'before' {
				['tidfault']
			} else {
				['tidfault', 'runtime', 'tidwake']
			}
			for name in names {
				probe := states + (if phase == 'before' {'p1-'} else {'p2-'}) + phase + '-' + suffix + '/' + name
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
	for row in os.read_file(area + 'watch-final.log')!.split_into_lines() {
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
		assert git(tree, ['diff', '--name-only', 'HEAD', '--', 'kernel'])! == 'kernel/resource/cache.v\nkernel/userland/linux_task.v'
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
            'mapping_source_before': digest(area+'before-cache.v')
            'mapping_source_after': digest(area+'after-cache.v')
            'first_corrected_c': digest(area+'p1-after-'+suffix+'.c')
			'fixture_source':           digest(root + 'tests/linux-compat/tidfaultfixture/core.v')
			'audit_source':             digest(@FILE)
			'linux_primary_source':     digest(area + 'linux-fork-v6.12.c')
			'linux_primary_pin':        digest(area + 'linux-source.json')
			'private_sdk': digest(area + 'sdk-inputs.json')
			'sdk_prior_inputs': digest('/Users/alex/.cache/vinix-linux-compat/tidwake-20261015/sdk-inputs.json')
			'arm_compiler_adapter': digest(area + 'arm-cc.v')
			'arm_compiler_adapter_binary': digest(area + 'arm-cc')
			'prior_diagnostics': digest(area + 'diagnostic-pins.json')
			'scope_contract': digest(area + 'scope-check.log')
			'native_controller':        digest(area + 'run')
			'native_controller_source': digest(root + 'tests/linux-compat/run.v')
			'reference_controller':     digest(area + 'reference')
			'watch_pins':               digest(area + 'watch-final-retained-inputs.json')
			'watch_log':                digest(area + 'watch-final.log')
		}
		for name in ['manage.v', 'manage', 'watch.v', 'watch', 'coverage-before-check.log', 'coverage-before-arm.json', 'coverage-before-x86.json'] {
			artifacts[name] = digest(area + name)
		}
		mut identity := map[string]string{}
		for phase in ['before', 'after'] {
			state := states + (if phase == 'before' {'p1-'} else {'p2-'}) + phase + '-' + suffix
			kernel := area + if phase == 'before' { 'baseline-' } else { 'kernel-' } + suffix + '/kernel/bin/vinix'
			names := if phase == 'before' {
				['tidfault']
			} else {
				['tidfault', 'runtime', 'tidwake']
			}
			captured := receipt(state, arch, digest(kernel), names, phase == 'before')!
			for key, value in captured { artifacts[phase + '_' + key] = value }
			for key in ['tidfault_source', 'tidfault_init', 'tidfault_c'] {
				if phase == 'before' {
					identity[key] = captured[key]
				} else {
					assert identity[key] == captured[key]
				}
			}
			text := os.read_file(state + '/tidfault/serial.log')!
			semantics(text, phase, arch, false)
			storage(text, arch, phase)
			build := area + (if phase == 'before' {'build-'} else {'p2-build-'}) + phase + '-' + suffix + '.log'
			text_build := os.read_file(build)!
			assert text_build.contains('-o bin/vinix') && !text_build.contains('Nothing to be done') && !text_build.contains('Error ')
			producer := area + if phase == 'before' { 'initial-build-' + suffix + '-before.log' } else { 'p2-build-' + suffix + '-producer.log' }
			assert os.read_file(producer)!.trim_space() == suffix + ' ' + phase + ' production build: PASS'
			artifacts[phase + '_build_producer'] = digest(producer)
			artifacts[phase + '_kernel'] = digest(kernel)
			artifacts[phase + '_kernel_c'] = digest(area + (if phase == 'before' {''} else {'p2-'}) + phase + '-' + suffix + '.c')
			artifacts[phase + '_build'] = digest(build)
			for label, path in {
				'receipt':   state + '/receipt.json'
				'aggregate': state + '.log'
				'native':    state + '/tidfault/serial.log'
				'build':     build
			} {
				publish(path, out + 'tidfault-' + phase + '-' + arch + '-' + label + if label == 'receipt' {
					'.json'
				} else {
					'.log'
				})!
			}
			if phase == 'after' {
				for name in names {
					if name == 'tidfault' { continue }
					publish(state + '/' + name + '/serial.log', out + 'tidfault-regression-' + arch + '-' + name + '.log')!
				}
			}
		}
		probe := states + 'p1-before-' + suffix + '/tidfault'
		raw := os.read_file(probe + '/fixture.c')!
		assert raw.count('alloca(') == 14
		for token in ['malloc(', 'calloc(', 'realloc(', 'memdup(', 'array_push(', 'array_get(',
			'v_fixed_index('] {
			assert !raw.contains(token)
		}
		reference := states + 'p1-reference-' + suffix
		linux := reference_receipt(reference, arch, identity['tidfault_init'])!
		for key, value in linux { artifacts['reference_' + key] = value }
		for label, path in {
			'receipt':   reference + '/receipt.json'
			'aggregate': reference + '.log'
			'native':    reference + '/serial.log'
		} {
			publish(path, out + 'tidfault-reference-' + arch + '-' + label + if label == 'receipt' {
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
		os.write_file(out + 'tidfault-evidence-' + arch + '.json', json2.encode(Evidence{
			architecture:  arch
			context: 'Native clear-child-tid store-fault notifications:384 controls per architecture, originals128 failures, corrected and identical-ELF Linux6.12.51 zero. Four root/UID1000 initial/one-level PID namespace cohorts exercise shared read-only direct/alias, writable, PROT_NONE, unmapped and private read-only anonymous registrations; actual self process_vm read/write results independently check established permissions. Four initial words, two aligned offsets including native page tail, proven one/three shared queues, private/neighbor isolation, worker ESRCH while conductor leader remains alive, restored permissions before exact drains, and complete two-page conductor/parent alias canaries. Raw worker exit bypasses libc teardown after replacing its clear-tid pointer; it is not joined through musl, and conductor exit/reap retires its complete image. Four96-warmup/200-cycle cohorts measure complete cleanup with three shared waiters per trial, including partial-queue drain. Six fresh production builds, runtime/tidwake regressions, unchanged allocation diagnostics,67 inventory/2014 SDK/15146 compiler pins, fifteen final ARM command receipts,84 retained native case files, exact three-function whole-C scope and executing audit negative controls. Initial corrected cleanup refuses 64 retained size16 objects per cohort; an independent tracking kernel names96 receiver boxes each at resource.reserve_shared_mapping and resource.lazy_shared_mapping after600 trials. Reviewed synchronous stack receivers remove those two hidden memdup calls without changing the probe workload. The failed profiles and both tracking setups remain pinned. Last-map-user behavior, private-file keys, anonymous shared backings, unaligned/cross-page stores, concurrent mapping/credential changes, exec/forced sibling exit, GNU/foreign paths and the three broad roadmap gates remain separate.'
			base_commit:   base
			artifacts:     artifacts
			source_inputs: inputs
		},
			prettify: true
		) + '\n')!
	}
	for name in ['host-tests.log', 'allocs-before.log', 'allocs-after.log', 'coverage-check.log',
		'scope-check.log', 'assertion-control.log', 'passing-log-control.log', 'watch-final.log',
		'coverage-before-check.log'] {
		publish(area + name, out + 'tidfault-' + name)!
	}
	publish(area + 'watch-final-retained-inputs.json', out + 'tidfault-watch-retained-inputs.json')!
	os.write_file(area + 'audit.log', 'Native tidfault conformance audit: PASS\n')!
	publish(area + 'audit.log', out + 'tidfault-audit.log')!
	println('Native tidfault conformance audit: PASS')
}




















fn semantics(log string,phase string,arch string,reference bool) {
 assert phase in ['before','after','failed-storage'] && arch in ['aarch64','x86_64']
 mut seen := map[string]bool{}
 topology := log.split_into_lines().filter(it.starts_with('LINUX TIDFAULT TOPOLOGY:')); assert topology.len == 4
 for row in topology {
  f := row.fields(); assert f.len == 14 && f[3] in ['ordinary=0','ordinary=1'] && f[4] in ['namespace=0','namespace=1']; key := f[3]+f[4]; assert key !in seen; seen[key] = true
  assert f[5].starts_with('self=') && f[6].starts_with('child=') && f[7].starts_with('worker=')
  self := f[5].all_after('=').int(); child := f[6].all_after('=').int(); worker := f[7].all_after('=').int(); assert self > 1 && child > 1 && worker > 1 && self != child && child != worker && worker != self
  if f[4] == 'namespace=1' {assert self == 2}; assert f[8] == 'uid='+if f[3] == 'ordinary=1' {'1000'} else {'0'}
  assert f[9..] == ['leader_alive=1','observed_ESRCH=1','queued=3','private=1','neighbor=1']
 }
 cohorts := log.split_into_lines().filter(it.starts_with('LINUX TIDFAULT COHORT:')); assert cohorts.len == 4; seen.clear()
 for row in cohorts {
  f := row.fields(); assert f.len == 12 && f[3] in ['ordinary=0','ordinary=1'] && f[4] in ['namespace=0','namespace=1']; key := f[3]+f[4]; assert key !in seen; seen[key] = true
  assert f[5].starts_with('self=') && f[5].all_after('=').int() > 1; if f[4] == 'namespace=1' {assert f[5] == 'self=2'}
  assert f[6] == 'uid='+if f[3] == 'ordinary=1' {'1000'} else {'0'}; assert f[7] == 'page='+if arch == 'aarch64' && !reference {'16384'} else {'4096'}
  assert f[8..] == ['raw=96','classes=6','access_checks=192','measured_shared=3']
 }
 access_rows := log.split_into_lines().filter(it.starts_with('LINUX TIDFAULT ACCESS:')); assert access_rows.len == 384; seen.clear()
 for row in access_rows {
  f := row.fields(); assert f.len == 10 && f[3] in ['ordinary=0','ordinary=1'] && f[4] in ['namespace=0','namespace=1'] && f[5].starts_with('kind=') && f[6].starts_with('index=')
  index := f[6].all_after('=').int(); class := index/16; assert index >= 0 && index < 96 && f[5] == 'kind='+class.str()
  key := f[3]+f[4]+f[6]; assert key !in seen; seen[key] = true
  assert f[7] == 'read='+if class in [3,4] {'-1/14'} else {'1/0'}
  assert f[8] == 'write='+if class == 2 {'1/0'} else {'-1/14'}; assert f[9] == 'guarded=1'
 }
 mut local := map[string]string{}
 for label in ['CASES:','FINAL:'] {
  rows := log.split_into_lines().filter(it.starts_with('LINUX TIDFAULT '+label)); assert rows.len == 24; seen.clear(); mut calls := 0; mut failures := 0
  for row in rows {
   f := row.fields(); assert f.len == 8 && f[3] in ['ordinary=0','ordinary=1'] && f[4] in ['namespace=0','namespace=1'] && f[5] in ['kind=0','kind=1','kind=2','kind=3','kind=4','kind=5']
   key := f[3]+f[4]+f[5]; assert key !in seen; seen[key] = true; kind := f[5].all_after('=').int(); assert f[6] == 'calls=16' && f[7].starts_with('failures='); bad := f[7].all_after('=').int()
   assert bad == if phase == 'before' {[16,16,0,0,0,0]![kind]} else {0}
   if label == 'CASES:' {local[key] = f[6]+f[7]} else {assert local[key] == f[6]+f[7]}; calls += 16; failures += bad
  }
  assert calls == 384 && failures == if phase == 'before' {128} else {0}
 }
 if phase == 'before' {assert log.contains('LINUX TIDFAULT DETAIL:') && log.contains('LINUX TIDFAULT FAIL:') && !log.contains('LINUX TIDFAULT: PASS')}
 else if phase == 'failed-storage' {assert !log.contains('LINUX TIDFAULT DETAIL:') && log.count('LINUX TIDFAULT FAIL: clear-child-tid store-fault notification, permissions, queue counts or retained storage') == 1 && !log.contains('LINUX TIDFAULT: PASS')}
 else {assert !log.contains('LINUX TIDFAULT DETAIL:') && !log.contains('LINUX TIDFAULT FAIL:')}
 if reference {assert log.contains('Linux version 6.12.51-0-virt') && log.contains('LINUX TIDFAULT REFERENCE: PASS') && !log.contains('LINUX TIDFAULT STORAGE:')}
 else if phase == 'after' {assert log.count('LINUX TIDFAULT: PASS') == 1}
 assert !log.contains('Kernel panic') && !log.contains('setup stage=')
}
fn check_source(area string,root string) ! {
 before := os.read_file(area+'before-linux_task.v')!; after := os.read_file(area+'after-linux_task.v')!
 old := '\tif !usercopy.copy_to_user(address, voidptr(&zero), sizeof(u32)) {\n\t\treturn\n\t}'
 replacement := '\tif !usercopy.copy_to_user(address, voidptr(&zero), sizeof(u32)) {\n\t\t// Linux still tries the shared wake after a failed store. A readable\n\t\t// shared mapping can supply its key; a read-only private anonymous\n\t\t// word cannot. Keep inaccessible or absent mappings out of the wake.\n\t\tif !mmap.is_shared_address(t.process.pagemap, address) { return }\n\t\tusercopy.read_u32(address) or { return }\n\t}'
 assert before.count(old) == 1 && before.replace('import katomic\n','import katomic\nimport memory.mmap\n').replace(old,replacement) == after
 base := os.read_file(area+'base.txt')!.trim_space()
 for suffix in ['arm','x86'] {tree := area+'kernel-'+suffix; assert git(tree,['show',base+':kernel/userland/linux_task.v'])!.trim_space() == before.trim_space(); assert digest(tree+'/kernel/userland/linux_task.v') == digest(area+'after-linux_task.v') && digest(root+'kernel/userland/linux_task.v') == digest(area+'after-linux_task.v')}
 check_mapping_source(area,root)!
}
fn check_mapping_source(area string,root string) ! {
 before := os.read_file(area+'before-cache.v')!; after := os.read_file(area+'after-cache.v')!
 mut expected := before
 for name,capability in {'reserve_shared_mapping':'ReservableMapping','lazy_shared_mapping':'LazySharedMapping'} {
  arguments := if name == 'lazy_shared_mapping' {''} else {'offset, length'}
  old := '\t\treturn res.'+name+'('+arguments+')'
  new := '\t\tmut backend := '+capability+'(res)\n\t\tmut stack := unsafe { &backend }\n\t\treturn stack.'+name+'('+arguments+')'
  assert expected.count(old) == 1; expected = expected.replace(old,new)
 }
 assert expected == after && digest(root+'kernel/resource/cache.v') == digest(area+'after-cache.v')
 base := os.read_file(area+'base.txt')!.trim_space()
 for suffix in ['arm','x86'] {tree := area+'kernel-'+suffix; assert git(tree,['show',base+':kernel/resource/cache.v'])!.trim_space() == before.trim_space() && digest(tree+'/kernel/resource/cache.v') == digest(area+'after-cache.v')}
}
fn check_c(area string,suffix string) ! {
 before := os.read_file(area+'before-'+suffix+'.c')!; after := os.read_file(area+'p2-after-'+suffix+'.c')!; first := os.read_file(area+'p1-after-'+suffix+'.c')!
 old := body(before,'userland__clear_child_tid'); new := body(after,'userland__clear_child_tid')
 original_branch := '\tif (!usercopy__copy_to_user(address, (void*)(&zero), sizeof(u32))) {\n\t\treturn;\n\t}'
 // Check the exact scalar-only replacement and the rest of each complete
 // production translation unit without normalizing generated C.
 expected_branch := '\tif (!usercopy__copy_to_user(address, (void*)(&zero), sizeof(u32))) {\n\t\tif (!mmap__is_shared_address(t->process->pagemap, address)) {\n\t\t\treturn;\n\t\t}\n\t\t__v_option_u32 __or_opt_0 = usercopy__read_u32(address);\n\t\tif (!__or_opt_0.ok) {\n\t\t\treturn;\n\t\t}\n\t}'
 assert old.count(original_branch) == 1 && old.replace(original_branch,expected_branch) == new
 first_matches := before.replace(old,'') == first.replace(body(first,'userland__clear_child_tid'),''); assert first_matches,'First correction changes only failed-store admission'
 mut rest_before := before.replace(old,''); mut rest_after := after.replace(new,'')
 for method,capability in {'lazy_shared_mapping':'LazySharedMapping','reserve_shared_mapping':'ReservableMapping'} {
  name := 'resource__'+method; original := body(before,name); revised := body(after,name); assert body(first,name) == original
  arguments := if method == 'lazy_shared_mapping' {''} else {', offset, length'}
  boxed := '\t\tresource__'+capability+' __iface_box_1 = __iface_cast_0;\n\t\treturn resource__'+capability+'__'+method+'((resource__'+capability+'*)(memdup(&__iface_box_1, sizeof(resource__'+capability+')))'+arguments+');'
  stack := '\t\tresource__'+capability+' backend = __iface_cast_0;\n\t\tresource__'+capability+'* stack = &backend;\n\t\treturn resource__'+capability+'__'+method+'((stack)'+arguments+');'
  assert original.count(boxed) == 1 && original.replace(boxed,stack) == revised && !revised.contains('memdup(')
  rest_before = rest_before.replace(original,''); rest_after = rest_after.replace(revised,'')
 }
 matches := rest_before == rest_after; assert matches,'Exact whole production C differs only in failed-store admission and two stack interface receivers; no normalization'
 for token in ['malloc(','calloc(','realloc(','memdup(','array__','free(','alloca(','vinix_stack_alloc(','pin_process(','unpin_process(','copy_to_user('] {assert old.count(token) == new.count(token),token}
 assert new.count('mmap__is_shared_address(') == 1 && new.count('usercopy__read_u32(') == 1 && new.count('futex__wake_n_key(address, 1, false)') == 1
}
fn sdk_and_primary(area string,out string) ! {
 sdk := object(area+'sdk-inputs.json')!; prior := object('/Users/alex/.cache/vinix-linux-compat/tidwake-20261015/sdk-inputs.json')!; assert sdk.len == 2014 && prior.len == sdk.len
 mut found := map[string]bool{}
 for path in os.walk_ext(area+'sdk','') {assert os.inode(path).typ == .regular; local := path.all_after(area+'sdk/'); assert local in sdk && local !in found; found[local] = true}; assert found.len == sdk.len
 for path,hash in sdk {assert hash.str() == prior[path]!.str() && digest(area+'sdk/'+path) == hash.str(),path}
 for state in ['p1-before-arm/tidfault','p2-after-arm/tidfault','p2-after-arm/runtime','p2-after-arm/tidwake','p1-reference-arm'] {for file in ['fixture.o','serial.o','init'] {driver := object(area+'states/'+state+'/'+file+'.compiler.json')!; assert driver['status']!.str() == '0' && driver['output']!.str() == ''; assert driver['arguments']!.str().contains('--gcc-install-dir='+area.trim_right('/')+'/sdk/usr/lib/gcc/aarch64-alpine-linux-musl/14.2.0') && driver['arguments']!.str().contains('--target=aarch64-linux-musl') && driver['arguments']!.str().contains('--sysroot='+area.trim_right('/')+'/sdk')}}
 primary := object(area+'linux-source.json')!; assert primary.len == 3
 for name,path in {'fork':'kernel/fork.c','core':'kernel/futex/core.c','waitwake':'kernel/futex/waitwake.c'} {file := area+'linux-'+name+'-v6.12.c'; assert primary[name]!.str() == digest(file)+' https://kernel.googlesource.com/pub/scm/linux/kernel/git/torvalds/linux/+/refs/tags/v6.12/'+path+'?format=TEXT'; assert base64.decode_str(os.read_file(area+'linux-'+name+'-v6.12.base64')!) == os.read_file(file)!}
 assert os.read_file(area+'linux-fork-v6.12.c')!.contains('put_user(0, tsk->clear_child_tid);') && os.read_file(area+'linux-waitwake-v6.12.c')!.contains('get_futex_key(uaddr, flags, &key, FUTEX_READ)') && os.read_file(area+'linux-core-v6.12.c')!.contains('A RO anonymous page will never change')
 for name in ['sdk-inputs.json','linux-source.json'] {publish(area+name,out+'tidfault-'+name)!}
}
fn diagnostics(area string,out string) ! {
 mut pins := map[string]string{}
 assert os.read_file(area+'helper-preflight.log')!.contains('Probe compiler preflight: PASS') && digest(area+'states/preflight-arm/fixture.c') == digest(area+'states/p1-before-arm/tidfault/fixture.c')
 assert os.read_file(area+'preflight-producer.log')!.trim_space() == 'preflight: PASS'
 assert os.read_file(area+'pipeline-producer.log')!.contains('All clear-child-tid qualification producers launched') && os.read_file(area+'p2-launch-producer.log')!.trim_space() == 'Final corrected production/guest/diagnostic jobs launched' && os.read_file(area+'watch-final-producer.log')!.count('Retired completed boot staging:') == 8
 failed_storage(area,out,mut pins)!
 assert os.read_file(area+'fetch.log')!.trim_space() == 'Tagged Linux fork/futex source contracts: PASS'
 assert os.read_file(area+'preaudit-contracts.log')!.trim_space() == 'Preserved storage failure and allocation-site contracts: PASS'
 assert os.read_file(area+'preaudit-refused-compile.log')!.contains('qualification_main') && os.read_file(area+'preaudit-refused-compile.log')!.contains('must return a Result')
 for name in ['preaudit.v','run-preaudit.v','run-preaudit','preaudit-producer.log','failed-audit.v','failed-audit-refused.v','failed-audit','preaudit-contracts.log','preaudit-corrected-compile.log','preaudit-refused-compile.log','scope-final-producer.log','p2-allocs-after.log','p2-coverage-check.log'] {pins[area+name] = digest(area+name)}
 for path in os.walk_ext(area+'states/preflight-arm','') {if os.inode(path).typ == .regular {pins[path] = digest(path)}}
 for name in ['setup.v','setup.log','probe-body.txt','launch-work.v','launch-work','preflight.v','preflight','preflight-producer.log','helper-preflight.log','pipeline.v','pipeline','pipeline-producer.log','fetch.v','fetch.log','linux-fork-v6.12.c','linux-fork-v6.12.base64','linux-core-v6.12.c','linux-core-v6.12.base64','linux-waitwake-v6.12.c','linux-waitwake-v6.12.base64','create-audit.v','contracts.txt','upgrade-audit.v','manage.v','manage','watch.v','watch','helper-watch.log','watch-producer.log','native-arm-before-producer.log','native-x86-before-producer.log','native-arm-after-producer.log','native-x86-after-producer.log','reference-arm-producer.log','reference-x86-producer.log','p2-setup.v','p2-launch.v','p2-launch','p2-launch-producer.log','manage-p2.v','manage-p2','rescan-final.v','rescan-final','rescan-final-producer.log','coverage-final.v','coverage-final','coverage-final-producer.log','watch-final.v','watch-final','watch-final-producer.log','native-arm-p2-after-producer.log','native-x86-p2-after-producer.log','before-cache.v','after-cache.v','lifetime-review.txt'] {pins[area+name] = digest(area+name)}
 data := json2.encode(pins,prettify:true)+'\n'; if os.exists(area+'diagnostic-pins.json') {assert os.read_file(area+'diagnostic-pins.json')! == data} else {os.write_file(area+'diagnostic-pins.json',data)!}
 publish(area+'diagnostic-pins.json',out+'tidfault-diagnostic-pins.json')!; for name in ['fetch.log','helper-preflight.log'] {publish(area+name,out+'tidfault-'+name)!}
}
fn failed_storage(area string,out string,mut pins map[string]string) ! {
 retained := object(area+'watch-failed-retained-inputs.json')!; assert retained.len == 84
 for path,hash in retained {assert os.inode(path).typ == .regular && digest(path) == hash.str(); pins[path] = hash.str()}
 assert os.read_file(area+'watch-failed-producer.log')!.count('Retired completed boot staging:') == 8
 assert os.read_file(area+'watch-producer.log')!.contains('assert code.int() ==')
 for arch,suffix in {'aarch64':'arm','x86_64':'x86'} {
  state := area+'states/p1-after-'+suffix; kernel := area+'p1-corrected-'+suffix+'/kernel/bin/vinix'; pins[kernel] = digest(kernel)
  receipt(state,arch,digest(kernel),['tidfault','runtime','tidwake'],true)!
  log := os.read_file(state+'/tidfault/serial.log')!; semantics(log,'failed-storage',arch,false)
  mut slabs := [4]int{}; mut pages := [4]int{}; mut seen := map[string]bool{}
  for row in log.split_into_lines().filter(it.starts_with('LINUX TIDFAULT SLAB:') || it.starts_with('LINUX TIDFAULT STORAGE:')) {
   f := row.fields(); assert f.len == 8 && f[3] in ['ordinary=0','ordinary=1'] && f[4] in ['namespace=0','namespace=1']; cohort := f[3].all_after('=').int()+2*f[4].all_after('=').int(); pair := f[6].all_after('=').split('/'); assert pair.len == 2 && pair.all(it != '' && it.bytes().all(it.is_digit()))
   key := f[3]+f[4]+f[5]; assert key !in seen; seen[key] = true
   if f[2] == 'SLAB:' {assert f[5].starts_with('size=') && f[7] == 'cycles=200'; size := f[5].all_after('=').int(); assert pair[1].u64()-pair[0].u64() == if size == 16 {u64(64)} else {u64(0)}; slabs[cohort]++}
   else {assert f[5] == 'cycles=200' && f[7] == 'FAIL' && pair[0] == pair[1]; pages[cohort]++}
  }
  for cohort in 0 .. 4 {assert slabs[cohort] == if suffix == 'arm' {18} else {14}; assert pages[cohort] == 1}
  for path in [state+'/receipt.json',state+'.log',area+'p1-after-'+suffix+'.c'] {pins[path] = digest(path)}
  publish(state+'/tidfault/serial.log',out+'tidfault-initial-storage-'+arch+'.log')!
 }
 assert os.read_file(area+'states/track-arm/serial.log')!.contains('LINUX TIDFAULT FAIL: setup stage=27 errno=1')
 track := os.read_file(area+'states/track-retry-arm/serial.log')!; assert track.contains('cycles=600') && track.contains('LINUX TIDFAULT TRACK: DONE') && track.contains('live 197 dropped 0')
 rows := track.split_into_lines().filter(it.fields().len == 12 && it.fields()[0] == '96' && it.fields()[1] == '16'); assert rows.len == 2
 named := os.read_file(area+'track-sites.named')!; assert named.count('tidfault: 96 x 16 bytes') == 2 && named.contains('resource__reserve_shared_mapping <- mmap__mmap_with_credit') && named.contains('resource__lazy_shared_mapping <- mmap__mmap_with_credit')
 assert os.read_file(area+'lifetime-review.txt')!.contains('PASS for the two synchronous stack interface receivers')
 for directory in ['states/track-arm','states/track-retry-arm','track-source','track-retry-source'] {for path in os.walk_ext(area+directory,'') {if os.inode(path).typ == .regular {pins[path] = digest(path)}}}
 for name in ['diagnose.v','diagnose','diagnose-producer.log','diagnose-retry.v','diagnose-retry','diagnose-retry-producer.log','track-build.log','track-kernel.c','name-sites.v','name-sites','track-sites.raw','track-sites.named','retain-failed.v','watch-failed.v','watch-failed','watch-failed.log','watch-failed-retained-inputs.json','watch-failed-producer.log'] {pins[area+name] = digest(area+name)}
 publish(area+'track-sites.named',out+'tidfault-mapping-allocation-sites.log')!
 publish(area+'states/track-retry-arm/serial.log',out+'tidfault-mapping-allocation-track.log')!
 publish(area+'states/track-arm/serial.log',out+'tidfault-initial-track-setup-refusal.log')!
 publish(area+'lifetime-review.txt',out+'tidfault-mapping-lifetime-review.txt')!
}
