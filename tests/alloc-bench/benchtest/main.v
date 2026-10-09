module benchtest

import androidhost as ah
import runtimebuild as rb

fn args_attr(args ah.Value, name string) !ah.Value { return attr(args, name)! }
fn main_body(args ah.Value, directory ah.Value, debug bool) ! {
	mut f := Frame{}
	work := f.named('work', if attr_true(args, 'state_dir')! { invoke(receiver(args_attr(args, 'state_dir')!, 'resolve')!, [], {})! } else { call('Path', [o(directory)])! })!
	if attr_true(args, 'state_dir')! { discard(invoke(attr(work, 'mkdir')!, [], {'parents': ah.Value(true), 'exist_ok': ah.Value(false)})!)! }
	arch := f.named('arch', if attr_equal(args, 'arch', 'aarch64')! { literal('arm64')! } else if attr_true(args, 'arch')! { literal('amd64')! } else { args_attr(args, 'host_arch')! })!
	mut cc := rb.null()
	if attr_equal(args, 'arch', 'aarch64')! {
		path_ctor := target('Path')!
		getenv := environ_get()!
		default_path := join_global('ROOT', 'build-aarch64-userland/sysroot')!
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
			append_text(cc, if truth_value(op('eq', arch, v('arm64'))!)! { 'arm64' } else { 'x86_64' })!
		}
	}
	basic_flags := list([v('-std=c11'), v('-O2'), v('-Wall'), v('-Wextra'), v('-Werror'), v('-fno-builtin')])!
	flags := f.named('flags', op('add', cc, o(basic_flags))!)!
	release([basic_flags])!
	if !attr_true(args, 'arch')! {
		append_text(flags, '-fsanitize=address,undefined')!
		append_text(flags, '-fno-omit-frame-pointer')!
	}
	if attr_true(args, 'arch')! {
		builder := target('build')!
		exe := f.named('exe', invoke(builder, [o(work), o(flags), o(arch), temp(args_attr(args, 'original_reference')!), temp(args_attr(args, 'model')!), rb.ordinary(ah.Value(true))], {})!)!
		run_ := factory('subprocess', 'run')!
		argv := list([v('python3'), temp(path_str(target('ROOT')!, 'tests/kernel-gaps/run.py')!), v('--arch'), temp(args_attr(args, 'arch')!), v('--prebuilt-init'), temp(str(exe)!), v('--kernel-dir'), temp(attr_str(args, 'kernel_dir')!), v('--state-dir'), temp(attr_str(args, 'guest_state_dir')!), v('--no-network'), v('--timeout'), v('360'), v('--expect'), v('ALLOC-DONE label=native workloads=6 checksum=453'), v('--fail'), v('ALLOC-ERROR')])!
		run_argv(run_, argv)!
	} else if attr_true(args, 'original_reference')! {
		statement(receiver(join(work, 'v')!, 'mkdir')!, [], {})!
		statement(receiver(join(work, 'c')!, 'mkdir')!, [], {})!
		build_v := target('build')!
		v_work := join(work, 'v')!
		v_exe := f.named('v', temporary_call(build_v, [o(v_work), o(flags), o(arch)], {'model': ah.Value(true)}, {}, [v_work])!)!
		build_c := target('build')!
		c_work := join(work, 'c')!
		c_exe := f.named('c', temporary_call(build_c, [o(c_work), o(flags), o(arch), temp(args_attr(args, 'original_reference')!)], {'model': ah.Value(true)}, {}, [c_work])!)!
		discard(invoke(target('compare')!, [o(v_exe), o(c_exe), o(work)], {})!)!
	} else {
		builder := target('build')!
		model := args_attr(args, 'model')!
		exe := f.named('exe', temporary_call(builder, [o(work), o(flags), o(arch)], {}, {'model': model}, [model])!)!
		invoker := target('invoke')!
		argv := list([v('--iterations'), v('2000'), v('--samples'), v('6'), v('--label'), v('host')])!
		output := f.named('output', temporary_call(invoker, [o(exe), o(argv)], {}, {}, [argv])!)!
		if debug && (!attr_compare(output, 'returncode', 'eq', n(0))! || !attr_compare(output, 'stdout', 'contains', bytes('ALLOC-DONE'))!) { fail_message(attr(output, 'stderr')!)! }
		statement(receiver(join(work, 'stdout')!, 'write_bytes')!, [temp(attr(output, 'stdout')!)], {})!
		statement(receiver(join(work, 'stderr')!, 'write_bytes')!, [temp(attr(output, 'stderr')!)], {})!
		statement(target('print')!, [v('Portable allocation benchmark: all six real host workloads passed')], {})!
	}
}
fn main_policy(args ah.Value, debug bool) ! {
	manager := invoke(factory('tempfile', 'TemporaryDirectory')!, [], {'prefix': ah.Value('vinix-bench-test-')})!
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
		'build' { rb.result_object(build(rb.borrow('work')!, rb.borrow('flags')!, rb.borrow('arch')!, rb.borrow('original')!, rb.borrow('model')!, rb.borrow('guest')!, debug)!) }
		'invoke' { rb.result_object(invoke_program(rb.borrow('exe')!, rb.borrow('args')!, rb.borrow('mode')!, rb.borrow('index')!)!) }
		'normalize' { rb.result_object(normalize(rb.borrow('contents')!, rb.borrow('help_text')!)!) }
		'compare' { compare(rb.borrow('v_exe')!, rb.borrow('c_exe')!, rb.borrow('work')!, debug)!; rb.null() }
		'main' { main_policy(rb.borrow('args')!, debug)!; rb.null() }
		else { return error('Unknown benchmark controller operation') }
	}
}
