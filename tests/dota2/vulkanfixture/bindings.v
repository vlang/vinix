// SPDX-License-Identifier: GPL-2.0-or-later
module vulkanfixture

import encoding.hex
import hosttest
import json2
import os
import vulkanbuild

fn words(values []string) json2.Any { return json2.Any(values.map(json2.Any(it))) }

fn path(value string) json2.Any {
	return json2.Any({
		'path_hex': json2.Any(value.bytes().hex())
	})
}

fn decoded(value json2.Any) !string {
	return hex.decode(value.as_map()['path_hex']!.str())!.bytestr()
}

fn data(value string) json2.Any {
	return json2.Any({
		'bytes_hex': json2.Any(value.bytes().hex())
	})
}

fn request(value map[string]json2.Any) !json2.Any {
	println(json2.encode({
		'callback': json2.Any(value)
	}, escape_unicode: true))
	result := hosttest.decode_json(os.get_raw_line())!.as_map()
	if 'error' in result { return vulkanbuild.BindingFailure{result['error']!.as_map()} }
	return result['value']!
}

fn public(name string, args []json2.Any) !json2.Any {
	return request({
		'kind':      json2.Any('public')
		'name':      json2.Any(name)
		'arguments': json2.Any(args)
	})!
}

fn global(name string) !json2.Any {
	return request({
		'kind': json2.Any('global')
		'name': json2.Any(name)
	})!
}

fn method(target json2.Any, name string, args []json2.Any) !json2.Any {
	return request({
		'kind':      json2.Any('method')
		'target':    target
		'name':      json2.Any(name)
		'arguments': json2.Any(args)
	})!
}

fn attribute(target json2.Any, name string) !json2.Any {
	return request({
		'kind':   json2.Any('attribute')
		'target': target
		'name':   json2.Any(name)
	})!
}

fn stage(name string, args []json2.Any) !json2.Any {
	return public('_stage_call', [json2.Any(name), json2.Any(args)])!
}

fn constant(name string) !json2.Any { return attribute(global('_stage')!, name)! }

fn unit(name string, args []json2.Any) ! { public('_unit', [json2.Any(name), json2.Any(args)])! }

fn member(name string) !json2.Any { return public('_member', [json2.Any(name)])! }

fn set_member(name string, value json2.Any) ! {
	public('_set_member', [json2.Any(name), value])!
}

fn equal(a json2.Any, b json2.Any) ! { unit('assertEqual', [a, b])! }

fn true_(a bool) ! { unit('assertTrue', [json2.Any(a)])! }

fn false_(a bool) ! { unit('assertFalse', [json2.Any(a)])! }

fn exit_context(target json2.Any, cause ?IError) !bool {
	mut row := {
		'kind':   json2.Any('context_exit')
		'target': target
	}
	if failure := cause { row['context'] = json2.Any(vulkanbuild.failure_record(failure)) }
	return request(row)!.bool()
}

fn with_patch(name string, value json2.Any) !json2.Any {
	owner := public('_patch', [json2.Any(name), value])!
	entered := method(owner, '__enter__', [])!
	return json2.Any({
		'owner':   owner
		'entered': entered
	})
}

fn value(v json2.Any) json2.Any {
	return json2.Any({
		'kind':  json2.Any('value')
		'value': v
	})
}

fn return_(v json2.Any) json2.Any {
	return json2.Any({
		'kind':  json2.Any('return')
		'value': v
	})
}

fn wrap(name string) json2.Any {
	return json2.Any({
		'kind': json2.Any('wrap')
		'name': json2.Any(name)
	})
}
