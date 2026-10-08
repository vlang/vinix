// SPDX-License-Identifier: GPL-2.0-or-later
// Immutable header oracles and unchanged independent native overflow fixtures.
module main

import os
import json2
import hosttest

const original = 'd0a65f5953058f4f7542cd588acbb38039491c04'

fn command(argv []string) !hosttest.Result {
	result := hosttest.capture(argv, '', -1, os.environ())!
	if result.code != 0 { return error(result.stdout + result.stderr) }
	return result
}

fn compile(argv []string) ! {
	result := command(argv)!
	print(result.stdout); eprint(result.stderr)
}

fn immutable_header(header string) !string {
	result := hosttest.capture_in(['git', 'show', original + ':kernel/linuxkpi/include/' + header], '', -1, os.environ(), hosttest.root())!
	if result.code != 0 { return error(result.stderr) }
	return result.stdout
}

fn remove_macro(text string, name string) !string {
	needle := '#define ' + name + '('
	mut start := 0
	for start < text.len {
		line_end := start + (text[start..].index('\n') or { text.len - start })
		if text[start..line_end].starts_with(needle) {
			mut end := start
			for end < text.len {
				stop := end + (text[end..].index('\n') or { text.len - end })
				continued := text[end..stop].ends_with('\\')
				end = if stop < text.len { stop + 1 } else { stop }
				if !continued { break }
			}
			return text[..start] + text[end..]
		}
		start = line_end + 1
	}
	return error('Missing immutable original macro: ' + name)
}

fn replace_policy_macro(text string, name string) !string {
	needle := '#define ' + name + '('
	mut result := ''
	mut count := 0
	mut start := 0
	for start < text.len {
		stop := start + (text[start..].index('\n') or { text.len - start })
		end := if stop < text.len { stop + 1 } else { stop }
		if stop < text.len && text[start..stop].starts_with(needle) {
			result += '#include <vinix/integer_policy.h>\n'; count++
		} else { result += text[start..end] }
		start = end
	}
	if count != 1 { return error('Expected one immutable ' + name + ' policy macro') }
	return result
}

fn prepare(work string, arch string) ! {
	root := hosttest.root()
	for name in ['overflowfixture', 'overflowdomain'] {
		source := os.join_path(work, name)
		os.mkdir(source)!
		os.cp(os.join_path(root, 'tests/linuxkpi', name, 'core.v'), os.join_path(source, 'core.v'))!
		hosttest.generate_module(source, os.join_path(work, name + '.c'), arch, ['nofloat'])!
	}
	os.mkdir(os.join_path(work, 'headercore'))!
	os.cp(os.join_path(root, 'kernel/linuxkpi/headercore/policy.v'), os.join_path(work, 'headercore/policy.v'))!
	schema_path := os.join_path(root, 'kernel/linuxkpi/abi/overflow.json')
	hosttest.generate_abi(schema_path, work, os.join_path(work, 'V/include/vinix/integer_policy.h'))!
	baseline := os.join_path(work, 'original/include')
	for header in ['linux/overflow.h', 'linux/slab.h', 'linux/preempt.h', 'linux/irqflags.h', 'asm/processor.h'] {
		path := os.join_path(baseline, header)
		os.mkdir_all(os.dir(path))!
		os.write_file(path, immutable_header(header)!)!
	}
	mut replacement := os.read_file(os.join_path(baseline, 'linux/overflow.h'))!
	schema := hosttest.decode_json(os.read_file(schema_path)!)!.as_map()
	for record in schema['native_intrinsic_bindings']!.as_array() { replacement = remove_macro(replacement, record.as_map()['name']!.str())! }
	boundary := schema['boundary']!.as_map()
	for record in boundary['native_constant_expression_macros']!.as_array() { replacement = remove_macro(replacement, record.as_map()['name']!.str())! }
	replacement = replacement.replace_once('#include <linux/const.h>\n', '#include <linux/const.h>\n#include <vinix/integer_policy.h>\n')
	generated := os.join_path(work, 'V/include/linux')
	os.mkdir_all(generated)!
	os.write_file(os.join_path(generated, 'overflow.h'), replacement)!
	os.mkdir_all(os.join_path(work, 'V/include/asm'))!
	os.cp(os.join_path(baseline, 'asm/processor.h'), os.join_path(work, 'V/include/asm/processor.h'))!
	for header, name in {'slab.h': 'ZERO_OR_NULL_PTR', 'preempt.h': 'preemptible'} {
		os.write_file(os.join_path(generated, header), replace_policy_macro(os.read_file(os.join_path(baseline, 'linux', header))!, name)!)!
	}
	os.mkdir_all(os.join_path(baseline, 'vinix'))!
	os.write_file(os.join_path(baseline, 'vinix/integer_policy.h'), '#include <linux/overflow.h>\n#include <linux/slab.h>\n#include <linux/preempt.h>\n')!
	for kind in ['original', 'V'] {
		for schema_name, header in {'spinlock': 'spinlock_adapters', 'atomic-exchange': 'atomic_exchange'} {
			hosttest.generate_abi(os.join_path(root, 'kernel/linuxkpi/abi', schema_name + '.json'), os.join_path(root, 'kernel/linuxkpi'),
				os.join_path(work, kind, 'include/vinix', header + '.h'))!
		}
	}
	hosttest.generate_header_primitives(os.join_path(work, 'primitive.c'), arch, true, true)!
}

