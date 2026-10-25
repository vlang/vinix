// SPDX-License-Identifier: GPL-2.0-or-later
// Headless Software fixtures do not qualify the hosted graphical backend.
// Fail immediately if a test unexpectedly crosses that boundary.
module main

import desktop.sessioncore
import ui2

struct HostedX11App {
mut:
	directory string
	xwd_path string
	damage_path string
	image_path string
	damage_counter &u32 = unsafe { nil }
	failed bool
}

enum HostedText { package_starting package_missing package_exited }
enum AppPointerPhase { move down up scroll horizontal_scroll }
enum AppPointerButton { no_button left middle right back }

fn open_hosted_x11_command(_ string, _ string, _ []string, _ bool, _ int, _ int,
	_ string, _ HostedText, _ HostedText, _ HostedText) &HostedX11App {
	panic('headless Software fixture reached the unqualified hosted launcher')
}

fn (mut a HostedX11App) build(_ ui2.Rect) !ui2.Element { panic('unqualified hosted build') }
fn (mut a HostedX11App) poll() bool { panic('unqualified hosted poll') }
fn (mut a HostedX11App) key_input(_ string) { panic('unqualified hosted key input') }
fn (mut a HostedX11App) paste_input(_ string) { panic('unqualified hosted paste input') }
fn (mut a HostedX11App) paste_data(_ sessioncore.DataKind, _ string) { panic('unqualified hosted paste data') }
fn (mut a HostedX11App) close_app() { panic('unqualified hosted close') }
fn (mut a HostedX11App) pointer_input_enabled() bool { panic('unqualified hosted pointer query') }
fn (mut a HostedX11App) pointer_event(_ AppPointerPhase, _ AppPointerButton, _ int, _ int, _ int, _ int, _ int) {
	panic('unqualified hosted pointer event')
}
fn (mut a HostedX11App) take_clipboard_copy_request() []u8 { panic('unqualified hosted clipboard request') }
fn (mut a HostedX11App) receive_clipboard_copy_reply(_ string) { panic('unqualified hosted clipboard reply') }
fn desktop_munmap(_ voidptr, _ u64) int { panic('unqualified hosted unmap') }
fn tr(_ string) string { panic('unqualified hosted translation') }
