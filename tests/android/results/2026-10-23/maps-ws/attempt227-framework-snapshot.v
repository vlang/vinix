import os
import json2
import crypto.sha256
import compress.gzip

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn main() {
 b := 'build/android-maps/framework227-canvas-z/'
 manifest := json2.decode[map[string]json2.Any](os.read_file(b + 'framework-manifest.json')!)!
 declared := manifest['sources']!.as_map()
 mut sources := map[string]string{}
 for path, digest in declared {
  frozen := if path.starts_with('tests/native-android-tools/androidtools/') {
   b + 'sources/androidtools/' + os.base(path)
  } else { path }
  assert hash(frozen)! == digest.str(), path
  sources[path] = os.read_file(frozen)!
 }
 assert hash(b + 'api-impl.jar')! == '635add658c93d2a93e5e4fc597fe5981afdddc3d88192c698036a7a55c712a26'
 os.write_file_array(b + 'exact-sources.json.gz', gzip.compress(json2.encode(sources).bytes())!)!
 restored := json2.decode[map[string]string](gzip.decompress(os.read_bytes(b + 'exact-sources.json.gz')!)!.bytestr())!
 assert restored.len == declared.len
 for path, source in restored { assert sha256.sum(source.bytes()).hex() == declared[path]!.str(), path }
 println('FRAMEWORK227-SOURCE-SNAPSHOT PASS ${sources.len} exact source identities; frozen generator module; manifest/output match')
}
