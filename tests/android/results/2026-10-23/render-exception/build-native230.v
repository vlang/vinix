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
 out := b + 'native230'
 assert !os.exists(out)
 os.mkdir_all(out)!
 assert sha256.sum(os.read_bytes(b + 'libnative228.so')!).hex() == '37d54bcc10b6ada24bdfb71bd54442fc582edf5a536478bd31006d40a15c7137'
 os.cp_all(b + 'native228/atlframework', out + '/atlframework', false)!
 old := os.read_file(out + '/atlframework/runtime.v')!
 marker := '\t\t\tws_input(e)\n'
 assert old.count(marker) == 1
 fixed := old.replace(marker, '\t\t\t// Rendering may leave the original Java exception pending. Input\n\t\t\t// dispatch uses JNI calls that are forbidden until it is reported.\n\t\t\tif !pending(e) { ws_input(e) }\n')
 // This pair changes exactly the measured render-to-input guard, preserving
 // immutable228's clipping implementation and inherited diagnostic code.
 assert fixed == os.read_file('build-support/android/nativews/runtime.v')!
 os.write_file(out + '/atlframework/runtime.v', fixed)!
 mut sources := map[string]string{}
 baseline := json2.decode[map[string]string](os.read_file(b + 'native228-sources.json')!)!
 for path in os.walk_ext(out + '/atlframework', '.v') {
  name := os.base(path)
  digest := sha256.sum(os.read_bytes(path)!).hex()
  if name != 'runtime.v' { assert digest == baseline[name]!, name }
  sources[name] = digest
 }
 assert sources.len == baseline.len && sources['runtime.v']! != baseline['runtime.v']!
 os.write_file(b + 'native230-sources.json', json2.encode(sources, prettify: true) + '\n')!
 for header in ['androidfw_c_api.h', 'sqlite3.h', 'stb_image.h', 'stb_truetype.h'] {
  os.cp(b + 'native228/' + header, out + '/' + header)!
 }
 checked(['build-support/compile-v-module', out + '/atlframework', out + '/android-native.c', '--arch', 'arm64'])
 runtime := 'build/android-framework/calculator/overlay/opt/vinix-android-aarch64'
 checked(['aarch64-linux-musl-gcc', '-D_GNU_SOURCE', '-O2', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-label', '-Wno-unused-parameter', '-fvisibility=hidden', '-shared', '-fPIC', '-I' + out, '-Wl,-z,max-page-size=65536', '-Wl,--allow-shlib-undefined', out + '/android-native.c', runtime + '/usr/lib/art/libandroidfw.so', '-Wl,--no-as-needed', runtime + '/usr/lib/libpng16.so.16', runtime + '/usr/lib/libsqlite3.so.0', '-ldl', '-lm', '-o', b + 'libnative230.so'])
 println('NATIVE230 ' + sha256.sum(os.read_bytes(b + 'libnative230.so')!).hex())
}
