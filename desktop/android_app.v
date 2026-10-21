// ART executes APK bytecode; the V Android backend presents directly to WS.
module main

const android_surface_width = 480
const android_surface_height = 640

__global android_label_loaded bool
__global android_label string

// The launcher slot keeps its stable identity; an image that selects another
// APK can supply its application label for the title bar and taskbar.
fn android_application_label() string {
	if !android_label_loaded {
		android_label_loaded = true
		mut bytes := [129]u8{}
		count := desktop_read_file('/usr/share/vinix/android-app-label', &bytes[0], u64(bytes.len))
		if count > 0 && count <= 128 {
			mut valid := true
			for i in 0 .. int(count) { if bytes[i] < 32 || bytes[i] == 127 { valid = false } }
			if valid { android_label = bytes[..int(count)].bytestr() }
		}
	}
	return android_label
}

fn open_android_calculator(mut _ Desktop) !NativeApp {
	mut app := &NativeSurfaceApp{
		surface_width: android_surface_width
		surface_height: android_surface_height
		icon: 'asset:calculator'
		starting: .android_starting
		exited: .android_exited
	}
	if C.access(c'/usr/bin/run-android-calculator', C.X_OK) != 0 {
		app.failed = true
		app.failure = .android_missing
		return app
	}
	app.surface_path = '/tmp/vinix-android-${C.getpid()}.surface'
	desktop_unlink(app.surface_path)
	client := desktop_spawn_native_surface('/usr/bin/run-android-calculator', '', '',
		app.surface_path, android_surface_width, android_surface_height) or {
		app.failed = true
		app.failure = .android_missing
		return app
	}
	app.client_pid = client.pid
	app.input_fd = client.input
	return app
}
