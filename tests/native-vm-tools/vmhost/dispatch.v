// SPDX-License-Identifier: GPL-2.0-or-later
module vmhost

pub fn dispatch(root string, name string, argv []string) !int {
	return match name {
		'browser' { browser_cli(root, argv)! }
		'activity' { activity_cli(root, argv)! }
		'pointer' { pointer_cli(root, argv)! }
		else { return error_with_code('unknown native VM command', 2) }
	}
}
