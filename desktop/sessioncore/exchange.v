// SPDX-License-Identifier: GPL-2.0-or-later
module sessioncore

pub const clipboard_limit = 65536
pub const clipboard_history_limit = 16
pub const grant_limit = 64

pub enum DataKind {
	text
	html
	uri_list
	png
}

pub fn (kind DataKind) mime() string {
	return match kind {
		.text { 'text/plain;charset=utf-8' }
		.html { 'text/html' }
		.uri_list { 'text/uri-list' }
		.png { 'image/png' }
	}
}

pub struct Clip {
pub mut:
	bytes     [clipboard_limit]u8
	len       int
	kind      DataKind
	owner_uid u32
	owner_pid int
	sensitive bool
}

pub fn (c &Clip) data() string { return unsafe { tos(&c.bytes[0], c.len) } }

pub struct Grant {
pub mut:
	token      u64
	uid        u32
	source_pid int
	target_pid int
	kind       DataKind
	expires    i64
	consumed   bool
}

pub struct Exchange {
pub mut:
	current         Clip
	history         [clipboard_history_limit]Clip
	count           int
	history_enabled bool = true
	grants          [grant_limit]Grant
}

pub fn (mut e Exchange) copy(uid u32, pid int, kind DataKind, value string, sensitive bool) ! {
	if pid <= 0 || value.len == 0 || value.len > clipboard_limit {
		return error('invalid clipboard payload')
	}
	if kind in [.text, .html, .uri_list] && value.contains('\x00') {
		return error('NUL in clipboard text')
	}
	e.current = Clip{ kind: kind, owner_uid: uid, owner_pid: pid, len: value.len, sensitive: sensitive }
	// A token grants the current offer, never data copied later by that owner.
	e.grants = [grant_limit]Grant{}
	for i, byte in value { e.current.bytes[i] = byte }
	if sensitive || !e.history_enabled { return }
	// Deduplicate without changing the data's source identity.
	mut existing := -1
	for i in 0 .. e.count {
		if e.history[i].kind == kind && e.history[i].data() == value {
			existing = i
			break
		}
	}
	if existing >= 0 {
		for i := existing; i > 0; i-- { e.history[i] = e.history[i - 1] }
	} else {
		last := if e.count == clipboard_history_limit { e.count - 1 } else { e.count }
		for i := last; i > 0; i-- { e.history[i] = e.history[i - 1] }
		if e.count < clipboard_history_limit { e.count++ }
	}
	e.history[0] = e.current
}

// Only the compositor calls grant after an explicit paste, drop or selection
// gesture. Tokens come from OS randomness and bind both endpoints and type.
pub fn (mut e Exchange) grant(token u64, uid u32, source_pid int, target_pid int, kind DataKind, now i64) ! {
	if token == 0 || source_pid <= 0 || target_pid <= 0 {
		return error('invalid exchange endpoints')
	}
	mut slot := -1
	for i in 0 .. grant_limit {
		if e.grants[i].token == token && !e.grants[i].consumed && e.grants[i].expires > now {
			return error('duplicate exchange token')
		}
		if e.grants[i].token == 0 || e.grants[i].consumed || e.grants[i].expires <= now { slot = i }
	}
	if slot < 0 { return error('too many pending exchanges') }
	e.grants[slot] = Grant{ token: token, uid: uid, source_pid: source_pid, target_pid: target_pid, kind: kind, expires: now + 5000 }
}

pub fn (mut e Exchange) consume(token u64, uid u32, source_pid int, target_pid int, kind DataKind, now i64) ! {
	for i in 0 .. grant_limit {
		g := e.grants[i]
		if g.token != token { continue }
		if g.consumed || g.expires <= now || g.uid != uid || g.source_pid != source_pid || g.target_pid != target_pid || g.kind != kind {
			return error('exchange permission denied')
		}
		e.grants[i].consumed = true
		return
	}
	return error('unknown exchange token')
}

pub fn (mut e Exchange) select_history(index int, uid u32) ! {
	if index < 0 || index >= e.count || e.history[index].owner_uid != uid {
		return error('clipboard history access denied')
	}
	e.current = e.history[index]
	e.grants = [grant_limit]Grant{}
}

