// SPDX-License-Identifier: GPL-2.0-or-later
module vulkanfixture

import encoding.hex
import json2

pub fn dispatch(row map[string]json2.Any, repo string, python string) !json2.Any {
	args := row['arguments']!.as_map()
	match row['operation']!.str() {
		'setup' { setup(repo, python)! }
		'write' { write(decoded(args['path']!)!, hex.decode(args['contents']!.str())!.bytestr())! }
		'deb_bytes' {
			mut files := map[string]string{}
			for name, contents in args['files']!.as_map() { files[name] = contents.str() }
			mut links := map[string]string{}
			for name, target in args['links']!.as_map() { links[name] = target.str() }
			return json2.Any(deb_bytes(files, links)!)
		}
		'run_stage' {
			run_stage(context(repo, python)!, args['extra']!.as_array().map(it.str()), []string{})!
		}
		'effect' {
			return effect(args['name']!.str(), args['context']!.as_map(), args['args']!.as_array(), args['keywords']!.as_map())!
		}
		'case' { run_case(context(repo, python)!, args['name']!.str())! }
		else { return error('Unknown Vulkan fixture operation') }
	}
	return json2.Any(json2.Null{})
}
