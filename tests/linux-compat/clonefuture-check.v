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
	architecture  string
	context       string
	base_commit   string
	artifacts     map[string]string
	source_inputs map[string]string
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

fn storage(log string, arch string, _phase string) {
	mut slabs := [4]int{}
	mut pages := [4]int{}
	mut seen := map[string]bool{}
	for row in log.split_into_lines().filter(it.starts_with('LINUX CLONEFUTURE SLAB:') || it.starts_with('LINUX CLONEFUTURE STORAGE:')) {
		fields := row.fields()
		assert fields.len == 8 && fields[3].starts_with('ordinary=') && fields[4].starts_with('route=')
		ordinary := fields[3].all_after('=').int()
		namespace := fields[4].all_after('=').int()
		assert ordinary in [0, 1] && namespace in [0, 1]
		cohort := ordinary + 2 * namespace
		pair := fields[6].all_after('=').split('/')
		assert pair.len == 2 && pair[0] == pair[1] && pair.all(it != '' && it.bytes().all(it.is_digit()))
		if fields[2] == 'SLAB:' {
			assert fields[5].starts_with('size=') && fields[7] == 'cycles=200'
			key := fields[3] + fields[4] + fields[5]
			assert key !in seen
			seen[key] = true
			slabs[cohort]++
		} else {
			assert fields[5] == 'cycles=200' && fields[7] == 'PASS' && pair[0].u64() > 0
			pages[cohort]++
		}
	}
	for cohort in 0 .. 4 {
		assert slabs[cohort] == if arch == 'aarch64' {
			18
		} else {
			14
		}
		assert pages[cohort] == 1
	}
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
		'wrapper_source':    state + '/source/clonefuturereferenceinit/core.v'
		'wrapper_c':         state + '/fixture.c'
		'wrapper_elf':       state + '/init'
		'initramfs':         state + '/initramfs.cpio'
		'serial':            state + '/serial.log'
		'serial_adapter_c':  state + '/serial.c'
		'controller_source': '/Users/alex/code/vinix/tests/linux-compat/clonefuture-reference.v'
		'qemu':              command[0]
	} {
		assert artifacts[label] == digest(path)
	}
	assert artifacts['probe'] == init && artifacts['wrapper_source'] == digest('/Users/alex/code/vinix/tests/linux-compat/clonefuturereferenceinit/core.v')
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

fn original_errors(log string) {
 rows:=log.split_into_lines().filter(it.starts_with('LINUX CLONEFUTURE DETAIL:'))
 assert rows.len==36
 mut seen:=map[string]bool{}
 for row in rows {
  f:=row.fields()
  assert f.len==12 && f[3] in ['ordinary=0','ordinary=1'] && f[4] in ['route=0','route=1']
  assert f[5] in ['kind=0','kind=1','kind=2']
  assert f[6] in if f[5]=='kind=2' {['index=0','index=1','index=2']} else {['index=0','index=1','index=2']}
  key:=f[3]+f[4]+f[5]+f[6];assert key !in seen;seen[key]=true
  assert f[7..]==['result=-1','errno='+if f[5]=='kind=2' {'95'} else {'9'},'expected=22','guarded=1','child=0']
 }
}

fn failure(log string, arch string) {
	assert log.contains('LINUX CLONEFUTURE DETAIL:'), 'clonefuture baseline failure markers required'
	semantics(log, 'before', arch, false)
}

fn descriptors(log string) {
 rows:=log.split_into_lines().filter(it.starts_with('LINUX CLONEFUTURE FD:'))
 assert rows.len==4
 mut seen:=map[string]bool{}
 for row in rows {
  f:=row.fields()
  assert f.len==6 && f[3] in ['ordinary=0','ordinary=1'] && f[4] in ['route=0','route=1']
  assert f[5].starts_with('wrong=') && f[5].all_after('=').int()>=0
  key:=f[3]+f[4];assert key !in seen;seen[key]=true
 }
}

fn capabilities(log string) {
 for label in ['CAPS:','CAPSRESTORED:'] {
  rows:=log.split_into_lines().filter(it.starts_with('LINUX CLONEFUTURE '+label))
  assert rows.len==4
  mut seen:=map[string]bool{}
  for row in rows {
   f:=row.fields()
   assert f.len==if label=='CAPS:' {8} else {6}
   assert f[3] in ['ordinary=0','ordinary=1'] && f[4] in ['route=0','route=1'] && f[5]=='sysadmin=0'
   if label=='CAPS:' {assert f[6..]==['permitted_sysadmin=1','keepcaps=1']}
   key:=f[3]+f[4];assert key !in seen;seen[key]=true
  }
 }
}

