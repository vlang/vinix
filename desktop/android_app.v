// Android APKs run through ART and Android Translation Layer on a private X11
// display, using the same pixel and input bridge as the other hosted apps.
module main

const android_surface_width = 480
const android_surface_height = 640

fn open_android_calculator(mut _ Desktop) !NativeApp {
	return open_hosted_x11_app('android', '/usr/bin/run-android-calculator',
		android_surface_width, android_surface_height, 'asset:calculator',
		.android_starting, .android_missing, .android_exited)
}
