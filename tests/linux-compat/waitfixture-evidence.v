// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import selectcheck
import json2
import os

fn require(good bool, reason string) ! {
	if !good { return error(reason) }
}

fn digest(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn body(source string, name string) !string {
	mut offset := 0
	mut start := -1
	for line in source.split_into_lines() {
		if !line.starts_with('\t') && line.contains(' ' + name + '(') && line.ends_with(' {') {
			require(start == -1, 'Repeated function definition')!
			start = offset
		}
		offset += line.len + 1
		if start >= 0 && line == '}' {
			return source[start..if offset <= source.len { offset } else { source.len }]
		}
	}
	return error('Missing function: ' + name)
}

fn pin(inputs map[string]string, suffix string, expected string) ! {
	mut found := 0
	for name, value in inputs {
		if name.ends_with(suffix) {
			require(value == expected, 'Different pinned input: ' + name)!
			found++
		}
	}
	require(found == 1, 'Missing/ambiguous pin: ' + suffix)!
}

fn object(path string) !map[string]json2.Any {
	return json2.decode[map[string]json2.Any](os.read_file(path)!)!
}

fn inventory(root string, relative string, mut files map[string]string) ! {
	path := if relative == '' { root } else { root + '/' + relative }
	require(!os.is_link(path), 'Unexpected artifact symlink: ' + relative)!
	if os.is_dir(path) {
		for name in os.ls(path)! {
			child := if relative == '' { name } else { relative + '/' + name }
			if child != 'manifest.json' { inventory(root, child, mut files)! }
		}
	} else {
		require(os.is_file(path), 'Unexpected artifact type: ' + relative)!
		files[relative] = digest(path)!
	}
}

fn generated(before string, after string, name string) ! {
	require(name in ['selectempty','maskwait'], 'Unknown fixture')!
	prefix := name+'fixture__'
	owners := if name == 'selectempty' { 2 } else { 1 }
	require(before.count('memdup(') == owners && !after.contains('memdup('), 'State still uses implicit heap copies')!
	mut reconstructed := before
	for suffix in if name == 'selectempty' { ['run','suite','storage','observer'] } else { ['run','suite'] } {
		old := body(before,prefix+suffix)!
		current := body(after,prefix+suffix)!
		reconstructed = reconstructed.replace(old,current)
		if suffix in ['suite','storage'] {
			old_proto := old.all_before('\n').trim_string_right(' {')+';\n'
			new_proto := current.all_before('\n').trim_string_right(' {')+';\n'
			require(reconstructed.count(old_proto) == 1, 'Unexpected helper prototype')!
			reconstructed = reconstructed.replace(old_proto,new_proto)
			require(current.contains(prefix+'State* s = scratch;') && current.contains('*s = ('+prefix+'State){'), 'Helper does not initialize borrowed State')!
		}
		for token in [prefix+'check(', 'printf(', 'pthread_create(', 'pthread_join('] {
			require(old.count(token) == current.count(token), 'Fixture checks or worker synchronization changed')!
		}
	}
	require(before.count('#include <alloca.h>') == 0 && after.count('#include <alloca.h>') == 1, 'Missing explicit stack allocator header')!
	if name == 'selectempty' {
		reconstructed = reconstructed.replace('i64 entered;', 'i32 entered;').replace('i64 done;','i32 done;')
		observer := body(after,prefix+'observer')!
		suite := body(after,prefix+'suite')!
		for text in ['__atomic_load_n(&s->done, 5)', '__atomic_load_n(&s->entered, 5)'] {
			require(observer.contains(text), 'Atomic load does not address shared State')!
		}
		for field in ['entered','done'] {
			require(suite.contains('__atomic_store_n(&s->'+field+', 1, 5)'), 'Atomic store does not address shared State')!
		}
		require(!observer.contains('_cabi_out_') && !suite.contains('_cabi_out_'), 'Atomic access still uses a temporary')!
		require(suite.contains('pthread_create(&worker_id, NULL, (') && suite.contains('('+prefix+'observer), s)')
			&& suite.contains('pthread_join(worker_id, NULL)'), 'Worker does not borrow/join the initialized State')!
	}
	require(reconstructed == after.replace('#include <alloca.h>\n',''), 'Generated C changed outside state ownership and atomic widths')!
	entry := body(after,prefix+'run')!
	require(entry.count(prefix+'State* scratch = ('+prefix+'State*)(alloca((size_t)(sizeof('+prefix+'State))));') == owners,
		'Entry frame must own every child State')!
}

fn verify_log(log string, name string, arch string, reference bool) ! {
	if name == 'selectempty' { selectcheck.verify(log,arch,false,reference)! }
	else { masked(log,arch,reference)! }
}

fn check(root string) ! {
	manifest := json2.decode[map[string]string](os.read_file(root+'/manifest.json')!)!
	mut actual := map[string]string{}
	inventory(root,'',mut actual)!
	require(actual == manifest, 'Missing, extra or altered evidence artifact')!
	for pair in [['arm','aarch64'],['x86','x86_64']] {
		suffix, arch := pair[0],pair[1]
		original := root+'/original-'+suffix
		native := root+'/native-'+suffix
		old_receipt := object(original+'/receipt.json')!
		receipt := object(native+'/receipt.json')!
		kernel := digest(native+'/kernel/bin/vinix')!
		for record in [old_receipt,receipt] {
			require(record['architecture']!.str() == arch && record['kernel_sha256']!.str() == kernel, 'Different native kernel/architecture')!
		}
		require(digest(original+'/kernel/bin/vinix')! == kernel, 'Baseline used a different kernel')!
		build := root+'/kernel-'+suffix
		require(os.read_file(build+'/build.log.status')!.trim_space() == '0', 'Reused kernel build failed')!
		outputs := json2.decode[map[string]string](os.read_file(build+'/outputs.json')!)!
		pin(outputs,'/kernel/bin/vinix',kernel)!
		require(digest(build+'/kernel/bin/vinix')! == kernel, 'Different reused kernel artifact')!
		for version in ['original','native'] {
			state := root+'/'+version+'-'+suffix
			results := if version == 'original' { old_receipt['results']!.as_array() } else { receipt['results']!.as_array() }
			require(results.len == 2, 'Both fixtures are required')!
			mut names := []string{}
			for value in results {
				row := value.as_map()
				name := row['name']!.str()
				require(name in ['selectempty','maskwait'] && name !in names, 'Unexpected/repeated fixture')!
				names << name
				files := if name == 'selectempty' { ['core.v','storage.v'] } else { ['core.v'] }
				pins := json2.decode[map[string]string](json2.encode(row['source_inputs']!))!
				require(pins.len == files.len, 'Incomplete frozen source set')!
				for file in files {
					expected := digest(root+'/source/'+version+'/'+name+'fixture/'+file)!
					pin(pins,'/'+name+'fixture/'+file,expected)!
					require(digest(state+'/sources/'+name+'fixture/'+file)! == expected, 'Frozen source changed')!
				}
				if version == 'original' {
					require(row['exit_code']!.int() == 1 && row['init_sha256']!.str() == '' && row['iso_sha256']!.str() == ''
						&& row['detail']!.str() == 'Command failed' && !os.exists(state+'/'+name+'/init'), 'Original unexpectedly compiled')!
					log := os.read_file(root+'/original-'+suffix+'.log')!
					require(log.contains('/'+name+'/fixture.c:') && log.contains('memdup') && log.contains('error:'), 'Missing original diagnostics')!
					continue
				}
				case_state := state+'/'+name
				probe := digest(case_state+'/init')!
				require(row['exit_code']!.int() == 0 && row['detail']!.str() == '' && row['init_sha256']!.str() == probe
					&& row['iso_sha256']!.str() == digest(case_state+'/test.iso')!, 'Fresh fixture did not pass or changed')!
				verify_log(os.read_file(case_state+'/serial.log')!,name,arch,false)!
				generated(os.read_file(original+'/'+name+'/fixture.c')!,os.read_file(case_state+'/fixture.c')!,name)!
				reference := root+'/linux-'+suffix+'-'+name
				r := object(reference+'/receipt.json')!
				require(r['architecture']!.str() == arch && r['passed']!.bool() && r['finished']!.bool()
					&& r['status']!.int() == 0 && digest(reference+'/probe')! == probe, 'Linux did not pass the fresh native ELF')!
				artifacts := r['artifacts']!.as_map()
				for key,path in {'kernel':'linux','probe':'probe','wrapper_elf':'init','initramfs':'initramfs.cpio','serial':'serial.log'} {
					require(artifacts[key]!.str() == digest(reference+'/'+path)!, 'Linux artifact changed: '+key)!
				}
				require(artifacts['wrapper_source']!.str() == digest(root+'/source/'+name+'referenceinit/core.v')!, 'Different Linux launcher source')!
				verify_log(os.read_file(reference+'/serial.log')!,name,arch,true)!
			}
		}
	}
	println('Wait fixture evidence: PASS ('+manifest.len.str()+' files; reproduced build failures, fresh native/Linux ELFs, flat cleanup and generated-C scope)')
}

fn self_test() ! {
	selectcheck.self_test()!
	good := case_lines().join('\n')+'\nLINUX MASKWAIT: PASS\nLINUX MASKWAIT SUMMARY: checks=1256 failures=0\n'
	mut positive, mut negative := 0, 0
	for arch in ['aarch64','x86_64'] { for reference in [false,true] {
		text := if reference { 'Linux version control\n'+good } else { good }
		masked(text,arch,reference)!; positive++
		mut variants := [text+'KERNEL PANIC injected\n',text.replace('checks=1256','checks=1255')]
		for line in text.split_into_lines().filter(it.starts_with('LINUX MASKWAIT')) { variants << text.replace(line+'\n',''); variants << text+line+'\n' }
		if reference { variants << good }
		for bad in variants { masked(bad,arch,reference) or { negative++; continue }; return error('Invalid mask-wait record accepted') }
	} }
	println('Fresh mask-wait parser controls: PASS ('+positive.str()+' positive, '+negative.str()+' negative)')
}

fn generated_controls(before string, after string, name string) ! {
	generated(before,after,name)!
	prefix := name+'fixture__'
	mut variants := [after+'void unrelated(void) {}', after.replace('alloca(', 'malloc('),
		after.replace(prefix+'State* s = scratch;',prefix+'State* s = memdup(scratch, sizeof(*scratch));')]
	if name == 'selectempty' {
		variants << [after.replace('__atomic_load_n(&s->done, 5)','__atomic_load_n(&temporary, 5)'),
			after.replace('i32 entered;','i64 entered;'),after.replace('pthread_join(worker_id, NULL)','0')]
	}
	mut refused := 0
	for bad in variants { generated(before,bad,name) or { refused++; continue }; return error('Invalid generated fixture accepted') }
	println('Wait fixture C controls: PASS '+name+' (1 positive, '+refused.str()+' negative)')
}

fn main() {
	if os.args.len == 2 && os.args[1] == 'self-test' { self_test() or { panic(err) }; return }
	if os.args.len == 5 && os.args[1] == 'generated' {
		generated_controls(os.read_file(os.args[3])!,os.read_file(os.args[4])!,os.args[2]) or { panic(err) }
		println('Wait fixture generated-C scope: PASS '+os.args[2]); return
	}
	if os.args.len != 2 { panic('Usage: waitfixture-evidence self-test|BUNDLE; generated CASE BEFORE-C AFTER-C') }
	check(os.args[1]) or { panic(err) }
}

fn case_lines() []string {
 mut result := []string{}
 for ordinary in 0 .. 2 { for signal in [10, 12] { for kind in 0 .. 6 { for mode in 0 .. 4 {
  checks := 11 + (if mode == 1 { 3 } else { 0 }) + (if kind in [1, 2, 3, 4] { 2 } else { 0 })
  result << 'LINUX MASKWAIT CASE: uid=' + if ordinary == 0 { '0 gid=0' } else { '1000 gid=2000' }
   + ' signal=' + signal.str() + ' wait=' + kind.str() + ' mode=' + mode.str() + ' checks=' + checks.str() + ' failures=0'
 } } } }
 return result
}
fn masked(text string, arch string, reference bool) ! {
 if arch !in ['aarch64', 'x86_64'] || (reference && !text.contains('Linux version ')) { return error('Reference architecture or Linux boot missing') }
 for bad in ['LINUX MASKWAIT FAIL', 'LINUX MASKWAIT: FAIL', 'LINUX MASKWAIT MISMATCH', 'REFERENCE FAIL', 'Kernel panic', 'BUG:', 'KERNEL PANIC', 'FATAL EXCEPTION'] {
  if text.contains(bad) { return error('Reference failure: ' + bad) }
 }
 mut expected := case_lines()
 expected << ['LINUX MASKWAIT: PASS', 'LINUX MASKWAIT SUMMARY: checks=1256 failures=0']
 mut counts := map[string]int{}
 for raw in text.split_into_lines() {
  line := raw.trim_space()
  if line.starts_with('LINUX MASKWAIT') {
   if line !in expected { return error('Unexpected reference case or summary: ' + line) }
  }
  counts[line]++
 }
 for line in expected { if counts[line] != 1 { return error('Missing or repeated result: ' + line) } }
}
