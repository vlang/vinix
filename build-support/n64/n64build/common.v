// SPDX-License-Identifier: MIT
module n64build

import androidhost as ah
import json2

fn global(name string) !string {
	return callback('resolve', {
		'name': ah.Value(name)
	})!.text()
}

fn lit(value string) !string { return literal(ah.Value(value))! }

fn get(id string, key string) !string { return call('operator.getitem', o(id), v(ah.Value(key)))! }

fn set(id string, key string, value string) ! {
	call('operator.setitem', o(id), v(ah.Value(key)), o(value))!
}

fn exists(id string) !bool { return truth(method(id, 'exists', [], {})!)! }

fn is_file(id string) !bool { return truth(method(id, 'is_file', [], {})!)! }

fn is_dir(id string) !bool { return truth(method(id, 'is_dir', [], {})!)! }

fn mkdir(id string, parents bool) ! {
	mut keywords := {
		'exist_ok': v(ah.Value(true))
	}
	if parents { keywords['parents'] = v(ah.Value(true)) }
	method(id, 'mkdir', [], keywords)!
}

fn list(items []string) !string { return collection('list', items)! }

fn words(items []string) !string {
	mut values := []string{}
	for item in items { values << lit(item)! }
	return list(values)!
}

fn public(name string, args []string, keywords map[string]ah.Value) !string {
	return invoke(name, args.map(o(it)), keywords)!
}

fn bytes(hex string) !string {
	return callback('literal', {
		'value': ah.Value([ah.Value('bytes'), ah.Value(hex)])
	})!.text()
}

fn slice(id string, start string, end string) !string {
	return call('operator.getitem', o(id), o(call('builtins.slice', o(start), o(end))!))!
}

fn length(id string) !string { return call('len', o(id))! }

fn activate(cause ?IError) ! {
	mut row := {
		'error': ah.Value(json2.Null{})
	}
	if error := cause { row['error'] = detail(error) }
	callback('active_error', row)!
}

fn own(id string, method_name string, keywords map[string]ah.Value, condition string) ! {
	callback('own', {
		'owner':     ah.Value(id)
		'method':    ah.Value(method_name)
		'kwargs':    ah.Value(keywords)
		'condition': ah.Value(condition)
	})!
}

fn own_function(id string, function string, condition string) ! {
	callback('own', {
		'owner':         ah.Value(id)
		'function_name': ah.Value(function)
		'condition':     ah.Value(condition)
	})!
}

fn close(id string, cause ?IError) ! {
	mut row := {
		'owner': ah.Value(id)
		'error': ah.Value(json2.Null{})
	}
	if error := cause { row['error'] = detail(error) }
	callback('close', row)!
}

fn env(name string, fallback string) !string {
	return invoke('os.environ.get', [v(ah.Value(name)), o(fallback)], {})!
}
