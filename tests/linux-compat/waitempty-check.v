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
 rows := log.split_into_lines().filter(it.starts_with('LINUX WAITEMPTY TOPOLOGY:')); assert rows.len == 4
 mut seen := map[string]bool{}; mut targets := map[string]string{}
 for row in rows {
  fields := row.fields(); assert fields.len == 11
  assert fields[3] in ['ordinary=0','ordinary=1'] && fields[4] in ['namespace=0','namespace=1']
  assert fields[5] == if fields[3] == 'ordinary=0' {'uid=0'} else {'uid=1000'}
  for index,prefix in {6:'self=',7:'pid=',8:'group=',9:'session=',10:'page='} {assert fields[index].starts_with(prefix)}
  self := fields[6].all_after('=').int(); pid := fields[7].all_after('=').int(); assert self > 1 && pid > 1 && pid != self
  if fields[4] == 'namespace=1' {assert self == 2 && pid == 3}
  key := fields[3]+fields[4]; assert key !in seen; seen[key] = true; targets[key] = fields[7]
  assert fields[8].all_after('=').int() == pid && fields[9].all_after('=').int() == self
  assert fields[10].all_after('=').int() == if arch == 'aarch64' && !reference {16384} else {4096}
 }
 for label in ['EXIT:','REAP:'] {
  edges := log.split_into_lines().filter(it.starts_with('LINUX WAITEMPTY '+label)); assert edges.len == 4; seen.clear()
  for row in edges {
   fields := row.fields(); assert fields.len == if label == 'EXIT:' {8} else {7}
   assert fields[3] in ['ordinary=0','ordinary=1'] && fields[4] in ['namespace=0','namespace=1']
   key := fields[3]+fields[4]; assert key !in seen && targets[key] == fields[5]; seen[key] = true
   if label == 'EXIT:' {assert fields[6] == 'wait=CLD_EXITED' && fields[7] == 'status=37'} else {assert fields[6] == 'status=37'}
  }
 }
 mut cases := map[string]string{}
 for label in ['CASES:','FINAL:'] {
  outcomes := log.split_into_lines().filter(it.starts_with('LINUX WAITEMPTY '+label)); assert outcomes.len == 24; seen.clear(); mut calls := 0; mut failures := 0
  for row in outcomes {
   fields := row.fields(); assert fields.len == 8
   assert fields[3] in ['ordinary=0','ordinary=1'] && fields[4] in ['namespace=0','namespace=1'] && fields[5] in ['kind=0','kind=1','kind=2','kind=3','kind=4','kind=5']
   key := fields[3]+fields[4]+fields[5]; assert key !in seen; seen[key] = true
   assert fields[6].starts_with('calls=') && fields[7].starts_with('failures=')
   kind := fields[5].all_after('=').int(); n := fields[6].all_after('=').int(); f := fields[7].all_after('=').int()
   assert n == [864,288,1152,6912,288,96]![kind]
   assert f == if phase == 'before' {[864,288,864,6720,0,48]![kind]} else {0}
   if label == 'CASES:' {cases[key] = fields[6]+fields[7]} else {assert cases[key] == fields[6]+fields[7]}
   calls += n; failures += f
  }
  assert calls == 38400 && failures == if phase == 'before' {35136} else {0}
 }
 if phase == 'before' {assert log.contains('LINUX WAITEMPTY DETAIL:') && log.contains('LINUX WAITEMPTY FAIL:') && !log.contains('LINUX WAITEMPTY: PASS')}
 else {assert !log.contains('LINUX WAITEMPTY DETAIL:') && !log.contains('LINUX WAITEMPTY FAIL:')}
 if reference {assert log.contains('Linux version 6.12.51-0-virt') && log.contains('LINUX WAITEMPTY REFERENCE: PASS') && !log.contains('LINUX WAITEMPTY STORAGE:')}
 else if phase == 'after' {assert log.count('LINUX WAITEMPTY: PASS') == 1}
 assert !log.contains('Kernel panic') && !log.contains('setup stage=')
}

