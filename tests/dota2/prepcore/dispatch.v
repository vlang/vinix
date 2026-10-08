// SPDX-License-Identifier: GPL-2.0-or-later
module prepcore

import json2

pub fn dispatch(row map[string]json2.Any) !json2.Any {
	args := row['args']!.as_array().map(decode(it.str())!)
	repo := decode(row['repo']!.str())!
	match row['operation']!.str() {
		'sha256' { return json2.Any(digest(args[0])!) }
		'probe_preloads' { return probe_preloads()! }
		'install' { install(args[0], args[1])! }
		'stage_vulkan_query' { stage_vulkan_query(args[0], args[1])! }
		'trim_runtime' { trim_runtime(args[0])! }
		'refresh_runtime' { refresh_runtime(args[0])! }
		'complete_native_closure' {
			mut queue := []string{}
			closure(args[0], repo, mut queue, true)!
		}
		'verify_sdk_closure' { verify_sdk_closure(args[0])! }
		'overlay_translator' { overlay_translator(args[0], args[1], repo)! }
		'prepare' { return prepare(args[0], repo)! }
		else { return error('unknown preparation operation') }
	}
	return json2.Any(json2.Null{})
}
