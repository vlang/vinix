// SPDX-License-Identifier: GPL-2.0-only
module main

import os
import json2
import hosttest

const scope = 'Execute unchanged const-string ownership, typed Linux facades, native range classifier and page/string allocation chain through independent endpoint/page transports. Native linker placement and retained kernel allocations require separate guest evidence.'
const functions = ['const_string_kfree','const_string_kstrdup','kstrdup','kstrndup','strnlen','kmemdup_nul','is_null','require','runtime_gfp_supported','runtime_alloc_gfp_pages','runtime_kmalloc','runtime_kfree','runtime_ksize','page_allocation_size','native_kmalloc','native_kfree']
const exports = ['vkc_kfree_const','vkc_kstrdup_const','kstrdup','kstrndup','kmemdup_nul','vinix_linuxkpi_gfp_supported','vinix_linuxkpi_alloc_gfp_pages','vkr_kmalloc','vkr_kfree','vkr_ksize','vkr_page_allocation_size','kmalloc','kfree']

fn generation_capture(argv []string,_log string,_timeout int,env map[string]string) !hosttest.Result {
	output := argv[argv.index('-o')+1]
	os.cp_all(argv.last(),output+'.source',false)!
	mut child := env.clone()
	for key, name in {'VCACHE':'vcache','V3CACHE':'v3cache','VTMP':'vtmp'} { child[key] = os.dir(output)+'/'+name }
	mut recorded := map[string]json2.Any{}
	for key in ['V','VEXE','V_MACOS_V3_CALLER_VEXE','VCACHE','V3CACHE','VTMP','TMPDIR'] { recorded[key] = child[key] or { '<unset>' } }
	hosttest.write_json(output+'.generation-environment.json',recorded)!
	result := hosttest.capture(argv,output+'.generation.log',180,child)!
	hosttest.write_json(output+'.generation-status.json',{'exit_code':json2.Any(result.code)})!
	if result.code != 0 { return error('V generation failed exit ${result.code}: ${output}.generation.log') }
	return result
}
fn generate(source string,path string) ! {
	hosttest.generate_module_with_capture(source,path,'amd64',['linuxkpi_host_test','linuxkpi','nofloat'],generation_capture)!
}
fn name(body string) string { return body.all_before('\n').all_before_last('(').all_after_last(' ').trim_left('*') }

fn select_source(raw string,group string) !string {
	mut selected := []string{}
	for body in hosttest.c_bodies(raw) {
		symbol := name(body)
		if symbol in [group+'__vinit',group+'__vinit_caller',group+'__vno_main_init_caller'] ||
			(group == 'compatcore' && (functions.map('compatcore__'+it).contains(symbol) || symbol in exports)) ||
			(group == 'headercore' && symbol in ['headercore__const_string_free','headercore__const_string_dup','kfree_const','kstrdup_const']) ||
			(group == 'linuxkpi' && symbol in ['linuxkpi__const_string_is_rodata','vinix_linuxkpi_is_kernel_rodata']) ||
			(group == 'conststringfixture' && (symbol.starts_with(group+'__') || symbol in ['main','csh_rodata_start','csh_rodata_end','vinix_linuxkpi_page_size','vinix_linuxkpi_may_sleep','vinix_linuxkpi_alloc_pages','vinix_linuxkpi_free_pages','vinix_linuxkpi_bug'])) {
			selected << body
		}
	}
	if selected.len == 0 { return error('Missing generated bodies: '+group) }
	mut metadata := []string{}
	mut globals := []string{}
	mut constants := []string{}
	for line in raw.split_into_lines() {
		if line.starts_with('typedef ') && line.contains('Array_fixed_') { metadata << line }
		if line.starts_with('#define ') && (line.starts_with('#define E_STRUCT ') || line.contains(group+'__')) { constants << line }
		if line.ends_with(';') && !line.starts_with('typedef ') && !line.starts_with('extern ') && !line.starts_with(' ') && !line.starts_with('\t') && !line.all_before('=').contains('(') && line.contains(group+'__') { globals << line }
	}
	if group == 'compatcore' {
		metadata << 'typedef struct compatcore__RuntimeAllocation compatcore__RuntimeAllocation;'
		metadata << hosttest.record(raw,'compatcore__RuntimeAllocation')!
	}
	header := match group {
		'compatcore' { '#include "linuxkpi_v_primitives.h"\n#include "linuxkpi_const_string_v_primitives.h"\n#include <string.h>\nvoid *vinix_linuxkpi_alloc_pages(size_t,bool);\n' }
		'headercore' { '#include "linuxkpi_const_string_v_contract.h"\n' }
		'linuxkpi' { '#include "linuxkpi_v_primitives.h"\n#include "linuxkpi_const_string_v_primitives.h"\n#include "symbols.h"\n' }
		else { '#include "contract.h"\n' }
	}
	unsigned := if group in ['compatcore','linuxkpi'] { 'typedef uint8_t u8;typedef uint16_t u16;typedef uint32_t u32;typedef uint64_t u64;\n' } else { '' }
	text := '#include <stdint.h>\n#include <stddef.h>\n#include <stdbool.h>\ntypedef int8_t i8;typedef int32_t i32;typedef int64_t i64;typedef size_t usize;typedef void *voidptr;\n#define VNORETURN __attribute__((noreturn))\n'+unsigned+header+metadata.join('\n')+'\n'+constants.join('\n')+'\n'+globals.join('\n')+'\n'+selected.map(it.all_before('\n').all_before_last(' {')+';').join('\n')+'\n'+selected.join('\n\n')+'\n'
	if hosttest.c_bodies(text) != selected { return error('Generated body changed: '+group) }
	return text
}

