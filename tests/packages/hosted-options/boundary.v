// SPDX-License-Identifier: GPL-2.0-or-later
// Focused capture boundary only. Never stage beside software_hosted_fixture.v.
module main

import desktop.sessioncore
import ui2
import tools.packages.pkgprotocol

__global (
	hosted_options_uid int = 501
	hosted_options_calls int
)

fn hosted_options_euid() int { return hosted_options_uid }

struct HostedX11App {
mut:
	directory string
	xwd_path string
	damage_path string
	image_path string
	damage_counter &u32 = unsafe { nil }
	failed bool
	command string
	argv []string
	package_session bool
	width int
	height int
}

enum HostedText { package_starting package_missing package_exited }
enum AppPointerPhase { move down up scroll horizontal_scroll }
enum AppPointerButton { no_button left middle right back }

fn open_hosted_x11_command(name string, command string, arguments []string, package_session bool,
	width int, height int, icon string, starting HostedText, missing HostedText, exited HostedText) &HostedX11App {
	if name != 'package' || icon != 'builtin:software' || starting != .package_starting || missing != .package_missing || exited != .package_exited {
		panic('unexpected hosted presentation contract')
	}
	hosted_options_calls++
	mut result := &HostedX11App{ command: command.clone(), argv: []string{cap: arguments.len},
		package_session: package_session, width: width, height: height }
	unsafe { result.argv.flags |= .noslices }
	for value in arguments { result.argv << value.clone() }
	return result
}

fn (mut a HostedX11App) close_app() {
	unsafe { a.command.free() }
	pkgprotocol.free_command_values(mut a.argv)
}
fn (mut a HostedX11App) build(_ ui2.Rect) !ui2.Element { panic('capture adapter does not qualify hosted rendering') }
fn (mut a HostedX11App) poll() bool { panic('capture adapter does not qualify hosted polling') }
fn (mut a HostedX11App) key_input(_ string) { panic('unqualified hosted input') }
fn (mut a HostedX11App) paste_input(_ string) { panic('unqualified hosted input') }
fn (mut a HostedX11App) paste_data(_ sessioncore.DataKind, _ string) { panic('unqualified hosted input') }
fn (mut a HostedX11App) pointer_input_enabled() bool { panic('unqualified hosted pointer') }
fn (mut a HostedX11App) pointer_event(_ AppPointerPhase, _ AppPointerButton, _ int, _ int, _ int, _ int, _ int) { panic('unqualified hosted pointer') }
fn (mut a HostedX11App) take_clipboard_copy_request() []u8 { panic('unqualified hosted clipboard') }
fn (mut a HostedX11App) receive_clipboard_copy_reply(_ string) { panic('unqualified hosted clipboard') }
fn desktop_munmap(_ voidptr, _ u64) int { panic('unqualified hosted mapping') }
fn tr(key string) string { return key }
