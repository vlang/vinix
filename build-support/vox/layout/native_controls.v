// SPDX-License-Identifier: GPL-2.0-or-later
module layout

import css
import painting

// Only replace the UA bezel. Author backgrounds, borders, radii, images and
// appearance:none stay on the ordinary web paint path. Layout and DOM input
// handling remain owned by the browser.
fn vinix_native_button(box &BlockBox) ?string {
	if box.layout_handle == unsafe { nil } || box.tag_name !in ['button', 'input']
		|| box.decorations().background_images.len > 0
		|| !box_radii_are_zero(box.decorations().border_radii) {
		return none
	}
	node := unsafe { &Node(box.layout_handle) }
	if node.computed_values().appearance() == .none_ { return none }
	dom_node := node.dom_node() or { return none }
	element := dom_node.as_element() or { return none }
	if box.tag_name == 'input' && element.get_attribute_value('type').to_lower() !in [
		'button',
		'submit',
		'reset',
	] {
		return none
	}
	scheme := box.form_control_color_scheme
	enabled := !element.is_actually_disabled()
	base := css.SystemColor.button_face(scheme)
	scale := node.document().layout_coordinate_scale()
	width := if box.snaps_background_rect { 2 * scale } else { scale }
	border_style := if box.snaps_background_rect {
		painting.LineStyle.outset
	} else {
		painting.LineStyle.solid
	}
	border_color := if box.snaps_background_rect {
		css.Color{118, 118, 118, 255}
	} else {
		css.SystemColor.button_border(scheme)
	}
	background := if box.snaps_background_rect { css.Color{239, 239, 239, 255} } else { base }
	// Chromium's UA override changes the resting bezel; its hover/disabled
	// rules still use the shared system colours. Keep all three states native.
	background_matches := if enabled {
		box.background_color == background || box.background_color == base.darkened(0.8)
	} else {
		box.background_color == base.with_alpha(128)
	}
	if !background_matches || box.border != BoxEdges{width, width, width, width}
		|| box.border_styles != BoxBorderStyles{border_style, border_style, border_style, border_style}
		|| effective_border_colors(box.border_colors, box.border_color) != BoxColors{border_color, border_color, border_color, border_color} {
		return none
	}
	return if enabled { 'vinix_button' } else { 'vinix_button_disabled' }
}
