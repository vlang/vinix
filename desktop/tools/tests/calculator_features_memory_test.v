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
