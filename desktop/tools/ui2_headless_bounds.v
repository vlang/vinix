// SPDX-License-Identifier: GPL-2.0-or-later
// `$vml` always starts from ui2.bounds(). A hosted headless application gives
// the root explicit model-backed dimensions, but the generated call must still
// exist on Linux/Vinix where no platform window backend is compiled.
module ui2

// Vinix hosts the compiled tree itself, so the model needs one narrow way to
// refresh dynamic text without making every Element field publicly mutable.
pub fn set_element_text_by_id(mut element Element, id string, text string) bool {
	if element.id == id {
		element.text = text
		return true
	}
	for mut child in element.children {
		if set_element_text_by_id(mut child, id, text) {
			return true
		}
	}
	return false
}

$if linux && ui2_headless ? {
	pub fn bounds() Rect {
		return Rect{
			width: 800
			height: 600
		}
	}
}