fn constant_flags() []string {
	kinds := {'I8':'signed char', 'U8':'unsigned char', 'I16':'short', 'U16':'unsigned short', 'I32':'int',
		'U32':'unsigned int', 'I64':'long long', 'U64':'unsigned long long', 'I128':'__int128', 'U128':'unsigned __int128'}
	mut flags := []string{}
	for name, native in kinds { flags << '-DVOP_MAX_' + name + '=type_max(' + native + ')' }
	flags << ['-DVOP_POLICY_INT=(__builtin_types_compatible_p(__typeof__(preemptible()), int) && __builtin_types_compatible_p(__typeof__(ZERO_OR_NULL_PTR((void *)0)), int))',
		'-DVOP_ZERO_CONST_I32=ZERO_OR_NULL_PTR(16)', '-DVOP_ZERO_CONST_PTR=ZERO_OR_NULL_PTR((void *)0)']
	return flags
}

struct Domain {
	native string
	maximum string
}

const operand_domains = [Domain{'signed _BitInt(17)', '0'}, Domain{'unsigned _BitInt(17)', '0'},
	Domain{'signed _BitInt(32)', 'type_max(vop_domain_t)'}, Domain{'unsigned _BitInt(8)', 'type_max(vop_domain_t)'},
	Domain{'signed _BitInt(128)', 'type_max(vop_domain_t)'}, Domain{'unsigned _BitInt(257)', '0'},
	Domain{'overflowdomain__DomainValue', 'type_max(vop_domain_t)'}, Domain{'volatile int', 'type_max(vop_domain_t)'},
	Domain{'const int', '0'}, Domain{'_Atomic(int)', '0'}, Domain{'_Bool', '0'}, Domain{'float', '0'},
	Domain{'signed _BitInt(17)', 'type_max(vop_domain_t)'}]

fn domains(work string, flags []string) ! {
	mut reports := []string{}
	for number, domain in operand_domains {
		mut accepted := []bool{}
		mut observations := []string{}
		for kind in ['original', 'V'] {
			target := os.join_path(work, kind, 'domain-' + number.str() + '.o')
			native := [flags[0], '-I' + os.join_path(work, kind, 'include'), ...flags[1..]]
			declarations := ['-Dvop_domain_t=' + domain.native, '-DVOP_DOMAIN_SIZE=sizeof(vop_domain_t)',
				'-DVOP_DOMAIN_MAX=' + domain.maximum, '-DVOP_DOMAIN_BOOL=__builtin_types_compatible_p(vop_domain_t, _Bool)']
			compiled := hosttest.capture([...native, ...declarations, '-c', os.join_path(work, 'overflowdomain.c'), '-o', target], '', -1, os.environ())!
			if compiled.code != 0 { accepted << false; observations << ''; continue }
			executable := hosttest.replace_suffix(target, '.test')
			dead_strip := $if macos { '-Wl,-dead_strip' } $else { '-Wl,--gc-sections' }
			compile([...native, target, dead_strip, '-o', executable])!
			mut env := os.environ(); env['ASAN_OPTIONS'] = 'detect_stack_use_after_return=1'; env['UBSAN_OPTIONS'] = 'halt_on_error=1'
			result := hosttest.command([executable], '', 10, env)!
			if result.stderr != '' { return error(domain.native + ': ' + result.stderr) }
			accepted << true; observations << result.stdout
		}
		if accepted[0] != accepted[1] || observations[0] != observations[1] { return error('Original/V operand domain differs: ' + domain.native) }
		// Retain json.dumps(sort_keys=True)'s original public output spacing.
		reports << '{"accepted": ' + accepted[0].str() + ', "constant": ' + json2.encode(domain.maximum) +
			', "observation": ' + json2.encode(observations[0].trim_space()) + ', "type": ' + json2.encode(domain.native) + '}'
	}
	println('Native operand/constant domains: [' + reports.join(', ') + ']')
}

