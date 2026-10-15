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

fn semantics(log string,phase string,arch string,reference bool) {
 assert phase in ['before','after'] && arch in ['aarch64','x86_64']
 rows := log.split_into_lines().filter(it.starts_with('LINUX WAITUSAGE TOPOLOGY:')); assert rows.len == 32
 mut seen := map[string]bool{}
 for row in rows {
  fields := row.fields(); assert fields.len == 12
  assert fields[3] in ['ordinary=0','ordinary=1'] && fields[4] in ['namespace=0','namespace=1']
  assert fields[5] in ['profile=0','profile=1','profile=2','profile=3'] && fields[6] in ['killed=0','killed=1']
  key := fields[3]+fields[4]+fields[5]+fields[6]; assert key !in seen; seen[key] = true
  for index,prefix in {7:'self=',8:'pid=',9:'real=',10:'effective=',11:'saved='} {assert fields[index].starts_with(prefix)}
  self := fields[7].all_after('=').int(); pid := fields[8].all_after('=').int(); assert self > 1 && pid > 1 && pid != self
  if fields[4] == 'namespace=1' {assert self == 2}
  profile := fields[5].all_after('=').int(); ordinary := fields[3] == 'ordinary=1'
  assert fields[9] == 'real='+if ordinary {'1000'} else {['0','1001','0','4294967294']![profile]}
  assert fields[10] == 'effective='+if ordinary {if profile%2 == 0 {'1000'} else {'1002'}} else {['0','0','1003','1004']![profile]}
  assert fields[11] == 'saved='+if ordinary {'1002'} else {['0','1002','0','0']![profile]}
 }
 mut cases := map[string]string{}
 for label in ['CASES:','FINAL:'] {
  outcomes := log.split_into_lines().filter(it.starts_with('LINUX WAITUSAGE '+label)); assert outcomes.len == 24; seen.clear(); mut calls := 0; mut failures := 0
  for row in outcomes {
   fields := row.fields(); assert fields.len == 8
   assert fields[3] in ['ordinary=0','ordinary=1'] && fields[4] in ['namespace=0','namespace=1'] && fields[5] in ['kind=0','kind=1','kind=2','kind=3','kind=4','kind=5']
   key := fields[3]+fields[4]+fields[5]; assert key !in seen; seen[key] = true
   assert fields[6].starts_with('calls=') && fields[7].starts_with('failures=')
   kind := fields[5].all_after('=').int(); n := fields[6].all_after('=').int(); f := fields[7].all_after('=').int()
   assert n == [12288,15360,9984,27648,6144,6176]![kind]
   assert f == if phase == 'before' {[12288,15360,9984,21504,5376,0]![kind]} else {0}
   if label == 'CASES:' {cases[key] = fields[6]+fields[7]} else {assert cases[key] == fields[6]+fields[7]}
   calls += n; failures += f
  }
  assert calls == 310400 && failures == if phase == 'before' {258048} else {0}
 }
 if phase == 'before' {assert log.contains('LINUX WAITUSAGE DETAIL:') && log.contains('LINUX WAITUSAGE FAIL:') && !log.contains('LINUX WAITUSAGE: PASS')}
 else {assert !log.contains('LINUX WAITUSAGE DETAIL:') && !log.contains('LINUX WAITUSAGE FAIL:')}
 if reference {assert log.contains('Linux version 6.12.51-0-virt') && log.contains('LINUX WAITUSAGE REFERENCE: PASS') && !log.contains('LINUX WAITUSAGE STORAGE:')}
 else if phase == 'after' {assert log.count('LINUX WAITUSAGE: PASS') == 1}
 assert !log.contains('Kernel panic') && !log.contains('setup stage=')
}