fn threads(log string,phase string) {
 rows:=log.split_into_lines().filter(it.starts_with('LINUX CLONEFUTURE PTHREAD:'))
 assert rows.len==8;mut seen:=map[string]bool{}
 for row in rows {
  f:=row.fields();assert f.len==10 && f[3] in ['ordinary=0','ordinary=1'] && f[4] in ['route=0','route=1'] && f[5] in ['different=0','different=1']
  key:=f[3]+f[4]+f[5];assert key !in seen;seen[key]=true
  refused:=phase=='after' && f[5]=='different=1'
  assert f[6..]==if refused {['result=11','ran=0','joined=0','valid=1']} else {['result=0','ran=1','joined=1','valid=1']}
 }
 keepers:=log.split_into_lines().filter(it.starts_with('LINUX CLONEFUTURE KEEPER:'));assert keepers.len==4;seen.clear()
 for row in keepers {
  f:=row.fields();assert f.len==9 && f[3] in ['ordinary=0','ordinary=1'] && f[4] in ['route=0','route=1'] && f[5].starts_with('outer=') && f[5].all_after('=').int()>1 && f[6..]==['inner=1','parent=0','reaped=1']
  key:=f[3]+f[4];assert key !in seen;seen[key]=true
 }
}

fn semantics(log string, phase string, arch string, reference bool) {
	assert phase in ['before', 'after'] && arch in ['aarch64', 'x86_64']
	capabilities(log)
	threads(log,phase)
	descriptors(log)
	mut seen := map[string]bool{}
	for label in ['CASES:', 'FINAL:'] {
		rows := log.split_into_lines().filter(it.starts_with('LINUX CLONEFUTURE ' + label))
		assert rows.len == 24
		seen.clear()
		mut total := 0
		mut failures := 0
		for row in rows {
			f := row.fields()
			assert f.len == 8 && f[3] in ['ordinary=0', 'ordinary=1'] && f[4] in [
				'route=0',
				'route=1',
			] && f[5] in ['kind=0', 'kind=1', 'kind=2', 'kind=3', 'kind=4', 'kind=5']
			key := label + f[3] + f[4] + f[5]
			assert key !in seen
			seen[key] = true
			class := f[5].all_after('=').int()
			calls := [96, 96, 108, 60, 72, 36]![class]
			bad := if phase == 'after' {0} else if class in [0,1] {calls} else if class==2 {81} else {0}
			assert f[6] == 'calls=' + calls.str() && f[7] == 'failures=' + bad.str()
			total += calls
			failures += bad
		}
		assert total == 1872 && failures == if phase == 'after' { 0 } else { 1092 }
	}
	cohorts := log.split_into_lines().filter(it.starts_with('LINUX CLONEFUTURE COHORT:'))
	assert cohorts.len == 4
	seen.clear()
	for row in cohorts {
		f := row.fields()
		assert f.len == 11 && f[3] in ['ordinary=0', 'ordinary=1'] && f[4] in [
			'route=0',
			'route=1',
		]
		key := f[3] + f[4]
		assert key !in seen
		seen[key] = true
		assert f[5].starts_with('self=') && f[5].all_after('=').int() > 1

		assert f[6] == 'uid=' + if f[3] == 'ordinary=1' { '1000' } else { '0' }
		assert f[7] == 'page=' + if arch == 'aarch64' && !reference { '16384' } else { '4096' }
		assert f[8..] == ['raw=468', 'classes=6', 'layouts=3']
	}
	for label in ['CHILDREN:', 'CHILDRENFINAL:'] {
		rows := log.split_into_lines().filter(it.starts_with('LINUX CLONEFUTURE ' + label))
		assert rows.len == 4
		seen.clear()
		for row in rows {
			f := row.fields()
			assert f.len == 7 && f[3] in ['ordinary=0', 'ordinary=1'] && f[4] in [
				'route=0',
				'route=1',
			]
			key := f[3] + f[4]
			assert key !in seen
			seen[key] = true
			assert f[5] == 'valid=36' && f[6] == 'unexpected=0'
		}
	}

	if phase == 'before' {
		original_errors(log)
		assert log.contains('LINUX CLONEFUTURE DETAIL:') && log.contains('LINUX CLONEFUTURE FAIL:') && !log.contains('LINUX CLONEFUTURE: PASS')
	} else {
		assert !log.contains('LINUX CLONEFUTURE DETAIL:') && !log.contains('LINUX CLONEFUTURE FAIL:')
	}
	if reference {
		assert log.contains('Linux version 6.12.51-0-virt') && log.contains('LINUX CLONEFUTURE REFERENCE: PASS') && !log.contains('LINUX CLONEFUTURE STORAGE:')
	} else if phase == 'after' {
		assert log.count('LINUX CLONEFUTURE: PASS') == 1
	}
	assert !log.contains('Kernel panic') && !log.contains('setup stage=')
}