fn compile_input(argv []string,source string,object string,env map[string]string) !json2.Any {
	dep := object+'.d'
	hosttest.command([...argv,'-E','-dD','-MD','-MF',dep,'-MT',object,source,'-o',object+'.i'],object+'.preprocess.log',180,env)!
	before := hosttest.hashes(hosttest.dependency_paths(os.read_file(dep)!,object)!)!
	hosttest.command([...argv,'-c',source,'-o',object],object+'.compile.log',180,env)!
	if before != hosttest.hashes(before.keys())! { return error('Compiler input changed: '+object) }
	return {'source':json2.Any(source),'object':object,'argv':hosttest.strings(argv),'dependency_sha256':hosttest.string_map(before)}
}

fn flags(work string,linux string,standard string,optimization string,host bool) ![]string {
	root := hosttest.root()
	mut argv := hosttest.shell_split(hosttest.env_default('CC','clang'))!
	if host {
		$if macos { argv << ['-arch','x86_64'] }
		argv << ['-iquote',work+'/include']
		argv << ['-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-D_FORTIFY_SOURCE=0','-DVINIX_LINUXKPI_HOST_TEST','-include',root+'/tests/linuxkpi/host_types.h']
	} else {
		argv << ['--target=x86_64-unknown-none','-nostdinc','-fno-stack-protector','-fstack-usage','-isystem',root+'/kernel/freestnd-c-hdrs','-I',root+'/kernel/c']
	}
	argv << ['-std='+standard,'-'+optimization,'-ffreestanding','-fno-builtin','-fwrapv','-fno-strict-aliasing','-ffunction-sections','-fdata-sections','-Wall','-Wextra','-Werror','-Wno-unused-function','-Wno-unused-parameter','-Wno-sign-compare','-DVINIX_LINUXKPI','-D__KERNEL__','-include','linux/kconfig.h','-include',linux+'/include/linux/compiler_types.h']
	for path in [work+'/include',root+'/tests/linuxkpi/conststringfixture',root+'/kernel/linuxkpi/include',linux+'/include',linux+'/include/uapi',linux+'/arch/x86/include',linux+'/arch/x86/include/uapi'] { argv << ['-I',path] }
	argv << ['-iquote',root+'/kernel/c']
	return argv
}