fn check_source(area string,root string) ! {
 before := os.read_file(area+'before-linux_task.v')!; after := os.read_file(area+'after-linux_task.v')!
 old := '\tif infop != 0 && !write_waitid_siginfo(infop, unsafe { &info }) {\n\t\tfinish_child_change(mut current_process, change, false)\n\t\treturn errno.err, errno.efault\n\t}\n\tif !write_child_rusage(rusage_ptr, child) {\n\t\tfinish_child_change(mut current_process, change, false)\n\t\treturn errno.err, errno.efault\n\t}'
 new := '\t// Linux copies rusage first: its faults must leave siginfo untouched.\n\tif !write_child_rusage(rusage_ptr, child) {\n\t\tfinish_child_change(mut current_process, change, false)\n\t\treturn errno.err, errno.efault\n\t}\n\tif infop != 0 && !write_waitid_siginfo(infop, unsafe { &info }) {\n\t\tfinish_child_change(mut current_process, change, false)\n\t\treturn errno.err, errno.efault\n\t}'
 assert before.count(old) == 1 && before != after && after == before.replace(old,new),'Only waitid event copyout order changes; claims, pins, credentials, helpers and consumption remain identical'
 assert digest(root+'kernel/userland/linux_task.v') == digest(area+'after-linux_task.v')
 for suffix in ['arm','x86'] {assert digest(area+'kernel-'+suffix+'/kernel/userland/linux_task.v') == digest(area+'after-linux_task.v')}
}

fn body(source string,name string) string {
 rows := source.split_into_lines().filter(it.contains(' '+name+'(') && it.ends_with('{'))
 assert rows.len == 1,name
 return definition(source,'\n'+rows[0])
}
fn check_c(area string,suffix string) ! {
 before := os.read_file(area+'before-'+suffix+'.c')!; after := os.read_file(area+'after-'+suffix+'.c')!
 old := body(before,'userland__syscall_waitid'); new := body(after,'userland__syscall_waitid'); assert old != new
 for token in ['malloc(','calloc(','realloc(','memdup(','array__','free(','alloca(','vinix_stack_alloc(','pin_process(','unpin_process(','finish_child_change(','proc__lock_table(','proc__unlock_table(','userland__write_child_rusage(','userland__write_waitid_siginfo('] {assert old.count(token) == new.count(token),token}
 old_info := old.index('userland__write_waitid_siginfo(') or {panic('missing original siginfo copy')}
 old_usage := old.index('userland__write_child_rusage(') or {panic('missing original rusage copy')}
 new_info := new.index('userland__write_waitid_siginfo(') or {panic('missing final siginfo copy')}
 new_usage := new.index('userland__write_child_rusage(') or {panic('missing final rusage copy')}
 assert old_info < old_usage && new_usage < new_info
 assert before.replace(old,'') == after.replace(new,''),'Whole production C differs outside waitid; no normalization'
}

