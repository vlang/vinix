// SPDX-License-Identifier: GPL-2.0-or-later
// Included in the native browser's existing --headless-smoke entrypoint.
module main

import html
import layout

fn vinix_button_diagnostic(box &layout.BlockBox) string {
	if box.tag_name == 'button' {
		return 'background=${box.background_color} border=${box.border} colors=${box.border_colors} fallback=${box.border_color} styles=${box.border_styles} snapped=${box.snaps_background_rect} scheme=${box.form_control_color_scheme}'
	}
	for child in box.children {
		detail := vinix_button_diagnostic(child)
		if detail != '' { return detail }
	}
	return ''
}

fn vinix_button_interaction_checks(chromium bool) {
	mut document := html.parse_document('<!doctype html><button id="control">Native</button><p id="status">Ready</p>')
	if chromium { document.set_font_rendering_policy(.chromium) }
	_ = layout.layout_document_typed_in_viewport(document, 320, 200)
	control := document.get_element_by_id('control') or { panic('missing native control') }
	for state in ['initial', 'hover', 'focus', 'mutation', 'leave', 'blur'] {
		match state {
			'hover' { document.set_hovered_node(control.as_node()) }
			'focus' { document.set_focused_area(control.as_node()) }
			'mutation' {
				status := document.get_element_by_id('status') or { panic('missing status') }
				mut node := status.as_node()
				node.set_text_content('Clicked') or { panic(err) }
			}
			'leave' { document.set_hovered_node(none) }
			'blur' { document.set_focused_area(none) }
			else {}
		}
		document.update_layout(.event_handler_handle_mouse_move)
		commands := layout.display_list_commands(layout.record_retained_display_list(mut document) or { panic('missing native button paint') })
		if commands.filter(it.kind == 'vinix_button').len != 1 {
			result := layout.document_layout_result(document) or { panic('missing native button layout') }
			panic('native button lost in ${state} (chromium=${chromium}): ' + vinix_button_diagnostic(&result.paint_tree))
		}
	}
}

fn vinix_document_checks() {
	for chromium in [false, true] {
		vinix_button_interaction_checks(chromium)
		for markup in ['<button>Native</button>', '<input type="submit" value="Native">',
			'<button disabled>Disabled</button>'] {
			mut document := html.parse_document('<!doctype html>' + markup)
			if chromium { document.set_font_rendering_policy(.chromium) }
			box := layout.layout_document_typed_in_viewport(document, 320, 200)
			controls := box.paint_commands().filter(it.kind.starts_with('vinix_button'))
			assert controls.len == 1, 'native bezel missing for ' + markup
			assert controls[0].width > 0 && controls[0].height > 0
			assert controls[0].kind.ends_with('_disabled') == markup.contains('disabled')
		}
		for style in ['appearance:none', 'background:red', 'border:3px solid blue', 'border-radius:8px',
			'background-image:linear-gradient(red,blue)'] {
			mut document := html.parse_document('<!doctype html><button style="${style}">Authored</button>')
			if chromium { document.set_font_rendering_policy(.chromium) }
			box := layout.layout_document_typed_in_viewport(document, 320, 200)
			assert !box.paint_commands().any(it.kind.starts_with('vinix_button')), 'native bezel replaced ' + style
		}
	}
	document := html.parse_document('<!doctype html><p style="font-size:13px"><a href="#link">Link gyp</a></p>')
	box := layout.layout_document_typed_in_viewport(document, 320, 200)
	text := box.paint_commands().filter(it.kind == 'draw_text' && it.text == 'Link gyp')
	assert text.len == 1 && text[0].glyph_translation_y > text[0].y
	println('Vinix document baselines and native HTML controls: passed')
}
