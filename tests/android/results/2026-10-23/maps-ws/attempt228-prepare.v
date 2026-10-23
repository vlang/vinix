import os
import json2

fn main() {
	b := 'build/android-maps/'
	mut cfg := json2.decode[map[string]json2.Any](os.read_file(b + 'attempt227.json')!)!
	cfg['output'] = b + 'attempt228'
	mut apps := cfg['applications']!.as_array()
	mut app := apps[0].as_map()
	app['startup_seconds'] = 360
	apps[0] = app
	cfg['applications'] = apps
	os.write_file(b + 'attempt228.json', json2.encode(cfg, prettify: true))!
	mut interaction := os.read_file(b + 'interact227.v')!.replace('attempt227', 'attempt228')
	old := '\tmut black := 0'
	assert interaction.count(old) == 1
	interaction = interaction.replace(old, '\tmut white := 0\n' + old)
	point := '\tunsafe {\n\t\tfor y in 555 .. 597 {'
	assert interaction.count(point) == 1
	interaction = interaction.replace(point, '\tunsafe {\n\t\tfor y in 150 .. 500 {\n\t\t\tfor x in 140 .. 580 {\n\t\t\t\ti := (y * img.width + x) * 4\n\t\t\t\tif img.data[i] > 230 && img.data[i+1] > 230 && img.data[i+2] > 230 { white++ }\n\t\t\t}\n\t\t}\n\t\tfor y in 555 .. 597 {')
	interaction = interaction.replace('\treturn black > 4500', '\treturn white > 50000 && black > 4500')
	interaction = interaction.replace('0 .. 100', '0 .. 140')
	os.write_file(b + 'interact228.v', interaction)!
	mut runner := os.read_file(b + 'run227.v')!.replace('framework227-canvas-z', 'framework228-outline').replace('libnative225.so', 'libnative228.so').replace('attempt227', 'attempt228').replace('interact227', 'interact228').replace('FRAMEWORK227', 'FRAMEWORK228')
	runner = runner.replace('592cef0d9d52b9a2795ba78724b6b1b514299511a897996a0d994e7fb56c5f3a', '37d54bcc10b6ada24bdfb71bd54442fc582edf5a536478bd31006d40a15c7137')
	os.write_file(b + 'run228.v', runner)!
}
