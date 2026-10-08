// SPDX-License-Identifier: GPL-2.0-or-later
module gamecore

import androidhost as ah
import gapcore as gc

fn pair_values(value string) ![]string {
	pair := call('_vm.unpack_pair', o(value))!
	return [get(pair, n(0))!, get(pair, n(1))!]
}

fn set_attr(id string, name string, value ah.Value) ! {
	call('builtins.setattr', o(id), s(name), value)!
}

fn field(id string, name string) !string { return get(id, s(name))! }

fn module_load(name string, file string) !string {
	spec := call('importlib.util.spec_from_file_location', o(name), o(file))!
	result := call('importlib.util.module_from_spec', o(spec))!
	call('operator.setitem', o(call('sys.modules')!), o(name), o(result))!
	method(attr(spec, 'loader')!, 'exec_module', [o(result)], {})!
	return result
}

fn started(transcript string) !bool {
	for marker in ['VINIX-DOTA2-GAME-STARTED:', 'VINIX-DOTA2-GAME-ALIVE'] {
		if truth(call('operator.contains', o(transcript), b(marker.bytes().hex()))!)! {
			return true
		}
	}
	return false
}

fn screenshot(socket string, target string) !bool {
	if !truth(method(socket, 'is_socket', [], {})!)! { return false }
	env := call('builtins.dict', o(call('os.environ')!))!
	set(env, 'VINIX_QMP_SOCKET', o(call('builtins.str', o(socket))!))!
	args := list()!
	append(args, o(call('builtins.str', o(join('repo', 'desktop/tools/screenshot.sh')!))!))!
	append(args, o(call('builtins.str', o(target))!))!
	result := invoke('subprocess.run', [o(args)], {
		'env':            o(env)
		'text':           v(ah.Value(true))
		'capture_output': v(ah.Value(true))
		'timeout':        n(35)
	}) or {
		failure := err
		gc.activate(failure, true)!
		if !exception_is(failure, 'subprocess.TimeoutExpired')! { return failure }
		gc.activate(failure, true)!
		invoke('builtins.print', [s('Screenshot request timed out')], {
			'flush': v(ah.Value(true))
		})!
		return false
	}
	if truth(attr(result, 'returncode')!)! {
		invoke('builtins.print', [s('Screenshot unavailable: ' + format(method(attr(result, 'stderr')!, 'strip', [], {})!)!)], {
			'flush': v(ah.Value(true))
		})!
		return false
	}
	invoke('builtins.print', [s('Actual guest capture: ' + format(target)!)], {
		'flush': v(ah.Value(true))
	})!
	return true
}

fn exception_is(cause IError, name string) !bool {
	if cause is gc.BindingError {
		class := gc.callback('resolve', {
			'name': ah.Value(name)
		})!.text()
		return gc.flag(gc.callback('exception_matches', {
			'error': ah.Value(cause.value)
			'class': ah.Value(class)
		})!)
	}
	return false
}
