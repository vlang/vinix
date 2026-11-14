// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import ppollsignalcheck
import json2
import os
import strconv
import strings

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

fn passed(receipt map[string]json2.Any, arch string) ! {
	require(receipt['architecture']!.str() == arch && receipt['passed']!.bool()
		&& receipt['finished']!.bool() && receipt['status']!.int() == 0, 'Unfinished/failed session')!
}

// V includes the source file's absolute-path hash in ignored-variable names.
// Separate worktrees change that identifier component without changing code.
fn canonical(source string) string {
	mut result := strings.new_builder(source.len)
	mut position := 0
	for position < source.len {
		if source[position] == `_` && position + 10 <= source.len && source[position..position + 10] == '__discard_' {
			result.write_string('__discard_')
			position += '__discard_'.len
			for position < source.len && source[position] >= `0` && source[position] <= `9` { position++ }
		} else {
			result.write_u8(source[position])
			position++
		}
	}
	return result.str()
}

fn groups(log string, kernel string, resolver string, cold bool) ! {
 mut headers := 0
 mut live := u64(0)
 mut total := u64(0)
 mut targets := map[u64]u64{}
 for raw in log.split_into_lines() {
  if !raw.contains('PERF-SITE ppollsignal phase=after ') { continue }
  f := raw.all_after('PERF-SITE ppollsignal phase=after ').trim_space().fields()
  if f.len == 4 && f[0] == 'live' {
   require(f[2] == 'dropped' && f[3] == '0','Allocation groups dropped')!
   live = strconv.parse_uint(f[1],10,64)!
   headers++
   continue
  }
  require(f.len == 12,'Truncated allocation group')!
  count := strconv.parse_uint(f[0],10,64)!
  size := strconv.parse_uint(f[1],10,64)!
  require(count > 0 && count <= 65536,'Bad group count')!
  total += count
  require(total <= 65536,'Allocation table count overflow')!
  mut command := [resolver,'-afi','-e',kernel]
  for pc in f[2..] {
   address := strconv.parse_uint(pc,16,64)!
   if address >= 4 { command << '0x'+(address-4).hex() }
  }
  if size in [u64(64),192] {
   require(cold,'Unexpected warm target-sized allocation')!
   named := os.exec(command)
   require(named.exit_code == 0 && named.output.contains('futex__get'),'Target allocation did not resolve to futex get')!
   targets[size] += count
  }
 }
 require(headers == 1 && total == live,'Incomplete/duplicate trace dump')!
 if cold { require(targets[64] == 2 && targets[192] == 1,'Missing 320-byte futex table pattern')! }
 else { require(targets.len == 0,'Warm cache still initialized inside measurement')! }
}
fn generated(before string, after string) ! {
 helper := body(after,'ppollsignalfixture__warm_join_futex')!
 prototype := helper.all_before('\n').trim_string_right(' {')+';\n'
 require(after.count(prototype) == 1,'Missing helper prototype')!
 stripped := after.replace(prototype,'').replace(helper+'\n','')
 old := body(before,'ppollsignalfixture__run')!
 new := body(after,'ppollsignalfixture__run')!
 calls := new.split_into_lines().filter(it.trim_space() == 'ppollsignalfixture__warm_join_futex();')
 require(calls.len == 1 && new.replace(calls[0]+'\n','') == old,'Child entry changed outside warm call')!
 require(canonical(before.replace(old,new)) == canonical(stripped),'Fixture C changed outside warm helper/entry call')!
 require(helper.count('alloca(') == 2 && helper.contains('.tv_nsec = 1') && helper.contains('128') && helper.contains('ETIMEDOUT'),'Wrong warm syscall/storage')!
 for bad in ['memdup(','malloc(','__new_array','array_push('] { require(!helper.contains(bad),'Warm helper allocated: '+bad)! }
}
fn check(root string, historical string) ! {
 require(digest(historical+'/manifest.json')! == 'f2721913f472189a9e1a84e72d9ecdebde97acaa0e516ce3c1298645b08c101e','Different historical bundle')!
 old_audit := os.exec([historical+'/evidence-final',historical])
 require(old_audit.exit_code == 0 && old_audit.output.contains('Ppoll signal evidence: PASS (785 files;'),'Complete historical audit failed: '+old_audit.output)!
 manifest := json2.decode[map[string]string](os.read_file(root+'/manifest.json')!)!
 mut found := map[string]string{}
 inventory(root,'',mut found)!
 require(found == manifest,'Current artifact inventory changed')!
 require(os.read_file(root+'/controls.log')!.trim_space() == 'Ppoll allocation controls: PASS (3 positive, 15 negative)','Diagnostic controls failed')!
 unchanged := os.exec([root+'/delta-final',root+'/native-arm/serial.log'])
 require(unchanged.exit_code == 0 && unchanged.output.trim_space() == '', 'Initial two-phase experiment did not retain identical complete groups')!
 review := os.read_file(root+'/review.txt')!
 require(review.contains('Independent warmup/diagnostic lifetime review: PASS.'),'Missing lifetime review')!
 for path in ['source/tests/linux-compat/ppollsignalfixture/core.v','source/tests/linux-compat/ppollsignalfixture/storage.v','source/tests/linux-compat/ppollsignalfixture/bounds.v','source/tests/linux-compat/ppollsignal-alloc-trace.v','source/tests/linux-compat/ppollsignal-slab-trace.v','source/tests/linux-compat/ppollsignal-alloc-delta.v','source/tests/linux-compat/ppollsignal-alloc-check.v','compile-warm-arm/fixture.c','compile-warm-x86/fixture.c','build-slab-arm/blob.c','compile-arm/fixture.c'] { require(review.contains(digest(root+'/'+path)!),'Outdated reviewed input: '+path)! }
 for pair in [['arm','aarch64'],['x86','x86_64']] {
  suffix, arch := pair[0],pair[1]
  compile := root+'/compile-warm-'+suffix
  probe := digest(compile+'/probe')!
  kernel := digest(historical+'/build-'+suffix+'/kernel/bin/vinix')!
  inputs := object(compile+'/receipt.json')!
  sources := json2.decode[map[string]string](json2.encode(inputs['inputs']!))!
  for file in ['core.v','storage.v','bounds.v'] { pin(sources,'/ppollsignalfixture/'+file,digest(root+'/source/tests/linux-compat/ppollsignalfixture/'+file)!)! }
  generated(os.read_file(historical+'/compile-'+suffix+'-r2/fixture.c')!,os.read_file(compile+'/fixture.c')!)!
  native := root+'/native-warm-'+suffix
  nr := object(native+'/receipt.json')!
  passed(nr,arch)!
  require(nr['kernel']!.str() == kernel && digest(native+'/kernel/bin/vinix')! == kernel && nr['probe']!.str() == probe && digest(native+'/rootfs/sbin/init')! == probe && nr['serial']!.str() == digest(native+'/serial.log')!,'Different native result identity')!
  ppollsignalcheck.verify(os.read_file(native+'/serial.log')!,arch,false,false)!
  reference := root+'/reference-warm-'+suffix
  rr := object(reference+'/receipt.json')!
  passed(rr,arch)!
  artifacts := rr['artifacts']!.as_map()
  for key,path in {'kernel':'linux','probe':'probe','wrapper_elf':'init','initramfs':'initramfs.cpio','serial':'serial.log'} { require(artifacts[key]!.str() == digest(reference+'/'+path)!,'Reference artifact changed')! }
  require(digest(reference+'/probe')! == probe && digest(reference+'/init')! == digest(compile+'/reference-init')!,'Reference used different ELF/launcher')!
  ppollsignalcheck.verify(os.read_file(reference+'/serial.log')!,arch,false,true)!
  registered := root+'/registered-warm-'+suffix+if suffix == 'arm' { '-r1' } else { '' }
  reg := object(registered+'/receipt.json')!
  require(reg['kernel_sha256']!.str() == kernel && reg['results']!.as_array().len == 1,'Different registered kernel/cases')!
  row := reg['results']!.as_array()[0].as_map()
  require(row['name']!.str() == 'ppollsignal' && row['exit_code']!.int() == 0 && row['init_sha256']!.str() == digest(registered+'/ppollsignal/init')! && row['iso_sha256']!.str() == digest(registered+'/ppollsignal/test.iso')!,'Registered case failed/changed')!
  frozen := json2.decode[map[string]string](json2.encode(row['source_inputs']!))!
  require(frozen.len == 3,'Incomplete frozen inputs')!
  for file in ['core.v','storage.v','bounds.v'] { pin(frozen,'/ppollsignalfixture/'+file,digest(root+'/source/tests/linux-compat/ppollsignalfixture/'+file)!)! }
  ppollsignalcheck.verify(os.read_file(registered+'/ppollsignal/serial.log')!,arch,false,false)!
 }
 traced_kernel := digest(root+'/build-slab-arm/kernel/bin/vinix')!
 for label in ['native-slab-arm','native-slab-warm-arm'] {
  r := object(root+'/'+label+'/receipt.json')!
  passed(r,'aarch64')!
  require(r['kernel']!.str() == traced_kernel && r['serial']!.str() == digest(root+'/'+label+'/serial.log')!,'Different attribution kernel/log')!
 }
 require(digest(root+'/native-slab-arm/rootfs/sbin/init')! == digest(historical+'/compile-arm-r2/probe')!,'Cold attribution changed production ELF')!
 require(digest(root+'/native-slab-warm-arm/rootfs/sbin/init')! == digest(root+'/compile-warm-arm/probe')!,'Warm attribution changed probe ELF')!
 cold := os.read_file(root+'/native-slab-arm/serial.log')!
 warm := os.read_file(root+'/native-slab-warm-arm/serial.log')!
 os.setenv('DYLD_LIBRARY_PATH',root+'/lib',true)
 groups(cold,root+'/build-slab-arm/kernel/bin/vinix',root+'/bin/llvm-addr2line',true)!
 groups(warm,root+'/build-slab-arm/kernel/bin/vinix',root+'/bin/llvm-addr2line',false)!
 mut refused := false
 ppollsignalcheck.verify(cold,'aarch64',false,false) or { refused = err.msg() == 'Storage changed' }
 require(refused,'Reproduced cold guard no longer refuses growth')!
 ppollsignalcheck.verify(warm,'aarch64',false,false)!
 println('Ppoll signal warmup evidence: PASS ('+manifest.len.str()+' files; complete historical audit, 320-byte attribution, unchanged production kernels, 672 native/Linux checks per architecture, flat warm cohorts; older extra size64 remains unattributed)')
}
fn main() {
 if os.args.len != 3 { panic('Usage: ppollsignal-warm-evidence BUNDLE HISTORICAL-POLL-SIGNAL-BUNDLE') }
 check(os.args[1],os.args[2]) or { panic(err) }
}