fn check_source(area string,root string) ! {
 before := os.read_file(area+'before-linux_task.v')!; after := os.read_file(area+'after-linux_task.v')!
 marker := '// waitid(idtype, id, infop, options, rusage).'
 old := before.all_after(marker)
 expected := before.all_before(marker)+'// Linux also writes the six siginfo fields on waitid errors. Preserve padding\n// and the unused child payload, and let a copyout fault override that error.\nfn empty_waitid_result(infop u64, error u64) (u64, u64) {\n\tif infop != 0 {\n\t\tif !usercopy.user_range(infop, sizeof(SigInfoChld)) {\n\t\t\treturn errno.err, errno.efault\n\t\t}\n\t\tzero := u32(0)\n\t\tfor index in 0 .. 6 {\n\t\t\toffset := u64(if index < 3 { index } else { index + 1 }) * 4\n\t\t\taddress := infop + offset\n\t\t\t// A faulting field must not commit a split-page prefix. Resolve both\n\t\t\t// ends before the synchronous store; no process/child borrow escapes.\n\t\t\tif !usercopy.writable(address) || !usercopy.writable(address + 3)\n\t\t\t\t|| !usercopy.copy_to_user(address, unsafe { voidptr(&zero) }, sizeof(u32)) {\n\t\t\t\treturn errno.err, errno.efault\n\t\t\t}\n\t\t}\n\t}\n\tif error != 0 { return errno.err, error }\n\treturn 0, 0\n}\n\n'+marker+old.replace('return errno.err, errno.einval','return empty_waitid_result(infop, errno.einval)').replace('\n\t\tif change.err != 0 {\n\t\t\treturn errno.err, change.err\n\t\t}\n\t\t// WNOHANG with nothing to report: Linux signals that with si_pid == 0.\n\t\tif infop != 0 {\n\t\t\tinfo := SigInfoChld{}\n\t\t\tif !usercopy.copy_to_user(infop, voidptr(&info), sizeof(SigInfoChld)) {\n\t\t\t\treturn errno.err, errno.efault\n\t\t\t}\n\t\t}\n\t\treturn 0, 0\n\t}\n','\n\t\treturn empty_waitid_result(infop, change.err)\n\t}\n')
 exact := after == expected && after != before; assert exact,'Only empty/error waitid output changes; successful child claims, events, locks and copyout remain identical'
 assert digest(root+'kernel/userland/linux_task.v') == digest(area+'after-linux_task.v')
 for suffix in ['arm','x86'] {assert digest(area+'kernel-'+suffix+'/kernel/userland/linux_task.v') == digest(area+'after-linux_task.v')}
}

