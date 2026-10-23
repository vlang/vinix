import os
import json2

fn main() {
	b := 'build/android-maps/'
	mut cfg := json2.decode[map[string]json2.Any](os.read_file(b + 'attempt228.json')!)!
	cfg['output'] = b + 'attempt231'
	mut apps := cfg['applications']!.as_array()
	mut app := apps[0].as_map()
	app['startup_seconds'] = 420
	apps[0] = app
	cfg['applications'] = apps
	os.write_file(b + 'attempt231.json', json2.encode(cfg, prettify: true))!
	mut interaction := os.read_file(b + 'interact228.v')!.replace('attempt228', 'attempt231')
	interaction = interaction.all_before('\ttime.sleep(10 * time.second)') + '}\n'
	os.write_file(b + 'interact231.v', interaction)!
	mut runner := os.read_file(b + 'run228.v')!.replace('libnative228.so', 'libnative231.so').replace('attempt228', 'attempt231').replace('interact228', 'interact231')
	runner = runner.replace("assert sha256.sum(os.read_bytes(b + 'libnative231.so')!).hex() == '37d54bcc10b6ada24bdfb71bd54442fc582edf5a536478bd31006d40a15c7137'", "println('NATIVE231 ' + sha256.sum(os.read_bytes(b + 'libnative231.so')!).hex())")
	os.write_file(b + 'run231.v', runner)!
}
