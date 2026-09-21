// SPDX-License-Identifier: GPL-2.0-or-later
// Launcher for every example in the sibling ~/code/ui2 checkout. Each example
// remains its own executable so its module-main model and globals cannot clash
// with another example or with the compositor.
module main

import ui2

const ui2_example_action_prefix = 'ui2.example.launch.'
const ui2_example_process_prefix = 'vinix-ui2-'
const ui2_examples_per_page = 16

const ui2_example_names = [
	'accent_color',
	'accordion',
	'accordion_widget',
	'anchor_layout',
	'box_layout',
	'box_layout_inside_row',
	'box_layout_sizing',
	'box_layout_with_textbox',
	'calculate',
	'calculator',
	'calculator_resizable',
	'canvas_layout',
	'canvas_layout_inside_row',
	'carousel',
	'cells',
	'change_title',
	'child_window',
	'circle_drawer',
	'colorbox',
	'counter',
	'crud',
	'custom_window',
	'demo_chunkview',
	'demo_event',
	'demo_label',
	'demo_radio',
	'demo_style_4colors',
	'dirbrowser',
	'double_listbox',
	'dropdown',
	'dynamic_layout',
	'editor',
	'file_dialog',
	'filebrowser',
	'files_dropped',
	'flight_booker',
	'float_layout',
	'fontchooser',
	'gg2048',
	'gradient_texture',
	'grid',
	'grid2',
	'grid_layout',
	'group',
	'group2',
	'label_justify',
	'logview',
	'menubar',
	'message',
	'modal_view',
	'nested_clipping',
	'nested_scrollview',
	'nested_scrollview_box_layout',
	'page_layout',
	'popup',
	'rasterview',
	'rectangles',
	'rectangles_resizable',
	'relative_layout',
	'resizable_menu_window',
	'rgb_color',
	'row_layout',
	'screen_manager',
	'scrollview',
	'slider_textbox',
	'spinner',
	'splitpanel',
	'stack_layout',
	'switch',
	'tabbed_panel',
	'tabs',
	'temperature_converter',
	'text_input',
	'text_style',
	'textbox',
	'timer',
	'toggle_button',
	'transitions',
	'tray_icon',
	'tree_view_widget',
	'treeview',
	'users',
	'users_box_layout',
	'windows_smoke',
]

fn ui2_example_title(name string) string {
	words := name.split('_')
	mut title := ''
	for index, word in words {
		if index > 0 {
			title += ' '
		}
		if word == 'ui2' {
			title += 'ui2'
		} else if word == 'gg2048' {
			title += '2048'
		} else if word.len > 0 {
			title += word[..1].to_upper() + word[1..]
		}
	}
	return title
}

fn ui2_example_named(name string) ?AppFactory {
	for example in ui2_example_names {
		if example == name {
			return AppFactory{
				title:            ui2_example_title(name)
				icon:             'builtin:calculator'
				width:            800
				height:           634
				process_name:     ui2_example_process_prefix + name
				polling:          true
				poll_interval_ms: 33
				keyboard:         true
				pointer:          true
				standalone:       true
			}
		}
	}
	return none
}

struct Ui2ExamplesApp {
mut:
	page int
}

fn (mut a Ui2ExamplesApp) build(size ui2.Rect) !ui2.Element {
	width := int(size.width)
	height := int(size.height)
	mut children := frame_elements(ui2_examples_per_page + 4)
	children << ui2.label('ui2.examples.heading', 'ui2 Examples', ui2.rect(22, 16,
		f64(width - 44), 28), ui2.TextStyle{
		size:  20
		bold:  true
		color: body_heading
	})
	page_count := (ui2_example_names.len + ui2_examples_per_page - 1) /
		ui2_examples_per_page
	children << ui2.label('ui2.examples.page', 'Page ${a.page + 1} of ${page_count}',
		ui2.rect(22, 45, f64(width - 44), 22), ui2.TextStyle{
			size:  13
			color: body_muted
		})
	start := a.page * ui2_examples_per_page
	button_width := (width - 66) / 2
	for slot := 0; slot < ui2_examples_per_page; slot++ {
		index := start + slot
		if index >= ui2_example_names.len {
			break
		}
		name := ui2_example_names[index]
		column := slot % 2
		row := slot / 2
		x := 22 + column * (button_width + 22)
		y := 76 + row * 46
		button := ui2.button('ui2.example.${name}', ui2_example_title(name),
			ui2.rect(f64(x), f64(y), f64(button_width), 30), ui2.BoxStyle{}, ui2.TextStyle{
				size:  14
				color: catalina_button_text
				align: .center
			})
		children << ui2.with_action(ui2.with_native_style(button),
			ui2_example_action_prefix + name)
	}
	navigation_y := height - 46
	if a.page > 0 {
		children << ui2.with_native_style(ui2.button('ui2.examples.previous', 'Previous',
			ui2.rect(22, f64(navigation_y), 100, 28), ui2.BoxStyle{}, ui2.TextStyle{
				color: catalina_button_text
				align: .center
			}))
	}
	if a.page + 1 < page_count {
		children << ui2.with_native_style(ui2.button('ui2.examples.next', 'Next',
			ui2.rect(f64(width - 122), f64(navigation_y), 100, 28), ui2.BoxStyle{}, ui2.TextStyle{
				color: catalina_button_text
				align: .center
			}))
	}
	return ui2.screen(app_surface, children)
}

fn (mut a Ui2ExamplesApp) handle(action string) ! {
	page_count := (ui2_example_names.len + ui2_examples_per_page - 1) /
		ui2_examples_per_page
	match action {
		'ui2.examples.previous' {
			if a.page > 0 {
				a.page--
			}
		}
		'ui2.examples.next' {
			if a.page + 1 < page_count {
				a.page++
			}
		}
		else {}
	}
}

fn open_ui2_examples(mut _ Desktop) !NativeApp {
	return &Ui2ExamplesApp{}
}
