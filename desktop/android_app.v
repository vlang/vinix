// ART executes APK bytecode; the V Android backend presents directly to WS.
module main

const android_surface_width = 480
const android_surface_height = 640

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
