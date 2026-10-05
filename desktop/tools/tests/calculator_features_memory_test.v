// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

#include "@VMODROOT/heap_tracker.h"

fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn test_calculator_interaction_and_history_release_owned_allocations() {
	mut app := new_calculator_app()
	begin_frame_elements()
	warm := app.build(ui2.rect(0, 0, 340, 510))!
	free_tree(warm)
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		app.key_input('c1.25+2.5=')
		app.key_input('%')
		app.handle('calculator.memory.add')!
		app.handle('calculator.memory.recall')!
		app.key_input('c123\x7f')
		app.paste_input(' -42.25 ')
		begin_frame_elements()
		tree := app.build(ui2.rect(0, 0, 340, 510))!
		free_tree(tree)
	}
	app.close_app()
	live := C.vinix_heap_end()
	assert live == 0, 'calculator retained ${live} bytes after closing'
}

fn test_calculator_scientific_operations_modes_history_and_errors_release_owned_memory() {
	mut app := new_calculator_app()
	app.handle('calculator.mode.scientific')!
	app.key_input('30')
	app.handle('calculator.scientific.sin')!
	begin_frame_elements()
	free_tree(app.build(ui2.rect(0, 0, 620, 576))!)
	// The compact view uses a persistent frame pool; warm its slot before
	// measuring transient layouts, operations, and history strings.
	begin_frame_elements()
	free_tree(app.build(ui2.rect(0, 0, 340, 510))!)
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		app.handle('calculator.angle.degrees')!
		for index, action in calculator_scientific_actions {
			app.key_input('c')
			app.paste_input(['9', '4', '-3', '30', '60', '45', '.5', '.5', '1', '1', '100', '0',
				'0', '0']![index])
			app.handle(action)!
		}
		app.key_input('c2+9')
		app.handle('calculator.scientific.sqrt')!
		app.key_input('==')
		app.handle('calculator.memory.add')!
		app.handle('calculator.memory.recall')!
		app.handle('calculator.history.0')!
		app.key_input('c')
		app.paste_input('1e308')
		app.handle('calculator.scientific.square')!
		assert app.calculator.has_error
		app.handle('calculator.scientific.pi')!
		app.handle('calculator.angle.radians')!
		app.key_input('/2=')
		app.handle('calculator.scientific.tan')!
		assert app.calculator.has_error
		for size in [ui2.rect(0, 0, 620, 576), ui2.rect(0, 0, 340, 510), ui2.rect(0, 0, 760, 620)]! {
			begin_frame_elements()
			free_tree(app.build(size)!)
		}
		app.key_input('\x13')
		begin_frame_elements()
		free_tree(app.build(ui2.rect(0, 0, 340, 540))!)
		app.key_input('\x13\x04')
	}
	app.close_app()
	app.close_app()
	assert C.vinix_heap_end() == 0
}

fn test_calculator_scientific_init_resize_and_close_release_all_owned_memory() {
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut app := new_calculator_app()
		begin_frame_elements()
		free_tree(app.build(ui2.rect(0, 0, 340, 540))!)
		app.handle('calculator.mode.scientific')!
		app.handle('calculator.scientific.pi')!
		for size in [ui2.rect(0, 0, 620, 576), ui2.rect(0, 0, 760, 620)]! {
			begin_frame_elements()
			free_tree(app.build(size)!)
		}
		app.close_app()
		unsafe { free(app) }
	}
	assert C.vinix_heap_end() == 0
}
