// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn (mut a PreviewApp) choose_open_image() {
	if a.portal_open { return }
	directory := os.dir(editor_bytes_text(a.open_path))
	defer { unsafe { directory.free() } }
	a.portal_open = session_dialog_open('preview.open', 0, 'Open image', if directory.starts_with('/') {
		directory
	} else {
		desktop_home
	}, '', '')
	if !a.portal_open { a.open_image() }
}

fn (mut a PreviewApp) poll() bool {
	if !a.portal_open { return false }
	if path := session_dialog_take('preview.open') {
		a.portal_open = false
		defer { unsafe { path.free() } }
		if path.len > 0 {
			preview_set_field(mut a.open_path, path)
			a.open_image()
			return true
		}
	}
	return false
}
