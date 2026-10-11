// SPDX-License-Identifier: GPL-2.0-or-later
module main
import ui2
import desktop.workflowcore

#include "@VMODROOT/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn test_workflow_panels_release_their_formatted_actions_and_text_each_frame() {
	mut app := FilesContextApp{}
	app.index_search.index.roots = [workflowcore.SearchRoot{path: '/home/test', enabled: true, contents: true}]
	app.index_search.results = ['/home/test/document.txt']
	app.operation.label = 'Copy complete'
	size := ui2.rect(0, 0, 800, 600)
	for _ in 0 .. 2 {
		begin_frame_elements()
		free_tree(app.index_panel(size))
		free_tree(app.operation_panel(size))
		free_tree(app.document_open_panel(size))
	}
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		begin_frame_elements()
		free_tree(app.index_panel(size))
		free_tree(app.operation_panel(size))
		free_tree(app.document_open_panel(size))
	}
	live := C.vinix_heap_end()
	assert live == 0, 'Workflow panels retained ${live} bytes over 100 frames'
}
