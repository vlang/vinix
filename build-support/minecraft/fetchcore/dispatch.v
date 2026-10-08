// SPDX-License-Identifier: GPL-2.0-or-later
module fetchcore

import androidhost as ah

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	args := ah.field(row, 'arguments').items()
	return match ah.field(row, 'operation').text() {
		'stage' { stage(args[0])! }
		'fetch' { fetch(args[0], args[1])! }
		'sha1_of' { ah.Value(sha1_of(args[0].text())!) }
		'download_to' { ah.Value(download(args[0], args[1].text(), args[2])!) }
		'rule_allows' { ah.Value(rule_allows(args[0], args[1])!) }
		'rule_matches' { ah.Value(rule_matches(args[0], args[1])!) }
		'fetch_version' { fetch_version(args[0])! }
		'resolve_version' { resolve_version(args[0], args[1])! }
		'maven_path' { ah.Value(maven_path(args[0])!) }
		'select_libraries' { select_libraries(args[0])! }
		'download_all' {
			download_all(args[0], args[1].text(), args[2], args[3])!
			null()
		}
		'download_assets' { assets(args[0], args[1].text(), args[2])! }
		'flatten_arguments' { ah.Value(flatten(args[0], args[1])!) }
		'shell_quote' { ah.Value(shell_quote(args[0])!) }
		'write_launch_env' {
			launch_environment(args[0].text(), args[1].object())!
			null()
		}
		'download_entry' {
			entry := args[0]
			url := item(entry, ah.Value('url'))!
			target := join(args[1].text(), item(entry, ah.Value('path'))!)!
			download_api(url, target, item(entry, ah.Value('sha1'))!)!
		}
		else { return failed('RuntimeError', 'unknown Minecraft native operation') }
	}
}
