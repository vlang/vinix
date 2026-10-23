import os
import time
import stbi

fn capture(path string, name string) {
	r := os.exec(['build/android-run', 'screenshot', '--socket', path + '/qmp.sock', '--destination', path + '/' + name + '.png'])
	assert r.exit_code == 0, r.output
	println('CAPTURE ' + name + ' at=' + time.now().str())
}

// Wait for the actual onboarding button to be presented before clicking Skip.
// Startup readiness precedes the first Maps window frame on this runtime.
fn onboarding(path string) bool {
	img := stbi.load(path, desired_channels: 4) or { return false }
	defer { img.free() }
	if img.width != 1024 || img.height != 768 { return false }
	mut white := 0
	mut black := 0
	unsafe {
		for y in 150 .. 500 {
			for x in 140 .. 580 {
				i := (y * img.width + x) * 4
				if img.data[i] > 230 && img.data[i+1] > 230 && img.data[i+2] > 230 { white++ }
			}
		}
		for y in 555 .. 597 {
			for x in 300 .. 419 {
				i := (y * img.width + x) * 4
				if img.data[i] < 20 && img.data[i + 1] < 20 && img.data[i + 2] < 20 { black++ }
			}
		}
	}
	return white > 50000 && black > 4500
}

fn main() {
	path := os.abs_path('build/android-maps/attempt232/google-maps')
	mut found := false
	for _ in 0 .. 260 {
		log := os.read_file(path + '/serial.log') or { '' }
		assert !log.contains('APK-SUITE-EXIT id='), 'Maps exited before interaction'
		if log.contains('ANDROID-WS-READY backend=vinix-native') {
			capture(path, 'waiting')
			if onboarding(path + '/waiting.png') { found = true; break }
		}
		time.sleep(3 * time.second)
	}
	assert found, 'Onboarding was not presented'
	capture(path, 'initial')
	println('ONBOARDING-PRESENTED at=' + time.now().str())
	r := os.exec(['build/android-run', 'input', 'click', '556', '134', '--socket', path + '/qmp.sock', '--settle', '0.15'])
	assert r.exit_code == 0, r.output
	println('SKIP-CLICK at=' + time.now().str())
}