fn body(source string,name string) string {
 rows := source.split_into_lines().filter(it.contains(' '+name+'(') && it.ends_with('{'))
 assert rows.len == 1,name
 return definition(source,'\n'+rows[0])
}
fn check_c(area string,suffix string) ! {
 mut before := os.read_file(area+'before-'+suffix+'.c')!; mut after := os.read_file(area+'after-'+suffix+'.c')!
 old := body(before,'userland__syscall_waitid'); new := body(after,'userland__syscall_waitid'); helper := body(after,'userland__empty_waitid_result')
 assert old != new && !before.contains('userland__empty_waitid_result')
 for token in ['malloc(','calloc(','realloc(','memdup(','array__','free(','alloca(','vinix_stack_alloc(','pin_process(','unpin_process('] {
  assert old.count(token) == new.count(token) && !helper.contains(token),token
 }
 assert helper.contains('usercopy__user_range') && helper.count('usercopy__writable') == 2 && helper.contains('usercopy__copy_to_user')
 before = before.replace(old,''); after = after.replace(new,'').replace(helper+'\n','')
 decl := after.split_into_lines().filter(it.contains(' userland__empty_waitid_result(') && it.ends_with(';')); assert decl.len == 1
 after = after.replace(decl[0]+'\n','')
 unchanged := before == after; assert unchanged,'Whole production C differs outside waitid and its added empty-result helper; no normalization'
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
 for path in ['states/p2-before-arm/waitempty','states/p2-after-arm/waitempty','states/p2-after-arm/runtime','states/p2-after-arm/waitabi','states/p2-reference-arm'] {
  for file in ['fixture.o','serial.o','init'] {
   driver := object(area+path+'/'+file+'.compiler.json')!; assert driver['status']!.str() == '0' && driver['output']!.str() == ''
   assert driver['arguments']!.str().contains('--gcc-install-dir='+area.trim_right('/')+'/sdk/usr/lib/gcc/aarch64-alpine-linux-musl/14.2.0')
   assert driver['arguments']!.str().contains('--target=aarch64-linux-musl') && driver['arguments']!.str().contains('--sysroot='+area.trim_right('/')+'/sdk')
  }
 }
 for name in ['sdk-inputs.json','primary-reuse.json','primary-source-note.txt'] {publish(area+name,out+'waitempty-'+name)!}
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
 for row in log.split_into_lines().filter(it.starts_with('LINUX WAITEMPTY SLAB:') || it.starts_with('LINUX WAITEMPTY STORAGE:')) {
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
	assert log.contains('LINUX WAITEMPTY DETAIL:'), 'waitempty baseline failure markers required'
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
		'wrapper_source':    state + '/source/waitemptyreferenceinit/core.v'
		'wrapper_c':         state + '/fixture.c'
		'wrapper_elf':       state + '/init'
		'initramfs':         state + '/initramfs.cpio'
		'serial':            state + '/serial.log'
		'serial_adapter_c':  state + '/serial.c'
		'controller_source': '/Users/alex/code/vinix/tests/linux-compat/waitempty-reference.v'
		'qemu':              command[0]
	} {
		assert artifacts[label] == digest(path)
	}
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/waitemptyreferenceinit/core.v')
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

fn diagnostics(area string,out string) ! {
 mut pins := map[string]string{}
 for suffix in ['arm','x86'] {
  state := area+'states/p1-before-'+suffix
  value := object(state+'/receipt.json')!; rows := value['results']!.as_array(); assert rows.len == 1
  row := rows[0].as_map(); assert row['name']!.str() == 'waitempty' && row['exit_code']!.int() == 1 && row['detail']!.str() == 'Command failed' && row['init_sha256']!.str() == '' && row['iso_sha256']!.str() == ''
  probe := state+'/waitempty'; assert !os.exists(probe+'/init') && !os.exists(probe+'/test.iso')
  raw := os.read_file(probe+'/fixture.c')!; assert raw.count('memdup(') == 1
  log := os.read_file(state+'.log')!; assert log.contains('memdup') && !log.contains('LINUX WAITEMPTY FINAL:')
  source := state+'/sources/waitemptyfixture/core.v'; assert digest(source) == row['source_sha256']!.str()
  original := os.read_file(source)!; assert original.contains('usage_pointer(&usage[0],use)')
  final := os.read_file('/Users/alex/code/vinix/tests/linux-compat/waitemptyfixture/core.v')!; assert !final.contains('usage_pointer(&usage[0],use)')
  for path in os.walk_ext(state,'') {if os.inode(path).typ == .regular {pins[path] = digest(path)}}
  pins[state+'.log'] = digest(state+'.log')
  for path in [source,probe+'/fixture.c',state+'/kernel/bin/vinix',state+'/receipt.json',state+'.log'] {assert path in pins}
  for label,path in {'source.v':source,'receipt.json':state+'/receipt.json','producer.log':state+'.log'} {publish(path,out+'waitempty-diagnostic-'+suffix+'-'+label)!}
 }
 assert os.read_file(area+'helper-watch-producer.log')!.contains('failed to open file "'+area+'states/p1-before-arm/waitempty/init"')
 pins[area+'helper-watch-producer.log'] = digest(area+'helper-watch-producer.log')
 os.write_file(area+'diagnostic-inputs.json',json2.encode(pins,prettify:true)+'\n')!
 publish(area+'diagnostic-inputs.json',out+'waitempty-diagnostic-inputs.json')!
 publish(area+'helper-watch-producer.log',out+'waitempty-diagnostic-watch-refusal.log')!
 note := 'The initial p1 probe compile emitted one hidden memdup for an unused guard-call rusage array, and the freestanding link/compile refused it on both architectures. No probe ELF/ISO or semantic result exists for those profiles. The watcher also refused missing init. Frozen source, emitted C, compiler metadata, kernel and producer/receipt files remain pinned. The final guard controls use only NULL or invalid rusage pointers, so the unused array was removed together with its redundant returned predicate. Final generated C has five explicit allocas and no allocator calls. p2 original/fixed/Linux profiles use one unchanged final source/C/ELF. Original semantic failures are counted only from p2 guest FINAL rows.\n'
 os.write_file(area+'diagnostic-note.txt',note)!; publish(area+'diagnostic-note.txt',out+'waitempty-diagnostic-note.txt')!
}

fn main() {
	if '--scope-only' in os.args {
		area := os.args[2].trim_right('/')+'/'
		check_source(area,'/Users/alex/code/vinix/')!
		for suffix in ['arm','x86'] {check_c(area,suffix)!}
		println('Native wait ABI source/C scope: PASS')
		return
	}
	if '--negative-control' in os.args {
		assert false, 'waitempty assertions must execute'
		return
	}
	if '--negative-pass-control' in os.args {
		failure(os.read_file(os.args[2])!, os.args[3])
		return
	}
	assert os.args.len == 2, 'Usage: waitempty-check.v EVIDENCE-AREA (compile without -prod)'
	area := os.args[1].trim_right('/') + '/'
	states := area + 'states/'
	root := '/Users/alex/code/vinix/'
	out := root + 'tests/linux-compat/results/2026-10-15/'
	os.mkdir_all(out)!
	sdk_and_primary(area, out)!
	diagnostics(area,out)!
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'waitempty assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control',
		states + 'p2-reference-arm/serial.log', 'aarch64'], 'waitempty baseline failure markers required'))!
	check_source(area, root)!
	for suffix in ['arm', 'x86'] { check_c(area, suffix)! }
	os.write_file(area + 'scope-check.log', 'arm/x86: complete production C differs only in waitid and its added empty-result helper; fixed six-field output, full numeric range check, per-field endpoint resolution and ordered writes; successful child/event paths, locks, claims, pins and ownership unchanged; no added allocation/free/pin or compiler normalization\n')!
	base := os.read_file(area + 'base.txt')!.trim_space()
	assert base == '0797ec9653a1570603e75ecffecd15145a3dded0'
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
		assert path.starts_with(states + 'p2-before-arm/') || path.starts_with(states + 'p2-before-x86/') || path.starts_with(states + 'p2-after-')
		assert !path.contains('/iso-build/') && !path.ends_with('/efivars.fd')
		assert os.inode(path).typ == .regular && digest(path) == hash.str(), path
	}
	mut walked := map[string]bool{}
	mut completed := map[string]bool{}
	for suffix in ['arm', 'x86'] {
		for phase in ['before', 'after'] {
			names := if phase == 'before' {
				['waitempty']
			} else {
				['waitempty', 'runtime', 'waitabi']
			}
			for name in names {
				probe := states + 'p2-' + phase + '-' + suffix + '/' + name
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
			'fixture_source':           digest(root + 'tests/linux-compat/waitemptyfixture/core.v')
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
			state := states + 'p2-' + phase + '-' + suffix
			kernel := area + if phase == 'before' { 'baseline-' } else { 'kernel-' } + suffix + '/kernel/bin/vinix'
			names := if phase == 'before' {
				['waitempty']
			} else {
				['waitempty', 'runtime', 'waitabi']
			}
			captured := receipt(state, arch, digest(kernel), names, phase == 'before')!
			for key, value in captured { artifacts[phase + '_' + key] = value }
			for key in ['waitempty_source', 'waitempty_init', 'waitempty_c'] {
				if phase == 'before' {
					identity[key] = captured[key]
				} else {
					assert identity[key] == captured[key]
				}
			}
			text := os.read_file(state + '/waitempty/serial.log')!
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
				'native':    state + '/waitempty/serial.log'
				'build':     build
			} {
				publish(path, out + 'waitempty-' + phase + '-' + arch + '-' + label + if label == 'receipt' {
					'.json'
				} else {
					'.log'
				})!
			}
			if phase == 'after' {
				for name in names {
					if name == 'waitempty' { continue }
					publish(state + '/' + name + '/serial.log', out + 'waitempty-regression-' + arch + '-' + name + '.log')!
				}
			}
		}
		probe := states + 'p2-before-' + suffix + '/waitempty'
		raw := os.read_file(probe + '/fixture.c')!
		assert raw.count('alloca(') == 5
		for token in ['malloc(', 'calloc(', 'realloc(', 'memdup(', 'array_push(', 'array_get(',
			'v_fixed_index('] {
			assert !raw.contains(token)
		}
		reference := states + 'p2-reference-' + suffix
		linux := reference_receipt(reference, arch, identity['waitempty_init'])!
		for key, value in linux { artifacts['reference_' + key] = value }
		for label, path in {
			'receipt':   reference + '/receipt.json'
			'aggregate': reference + '.log'
			'native':    reference + '/serial.log'
		} {
			publish(path, out + 'waitempty-reference-' + arch + '-' + label + if label == 'receipt' {
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
		os.write_file(out + 'waitempty-evidence-' + arch + '.json', json2.encode(Evidence{
			architecture:  arch
			context: 'Native waitid no-event/error siginfo field output and EFAULT priority:38400 controls per architecture, original35136 failures, corrected and identical-ELF Linux6.12.51 zero. Four root/UID1000 initial/one-level PID namespace cohorts. Twelve selectors/options, eight raw/musl forms, aligned/unaligned poisoned output, exact six32-bit fields with padding/tail preserved, NULL/valid/invalid rusage ignored without events, NULL/invalid/read-only/inaccessible infop, every cut0..32 and64/127/128 at a guard page including split fields, real status37 WNOWAIT/reaped controls. Full128-byte numeric range checked before ordered scalar writes; no mapped-tail requirement. Four warmed200-cycle cohorts with flat storage; four production builds, runtime/waitabi regressions, unchanged allocation diagnostics,67 inventory/2014 SDK/15146 compiler inputs, exact two-function whole-C scope and executing audit negatives. Initial hidden-memdup compile refusals and watcher missing-init refusal are retained separately. Successful-event padding/UID/accounting, consuming copyout faults, P_PIDFD, __W flags, cross-thread/ptrace waits, mprotect/unmap races, interrupted/restarted waits, GNU/foreign ABIs and three broad roadmap gates remain separate.'
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
		publish(area + name, out + 'waitempty-' + name)!
	}
	publish(area + 'watch-retained-inputs.json', out + 'waitempty-watch-retained-inputs.json')!
	os.write_file(area + 'audit.log', 'Native waitempty conformance audit: PASS\n')!
	publish(area + 'audit.log', out + 'waitempty-audit.log')!
	println('Native waitempty conformance audit: PASS')
}
