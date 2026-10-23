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
	out := b + 'native228'
	os.mkdir_all(out)!
	assert !os.exists(out + '/atlframework')
	os.cp_all(b + 'native225/atlframework', out + '/atlframework', false)!
	for name in ['graphics.v', 'canvases.v', 'ws_views.v', 'path_clipping.v'] {
		os.cp('build-support/android/nativews/' + name, out + '/atlframework/' + name)!
	}
	// Preserve the previously measured runtime, adding only the new explicit JNI
	// declaration. The full builder derives this same ABI from bindings.txt.
	generated := out + '/atlframework/ws_generated.v'
	os.write_file(generated, os.read_file(generated)! + '
@[export: "Java_android_atl_GskCanvas_native_1clipPath__JJI"]
fn ws_binding_clip_path228(e voidptr, this voidptr, p0 i64, p1 i64, p2 i32) u8 {
 unsafe {
  previous := ws_canvas_enter(e,this,p0)
  defer { ws_canvas_leave(previous) }
  if pending(e) { return 0 }
  return ws_clip_path(e,p1,p2)
 }
}
')!
	for header in ['androidfw_c_api.h', 'sqlite3.h', 'stb_image.h', 'stb_truetype.h'] {
		os.cp(b + 'native225/' + header, out + '/' + header)!
	}
	mut sources := map[string]string{}
	for path in os.walk_ext(out + '/atlframework', '.v') {
		sources[os.base(path)] = sha256.sum(os.read_bytes(path)!).hex()
	}
	os.write_file(b + 'native228-sources.json', json2.encode(sources, prettify: true) + '\n')!
	checked(['build-support/compile-v-module', out + '/atlframework', out + '/android-native.c', '--arch', 'arm64'])
	runtime := 'build/android-framework/calculator/overlay/opt/vinix-android-aarch64'
	checked(['aarch64-linux-musl-gcc', '-D_GNU_SOURCE', '-O2', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-label', '-Wno-unused-parameter', '-fvisibility=hidden', '-shared', '-fPIC', '-I' + out, '-Wl,-z,max-page-size=65536', '-Wl,--allow-shlib-undefined', out + '/android-native.c', runtime + '/usr/lib/art/libandroidfw.so', '-Wl,--no-as-needed', runtime + '/usr/lib/libpng16.so.16', runtime + '/usr/lib/libsqlite3.so.0', '-ldl', '-lm', '-o', b + 'libnative228.so'])
	println('NATIVE228 ' + sha256.sum(os.read_bytes(b + 'libnative228.so')!).hex())
}
