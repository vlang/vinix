// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// The built-in calculator's compile-time VML desktop adapter.
//
// The model comes from ui2's calculator example. The view is parsed and
// type-checked by V's `$vml` expression, which emits direct Element
// constructors; no VML parser or expression interpreter ships in the process.
module main

import ui2

const calculator_compiled_tree_key = 'vinix.compiled-vml-tree'

@[heap]
struct CalculatorApp {
mut:
	calculator  Calculator
	tree        ui2.Element
	tree_ready  bool
	width       f64
	height      f64
	panel_width f64
	panel_x     f64
	panel_y     f64
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

fn release_compiled_calculator_tree(element ui2.Element) {
	for child in element.children {
		release_compiled_calculator_tree(child)
	}
	if element.children.cap > 0 {
		unsafe { element.children.free() }
	}
}

fn (mut app CalculatorApp) build(size ui2.Rect) !ui2.Element {
	rebuild := !app.tree_ready || app.width != size.width || app.height != size.height
	if !rebuild {
		// The display is the only dynamic view property. The returned Element is
		// a shallow copy whose child arrays are the persistent compiled tree.
		if !ui2.set_element_text_by_id(mut app.tree, 'display', app.calculator.display) {
			return error('compiled Calculator VML has no display')
		}
		return app.tree
	}
	if app.tree_ready {
		release_compiled_calculator_tree(app.tree)
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
	app.tree = build_compiled_calculator(&app)
	app.tree_ready = true
	return app.tree
}

fn (mut app CalculatorApp) handle(event_id string) ! {
	app.calculator.press(event_id)
}

fn (mut app CalculatorApp) close_app() {
	if app.tree_ready {
		release_compiled_calculator_tree(app.tree)
		app.tree_ready = false
	}
}
