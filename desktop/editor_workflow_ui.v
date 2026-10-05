// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

const editor_save_as_height = 76
const editor_guard_height = 114

fn (a &TextEditorApp) build_save_as_panel(mut children []ui2.Element, width int, top int) {
	children << ui2.label('', tr('editor.workflow.save_as_hint'), ui2.rect(10, f64(top + 2), f64(width - 20), 24), ui2.TextStyle{ color: body_muted, size: 11 })
	children << editor_find_field(editor_action_save_as_path, a.save_as_path, 10, top + 30, width - 222, a.focus == .save_as)
	children << editor_edit_button(editor_action_save_as_create, tr('editor.workflow.save_as_create'), width - 206, top + 31, 118, true)
	children << editor_edit_button(editor_action_save_as_cancel, tr('editor.workflow.cancel'), width - 82, top + 31, 72, true)
}

fn (a &TextEditorApp) build_guard_panel(mut children []ui2.Element, width int, top int) {
	key := if a.discard_pending { 'editor.workflow.confirm_hint' } else {
		match a.pending_action {
			.new_document { 'editor.workflow.unsaved_new' }
			.open_document { 'editor.workflow.unsaved_open' }
			else { 'editor.workflow.unsaved_close' }
		}
	}
	children << ui2.label('', tr(key), ui2.rect(10, f64(top + 2), f64(width - 20), 44), ui2.TextStyle{ color: editor_modified, size: 12, lines: 2 })
	children << editor_edit_button(editor_action_guard_save, tr('editor.save'), 10, top + 48, 112, true)
	children << editor_edit_button(editor_action_keep_editing, tr('editor.workflow.keep_editing'), 128, top + 48, 150, true)
	children << editor_edit_button(editor_action_discard, tr('editor.workflow.discard'), 10, top + 80, 144, true)
	if a.discard_pending {
		children << editor_edit_button(editor_action_confirm_discard, tr('editor.workflow.confirm_discard'), 160, top + 80, 160, true)
	}
}
