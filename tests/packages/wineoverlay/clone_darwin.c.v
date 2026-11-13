// SPDX-License-Identifier: GPL-2.0-or-later
module wineoverlay

import os

#include <sys/clonefile.h>
#define wine_overlay_clonefile clonefile
fn C.wine_overlay_clonefile(&char, &char, u32) i32

fn clone_fresh_darwin(source string, target string) ! {
	if os.lstat(source)!.get_filetype() != .regular || os.exists(target) || os.is_link(target) { return error('overlay clone needs ordinary source and fresh target') }
	if C.wine_overlay_clonefile(source.str, target.str, C.CLONE_NOFOLLOW) != 0 { return error('overlay copy-on-write clone refused; no full-copy fallback') }
}
