// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module pysmoke

import cpythonapi
import os

pub fn execute(arguments []string) !int {
	if arguments == ['--help'] {
		println('Usage: python3-smoke [--abi-only]\nRun the original CPython runtime checks from V through its C API. VINIX_CPYTHON_LIBRARY selects the target SDK. --abi-only resolves symbols without initializing the interpreter.')
		return 0
	}
	if arguments.len > 1 || (arguments.len == 1 && arguments[0] != '--abi-only') {
		return error_with_code('unknown argument', 2)
	}
	mut api := cpythonapi.open(os.getenv_opt('VINIX_CPYTHON_LIBRARY') or { 'libpython3.12.so.1.0' })!
	defer { api.close_library() }
	if arguments.len == 1 {
		println('Resolved ${cpythonapi.symbols.len} CPython ABI symbols without initializing the interpreter')
		return 0
	}
	api.initialize(1)
	callback_api = &api
	mut smoke := Smoke{}
	mut status := 0
	smoke.run(&api) or {
		eprintln('CPython smoke aborted: ' + err.msg())
		status = if err.msg() == 'KeyboardInterrupt' { 130 } else { 1 }
	}
	println('PYTHON3 SMOKE ' + if smoke.failures.len > 0 || status != 0 { 'FAIL' } else { 'PASS' } + ' (${smoke.failures.len} failures)')
	if smoke.failures.len > 0 {
		println('failed: ' + smoke.failures.join(', '))
		status = 1
	}
	flush_stdout()
	if api.finalize() != 0 { status = 120 }
	callback_api = unsafe { nil }
	return status
}
