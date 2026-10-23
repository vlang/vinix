import os
import json2

fn main() {
	b := 'build/android-maps/'
	mut cfg := json2.decode[map[string]json2.Any](os.read_file(b + 'attempt225.json')!)!
	cfg['output'] = b + 'attempt227'
	cfg['boot_image'] = b + 'maps-live-vm/boot.img'
	cfg['efivars'] = b + 'maps-live-vm/efivars.fd'
	mut apps := cfg['applications']!.as_array()
	mut app := apps[0].as_map()
	app['startup_seconds'] = 300
	apps[0] = app
	cfg['applications'] = apps
	os.write_file(b + 'attempt227.json', json2.encode(cfg, prettify: true))!
}
