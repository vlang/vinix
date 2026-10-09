// SPDX-License-Identifier: GPL-2.0-or-later
module samplertest

import androidhost as ah
import boothost
import runtimebuild as rb

fn main_body(args ah.Value, directory ah.Value, debug bool) ! {
	mut f := Frame{}
	work := f.named('work', if attr_true(args, 'state_dir')! { invoke(receiver(attr(args, 'state_dir')!, 'resolve')!, [], {})! } else { call('Path', [o(directory)])! })!
	if attr_true(args, 'state_dir')! { discard(invoke(attr(work, 'mkdir')!, [], {'parents': ah.Value(true), 'exist_ok': ah.Value(false)})!)! }
	arch_arg := attr(args, 'arch')!
	arch := f.named('arch', if truth(arch_arg)! { arch_arg } else {
		release([arch_arg])!
		literal(if attr_equal(args, 'host_arch', 'arm64')! { 'aarch64' } else { 'x86_64' })!
	})!
	mut cc := rb.null()
	if attr_equal(args, 'arch', 'aarch64')! {
		path_ctor := target('Path')!
		getenv := environ_get()!
		default_path := path_str(target('ROOT')!, 'build-aarch64-userland/sysroot')!
		sdk_value := temporary_call(getenv, [v('VINIX_AARCH64_SYSROOT'), o(default_path)], {}, {}, [default_path])!
		sdk := f.named('sdk', temporary_call(path_ctor, [o(sdk_value)], {}, {}, [sdk_value])!)!
		clang := invoke(environ_get()!, [v('CC_AARCH64'), v('clang')], {})!
		sysroot := rb.api('_sysroot', [o(sdk)], {}, true)!
		library := rb.api('_library', [o(sdk)], {}, true)!
		cc = f.named('cc', list([o(clang), v('--target=aarch64-linux-musl'), o(sysroot), v('-fuse-ld=lld'), o(library)])!)!
		release([clang, sysroot, library])!
	} else if attr_true(args, 'arch')! {
		gcc := invoke(environ_get()!, [v('CC_AMD64'), v('x86_64-linux-musl-gcc')], {})!
		cc = f.named('cc', list([o(gcc)])!)!
		release([gcc])!
	} else {
		compiler := invoke(environ_get()!, [v('CC'), v('clang')], {})!
		cc = f.named('cc', list([o(compiler)])!)!
		release([compiler])!
		uname := invoke(factory('os', 'uname')!, [], {})!
		sysname := attr(uname, 'sysname')!
		release([uname])!
		if truth_value(temporary_call(factory('_operator', 'eq')!, [o(sysname), v('Darwin')], {}, {}, [sysname])!)! {
			append_text(cc, '-arch')!
			append_text(cc, if attr_equal(args, 'host_arch', 'arm64')! { 'arm64' } else { 'x86_64' })!
		}
	}
	base := list([v('-std=c11'), v('-O2'), v('-g'), v('-Wall'), v('-Wextra'), v('-Werror'), v('-fno-builtin'), v('-ffreestanding'), v('-fno-strict-aliasing'), v('-fno-stack-protector')])!
	flags := f.named('flags', op('add', cc, o(base))!)!
	release([base])!
	if !attr_true(args, 'arch')! {
		append_text(flags, '-fsanitize=address,undefined')!
		append_text(flags, '-fno-omit-frame-pointer')!
	}
	builder := target('build')!
	original := if attr_true(args, 'original_reference')! { invoke(receiver(attr(args, 'original_reference')!, 'resolve')!, [], {})! } else { call('_none', [])! }
	guest := call('bool', [temp(attr(args, 'arch')!)])!
	executable := f.named('exe', temporary_call(builder, [o(work), o(arch), o(flags), o(original), o(guest)], {}, {}, [original, guest])!)!
	if attr_true(args, 'arch')! {
		runner := factory('subprocess', 'run')!
		argv := list([v('python3'), temp(path_str(target('ROOT')!, 'tests/kernel-gaps/run.py')!), v('--arch'), o(arch), v('--prebuilt-init'), temp(str(executable)!), v('--kernel-dir'), temp(attr_str(args, 'kernel_dir')!), v('--state-dir'), temp(attr_str(args, 'guest_state_dir')!), v('--no-network'), v('--timeout'), v('360'), v('--expect'), temp(target('VERDICT')!)])!
		discard(temporary_call(runner, [o(argv)], {'check': ah.Value(true)}, {}, [argv])!)!
	} else {
		output := f.named('output', invoke(factory('subprocess', 'check_output')!, [temp(list([temp(str(executable)!)])!)], {})!)!
		if debug {
			verdict := target('VERDICT')!
			newline := plus(verdict, '\n')!
			release([verdict])!
			encoded := invoke(receiver(newline, 'encode')!, [], {})!
			equal := temporary_call(factory('_operator', 'eq')!, [o(output), o(encoded)], {}, {}, [encoded])!
			if !truth_value(equal)! { fail_message(output)! }
		}
		statement(receiver(join(work, 'stdout')!, 'write_bytes')!, [o(output)], {})!
		printer := target('print')!
		decoded := method(output, 'decode', []) or { release([printer])!; return err }
		statement(printer, [temp(decoded)], {'end': ah.Value('')})!
	}
	statement(target('print')!, [v('Shared kernel allocator sampler: original ownership and no implicit allocator imports passed')], {})!
}

fn main_policy(args ah.Value, debug bool) ! {
	manager := invoke(factory('tempfile', 'TemporaryDirectory')!, [], {'prefix': ah.Value('vinix-sampler-test-')})!
	directory := rb.callback('enter_existing', {'id': manager}) or { release([manager])!; return err }
	release([manager])!
	main_body(args, directory, debug) or {
		cause := err
		if exit(directory, cause)! { return }
		return cause
	}
	exit(directory, none)!
}

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	debug := ah.field(row, 'debug') == ah.Value(true)
	return match ah.field(row, 'operation').text() {
		'build' { rb.result_object(build(rb.borrow('work')!, rb.borrow('arch')!, rb.borrow('flags')!, rb.borrow('original')!, rb.borrow('guest')!, debug)!) }
		'main' { main_policy(rb.borrow('args')!, debug)!; rb.null() }
		else { return boothost.PolicyError{kind: 'ValueError', message: 'Unknown sampler validation operation'} }
	}
}
