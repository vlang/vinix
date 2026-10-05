// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn activity_views_element(element ui2.Element, id string) ?ui2.Element {
	if element.id == id { return element }
	for child in element.children {
		if result := activity_views_element(child, id) { return result }
	}
	return none
}

fn test_activity_view_navigation_preserves_process_selection() {
	mut app := ActivityApp{}
	defer { app.close_app() }
	app.monitor.selected_pid = 42
	app.search_focused = true
	app.columns_open = true
	for index, action in ['activity.view.processes', 'activity.view.resources', 'activity.view.gpu',
		'activity.view.energy', 'activity.view.startup'] {
		app.inspector_open = true
		assert app.handle_view(action)
		assert int(app.view) == index
		assert !app.inspector_open && !app.search_focused && !app.columns_open
		assert app.monitor.selected_pid == 42
	}
	assert !app.handle_view('unknown')
	app.inspector_open = true
	assert app.handle_view(activity_inspect_close)
	assert !app.inspector_open
}

fn test_activity_alternate_views_replace_process_body_and_place_below_toolbar() {
	mut app := ActivityApp{}
	defer { app.close_app() }
	for view, id in {
		ActivityView.resources: 'activity.resources'
		ActivityView.gpu:       'activity.gpu.body'
		ActivityView.energy:    'activity.energy'
	} {
		app.view = view
		tree := app.build(ui2.rect(0, 0, 900, 640))!
		body := activity_views_element(tree, id) or { panic('missing view body ${id}') }
		assert body.frame.y == f64(activity_toolbar_height)
		assert activity_views_element(tree, activity_action_name) == none
		free_tree(tree)
	}
}

fn test_activity_gpu_unavailable_does_not_fabricate_valid_history() {
	mut resources := ActivityResources{}
	defer { resources.free() }
	mut gpu := ActivityGpu{}
	defer { gpu.free() }
	gpu.sample(mut resources)
	// macOS test hosts have no Vinix GPU node. A missing node must remain
	// unavailable rather than becoming an idle 0% device.
	if !gpu.available {
		assert !gpu.initialized
		assert !gpu.history.available()
	}
	tree := gpu.build(900, 540)
	free_tree(tree)
}

fn test_activity_energy_accepts_signed_current_and_bounds() {
	stats := activity_energy_parse('voltage_mv: 12345\ncurrent_ma: -421\npower_mw: -5197\n')
	assert stats.has_voltage && stats.voltage_mv == 12345
	assert stats.has_current && stats.current_ma == -421
	assert stats.has_power && stats.power_mw == -5197
	minimum := activity_energy_signed_field('power_mw: -9223372036854775808\n', 'power_mw') or { panic('missing signed field') }
	assert minimum == i64(-9223372036854775807) - 1
	assert activity_energy_signed_field('power_mw: 9223372036854775808\n', 'power_mw') == none
	missing := activity_energy_parse('voltage_mv: unavailable\n')
	assert !missing.has_voltage && !missing.has_current && !missing.has_power
}

fn test_activity_gpu_parses_real_counters_and_invalidates_missing_or_reset_rates() {
	mut gpu := ActivityGpu{}
	defer { gpu.free() }
	gpu.accept_sample('devices: 2\nsubmissions: 10\ndrivers: virtio_gpu apple\n', 1000)
	assert gpu.available && gpu.initialized
	assert gpu.devices == 2 && gpu.submissions == 10
	assert gpu.drivers == 'virtio_gpu apple'
	assert !gpu.history.available()
	gpu.accept_sample('devices: 2\nsubmissions: 35\ndrivers: virtio_gpu apple\n', 1500)
	assert gpu.history.available() && gpu.history.latest() == 50.0
	gpu.accept_sample('devices: 2\nsubmissions: broken\n', 2000)
	assert !gpu.available && !gpu.initialized && !gpu.history.available()
	assert gpu.drivers == ''
	gpu.accept_sample('devices: 2\nsubmissions: 45\n', 2500)
	assert gpu.available && !gpu.history.available()
	gpu.accept_sample('devices: 2\nsubmissions: 45\n', 3000)
	assert gpu.history.available() && gpu.history.latest() == 0.0
	gpu.accept_sample('devices: 2\nsubmissions: 3\n', 3500)
	assert gpu.available && !gpu.history.available()
	gpu.accept_sample('devices: 2\nsubmissions: 9 garbage\n', 4000)
	assert !gpu.available && !gpu.history.available()
	gpu.accept_sample('devices: 0\nsubmissions: 9\n', 4500)
	assert !gpu.available && !gpu.history.available()
}