fn run(keep string) ! {
	root := hosttest.root()
	linux := hosttest.env_default('LINUXKPI_SOURCE_DIR',root+'/third_party/linux-i915/linux-6.6.157')
	hosttest.verify_upstream(linux,hosttest.upstream_pin()!)!
	work := hosttest.work_dir(keep,'vinix-const-string-')!
	defer { if keep == '' { hosttest.remove_work_dir(work) or { eprintln(err) } } }
	mut inputs := [@FILE,os.executable(),root+'/kernel/linuxkpi/const_string_d_linuxkpi.v',root+'/tests/linuxkpi/conststringfixture/README.md',root+'/build-support/find-v.sh']
	for schema in ['atomic-exchange','overflow','spinlock'] { inputs << root+'/kernel/linuxkpi/abi/'+schema+'.json' }
	for directory in ['kernel/linuxkpi/compatcore','kernel/linuxkpi/headercore','kernel/c','tests/linuxkpi/hosttest','tests/linuxkpi/conststringfixture'] {
		for extension in ['.v','.h'] { inputs << os.walk_ext(root+'/'+directory,extension) }
	}
	mut env := os.environ()
	mut tool_proofs := []json2.Any{}
	mut tool_commands := map[string][]string{'cc':hosttest.shell_split(hosttest.env_default('CC','clang'))!,'nm':[hosttest.tool('llvm-nm')],'objdump':[hosttest.tool('llvm-objdump')]}
	for key in ['V','VEXE'] { if command := env[key] { if command != '' { tool_commands[key] = [command] } } }
	for key,argv in tool_commands {
		if argv.len == 0 { return error('Empty tool: '+key) }
		path := os.find_abs_path_of_executable(argv[0])!
		inputs << path
		version := hosttest.command([...argv,if key in ['V','VEXE'] { 'version' } else { '--version' }],work+'/tool-'+key+'.log',30,env)!
		tool_proofs << json2.Any({'name':json2.Any(key),'path':path,'sha256':hosttest.sha(path)!,'version':version.stdout+version.stderr})
	}
	before := hosttest.hashes(inputs)!
	env['ASAN_OPTIONS'] = 'detect_stack_use_after_return=1:abort_on_error=1'
	env['UBSAN_OPTIONS'] = 'halt_on_error=1'
	for group in ['compatcore','headercore','linuxkpi','conststringfixture'] { os.mkdir_all(work+'/stage/'+group)! }
	for path in ['const_string.v','runtime.v','primitives.v','string.v'] { os.cp(root+'/kernel/linuxkpi/compatcore/'+path,work+'/stage/compatcore/'+path)! }
	for group in ['compatcore','headercore','linuxkpi'] { os.write_file(work+'/stage/'+group+'/anchor.v','@[translated]\nmodule '+group+'\n__global csh_guard_anchor i32=-1\n')! }
	os.cp(root+'/kernel/linuxkpi/headercore/const_string.v',work+'/stage/headercore/const_string.v')!
	os.cp(root+'/kernel/linuxkpi/const_string_d_linuxkpi.v',work+'/stage/linuxkpi/core.v')!
	os.cp(root+'/tests/linuxkpi/conststringfixture/core.v',work+'/stage/conststringfixture/core.v')!
	for schema, file in {'atomic-exchange':'atomic_exchange','overflow':'integer_policy','spinlock':'spinlock_adapters'} { hosttest.generate_abi(root+'/kernel/linuxkpi/abi/'+schema+'.json',root+'/kernel/linuxkpi',work+'/include/vinix/'+file+'.h')! }
	os.write_file(work+'/include/symbols.h','void *csh_rodata_start(void);\nvoid *csh_rodata_end(void);\n#define rodata_start (csh_rodata_start())\n#define rodata_end (csh_rodata_end())\n')!
	mut proofs := []json2.Any{}
	for group in ['compatcore','headercore','linuxkpi','conststringfixture'] {
		actual := work+'/'+group+'-actual.c'
		generate(work+'/stage/'+group,actual)!
		selected := select_source(os.read_file(actual)!,group)!
		os.write_file(work+'/'+group+'-selected.c',selected)!
		mut hashes := map[string]string{}
		for body in hosttest.c_bodies(selected) { hashes[name(body)] = hosttest.text_sha(body) }
		if group in ['compatcore','headercore'] {
			reference := work+'/'+group+'-full.c'
			generate(root+'/kernel/linuxkpi/'+group,reference)!
			full := hosttest.c_bodies(os.read_file(reference)!)
			for body in hosttest.c_bodies(selected) {
				if name(body) == group+'__vinit' { continue }
				matches := full.filter(hosttest.named_body(it,name(body)))
				if matches.len != 1 || matches[0] != body { return error('Full production parity failed: '+name(body)) }
			}
		}
		if group != 'conststringfixture' {
			for forbidden in ['memdup(','new_array','new_map','v_malloc(','string__substr(','box_to_interface'] {
				if selected.contains(forbidden) { return error('Hidden production allocation: '+forbidden) }
			}
		}
		proofs << json2.Any({'module':json2.Any(group),'body_sha256':hosttest.string_map(hashes)})
	}
	mut objects := []json2.Any{}
	mut runs := []json2.Any{}
	for standard in ['gnu99','gnu11'] {
		for optimization in ['O0','O1','O2'] {
			tag := standard+'-'+optimization
			mut linked := []string{}
			for host in [false,true]! {
				for group in ['compatcore','headercore','linuxkpi','conststringfixture'] {
					if !host && group == 'conststringfixture' { continue }
					mut argv := flags(work,linux,standard,optimization,host)!
					if group == 'compatcore' { argv << '-DVINIX_V_RUNTIME' }
					object := work+'/'+tag+'-'+group+if host { '-host.o' } else { '-native.o' }
					objects << compile_input(argv,work+'/'+group+'-selected.c',object,env)!
					if host { linked << object; continue }
					imports := hosttest.command([hosttest.tool('llvm-nm'),'--undefined-only',object],object+'.imports.log',30,env)!.stdout
					mut allowed := match group {
						'compatcore' { ['vinix_linuxkpi_is_kernel_rodata','vinix_linuxkpi_page_size','vinix_linuxkpi_may_sleep','vinix_linuxkpi_alloc_pages','vinix_linuxkpi_free_pages','vinix_linuxkpi_bug','memcpy','memset'] }
						'headercore' { ['vkc_kfree_const','vkc_kstrdup_const'] }
						else { ['rodata_start','rodata_end'] }
					}
					mut actual := imports.split_into_lines().filter(it.fields().len > 0).map(it.fields().last())
					actual.sort(); allowed.sort()
					if actual != allowed { return error('Changed production imports: '+imports) }
					stack := os.read_file(object[..object.len-2]+'.su')!
					if stack == '' || stack.split_into_lines().any(it != '' && !it.ends_with('\tstatic')) { return error('Missing/unbounded stack: '+object) }
					hosttest.command([hosttest.tool('llvm-objdump'),'-dr','--no-show-raw-insn',object],object+'.disassembly.log',60,env)!
				}
			}
			executable := work+'/'+tag
			strip := $if macos { '-Wl,-dead_strip' } $else { '-Wl,--gc-sections' }
			hosttest.command([...flags(work,linux,standard,optimization,true)!,...linked,strip,'-o',executable],executable+'.link.log',180,env)!
			passed := hosttest.command([executable],executable+'.run.log',60,env)!
			if passed.stderr != '' || !passed.stdout.contains('PASS: original const strings;') || !passed.stdout.contains('scenarios=4') || !passed.stdout.contains('live_pages=0') { return error('Missing clean verdict: '+executable) }
			runs << json2.Any({'standard':json2.Any(standard),'optimization':optimization,'exit_code':passed.code,'output':passed.stdout})
			println(tag+': '+passed.stdout.trim_space())
		}
	}
	if before != hosttest.hashes(before.keys())! { return error('Sources changed during const-string checks') }
	hosttest.write_json(work+'/result.json',{'scope':json2.Any(scope),'source_sha256':hosttest.string_map(before),'tools':tool_proofs,'generated_body_proofs':proofs,'objects':objects,'runs':runs,'artifact_sha256':hosttest.string_map(hosttest.hashes(os.walk_ext(work,''))!)})!
}

fn main() {
	keep := hosttest.parse_keep_dir(os.args[1..],'Usage: const_string.v [--keep-dir NEW]',scope) or { eprintln(err); exit(2) }
	run(keep) or { eprintln(err); exit(1) }
}
