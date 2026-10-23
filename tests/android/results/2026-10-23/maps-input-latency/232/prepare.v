import os
import json2

fn main() {
	b := 'build/android-maps/'
	mut cfg := json2.decode[map[string]json2.Any](os.read_file(b + 'attempt231.json')!)!
	cfg['output'] = b + 'attempt232'
	mut apps := cfg['applications']!.as_array()
	mut app := apps[0].as_map()
	app['startup_seconds'] = 900
	apps[0] = app
	cfg['applications'] = apps
	os.write_file(b + 'attempt232.json', json2.encode(cfg, prettify: true))!
	for name in ['interact', 'manual', 'run'] {
		mut body := os.read_file(b + name + '231.v')!.replace('231', '232')
		if name == 'interact' { body = body.replace('0 .. 140', '0 .. 260') }
		os.write_file(b + name + '232.v', body)!
		result := os.exec(['/Users/alex/code/v/v_old', '-nocache', '-cc', 'cc', '-o', b + name + '232', b + name + '232.v'])
		print(result.output)
		assert result.exit_code == 0
	}
}
