// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os

fn checked(args []string) string {
	result := os.exec(args)
	if result.exit_code != 0 { panic(args.join(' ') + '\n' + result.output) }
	return result.output
}

fn function(source string, name string) string {
	marker := 'pub fn ' + name + '('
	assert source.count(marker) == 1
	start := source.index(marker) or { panic(name) }
	end := source.index_after('\n}', start) or { panic('function end') }
	return source[start .. end + 2]
}

fn main() {
	if os.args.len != 3 { panic('usage: run CURRENT_V FRESH_EXTERNAL_ROOT') }
	v := os.real_path(os.args[1])
	root := os.abs_path(os.args[2])
	assert !os.exists(root) && !root.starts_with(os.real_path(os.getwd()) + '/')
	os.mkdir_all(root)!
	proc_source := os.read_file('kernel/proc/proc_arm64.v')!
	cpu_source := os.read_file('kernel/aarch64/cpu/cpu.v')!
	accessor := function(proc_source, 'current_thread').replace('cpu.', '')
	setter := function(proc_source, 'set_current_thread')
	model := os.read_file('tests/kernel-current-thread/model.v')!
	variants := {
		'fixed': accessor
		'unguarded': accessor.replace('saved := interrupt_save()', 'saved := model_daif')
		'early-restore': accessor.replace('cpu_num := read_tpidr_el1()', 'cpu_num := read_tpidr_el1()\n interrupt_restore(saved)').replace('\n\tinterrupt_restore(saved)\n\treturn', '\n\treturn')
		'enable-all': accessor.replace('interrupt_restore(saved)', 'interrupt_restore(0)').replace('saved := interrupt_save()', '_ := interrupt_save()')
		'leave-masked': accessor.replace('interrupt_restore(saved)', 'assert saved <= 0x3c0')
	}
	mut outcomes := map[string]json2.Any{}
	for name, body in variants {
		path := root + '/' + name
		os.write_file(path + '.v', model + '\n' + body + '\n' + setter)!
		checked([v, '-new-compiler', '-no-parallel', '-nocache', '-gc', 'none', '-cc', 'cc', '-o', path + '.c', path + '.v'])
		vlib := os.dir(v) + '/vlib'
		checked(['cc', '-O0', '-pthread', '-I' + vlib + '/builtin', path + '.c', vlib + '/builtin/segfault_handler_nix.c', vlib + '/os/execute_capture_nix.c', '-lm', '-o', path])
		result := os.exec([path])
		os.write_file(path + '.log', result.output)!
		assert (result.exit_code == 0) == (name == 'fixed'), name + ' mutation result unexpected'
		outcomes[name] = json2.Any(result.exit_code)
	}
	// Compile the exact privileged production assembly without executing it.
	assembly := function(cpu_source, 'interrupt_save') + '\n' + function(cpu_source, 'interrupt_restore') + '\n' + function(cpu_source, 'read_tpidr_el1')
	cross := root + '/arm64'
	os.write_file(cross + '.v', '@[has_globals]\nmodule main\nstruct Thread { id u64 }\n__global ( per_cpu_current_thread [256]voidptr )\n' + accessor + '\n' + setter + '\n' + assembly + '\nfn main() { println(current_thread()) }\n')!
	checked([v, '-new-compiler', '-no-parallel', '-nocache', '-gc', 'none', '-os', 'linux', '-arch', 'arm64', '-o', cross + '.c', cross + '.v'])
	checked(['/opt/homebrew/bin/aarch64-linux-musl-gcc', '-O2', '-fno-inline', '-S', cross + '.c', '-o', cross + '.s'])
	asm_text := os.read_file(cross + '.s')!
	lookup := asm_text.all_after('\ncurrent_thread:').all_before('\n\t.size\tcurrent_thread,')
	save := lookup.index('bl\tinterrupt_save') or { panic('ARM save missing') }
	index := lookup.index('bl\tread_tpidr_el1') or { panic('ARM CPU read missing') }
	load := lookup.index('lsl 3]') or { panic('ARM slot load missing') }
	restore := lookup.index('bl\tinterrupt_restore') or { panic('ARM restore missing') }
	assert save < index && index < load && load < restore
	assert asm_text.contains('mrs x0, daif') && asm_text.contains('msr daifset, #0xf')
	assert asm_text.contains('msr daif, x0')
	generated := os.read_file(cross + '.c')!
	for signature in ['void interrupt_restore(u64 saved) {', 'u64 interrupt_save(void) {'] {
		assert generated.count(signature) == 1
		assert generated.all_after(signature).all_before('\n}').contains('"memory"')
	}
	os.write_file(root + '/audit.json', json2.encode({
		'compiler': json2.Any(checked([v, 'version']).trim_space()),
		'compiler_sha256': json2.Any(sha256.sum(os.read_bytes(v)!).hex()),
		'proc_sha256': json2.Any(sha256.sum(proc_source.bytes()).hex()),
		'cpu_sha256': json2.Any(sha256.sum(cpu_source.bytes()).hex()),
		'outcomes': json2.Any(outcomes)
	}, prettify: true))!
	println('CURRENT-THREAD-CHECK-PASS production accessor, four refused mutants, ARM assembly retained')
}
