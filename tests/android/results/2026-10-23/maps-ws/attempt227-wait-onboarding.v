import os
import time
import stbi

fn main() {
	path := os.abs_path('build/android-maps/attempt227/google-maps')
	for _ in 0 .. 70 {
		shot := path + '/presented-wait.png'
		r := os.exec(['build/android-run', 'screenshot', '--socket', path + '/qmp.sock', '--destination', shot])
		assert r.exit_code == 0, r.output
		img := stbi.load(shot, desired_channels: 4)!
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
					if img.data[i] < 20 && img.data[i+1] < 20 && img.data[i+2] < 20 { black++ }
				}
			}
		}
		img.free()
		println('PRESENTED white=${white} black=${black} at=' + time.now().str())
		if white > 50000 && black > 4500 {
			os.cp(shot, path + '/onboarding-presented.png')!
			r2 := os.exec(['build/android-run', 'input', 'click', '556', '134', '--socket', path + '/qmp.sock', '--settle', '0.15'])
			assert r2.exit_code == 0, r2.output
			println('VISIBLE-SKIP-CLICK at=' + time.now().str())
			return
		}
		time.sleep(3 * time.second)
	}
	panic('No visible onboarding')
}