fn scope(area string,root string) ! {
 base:=os.read_file(area+'base.txt')!.trim_space();assert base=='c119f56506bcc138fd1d0657175010c6c40ad050'
 helper:='// Threads must stay in their process\' birth PID namespace. unshare/setns\n// can select a different namespace for future children without a NEWPID flag.\nfn valid_clone_pid_namespace(flags u64) bool {\n\tif flags & clone_thread == 0 { return true }\n\tprocess := proc.current_thread().process\n\treturn voidptr(process.ns.pid) == voidptr(process.ns.pid_for_children)\n}\n\n'
 for path in ['linux_task.v','clone_arm64.v','clone_amd64.v'] {
  before:=os.read_file(area+'before-'+path)!;after:=os.read_file(area+'after-'+path)!
  mut expected:=before
  if path=='linux_task.v' {at:='// FS, descriptor and handler ownership is currently process-scoped.';assert before.count(at)==1;expected=before.replace(at,helper+at)}
  else {
   at:='\tif !valid_clone_parent(args.flags) {\n\t\treturn errno.err, errno.einval\n\t}\n\n';assert before.count(at)==1
   expected=before.replace(at,at+'\tif !valid_clone_pid_namespace(args.flags) {\n\t\treturn errno.err, errno.einval\n\t}\n\n')
   at2:='\tif !valid_clone_parent(flags) { return errno.err, errno.einval }\n';assert before.count(at2)==1
   expected=expected.replace(at2,at2+'\tif !valid_clone_pid_namespace(flags) { return errno.err, errno.einval }\n')
  }
  assert expected==after && digest(root+'kernel/userland/'+path)==digest(area+'after-'+path)
  for suffix in ['arm','x86'] {tree:=area+'kernel-'+suffix;assert git(tree,['show',base+':kernel/userland/'+path])!.trim_space()==before.trim_space();assert digest(tree+'/kernel/userland/'+path)==digest(area+'after-'+path)}
 }
 for suffix in ['arm','x86'] {
  tree:=area+'kernel-'+suffix;assert git(tree,['rev-parse','HEAD'])! == base
  assert git(tree,['diff','--name-only','HEAD','--','kernel'])! == 'kernel/userland/clone_amd64.v\nkernel/userland/clone_arm64.v\nkernel/userland/linux_task.v'
  before:=os.read_file(area+'before-'+suffix+'.c')!;after:=os.read_file(area+'after-'+suffix+'.c')!
  added:=definition(after,'\nbool userland__valid_clone_pid_namespace(u64 flags) {')
  expected_helper:='\nbool userland__valid_clone_pid_namespace(u64 flags) {\n\tif ((flags & userland__clone_thread) == 0) {\n\t\treturn true;\n\t}\n\tproc__Process* process = (proc__current_thread())->process;\n\treturn (void*)(process->ns.pid) == (void*)(process->ns.pid_for_children);\n}'
  assert added==expected_helper
  mut expected:=before
  common:='\nmulti_return_u64_u64 userland__do_clone'+if suffix=='arm' {'_into'} else {''}+'(local__GPRState* state, u64 flags, u64 child_stack, u64 parent_tid, '+if suffix=='arm' {'u64 tls, u64 child_tid'} else {'u64 child_tid, u64 tls'}+', bool into_cgroup, void* cgroup) {'
  for marker in ['\nmulti_return_u64_u64 userland__syscall_clone3(void* '+if suffix=='arm' {'_gpr_state'} else {'gpr_state'}+', u64 uargs, u64 size) {',common] {
   old:=definition(before,marker);new:=definition(after,marker)
   arg:=if marker.contains('syscall_clone3') {'args.flags'} else {'flags'}
   at:='\tif (!userland__valid_clone_parent('+arg+')) {\n\t\treturn (multi_return_u64_u64){errno__err, errno__einval};\n\t}\n'
   guard:='\tif (!userland__valid_clone_pid_namespace('+arg+')) {\n\t\treturn (multi_return_u64_u64){errno__err, errno__einval};\n\t}\n'
   assert old.count(at)==1 && old.replace(at,at+guard)==new
   expected=expected.replace(old,new)
  }
  stripped:=after.replace('\nbool userland__valid_clone_pid_namespace(u64 flags);','').replace(added+'\n','')
  equal:=expected==stripped;assert equal,'Whole C differs only in one scalar helper/prototype and four call sites'
  for word in ['malloc(', 'memdup(', 'new_array', 'free(', 'spinlock', 'unpin', 'pin_process'] {assert !added.contains(word)}
 }
}


