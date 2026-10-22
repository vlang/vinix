// SPDX-License-Identifier: GPL-2.0-or-later
module qmpclient

import hosttest
import json2
import strconv

struct WireNumber {
mut:
	token string
}

fn (mut number WireNumber) from_json_number(token string) ! { number.token = token }

type WireValue = []WireValue | bool | map[string]WireValue | string | WireNumber | json2.Null

fn wire_decode(text string) !WireValue {
	hosttest.module_decode_utf8(text)!
	if text.len > 64 * 1024 * 1024 { return error('QMP JSON exceeds limit') }
	return json2.decode[WireValue](text, strict:true)
}

fn wire_encode(value WireValue) string {
	return match value {
		WireNumber { value.token }
		string { json2.encode(value) }
		bool { if value { 'true' } else { 'false' } }
		json2.Null { 'null' }
		[]WireValue { '[' + value.map(wire_encode(it)).join(',') + ']' }
		map[string]WireValue {
			mut fields := []string{}
			for key, item in value { fields << json2.encode(key) + ':' + wire_encode(item) }
			'{' + fields.join(',') + '}'
		}
	}
}

// Do not round arbitrary-sized integer tokens through json2.Any's f64.
// Decoding also applies JSON string escapes and last-value duplicate keys.
pub fn normalize_request(text string) !string {
	value := wire_decode(text)!
	if value !is map[string]WireValue { return error('QMP request must be a JSON object') }
	return wire_encode(value)
}

pub struct BatchExit {
pub:
	is_error bool
	status int
	print_error bool
	message string
}

fn wire_error(value WireValue) !BatchExit {
	if value !is map[string]WireValue { return error('QMP error must be a JSON object') }
	desc := value['desc'] or { return BatchExit{is_error:true, status:1, print_error:true, message:'QMP error'} }
	return match desc {
		string { BatchExit{is_error:true, status:1, print_error:true, message:desc} }
		json2.Null { BatchExit{is_error:true} }
		bool { BatchExit{is_error:true, status:if desc {1} else {0}} }
		WireNumber {
			if !desc.token.contains_any('.eE') {
				integer := strconv.parse_int(desc.token,10,64) or { return BatchExit{is_error:true,status:255} }
				BatchExit{is_error:true, status:int(integer & 255)}
			} else { return error('QMP error description must be text or an exit status') }
		}
		else { return error('QMP error description must be text or an exit status') }
	}
}

// The ISO runner consumes one text greeting, ignores a capabilities error,
// and takes the first terminal reply without ID correlation. Its policy is
// separate from checked/request consumers, whose existing behavior is unchanged.
pub fn connect_text(path string, deadline u64, cancel fn () bool) !Monitor {
	mut connection := owned_connection(path,deadline,cancel)!
	mut monitor := Monitor{connection:connection,deadline:deadline,cancel:cancel}
	mut retained := false
	defer { if !retained { monitor.close() } }
	hosttest.module_decode_utf8(monitor.read_line()!)!
	monitor.terminal_json('{"execute":"qmp_capabilities"}')!
	retained = true
	return monitor
}

pub fn (mut monitor Monitor) exchange_json(request string) !BatchExit {
	value := monitor.terminal_json(request)!
	if failure := value['error'] { return wire_error(failure) }
	return BatchExit{}
}

fn (mut monitor Monitor) terminal_json(request string) !map[string]WireValue {
	monitor.send_text(normalize_request(request)! + '\n')!
	for {
		value := wire_decode(monitor.read_line()!)!
		if value !is map[string]WireValue { return error('QMP reply must be a JSON object') }
		if 'error' in value || 'return' in value { return value }
	}
	return error('QMP closed')
}

pub fn batch(path string, requests []string, deadline u64, cancel fn () bool) !BatchExit {
	mut monitor := connect_text(path,deadline,cancel)!
	defer { monitor.close() }
	for request in requests {
		result := monitor.exchange_json(request)!
		if result.is_error { return result }
	}
	return BatchExit{}
}
