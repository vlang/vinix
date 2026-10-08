// SPDX-License-Identifier: GPL-2.0-or-later
// Line-oriented native API for independent captured-transcript comparisons.
module main

import encoding.hex
import json2
import os
import perfreport as p

fn query(row p.Row) !p.Value {
	operation := p.string_value(p.value(row, 'operation'))
	if operation == 'detail' { return p.detail_values(p.value(row, 'row').as_map()) }
	if operation == 'valid_desktop_result' {
		return p.Value(p.valid_desktop_result(p.value(row, 'row').as_map())!)
	}
	if operation == 'summarize' {
		return p.Value(p.summarize(p.value(row, 'rows').arr().map(it.as_map()))!)
	}
	variants := p.value(row, 'variants').arr().map(p.string_value(it))
	selected := p.value(row, 'scenarios').arr().map(p.string_value(it))
	rounds := p.string_value(p.value(row, 'rounds')).int()
	if operation == 'expected' {
		return json2.decode[p.Value](json2.encode(p.expected(variants, selected, rounds)))!
	}
	transcript := hex.decode(p.string_value(p.value(row, 'transcript_hex')))!
	timeout_value := p.value(row, 'timed_out')
	timed_out := timeout_value is bool && timeout_value
	code := p.value(row, 'exit_code')
	mut exit_code := ?p.Value(none)
	if code !is json2.Null { exit_code = code }
	if operation == 'inspect' {
		return p.inspect(transcript, variants, selected, rounds, timed_out, exit_code).to_value()
	}
	path := p.value(row, 'json_path')
	json_path := if path is json2.Null { ?string(none) } else { ?string(p.string_value(path)) }
	output := p.finish(transcript, variants, selected, rounds, json_path, timed_out, exit_code)!
	return p.Value(map[string]p.Value{
		'verdict': output.verdict.to_value()
		'stdout':  p.Value(output.stdout)
		'stderr':  p.Value(output.stderr)
		'status':  p.Value(p.Number{output.status.str()})
	})
}

fn main() {
	if os.args.len == 3 && os.args[1] == '--install-query' {
		os.cp(os.executable(), os.args[2]) or {
			eprintln(err)
			exit(1)
		}
		os.chmod(os.args[2], 0o700) or {
			eprintln(err)
			exit(1)
		}
		return
	}

	for {
		line := os.get_raw_line()
		if line == '' { break }
		request := json2.decode[p.Row](line) or {
			println(json2.encode({
				'error': p.Value(err.msg())
			}))
			continue
		}
		result := query(p.from_wire(p.Value(request)).as_map()) or {
			println(p.encode(p.Value(map[string]p.Value{
				'error': p.Value(err.msg())
				'errno': p.Value(p.Number{err.code().str()})
			}), false))
			continue
		}
		println(p.encode(result, false))
	}
}
