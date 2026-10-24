import os
import json2
import crypto.sha256
import time

fn main() {
	b := 'build/android-maps/'
	out := b + 'identity245-inputs/'
	assert !os.exists(out + 'helpers-before-run.json'), 'Helper identity is immutable'
	mut sums := map[string]string{}
	for name in ['prepare245-resume.v', 'suite245-resume.v', 'suite245-resume-delta.json',
		'run245.v', 'interact245.v', 'manual245.v', 'preflight245.v', 'freeze245-helpers.v',
		'suite245-resume', 'run245', 'interact245', 'manual245', 'preflight245-fast',
		'attempt245.json'] {
		data := os.read_bytes(b + name)!
		sums[b + name] = sha256.sum(data).hex()
		if os.file_ext(name) in ['.v', '.json'] {
			os.mkdir_all(out + 'helpers')!
			os.write_file_array(out + 'helpers/' + name, data)!
		}
	}
	sums['build/android-run'] = sha256.sum(os.read_bytes('build/android-run')!).hex()
	os.write_file(out + 'helpers-before-run.json', json2.encode(sums, prettify: true) + '\n')!
	os.write_file(out + 'helpers-before-run-scope.txt', time.utc().str() + ' UTC\nFrozen before Maps245 launch. Framework244/native236 already staged in the boot image; this continuation only replaces module preparation with immutable preflight validation. Sources are retained and binary identities are hashed.\n')!
	println('MAPS245 HELPERS FROZEN PASS ' + sums.len.str() + ' identities')
}