pub fn (mut e Exchange) revoke(pid int) {
	for i in 0 .. grant_limit {
		if e.grants[i].source_pid == pid || e.grants[i].target_pid == pid {
			e.grants[i].consumed = true
		}
	}
	if e.current.owner_pid == pid && e.current.sensitive { e.current = Clip{} }
}

pub fn (mut e Exchange) clear() {
	e.current = Clip{}
	e.history = [clipboard_history_limit]Clip{}
	e.count = 0
	e.grants = [grant_limit]Grant{}
}

pub struct Association {
pub mut:
	type Text
	app  Text
	uri  bool
}

pub struct Associations {
pub mut:
	items [128]Association
	count int
}

pub fn (mut a Associations) set(kind string, app string, uri bool) ! {
	// Package IDs have the same 128-byte bound, plus an explicit namespace.
	valid_app := identifier(app) || (app.starts_with('package.') && identifier(unsafe { tos(app.str + 'package.'.len, app.len - 'package.'.len) }))
	if !valid_app || kind.len == 0 || kind.len > 128 || kind.contains('\x00') || kind.contains(' ')
		|| (uri && !uri_scheme(kind)) || (!uri && (!kind.contains('/') || kind.starts_with('/') || kind.ends_with('/'))) {
		return error('invalid association')
	}
	entry := Association{ type: text(kind)!, app: text(app)!, uri: uri }
	for i in 0 .. a.count {
		if a.items[i].uri == uri && a.items[i].type.str() == kind {
			a.items[i] = entry
			return
		}
	}
	if a.count == a.items.len { return error('too many associations') }
	a.items[a.count] = entry
	a.count++
}

pub fn (a &Associations) resolve(kind string, uri bool) ?string {
	for i in 0 .. a.count {
		if a.items[i].type.str() == kind && a.items[i].uri == uri { return a.items[i].app.str() }
	}
	return none
}

pub fn uri_scheme(value string) bool {
	if value.len == 0 || value.len > 32 || !value[0].is_letter() { return false }
	for byte in value {
		if !byte.is_letter() && !byte.is_digit() && byte !in [`+`, `-`, `.`] { return false }
	}
	return true
}

fn extension_matches(path string, start int, expected string) bool {
	if path.len - start != expected.len { return false }
	for i in 0 .. expected.len {
		byte := path[start + i]
		folded := if byte >= `A` && byte <= `Z` { byte + 32 } else { byte }
		if folded != expected[i] { return false }
	}
	return true
}

pub fn mime_for_path(path string) string {
	// Compare against the caller's path; taking a pointer to a local normalized
	// extension made V move its fixed buffer to the heap on every lookup.
	mut start := path.len
	for start > 0 && path[start - 1] != `.` && path[start - 1] != `/` { start-- }
	if start == 0 || path[start - 1] != `.` { return 'application/octet-stream' }
	for ext in ['txt', 'md', 'v', 'c', 'h', 'log', 'csv', 'json', 'xml', 'yaml', 'sh']! {
		if extension_matches(path, start, ext) { return 'text/plain' }
	}
	if extension_matches(path, start, 'html') || extension_matches(path, start, 'htm') { return 'text/html' }
	if extension_matches(path, start, 'png') { return 'image/png' }
	if extension_matches(path, start, 'jpg') || extension_matches(path, start, 'jpeg') { return 'image/jpeg' }
	if extension_matches(path, start, 'pdf') { return 'application/pdf' }
	if extension_matches(path, start, 'ics') { return 'text/calendar' }
	if extension_matches(path, start, 'zip') { return 'application/zip' }
	if extension_matches(path, start, 'tar') { return 'application/x-tar' }
	if extension_matches(path, start, 'mp3') { return 'audio/mpeg' }
	if extension_matches(path, start, 'wav') { return 'audio/wav' }
	if extension_matches(path, start, 'mp4') { return 'video/mp4' }
	return 'application/octet-stream'
}
