// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module asahipolicy

import cpythonapi as py
import encoding.utf8
import os

fn logging_setup(mut a py.Arena, logger py.Ref) ! {
	a.method(logger, 'basicConfig', [], {
		'level':    a.attr(logger, 'DEBUG')!
		'format':   a.text('%(asctime)s %(name)-12s %(levelname)-8s %(message)s')!
		'datefmt':  a.text('%m-%d %H:%M')!
		'filename': a.text('installer.log')!
		'filemode': a.text('w')!
	})!
	console := a.method(logger, 'StreamHandler', [], {})!
	a.method(console, 'setLevel', [a.attr(logger, 'ERROR')!], {})!
	formatter := a.method(logger, 'Formatter', [a.text('%(name)-12s: %(levelname)-8s %(message)s')!], {})!
	a.method(console, 'setFormatter', [formatter], {})!
	a.method(a.method(logger, 'getLogger', [a.text('')!], {})!, 'addHandler', [console], {})!
}

fn report_error(mut a py.Arena, failure IError) !int {
	defer { if failure is SdkError { failure.close() } }
	mut message := 'Installation failed'
	if failure is SdkError {
		if failure.saved.name == 'KeyboardInterrupt' {
			println('')
			say(mut a, 'p_error', 'Interrupted; no further disk changes will be made.')!
			return 130
		}
		if failure.saved.name == 'SystemExit' {
			code := a.attr(failure.saved.value, 'code')!
			if code == a.api.none { return 0 }
			return int(a.integer(code) or {
				if err is SdkError { err.close() }
				1
			})
		}
		if failure.saved.name == 'CalledProcessError' {
			command := a.attr(failure.saved.value, 'cmd')!
			joined := a.method(a.load('shlex')!, 'join', [command], {})!
			say(mut a, 'p_error', 'Failed to run process: ' + a.string(joined)!)!
			output := a.attr(failure.saved.value, 'output')!
			if output != a.api.none {
				say(mut a, 'p_error', 'Output: ' + a.string(a.take(a.api.stringify(output))!)!)!
			}
			message = 'Process execution failed'
		} else {
			say(mut a, 'p_error', failure.msg())!
		}
		trace := if failure.saved.trace == unsafe { nil } {
			a.borrow(a.api.none)!
		} else {
			a.borrow(failure.saved.trace)!
		}
		a.method(active.logging, 'error', [a.text(message)!], {
			'exc_info': a.tuple([failure.saved.kind, failure.saved.value, trace])!
		})!
	} else {
		say(mut a, 'p_error', failure.msg())!
		a.method(active.logging, 'error', [a.text(message)!], {})!
	}
	say(mut a, 'p_warning', 'Installer files and installer.log were retained for diagnosis.')!
	return 1
}

fn install(mut a py.Arena, context &Context) ! {
	version := os.read_file('version.tag')!.trim_space()
	if !utf8.validate_str(version) {
		return Failure{ description: 'Invalid installer version tag' }
	}
	for name, expected in {
		'PART_ALIGN':  partition_alignment
		'STUB_SIZE':   stub_bytes
		'MIN_FREE_OS': minimum_macos_free
		'MIN_FREE':    minimum_other_free
	} {
		if a.integer(a.attr(context.upstream, name)!)! != expected {
			return Failure{ description: 'Pinned Asahi installer constant mismatch: ' + name }
		}
	}
	type_object := a.method(context.builtins, 'type', [a.text('VinixInstaller')!,
		a.tuple([context.base])!, a.take(a.api.dict())!], {})!
	for index in 0 .. context.methods.len {
		definition := unsafe { &context.methods[index] }
		descriptor := a.take(a.api.descriptor_new(type_object, definition))!
		a.set_attr(type_object, unsafe { definition.name.vstring() }, descriptor)!
	}
	instance := a.call(type_object, [a.text(version)!], {})!
	a.method(instance, 'main', [], {})!
}

pub fn execute(arguments []string) !int {
	if arguments == ['--help'] {
		println('Usage: vinix-auto\nRun the V installer policy with the verified prepared Asahi SDK. VINIX_TARGET_DISK and VINIX_SPACE_BYTES come from the confirmed GUI selection. Authentication stays in the upstream terminal UI.')
		return 0
	}
	if arguments.len != 0 { return error_with_code('unknown installer policy argument', 2) }
	selected := config(os.getenv('VINIX_TARGET_DISK'), os.getenv('VINIX_SPACE_BYTES'))!
	work := os.getwd()
	framework := work + '/Frameworks/Python.framework/Versions/3.13'
	if !os.is_file(framework + '/Python') {
		return Failure{ description: 'Verified Asahi framework is missing' }
	}
	// The external SDK retains its own stdlib; no first-party source is evaluated.
	os.setenv('PYTHONHOME', framework, true)
	base_api := py.open(framework + '/Python')!
	mut api := py.Api{ ...base_api, error_factory: sdk_error }
	defer { api.close_library() }
	api.initialize(1)
	mut a := py.Arena{ api: &api }
	// Every SDK reference and descriptor definition remains live until callback
	// use has ended; context memory itself remains through finalization.
	mut status := 1
	setup := setup_context(mut a, selected, work) or {
		if err is SdkError { err.close() }
		eprintln(err)
		a.close()
		api.finalize()
		return 1
	}
	active = setup
	logging_setup(mut a, setup.logging) or {
		if err is SdkError { err.close() }
		eprintln(err)
		active = unsafe { nil }
		a.close()
		api.finalize()
		active = unsafe { nil }
		return 1
	}
	install(mut a, setup) or {
		status = report_error(mut a, err) or {
			if err is SdkError { err.close() }
			eprintln(err)
			1
		}
		active = unsafe { nil }
		a.close()
		if api.finalize() != 0 { status = 120 }
		active = unsafe { nil }
		return status
	}
	status = 0
	active = unsafe { nil }
	a.close()
	if api.finalize() != 0 { status = 120 }
	active = unsafe { nil }
	return status
}

fn setup_context(mut a py.Arena, selected Config, work string) !&Context {
	sys := a.load('sys')!
	a.method(a.attr(sys, 'path')!, 'insert', [a.int(0)!, a.text(work)!], {})!
	upstream := a.load('main')!
	builtins := a.load('builtins')!
	return &Context{
		api:         a.api
		selected:    selected
		upstream:    upstream
		base:        a.attr(upstream, 'InstallerMain')!
		builtins:    builtins
		logging:     a.load('logging')!
		value_error: a.attr(builtins, 'ValueError')!
		type_error:  a.attr(builtins, 'TypeError')!
		methods:     methods()
	}
}