fn sdk_and_primary(area string,out string) ! {
 sdk := object(area+'sdk-inputs.json')!; assert sdk.len == 2014
 prior := object('/Users/alex/.cache/vinix-linux-compat/waitabi-20261015/sdk-inputs.json')!; assert sdk.len == prior.len
 for path,hash in sdk {assert hash.str() == prior[path]!.str() && digest(area+'sdk/'+path) == hash.str(),path}
 mut found := map[string]bool{}
 for path in os.walk_ext(area+'sdk','') {assert os.inode(path).typ == .regular; local := path.all_after(area+'sdk/'); assert local in sdk && local !in found; found[local] = true}
 assert found.len == sdk.len
 primary := object(area+'primary-reuse.json')!
 assert primary['source_url']!.str() == 'https://raw.githubusercontent.com/torvalds/linux/v6.12/kernel/exit.c'
 assert primary['sha256']!.str() == '7c28bfc644117470b9cbe6d46c84580de98225755bbb227e61d638ea7104025d'
 assert digest(area+'linux-exit-v6.12.c') == primary['sha256']!.str() && digest(primary['cached_source']!.str()) == primary['sha256']!.str()
 for path in ['states/p1-before-arm/waitusage','states/p1-after-arm/waitusage','states/p1-after-arm/runtime','states/p1-after-arm/waitevent','states/p1-reference-arm'] {
  for file in ['fixture.o','serial.o','init'] {
   driver := object(area+path+'/'+file+'.compiler.json')!; assert driver['status']!.str() == '0' && driver['output']!.str() == ''
   assert driver['arguments']!.str().contains('--gcc-install-dir='+area.trim_right('/')+'/sdk/usr/lib/gcc/aarch64-alpine-linux-musl/14.2.0')
   assert driver['arguments']!.str().contains('--target=aarch64-linux-musl') && driver['arguments']!.str().contains('--sysroot='+area.trim_right('/')+'/sdk')
  }
 }
 refused := os.read_file(area+'initial-audit-compile.log')!
 assert refused.contains('to propagate a Result, the call must also return a Result type')
 assert os.read_file(area+'initial-audit-source.v')!.contains("old.index('userland__write_waitid_siginfo(')!")
 for name in ['sdk-inputs.json','primary-reuse.json','primary-source-note.txt','initial-audit-compile.log','initial-audit-source.v'] {publish(area+name,out+'waitusage-'+name)!}
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
 for row in log.split_into_lines().filter(it.starts_with('LINUX WAITUSAGE SLAB:') || it.starts_with('LINUX WAITUSAGE STORAGE:')) {
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
	assert log.contains('LINUX WAITUSAGE DETAIL:'), 'waitusage baseline failure markers required'
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
		'wrapper_source':    state + '/source/waitusagereferenceinit/core.v'
		'wrapper_c':         state + '/fixture.c'
		'wrapper_elf':       state + '/init'
		'initramfs':         state + '/initramfs.cpio'
		'serial':            state + '/serial.log'
		'serial_adapter_c':  state + '/serial.c'
		'controller_source': '/Users/alex/code/vinix/tests/linux-compat/waitusage-reference.v'
		'qemu':              command[0]
	} {
		assert artifacts[label] == digest(path)
	}
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/waitusagereferenceinit/core.v')
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
		println('Native waitid rusage-order source/C scope: PASS')
		return
	}
	if '--negative-control' in os.args {
		assert false, 'waitusage assertions must execute'
		return
	}
	if '--negative-pass-control' in os.args {
		failure(os.read_file(os.args[2])!, os.args[3])
		return
	}
	assert os.args.len == 2, 'Usage: waitusage-check.v EVIDENCE-AREA (compile without -prod)'
	area := os.args[1].trim_right('/') + '/'
	states := area + 'states/'
	root := '/Users/alex/code/vinix/'
	out := root + 'tests/linux-compat/results/2026-10-15/'
	os.mkdir_all(out)!
	sdk_and_primary(area, out)!
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'waitusage assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control',
		states + 'p1-reference-arm/serial.log', 'aarch64'], 'waitusage baseline failure markers required'))!
	check_source(area, root)!
	for suffix in ['arm', 'x86'] { check_c(area, suffix)! }
	os.write_file(area + 'scope-check.log', 'arm/x86: complete production C differs only in waitid; copy child rusage before siginfo, retain existing helpers and error/claim paths; credentials, accounting implementation, pins, ownership and consumption unchanged; no added allocation/free/pin and no normalization\n')!
	base := os.read_file(area + 'base.txt')!.trim_space()
	assert base == '513723b3f0aa81ade15a203e98501d75a380082f'
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
	assert os.read_file(area + 'linux-source.sha256')!.trim_space() == digest(area + 'linux-exit-v6.12.c') + ' https://raw.githubusercontent.com/torvalds/linux/v6.12/kernel/exit.c'
	linux_source := os.read_file(area + 'linux-exit-v6.12.c')!
	assert linux_source.contains('SYSCALL_DEFINE5(waitid, int, which, pid_t, upid') && linux_source.contains('SYSCALL_DEFINE4(wait4, pid_t, upid') && linux_source.contains('if (upid == INT_MIN)')
	assert os.read_file(area + 'watch.log')!.split_into_lines().filter(it.starts_with('Completed ')).len == 8
	retained := object(area + 'watch-retained-inputs.json')!
	assert retained.len == 84
	for path, hash in retained {
		assert path.starts_with(states + 'p1-before-arm/') || path.starts_with(states + 'p1-before-x86/') || path.starts_with(states + 'p1-after-')
		assert !path.contains('/iso-build/') && !path.ends_with('/efivars.fd')
		assert os.inode(path).typ == .regular && digest(path) == hash.str(), path
	}
	mut walked := map[string]bool{}
	mut completed := map[string]bool{}
	for suffix in ['arm', 'x86'] {
		for phase in ['before', 'after'] {
			names := if phase == 'before' {
				['waitusage']
			} else {
				['waitusage', 'runtime', 'waitevent']
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
			'fixture_source':           digest(root + 'tests/linux-compat/waitusagefixture/core.v')
			'audit_source':             digest(@FILE)
			'linux_primary_source':     digest(area + 'linux-exit-v6.12.c')
			'linux_primary_pin':        digest(area + 'linux-source.sha256')
			'private_sdk': digest(area + 'sdk-inputs.json')
			'primary_source_note': digest(area + 'primary-source-note.txt')
			'sdk_prior_inputs': digest('/Users/alex/.cache/vinix-linux-compat/waitabi-20261015/sdk-inputs.json')
			'arm_compiler_adapter': digest(area + 'arm-cc.v')
			'arm_compiler_adapter_binary': digest(area + 'arm-cc')
			'primary_reuse': digest(area + 'primary-reuse.json')
			'scope_contract': digest(area + 'scope-check.log')
			'initial_audit_compile': digest(area + 'initial-audit-compile.log')
			'initial_audit_source': digest(area + 'initial-audit-source.v')
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
				['waitusage']
			} else {
				['waitusage', 'runtime', 'waitevent']
			}
			captured := receipt(state, arch, digest(kernel), names, phase == 'before')!
			for key, value in captured { artifacts[phase + '_' + key] = value }
			for key in ['waitusage_source', 'waitusage_init', 'waitusage_c'] {
				if phase == 'before' {
					identity[key] = captured[key]
				} else {
					assert identity[key] == captured[key]
				}
			}
			text := os.read_file(state + '/waitusage/serial.log')!
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
				'native':    state + '/waitusage/serial.log'
				'build':     build
			} {
				publish(path, out + 'waitusage-' + phase + '-' + arch + '-' + label + if label == 'receipt' {
					'.json'
				} else {
					'.log'
				})!
			}
			if phase == 'after' {
				for name in names {
					if name == 'waitusage' { continue }
					publish(state + '/' + name + '/serial.log', out + 'waitusage-regression-' + arch + '-' + name + '.log')!
				}
			}
		}
		probe := states + 'p1-before-' + suffix + '/waitusage'
		raw := os.read_file(probe + '/fixture.c')!
		assert raw.count('alloca(') == 5
		for token in ['malloc(', 'calloc(', 'realloc(', 'memdup(', 'array_push(', 'array_get(',
			'v_fixed_index('] {
			assert !raw.contains(token)
		}
		reference := states + 'p1-reference-' + suffix
		linux := reference_receipt(reference, arch, identity['waitusage_init'])!
		for key, value in linux { artifacts['reference_' + key] = value }
		for label, path in {
			'receipt':   reference + '/receipt.json'
			'aggregate': reference + '.log'
			'native':    reference + '/serial.log'
		} {
			publish(path, out + 'waitusage-reference-' + arch + '-' + label + if label == 'receipt' {
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
		os.write_file(out + 'waitusage-evidence-' + arch + '.json', json2.encode(Evidence{
			architecture:  arch
			context: 'Native waitid rusage-before-siginfo ordering:310400 controls per architecture, original258048 failures, corrected and identical-ELF Linux6.12.51 zero. Four root/UID1000 initial/one-level PID namespace cohorts, four real/effective/saved credential profiles including UID4294967294, stopped/continued/exit37/SIGKILL. Three selectors, eight raw/musl forms, WNOWAIT with/without WNOHANG and mapped offsets. Invalid/wrapping/unmapped/read-only/PROT_NONE rusage leaves siginfo poisoned; valid rusage stays visible after invalid siginfo. Thirteen partial-rusage guard cuts assert EFAULT/no siginfo with leading canaries, without imposing partial copy counts. All siginfo cuts0..32 plus64/127/128 require prior valid rusage and six ordered fields. Seven overlapping layouts plus one adjacent control require final siginfo fields to win; all bytes outside the rusage/field footprint stay poisoned. Valid/NULL rusage and consuming/cleared unused-rusage controls pass. Rusage validity checks nonnegative LP64 counters and normalized microseconds, without exact accounting claims. Four flat200-cycle cohorts, four production builds, runtime/waitevent regressions, unchanged allocation diagnostics,67 inventory/2014 SDK/15146 compiler pins, exact one-function C scope and executing audit negatives. Consuming faults, exact partial rusage copy counts/accounting, arbitrary alias offsets, concurrent mappings/credentials, user namespace mapping, P_PIDFD/__W/ptrace/restart/GNU/foreign paths and broad roadmap gates remain separate.'
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
		publish(area + name, out + 'waitusage-' + name)!
	}
	publish(area + 'watch-retained-inputs.json', out + 'waitusage-watch-retained-inputs.json')!
	os.write_file(area + 'audit.log', 'Native waitusage conformance audit: PASS\n')!
	publish(area + 'audit.log', out + 'waitusage-audit.log')!
	println('Native waitusage conformance audit: PASS')
}