fn refusals(area string,out string) ! {
 folder:=area+'probe-compile-refusal/'
 assert os.read_file(folder+'status.txt')!.trim_space()=='1'
 assert os.read_file(folder+'reproduced.log')!.contains('cannot dereference a function call on the left side')
 assert os.read_file(folder+'states__reference-arm.log.status')!.trim_space()=='1'
 assert os.read_file(folder+'reference-arm-producer.log')!.contains('states/preflight-arm/init')
 before:=os.read_file(folder+'core.v')!
 old:='value.address=u64(C.__errno_location());*C.__errno_location()=91;value.ran=1'
 new:='mut code:=C.__errno_location();value.address=u64(code);*code=91;value.ran=1'
 second:=area+'probe-c-refusal/'
 middle:=os.read_file(second+'core.v')!
 assert before.count(old)==1 && before.replace(old,new)==middle
 assert os.read_file(second+'status.txt')!.trim_space()=='1'
 diagnostic:=os.read_file(second+'reproduced.log')!
 assert diagnostic.contains('v_fixed_index') && diagnostic.contains('pointer-sign')
 repaired:=middle.replace('mut active:=[128]u8{};mut future:=[128]u8{}','mut active:=[128]char{};mut future:=[128]char{}').replace('fn cycle(state &State,index i32) bool {','fn cycle(state &State,index i32) bool {unsafe {').replace('\n}\n\nfn qualify(','\n}}\n\nfn qualify(')
 assert repaired==os.read_file('/Users/alex/code/vinix/tests/linux-compat/clonefuturefixture/core.v')!
 mut pins:=map[string]string{}
 for path in os.walk_ext(folder,'') {if os.inode(path).typ==.regular {pins[path.all_after(folder)]=digest(path)}}
 for path in os.walk_ext(second,'') {if os.inode(path).typ==.regular {pins['c-refusal/'+path.all_after(second)]=digest(path)}}
 reference:=area+'reference-route-refusal/'
 controller:=os.read_file(reference+'reference.v')!
 assert controller.replace('namespace=','route=')==os.read_file('/Users/alex/code/vinix/tests/linux-compat/clonefuture-reference.v')!
 assert os.read_file(reference+'states__reference-arm.log.status')!.trim_space()=='1'
 assert os.read_file(reference+'reference-arm-producer.log')!.contains('Invalid reference outcomes')
 value:=object(reference+'state/receipt.json')!
 assert !value['passed']!.bool() && value['finished']!.bool() && value['forced']!.bool() && value['status']!.int()==0
 semantics(os.read_file(reference+'state/serial.log')!,'after','aarch64',true)
 assert digest(reference+'state/probe')==digest(area+'states/preflight-arm/init')
 for path in os.walk_ext(reference,'') {if os.inode(path).typ==.regular {pins['reference-refusal/'+path.all_after(reference)]=digest(path)}}
 os.write_file(area+'probe-refusal-inputs.json',json2.encode(pins,prettify:true)+'\n')!
 publish(area+'probe-refusal-inputs.json',out+'clonefuture-probe-refusal-inputs.json')!
 publish(folder+'reproduced.log',out+'clonefuture-probe-compile-refusal.log')!
 publish(folder+'reference-arm-producer.log',out+'clonefuture-reference-launch-refusal.log')!
 publish(second+'reproduced.log',out+'clonefuture-probe-c-refusal.log')!
 publish(reference+'reference-arm-producer.log',out+'clonefuture-reference-validator-refusal.log')!
 publish(reference+'state/serial.log',out+'clonefuture-reference-validator-serial.log')!
 publish(reference+'state/receipt.json',out+'clonefuture-reference-validator-receipt.json')!
}

