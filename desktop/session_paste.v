// SPDX-License-Identifier: GPL-2.0-or-later
module main

import desktop.sessioncore

interface RichPasteApp {
mut:
	paste_data(kind sessioncore.DataKind, data string)
}

fn hosted_session_client(name string) bool {
	return name in ['vinix-firefox', 'vinix-chromium', 'vinix-libreoffice', 'vinix-gimp',
		'vinix-wine-notepad', 'vinix-wine-word2013', 'vinix-wine-calculator', 'vinix-obs', 'vinix-steam', 'vinix-zed']
}

fn native_rich_paste(mut app NativeApp, kind sessioncore.DataKind, data string) {
	if mut app is RichPasteApp {
		mut paster := RichPasteApp(app)
		paster.paste_data(kind, data)
		return
	}
	if kind == .html {
		plain := sessioncore.html_text(data)
		defer { unsafe { plain.free() } }
		if mut app is PastingApp {
			mut paster := PastingApp(app)
			paster.paste_input(plain)
		}
	} else if kind in [.text, .uri_list] {
		if mut app is PastingApp {
			mut paster := PastingApp(app)
			paster.paste_input(data)
		}
	}
}

fn (mut a PreviewApp) paste_data(kind sessioncore.DataKind, data string) {
	if kind != .png { return }
	directory := session_runtime_directory()
	path := '${directory}/paste-${C.getpid()}.png'
	defer {
		C.unlink(&char(path.str))
		unsafe {
			directory.free()
			path.free()
		}
	}
	if !session_private_directory(directory) { return }
	sessioncore.save(path, data) or { return }
	preview_set_field(mut a.open_path, path)
	a.open_image()
}

fn (mut app RemoteApp) paste_data(kind sessioncore.DataKind, data string) {
	if app.closed || app.standalone { return }
	if app.peer_features & app_feature_rich_clipboard == 0 {
		if kind == .html {
			plain := sessioncore.html_text(data)
			defer { unsafe { plain.free() } }
			app.paste_input(plain)
		} else if kind in [.text, .uri_list] {
			app.paste_input(data)
		}
		return
	}
	mut bytes := []u8{cap: data.len + 1}
	bytes << u8(kind)
	for byte in data { bytes << byte }
	defer { unsafe { bytes.free() } }
	reply := app.transact(.rich_paste, 0, 0, unsafe { tos(bytes.data, bytes.len) }) or { return }
	if reply.payload.cap > 0 { unsafe { reply.payload.free() } }
	app.tree_stale = true
	app.poll_sampled = false
}

fn (mut d Desktop) paste_session_data() bool {
	if d.start_menu_open || d.hub.clipboard == unsafe { nil } || d.hub.clipboard.current.len == 0 || d.hub.clipboard.current.kind == .text {
		return false
	}
	for w in d.windows {
		if w.id != d.focus || w.app_index < 0 || w.app_index >= d.apps.len { continue }
		mut app := d.apps[w.app_index]
		if mut app is RichPasteApp {
			mut paster := RichPasteApp(app)
			paster.paste_data(d.hub.clipboard.current.kind, d.hub.clipboard.current.data())
			d.dirty = true
			return true
		}
	}
	return false
}
