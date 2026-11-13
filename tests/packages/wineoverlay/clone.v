// SPDX-License-Identifier: GPL-2.0-or-later
module wineoverlay

pub fn clone_fresh(source string, target string) ! {
	$if macos { return clone_fresh_darwin(source, target) }
	$else { return error('Wine ISO overlay requires macOS copy-on-write clones') }
}
