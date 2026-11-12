// SPDX-License-Identifier: GPL-2.0-or-later
module launchhold

fn test_unsupported_host_refuses_without_starting_a_holder() {
	$if !linux {
		if _ := run(Command{}, -1) { assert false }
		else { assert err.msg() == 'generation lease supervision requires Linux subreaping'; unsafe { err.free() } }
	}
}