fn main() {
	if '--scope-only' in os.args {
		scope(os.args[2].trim_right('/') + '/', '/Users/alex/code/vinix/')!
		println('Native clonefuture exact source/C scope: PASS')
		return
	}
	if '--negative-control' in os.args {
		assert false, 'clonefuture assertions must execute'
		return
	}
	if '--negative-pass-control' in os.args {
		failure(os.read_file(os.args[2])!, os.args[3])
		return
	}
	assert os.args.len in [2, 3] && (os.args.len == 2 || os.args[2] == '--verify-only'), 'Usage: clonefuture-check.v EVIDENCE-AREA [--verify-only] (compile without -prod)'
	area := os.args[1].trim_right('/') + '/'
	root := '/Users/alex/code/vinix/'
	out := if os.args.len == 3 {
		area + 'preview/'
	} else {
		root + 'tests/linux-compat/results/2026-10-16/'
	}
	os.mkdir_all(out)!
	scope(area, root)!
	refusals(area,out)!
	os.write_file(area + 'assertion-control.log', control(['--negative-control'], 'clonefuture assertions must execute'))!
	os.write_file(area + 'passing-log-control.log', control(['--negative-pass-control',
		area + 'states/reference-arm/serial.log', 'aarch64'], 'clonefuture baseline failure markers required'))!
	for arch, suffix in {
		'aarch64': 'arm'
		'x86_64':  'x86'
	} {
		before := area + 'states/before-' + suffix
		after := area + 'states/after-' + suffix
		mut artifacts := map[string]string{}
		for phase, state in {
			'before': before
			'after':  after
		} {
			names := if phase == 'before' {
				['clonefuture']
			} else {
				['clonefuture', 'runtime', 'clonecgperm']
			}
			kernel := digest(state + '/kernel/bin/vinix')
			assert kernel == digest(area + '/' + if phase == 'before' {
				'baseline-' + suffix
			} else {
				'kernel-' + suffix
			} + '/kernel/bin/vinix')
			got := receipt(state, arch, kernel, names, phase == 'before')!
			for key, hash in got { artifacts[phase + '_' + key] = hash }
			log := os.read_file(state + '/clonefuture/serial.log')!
			if phase == 'before' {
				failure(log, arch)
			} else {
				semantics(log, 'after', arch, false)
			}
			storage(log, arch, phase)
			probe_c := os.read_file(state + '/clonefuture/fixture.c')!
			for forbidden in ['memdup(', 'malloc(', 'calloc(', 'realloc(', 'new_array', 'v_fixed_index'] {
				assert !probe_c.contains(forbidden), forbidden
			}
			assert probe_c.count('alloca(') == 14
			assert digest(state + '/clonefuture/fixture.c') == digest(before + '/clonefuture/fixture.c') && digest(state + '/clonefuture/init') == digest(before + '/clonefuture/init')
			for name in names {
				publish(state + '/' + name + '/serial.log', out + 'clonefuture-' + phase + '-' + suffix + '-' + name + '.log')!
			}
			for path in ['receipt.json'] {
				publish(state + '/' + path, out + 'clonefuture-' + phase + '-' + suffix + '-' + path)!
			}
			publish(state + '.log', out + 'clonefuture-' + phase + '-' + suffix + '-producer.log')!
			publish(area + 'build-' + phase + '-' + suffix + '.log', out + 'clonefuture-build-' + phase + '-' + suffix + '.log')!
			artifacts[phase + '_kernel_c'] = digest(area + phase + '-' + suffix + '.c')
			artifacts[phase + '_build_log'] = digest(area + 'build-' + phase + '-' + suffix + '.log')
		}
		refstate := area + 'states/reference-' + suffix
		reference := reference_receipt(refstate, arch, digest(before + '/clonefuture/init'))!
		for key, hash in reference { artifacts['reference_' + key] = hash }
		publish(refstate + '/receipt.json', out + 'clonefuture-reference-' + suffix + '-receipt.json')!
		publish(refstate + '/serial.log', out + 'clonefuture-reference-' + suffix + '.log')!
		mut sources := {
			'auditor':              digest(@FILE)
			'controller':           digest(root + 'tests/linux-compat/run.v')
			'reference_controller': digest(root + 'tests/linux-compat/clonefuture-reference.v')
			'probe':                digest(root + 'tests/linux-compat/clonefuturefixture/core.v')
		}
		for path in ['linux_task.v', 'clone_arm64.v', 'clone_amd64.v'] {
			sources['kernel/userland/' + path] = digest(root + 'kernel/userland/' + path)
		}
		value := Evidence{ architecture: arch, context: '1880 native musl clone/clone3/pthread future-child PID namespace controls; Linux identical ELF; original 1092 raw plus 4 pthread failures; root/UID1000 and unshare/setns entry routes in initial PID namespace; namespace restoration, actual threads/keepers and fork/reap; identical cleanup inputs; targeted kernel heap retention only', base_commit: os.read_file(area + 'base.txt')!.trim_space(), artifacts: artifacts, source_inputs: sources }
		os.write_file(area + 'evidence-' + arch + '.json', json2.encode(value, prettify: true) + '\n')!
		publish(area + 'evidence-' + arch + '.json', out + 'clonefuture-evidence-' + arch + '.json')!
	}
	assert digest(area + 'states/preflight-arm/fixture.c') == digest(area + 'states/before-arm/clonefuture/fixture.c')
	assert os.read_file(area + 'preflight.log')!.contains('Probe compiler preflight: PASS')
	pins := object('/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler-inputs.json')!
	assert pins.len == 15146
	for path, hash in pins {
		assert digest('/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler/' + path) == hash.str(), path
	}
	sdk := object('/Users/alex/.cache/vinix-linux-compat/tidfault-20261015/sdk-inputs.json')!
	assert sdk.len == 2014
	for path, hash in sdk {
		assert digest(area + 'sdk/' + path) == hash.str(), path
	}
	for suffix in ['arm', 'x86'] {
		view := area + 'kernel-' + suffix + '/'
		inventory := object(view + 'docs/linux-syscall-coverage.json')!
		inputs := inventory['inputs']!.as_map()
		assert inputs.len == 67
		for path, hash in inputs {
			assert digest(view + path) == hash.str(), path
		}
		assert digest(view + 'docs/linux-syscall-coverage.json') == digest(area + 'kernel-arm/docs/linux-syscall-coverage.json')
	}
	retained := object(area + 'watch-final-retained-inputs.json')!
	assert retained.len == 84
	for path, hash in retained {
		assert path.starts_with(area + 'states/') && os.inode(path).typ == .regular && digest(path) == hash.str()
		if path.ends_with('.compiler.json') {
			command := object(path)!
			assert command['status']!.str() == '0' && command['arguments']!.str().contains('--target=aarch64-linux-musl') && command['arguments']!.str().contains('--sysroot=' + area + 'sdk')
		}
	}
	mut walked := map[string]bool{}
	for suffix in ['arm', 'x86'] {
		for phase in ['before', 'after'] {
			names := if phase == 'before' {
				['clonefuture']
			} else {
				['clonefuture', 'runtime', 'clonecgperm']
			}
			for name in names {
				probe := area + 'states/' + phase + '-' + suffix + '/' + name
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
	assert walked.len == retained.len && os.read_file(area + 'watch-final.log')!.split_into_lines().len == 8
	assert os.read_file(area + 'coverage-check.log')!.count('Linux dispatch coverage: PASS') == 4
	mut diagnostics := map[string]string{}
	for path in ['manage.v', 'manage', 'arm-cc.v', 'arm-cc', 'preflight.v', 'preflight', 'preflight.log',
		'states/preflight-arm/fixture.c', 'states/preflight-arm/init', 'assertion-control.log',
		'passing-log-control.log', 'before-linux_task.v', 'after-linux_task.v', 'before-clone_arm64.v',
		'after-clone_arm64.v', 'before-clone_amd64.v', 'after-clone_amd64.v', 'watch.v',
		'watch-final-retained-inputs.json', 'coverage-check.log', 'linux-fork-v6.12.c', 'linux-cgroup-v6.12.c','linux-nsproxy-v6.12.c'] {
		diagnostics[path] = digest(area + path)
	}
 for path in ['early-reference.v','early-reference','scope.log','scope.log.status','adjust.v','repair-probe.v'] {diagnostics[path] = digest(area+path)}
 publish(area+'scope.log',out+'clonefuture-scope.log')!
	os.write_file(area + 'diagnostic-pins.json', json2.encode(diagnostics, prettify: true) + '\n')!
	publish(area + 'diagnostic-pins.json', out + 'clonefuture-diagnostic-pins.json')!
	for path in ['assertion-control.log', 'passing-log-control.log', 'watch-final.log', 'preflight.log'] {
		publish(area + path, out + 'clonefuture-' + path)!
	}
	println('Native clonefuture conformance audit: PASS')
}
