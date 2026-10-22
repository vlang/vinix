// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn test_software_factory_enables_remote_hosted_pointer_transport() {
	mut found := false
	for factory in available_apps {
		if factory.process_name != 'vinix-software' { continue }
		found = true
		// RemoteApp snapshots this flag when the catalog process starts, before
		// a hosted package exists. The future surface must receive raw input.
		assert factory.pointer && factory.keyboard && factory.polling
		assert factory.open != unsafe { nil }
	}
	assert found
}

fn test_software_pointer_delegates_scaled_motion_press_and_release_only_when_ready() {
	mut pair := [2]i32{}
	assert C.pipe(&pair[0]) == 0
	defer { C.close(pair[0]); C.close(pair[1]) }
	mut hosted := HostedX11App{input_fd: pair[1], surface_width: 1024, surface_height: 768}
	mut software := SoftwareApp{hosted_app: unsafe { &hosted }}
	assert !software.pointer_input_enabled()
	hosted.ready = true
	assert software.pointer_input_enabled()
	software.pointer_event(.move, .no_button, 0, 100, 75, 512, 384)
	software.pointer_event(.down, .left, 0, 100, 75, 512, 384)
	software.pointer_event(.up, .left, 0, 100, 75, 512, 384)
	mut events := [3]WineHostEvent{}
	assert desktop_read_all_with_timeout(pair[0], &events[0], sizeof(WineHostEvent) * 3, 1000)
	for index, kind in [WineHostEventKind.motion, .button_down, .button_up] {
		assert events[index].magic == wine_host_event_magic
		assert events[index].kind == u32(kind)
		assert events[index].x == 200 && events[index].y == 150
		assert events[index].length == 0
	}
	software.hosted_app = unsafe { nil }
	assert !software.pointer_input_enabled()
}
