// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Whether this is the newest Vinix. At boot PID 1 starts vinix-version-check
// (build-support/), which asks vinix-os.org/version for the newest release and
// leaves its tag in /run. The desktop takes that answer, compares it with
// /etc/vinix-release, the release this system was built as, and when the
// system is older opens a window asking the user to download the new ISO.
//
// Only release images carry /etc/vinix-release; a development image is never
// told it is out of date.
module main

import os
import ui2

const installed_release_path = '/etc/vinix-release'
// Written whole by the helper, and taken (removed) by the desktop, so a
// reloaded desktop does not open the window a second time in one boot.
const latest_release_path = '/run/vinix-latest-release'
// The helper asks for up to ten minutes; a look every few seconds is plenty
// and costs one access(2).
const version_check_sample_ms = i64(5000)
const outdated_window_title = 'Vinix Update'
const outdated_window_width = 480
const outdated_window_height = 236

struct VersionCheck {
mut:
	// Nothing more to learn this session: a development image, or the answer
	// has been taken.
	done       bool
	sampled    bool
	sampled_ms i64
	// Both tags, for the window to show.
	installed string
	latest    string
}

fn (mut d Desktop) poll_version_check() {
	d.poll_version_check_at(monotonic_millis())
}

fn (mut d Desktop) poll_version_check_at(now i64) {
	if d.version_check.done {
		return
	}
	if d.version_check.sampled && now >= d.version_check.sampled_ms
		&& now - d.version_check.sampled_ms < version_check_sample_ms {
		return
	}
	if !d.version_check.sampled {
		d.version_check.installed = read_release_tag(installed_release_path)
		if d.version_check.installed.len == 0 {
			d.version_check.done = true
			return
		}
	}
	d.version_check.sampled = true
	d.version_check.sampled_ms = now
	if C.access(&char(latest_release_path.str), C.F_OK) != 0 {
		return
	}
	d.version_check.latest = read_release_tag(latest_release_path)
	os.rm(latest_release_path) or {}
	d.version_check.done = true
	if release_is_older(d.version_check.installed, d.version_check.latest) {
		d.open_outdated_window()
	}
}

// read_release_tag returns the first line of a release file, or '' when there
// is none. The result belongs to the caller.
fn read_release_tag(path string) string {
	text := os.read_file(path) or { return '' }
	tag := text.trim_space()
	unsafe { text.free() }
	return tag
}

fn (mut d Desktop) open_outdated_window() {
	mut width := outdated_window_width
	if width > d.canvas.width - 24 {
		width = d.canvas.width - 24
	}
	x := (d.canvas.width - width) / 2
	y := (d.canvas.height - outdated_window_height) / 3
	id := d.spawn(outdated_window_title, .outdated, x, y, width, outdated_window_height)
	index := d.window_index(id) or { return }
	d.clamp_to_screen(index)
}

fn outdated_page(width int, desktop &Desktop) []ui2.Element {
	pad := 18
	inner := width - 2 * pad
	versions := tr_fill2('window.outdated.versions', desktop.version_check.installed,
		desktop.version_check.latest)
	mut children := frame_elements(9)
	children << ui2.view('', ui2.rect(f64(pad), 18, f64(inner), 4), ui2.BoxStyle{
		bg:     app_accent
		radius: 2
	}, [])
	children << heading(tr('window.outdated.heading'), pad, 32, inner)
	children << body_line(tr('window.outdated.line_1'), pad, 62, inner)
	children << body_line(tr('window.outdated.line_2'), pad, 88, inner)
	children << body_line(tr('window.outdated.line_3'), pad, 106, inner)
	children << body_line(tr('window.outdated.line_4'), pad, 132, inner)
	children << ui2.view('', ui2.rect(f64(pad), 162, f64(inner), 1), ui2.BoxStyle{
		bg: body_rule
	}, [])
	children << ui2.label(frame_owned_text_id, versions, ui2.rect(f64(pad), 174, f64(inner), 16),
		ui2.TextStyle{
		color: body_muted
		size:  11
	})
	return children
}

// release_order ranks the tags deploy-iso.sh gives releases: iso-YYYY-MM-DD,
// then -2, -3, ... for more releases on the same day. 0 is no such tag.
fn release_order(tag string) i64 {
	if tag.len < 14 || tag.len > 20 || !tag.starts_with('iso-') {
		return 0
	}
	mut date := i64(0)
	for i in 4 .. 14 {
		c := tag[i]
		if i == 8 || i == 11 {
			if c != `-` {
				return 0
			}
			continue
		}
		if !c.is_digit() {
			return 0
		}
		date = date * 10 + i64(c - `0`)
	}
	mut same_day := i64(1)
	if tag.len > 14 {
		if tag[14] != `-` || tag.len == 15 {
			return 0
		}
		same_day = 0
		for i in 15 .. tag.len {
			c := tag[i]
			if !c.is_digit() {
				return 0
			}
			same_day = same_day * 10 + i64(c - `0`)
		}
	}
	return date * 100_000 + same_day
}

// release_is_older is true only when both are release tags and the installed
// one came first. A system newer than what the site names (a release not yet
// on it, or a site that answers wrongly) is left alone.
fn release_is_older(installed string, latest string) bool {
	a := release_order(installed)
	b := release_order(latest)
	return a > 0 && b > 0 && a < b
}
