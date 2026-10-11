// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

const workflow_owned_id_key = '__vinix.workflow.id'
const workflow_owned_id_text_key = '__vinix.workflow.id_text'
const workflow_owned_text_key = '__vinix.workflow.text'
const workflow_owned_image_key = '__vinix.workflow.image'

fn workflow_button(id string, text string, frame ui2.Rect, own_text bool) ui2.Element {
	return ui2.Element{
		...ui2.button(id, text, frame, ui2.BoxStyle{bg: body_panel}, ui2.TextStyle{color: body_text, size: 11, align: .left})
		key: if own_text { workflow_owned_id_text_key } else { workflow_owned_id_key }
	}
}

fn workflow_free_strings(values []string) {
	unsafe { values.free() }
}
