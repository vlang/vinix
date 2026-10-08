// SPDX-License-Identifier: GPL-2.0-only
module stagehost

import json2

pub fn dispatch(row map[string]json2.Any) !json2.Any {
	op := row['operation']!.str()
	args := row['args']!.as_array().map(decode(it.str())!)
	match op {
		'patterns' {
			return {
				'main':     json2.Any(main_pattern.bytes().hex())
				'embedded': json2.Any(embedded_view_pattern.bytes().hex())
				'legacy':   json2.Any(legacy_license_preamble.bytes().hex())
			}
		}
		'native_v3_source' { return native_v3_source(args[0])!.bytes().hex() }
		'v_string' { return v_string(args[0]).bytes().hex() }
		'strip_main' { return strip_main(args[0], args[1])!.bytes().hex() }
		'stage_desktop' { stage_desktop(args[0], args[1])! }
		'stage_translations' { stage_translations(args[0], args[1])! }
		'stage_icon_data' { stage_icon_data(args[0], args[1])! }
		'stage_example' { stage_example(args[0], args[1])! }
		'app_main' { app_main(args)! }
		'staged_source' { return staged_source(args[0], args[1])! }
		'symlink_entries' { symlink_entries(args[0], args[1])! }
		'module_subdirs' {
			return json2.Any(module_subdirs(args[0])!.map(json2.Any(it.bytes().hex())))
		}
		'filter_manifest_subdirs' { return filter_manifest_subdirs(args[0])!.bytes().hex() }
		'ui_main' { ui_main(args)! }
		else { return error('unknown staging operation ' + op) }
	}
	return json2.Null{}
}

fn write_after_open(target string, operation string, args []string) ! {
	handle := primitive('open_write', [target])!
	mut failed := false
	mut cause := IError(none)
	content := match operation {
		'strip_main' { strip_main(args[0], args[1]) or {
			failed = true
			cause = err
			''
		} }
		'filter_manifest' { filter_manifest_subdirs(args[0]) or {
			failed = true
			cause = err
			''
		} }
		else { '' }
	}
	if !failed {
		callback('write_handle', {
			'handle': handle
			'args':   encoded([content])
		}) or {
			failed = true
			cause = err
		}
	}
	callback('close_handle', {
		'handle': handle
	})!
	if failed { return cause }
}
