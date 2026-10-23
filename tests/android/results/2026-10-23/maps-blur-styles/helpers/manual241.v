import os
import time
import stbi

fn record(text string) {
	line := time.now().str() + ' UTC+3 ' + text + '\n'
	print(line)
	mut file := os.open_append('build/android-maps/attempt241/google-maps/manual-timeline.log') or { panic(err) }
	file.write_string(line) or { panic(err) }
	file.close()
}

fn main() {
	path := 'build/android-maps/attempt241/google-maps/'
	assert os.args.len >= 2
	if os.args[1] == 'wait-map' {
		for _ in 0 .. 200 {
			log := os.read_file(path + 'serial.log') or { '' }
			assert !log.contains('APK-SUITE-EXIT id='), 'Maps exited before map presentation'
			r := os.exec(['build/android-run', 'screenshot', '--socket', path + 'qmp.sock', '--destination', path + 'map-probe.png'])
			if r.exit_code == 0 {
				img := stbi.load(path + 'map-probe.png', desired_channels: 4) or { panic(err) }
				mut sea := 0
				unsafe {
					for y in 200 .. 500 {
						for x in 140 .. 580 {
							i := (y * img.width + x) * 4
							if img.data[i] < 180 && img.data[i+1] > 150 && img.data[i+2] > 150 { sea++ }
						}
					}
				}
				img.free()
				if sea > 25000 {
					os.cp(path + 'map-probe.png', path + 'map-before-input.png')!
					record('MAP-COLOR-DETECTED cyan=' + sea.str())
					return
				}
			}
			time.sleep(3 * time.second)
		}
		panic('Map not presented')
	}
	args := if os.args[1] == 'capture' {
		['build/android-run', 'screenshot', '--socket', path + 'qmp.sock', '--destination', path + os.args[2] + '.png']
	} else {
		['build/android-run', 'input', ...os.args[1..], '--socket', path + 'qmp.sock', '--settle', '0.15']
	}
	record('BEGIN ' + args.str())
	r := os.exec(args)
	record('END exit=' + r.exit_code.str() + ' output=' + r.output.trim_space())
	assert r.exit_code == 0, r.output
}
