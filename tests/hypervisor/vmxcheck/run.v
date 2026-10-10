// SPDX-License-Identifier: GPL-2.0-only
module vmxcheck

import fixturehost
import hosttest
import os

fn (c Config) instructions(text string) ! {
	obj := c.output('privileged.o')
	c.inherited(combine(c.cross(), generated_flags(), ['-c', c.output('privileged.c'), '-o', obj]))!
	c.audit(obj)!
	mut objdump := c.env['LLVM_OBJDUMP'] or { '' }
	if objdump == '' { objdump = c.objdump_path() }
	assembly := c.text_command([objdump, '-d', '--no-show-raw-insn', obj])!
	check_instructions(assembly, text)!
}

fn (c Config) check(original string) ! {
	c.host()!
	source := c.output('privileged.c')
	mut text := hosttest.module_read_text(source)!
	text += '\n_Static_assert(sizeof(lib__VmxFxState) == 512, "FXSAVE area");\n'
	text += '_Static_assert(sizeof(struct vinix_vmx_descriptor) == 10, "GDTR/IDTR area");\n'
	hosttest.module_write_text(source, text)!
	c.instructions(text)!
	println('VMX INSTRUCTION PASS: optimized x86 ports, CF/ZF capture, operands and barriers')
	c.inherited(combine(c.cross(), ['-c', c.path('kernel/asm/x86_64/vmx.S'), '-o', c.output('entry.o')]))!
	if original != '' {
		c.inherited(combine(c.cross(), ['-c', original, '-o', c.output('original.o')]))!
		old := symbol_bytes(c.output('original.o'), 'vinix_vmx_enter')!
		new := symbol_bytes(c.output('entry.o'), 'vinix_vmx_enter')!
		if old.len == 0 || old != new { return CheckError{ message: 'VM entry bytes changed' } }
		println('VMX ENTRY PASS: all ${new.len} instruction bytes match original C assembly')
	}
	println('PASS VMX production V C ABI, ASan/UBSan, x86 assembly and no allocator imports')
}

fn failure_message(err IError) string {
	if err is fixturehost.CommandError {
		return 'Command failed (${err.status}): ' + hosttest.shell_join(err.argv)
	}
	if err is fixturehost.FileError && err.filename != '' {
		return err.message + ': ' + err.filename
	}
	return err.msg()
}

pub fn run(arguments []string) int {
	options := hosttest.parse_arguments(arguments, [hosttest.Option{'--original', true, []string{}}], 0,
		'Usage: tests/hypervisor/check-vmx [--original PRE_PORT_VMX_C]',
		'Test production VMX exports, compile privileged ports and compare entry bytes.') or {
		eprintln(err.msg())
		return 2
	}
	original := if '--original' in options.options {
		hosttest.module_resolve(options.options['--original']) or {
			eprintln(err.msg())
			return 1
		}
	} else {
		''
	}
	root := hosttest.root()
	caller := if os.uname().machine in ['arm64', 'aarch64'] { 'arm64' } else { 'amd64' }
	base := Config{ caller: caller, env: os.environ() }
	v := base.text_command(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'find-v',
		root]) or {
		eprintln(failure_message(err))
		return 1
	}
	work := hosttest.work_dir('', 'vinix-vmx-') or {
		eprintln(err.msg())
		return 1
	}
	defer { hosttest.remove_work_dir(work) or { eprintln(err.msg()) } }
	c := Config{ root: root, work: work, caller: caller, compiler: hosttest.env_default('CC', 'clang'), v: v, env: os.environ() }
	c.check(original) or {
		eprintln(failure_message(err))
		return 1
	}
	return 0
}
