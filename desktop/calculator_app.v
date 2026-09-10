// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// The built-in calculator's compile-time VML desktop adapter.
//
// The model comes from ui2's calculator example. The view is parsed and
// type-checked by V's `$vml` expression, which emits direct Element
// constructors; no VML parser or expression interpreter ships in the process.
module main

import ui2

@[heap]
struct CalculatorApp {
mut:
	calculator   Calculator
	layout       ui2.Element
	layout_ready bool
	width        f64
	height       f64
	panel_width  f64
	panel_x      f64
	panel_y      f64
}

fn new_calculator_app() &CalculatorApp {
	return &CalculatorApp{
		calculator: initial_calculator()
	}
}

fn open_native_calculator() NativeApp {
	return new_calculator_app()
}

fn build_compiled_calculator(app &CalculatorApp) ui2.Element {
	return $vml('calculator_vinix.vml')
}

// Current `$vml` lowers a dynamic string expression to an interpolation that
// owns a temporary string. Substitute the model-owned display after the VML
// layout is built so the tree still has no parser or retained mutable state.
fn calculator_layout_with_display(element ui2.Element, display string) ui2.Element {
	if element.id == 'display' {
		return ui2.Element{
			...element
			text: display
		}
	}
	if element.children.len == 0 {
		return element
	}
	mut children := []ui2.Element{cap: element.children.len}
	for child in element.children {
		children << calculator_layout_with_display(child, display)
	}
	return ui2.Element{
		...element
		children: children
	}
}

// The `$vml` layout uses literals and owns only its child arrays. The adapted
// copy above owns its replacement arrays and is released by free_tree.
fn release_compiled_calculator_layout(element ui2.Element) {
	for child in element.children {
		release_compiled_calculator_layout(child)
	}
	if element.children.cap > 0 {
		unsafe { element.children.free() }
	}
}

fn (mut app CalculatorApp) build(size ui2.Rect) !ui2.Element {
	rebuild := !app.layout_ready || app.width != size.width || app.height != size.height
	if rebuild {
		if app.layout_ready {
			release_compiled_calculator_layout(app.layout)
		}
		app.width = size.width
		app.height = size.height
		available_width := size.width - 24
		app.panel_width = if available_width < 260 { available_width } else { 260 }
		app.panel_x = if size.width > app.panel_width {
			(size.width - app.panel_width) / 2
		} else {
			0
		}
		app.panel_y = if size.height > 340 { (size.height - 340) / 2 } else { 0 }
		app.layout = build_compiled_calculator(&app)
		app.layout_ready = true
	}
	// ui2 Elements are immutable declarations in current ui2. `$vml` lowers
	// the static layout once; each adapted frame owns replacement arrays while
	// the Calculator owns the display string.
	return calculator_layout_with_display(app.layout, app.calculator.display)
}

fn (mut app CalculatorApp) handle(event_id string) ! {
	app.calculator.press(event_id)
}

fn (mut app CalculatorApp) close_app() {
	if app.layout_ready {
		release_compiled_calculator_layout(app.layout)
		app.layout_ready = false
	}
}
