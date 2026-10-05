// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn test_terminal_rebuild_record_identifies_the_initiating_shell() {
	record := terminal_rebuild_record('42 1000.00 77\n', 42, 1_001_890) or {
		panic('valid rebuild record was rejected')
	}
	assert record.started_ms == 1_000_000
	assert record.shell_pid == 77
	assert terminal_rebuild_message('42 1000.00 77\n', 42, 1_001_890) ==
		'vinix-desktop has been rebuilt in 1.89 seconds\r\n'
	assert terminal_rebuild_message('42 1000.00 0\n', 42, 1_001_890) == ''
}

fn test_terminal_rebuild_snapshot_flattens_scrollback_and_visible_rows() {
	mut terminal := TerminalApp{}
	terminal.set_geometry(3, 12)
	terminal.lines << 'earlier output'.clone()
	terminal.ingest_output('~ vinix-desktop-build\r\n==> Building'.bytes())
	assert terminal.rebuild_snapshot() ==
		'earlier output\r\n~ vinix-desk\r\ntop-build\r\n==> Building\r\n'
}