fn run_profile(requested_arch string) ! {
	root := hosttest.root()
	linux := hosttest.env_default('LINUXKPI_SOURCE_DIR', os.join_path(root, 'third_party/linux-i915/linux-6.6.157'))
	machine := os.uname().machine.to_lower()
	if machine !in ['arm64', 'aarch64', 'x86_64', 'amd64'] { return error('Unsupported native host: ' + machine) }
	native_arch := if machine in ['arm64', 'aarch64'] { 'arm64' } else { 'amd64' }
	arch := if requested_arch != '' { requested_arch } else { native_arch }
	work := hosttest.work_dir('', 'vinix-overflow-policy-')!
	defer { hosttest.remove_work_dir(work) or { eprintln(err) } }
	prepare(work, arch)!
	mut flags := [hosttest.env_default('CC', 'clang'), '-std=gnu11', '-fgnu89-inline', '-O1', '-g',
		'-ffreestanding', '-fno-builtin', '-fwrapv', '-fno-strict-aliasing', '-ffunction-sections', '-fdata-sections',
		'-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-parameter', '-D_FORTIFY_SOURCE=0',
		'-D__sputc=vop_header_sputc', '-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-DVINIX_LINUXKPI',
		'-DVINIX_LINUXKPI_HOST_TEST', '-D__KERNEL__', '-Dvop_i128=__int128', '-include', os.join_path(root, 'tests/linuxkpi/host_types.h'),
		'-include', 'linux/kconfig.h', '-include', os.join_path(linux, 'include/linux/compiler_types.h'), '-iquote', os.join_path(root, 'kernel/c'),
		'-I' + os.join_path(root, 'kernel/linuxkpi/include'), '-I' + os.join_path(linux, 'include'), '-I' + os.join_path(linux, 'include/uapi'),
		'-I' + os.join_path(linux, 'arch/x86/include'), '-I' + os.join_path(linux, 'arch/x86/include/uapi')]
	$if macos { if arch != native_arch { flags = [flags[0], '-target', if arch == 'amd64' { 'x86_64-apple-darwin' } else { 'arm64-apple-darwin' }, ...flags[1..]] } }
	domains(work, flags)!
	mut outputs := []hosttest.Result{}
	for kind in ['original', 'V'] {
		native := [flags[0], '-I' + os.join_path(work, kind, 'include'), ...flags[1..]]
		mut objects := []string{}
		for name in ['overflowfixture', 'primitive'] {
			source := os.join_path(work, name + '.c'); target := os.join_path(work, kind, name + '.o')
			additional := if name == 'overflowfixture' { constant_flags() } else { []string{} }
			compile([...native, ...additional, '-c', source, '-o', target])!
			symbols := command(['nm', '-u', target])!.stdout
			if hosttest.allocation_symbols(symbols) { return error('Implicit allocation in ' + name + ':\n' + symbols) }
			objects << target
		}
		executable := os.join_path(work, kind, 'test')
		dead_strip := $if macos { '-Wl,-dead_strip' } $else { '-Wl,--gc-sections' }
		compile([...native, ...objects, dead_strip, '-o', executable])!
		mut env := os.environ(); env['ASAN_OPTIONS'] = 'detect_stack_use_after_return=1'; env['UBSAN_OPTIONS'] = 'halt_on_error=1'
		result := hosttest.command([executable], '', 60, env)!
		println(kind + ': ' + result.stdout.trim_space()); outputs << result
	}
	if outputs[0].stdout != outputs[1].stdout || outputs[0].stderr != outputs[1].stderr { return error('Original/V overflow output differs') }
	println('LinuxKPI overflow:589824 exhaustive narrow checks, mixed native128 boundaries, constants and lvalues passed')
}

fn main() {
	args := hosttest.parse_arguments(os.args[1..], [hosttest.Option{'--arch', true, ['arm64', 'amd64']}], 0,
		'Usage: overflow_policy.v [--arch arm64|amd64]', 'Compare native overflow/constant/policy behavior with immutable C headers.') or { eprintln(err.msg()); exit(2) }
	run_profile(args.options['--arch']) or { eprintln(err.msg()); exit(1) }
}
