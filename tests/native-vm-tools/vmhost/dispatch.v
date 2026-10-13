// SPDX-License-Identifier: GPL-2.0-or-later
module vmhost

pub fn dispatch(root string, name string, argv []string) !int {
	return match name {
		'browser' { browser_cli(root, argv)! }
		'activity' { activity_cli(root, argv)! }
		'pointer' { pointer_cli(root, argv)! }
		'roblox-windows' { roblox_cli(root, argv)! }
		'roblox-upload' {
			if argv.len != 2 { return error_with_code('expected upload directory and port', 2) }
			roblox_serve(argv[0], argv[1])!
		}
		else { return error_with_code('unknown native VM command', 2) }
	}
}
