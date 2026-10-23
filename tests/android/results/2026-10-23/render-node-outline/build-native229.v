import os
import crypto.sha256
import json2

fn checked(args []string) {
	r := os.exec(args)
	print(r.output)
	assert r.exit_code == 0, r.output
}

fn main() {
	b := 'build/android-maps/'
	out := b + 'native229'
	assert !os.exists(out)
	os.cp_all(b + 'native228', out, false)!
	os.cp('build-support/android/nativews/path_clipping.v', out + '/atlframework/path_clipping.v')!
	mut sources := map[string]string{}
	mut changed := []string{}
	for path in os.walk_ext(out + '/atlframework', '.v') {
		name := os.base(path)
		sources[name] = sha256.sum(os.read_bytes(path)!).hex()
		if sources[name] != sha256.sum(os.read_bytes(b + 'native228/atlframework/' + name)!).hex() {
			changed << name
		}
	}
	assert changed == ['path_clipping.v'], changed.str()
	os.write_file(b + 'native229-sources.json', json2.encode(sources, prettify: true) + '\n')!
	checked(['build-support/compile-v-module', out + '/atlframework', out + '/android-native.c', '--arch', 'arm64'])
	runtime := 'build/android-framework/calculator/overlay/opt/vinix-android-aarch64'
	checked(['aarch64-linux-musl-gcc', '-D_GNU_SOURCE', '-O2', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-label', '-Wno-unused-parameter', '-fvisibility=hidden', '-shared', '-fPIC', '-I' + out, '-Wl,-z,max-page-size=65536', '-Wl,--allow-shlib-undefined', out + '/android-native.c', runtime + '/usr/lib/art/libandroidfw.so', '-Wl,--no-as-needed', runtime + '/usr/lib/libpng16.so.16', runtime + '/usr/lib/libsqlite3.so.0', '-ldl', '-lm', '-o', b + 'libnative229.so'])
	identity := 'NATIVE229 ' + sha256.sum(os.read_bytes(b + 'libnative229.so')!).hex()
	println(identity)
	os.write_file(b + 'native229-identity.txt', identity + '\n')!
}
