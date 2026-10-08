// SPDX-License-Identifier: GPL-2.0-or-later
module packagestore

import androidhost as ah

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	args := ah.field(row, 'arguments').items().map(it.text())
	match ah.field(row, 'operation').text() {
		'validate_overlay' { validate(args[0], args[1])! }
		'get' { get(args[0])! }
		'send_app_build' { send_app(args[0], args[1], args[2])! }
		'send_source_snapshot' { send_snapshot(args[0])! }
		'save_overlay' { save(args[0])! }
		'git_worktree_files' { return ah.Value(git_files(args[0])!) }
		'extra_worktree_files' { return ah.Value(extra_files(args[0], args[1])!) }
		'stage_desktop_sources' { stage_desktop(args[0], args[1], args[2])! }
		'normalize_staged_member' { return ah.Value(normalize(args[0])!) }
		'build_source_snapshot' { return ah.Value(source_snapshot(args[0], args[1], args[2])!) }
		'main' { main_policy(args[0], args[1])! }
		'log_message' { log_message(args[0], args[1])! }
		else { return error('unknown package-store operation') }
	}
	return ah.Value(null()!)
}
