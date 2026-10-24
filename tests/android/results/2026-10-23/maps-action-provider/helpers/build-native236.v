import os
import crypto.sha256
import json2
import compress.gzip

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn checked(args []string) {
 r := os.exec(args)
 print(r.output)
 assert r.exit_code == 0, r.output
}
fn main() {
 b := 'build/android-maps/'
 out := b + 'native236'
 assert !os.exists(out) && !os.exists(b + 'libnative236.so')
 assert hash(b + 'libnative235.so')! == '0d6b3cd8dfa5c7f109b1fb5305eac54d1b90f40ffc764a94359d19061345aad9'
 baseline := json2.decode[map[string]string](os.read_file(b + 'native235-sources.json')!)!
 base_source := json2.decode[map[string]string](gzip.decompress(os.read_bytes(b + 'native235-exact-sources.json.gz')!)!.bytestr())!
 assert baseline.len == 83 && base_source.len == baseline.len
 for name, source in base_source {
  assert sha256.sum(source.bytes()).hex() == baseline[name]!, name
  assert hash(b + 'native235/atlframework/' + name)! == baseline[name]!, name
 }
 // The only native delta reviewed for PopupMenu: Context-based resource
 // resolution, submenu propagation, and guards on Activity action views.
 path := 'build-support/android/atlframework/menus.v'
 overlay := os.read_file(path)!
 digest := sha256.sum(overlay.bytes()).hex()
 os.mkdir_all(out + '/atlframework')!
 for name, source in base_source { os.write_file(out + '/atlframework/' + name, source)! }
 os.write_file(out + '/atlframework/menus.v', overlay)!
 mut hashes := map[string]string{}
 mut exact := map[string]string{}
 mut changed := []string{}
 mut paths := os.walk_ext(out + '/atlframework', '.v')
 paths.sort()
 for source_path in paths {
  name := os.base(source_path)
  assert name !in hashes, name
  hashes[name] = hash(source_path)!
  exact[name] = os.read_file(source_path)!
  if hashes[name] != baseline[name] { changed << name }
 }
 assert changed == ['menus.v'] && hashes.len == 83, changed.str()
 assert hashes['menus.v']! == digest && hash(path)! == digest
 os.write_file(b + 'native236-sources.json', json2.encode(hashes, prettify: true) + '\n')!
 os.write_file_array(b + 'native236-exact-sources.json.gz', gzip.compress(json2.encode(exact).bytes())!)!
 os.write_file(b + 'native236-source-delta.json', json2.encode({'menus.v': baseline['menus.v']! + ' -> ' + digest}, prettify: true) + '\n')!
 mut identities := {
  'baseline_native235_sha256': hash(b + 'libnative235.so')!
  'baseline_sources_sha256': hash(b + 'native235-sources.json')!
  'baseline_exact_sources_sha256': hash(b + 'native235-exact-sources.json.gz')!
  path: digest
 }
 for header in ['androidfw_c_api.h', 'sqlite3.h', 'stb_image.h', 'stb_truetype.h'] {
  os.cp(b + 'native235/' + header, out + '/' + header)!
  assert hash(out + '/' + header)! == hash(b + 'native235/' + header)!, header
  identities['header/' + header] = hash(out + '/' + header)!
 }
 os.write_file(b + 'native236-production-source-sha256.json', json2.encode(identities, prettify: true) + '\n')!
 println('NATIVE236-SOURCES PASS83 exact sources; only reviewed menus.v changed')
 os.setenv('VINIX_V_COMPILER', '/Users/alex/code/v/v_old', true)
 checked(['/Users/alex/code/v/v_old', '-nocache', '-cc', 'cc', 'run', 'tests/linuxkpi/generate_module.v', out + '/atlframework', out + '/android-native.c', '--arch', 'arm64'])
 runtime_root := 'build/android-framework/calculator/overlay/opt/vinix-android-aarch64'
 checked(['aarch64-linux-musl-gcc', '-D_GNU_SOURCE', '-O2', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-label', '-Wno-unused-parameter', '-fvisibility=hidden', '-shared', '-fPIC', '-I' + out, '-Wl,-z,max-page-size=65536', '-Wl,--allow-shlib-undefined', out + '/android-native.c', runtime_root + '/usr/lib/art/libandroidfw.so', '-Wl,--no-as-needed', runtime_root + '/usr/lib/libpng16.so.16', runtime_root + '/usr/lib/libsqlite3.so.0', '-ldl', '-lm', '-o', b + 'libnative236.so'])
 identity := 'NATIVE236 ' + hash(b + 'libnative236.so')!
 os.write_file(b + 'native236-identity.txt', identity + '\n')!
 println(identity)
}
