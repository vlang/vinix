// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn capture_feature_has_action(tree ui2.Element, action string) bool {
	if tree.id == action || tree.action_id == action { return true }
	for child in tree.children {
		if capture_feature_has_action(child, action) { return true }
	}
	return false
}

fn test_capture_video_timer_and_keyboard_commands() {
	mut desktop := Desktop{}
	mut app := CaptureApp{ desktop: &desktop, page: .video }
	begin_frame_elements()
	tree := app.build(ui2.rect(0, 0, 560, 396))!
	assert capture_feature_has_action(tree, capture_action_delay_0)
	assert capture_feature_has_action(tree, capture_action_delay_3)
	assert capture_feature_has_action(tree, capture_action_delay_5)
	free_tree(tree)
	app.handle(capture_action_delay_5)!
	app.key_input('\r')
	assert desktop.capture.request.command == .start_video
	assert desktop.capture.request.delay == 5
	before := desktop.capture.request.sequence
	app.paste_input('\r\x1b')
	app.key_input('\x1b[3~')
	assert desktop.capture.request.sequence == before
	desktop.capture.report.phase = .recording
	app.key_input('\n')
	assert desktop.capture.request.command == .stop
	desktop.capture.report.phase = .screenshot_countdown
	app.key_input('\x1b')
	assert desktop.capture.request.command == .stop
}
