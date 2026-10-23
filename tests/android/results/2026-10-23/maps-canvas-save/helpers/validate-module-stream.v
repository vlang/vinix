import os
import json2
import crypto.sha256
fn main() {
 b := 'build/android-maps/'
 mut hashes := map[string]string{}
 for path in ['build-support/android/modulestream/stream.v', 'build-support/android/modulestream/stream_test.v', 'tests/native-android-ws/suite.v'] {
  hashes[path] = sha256.sum(os.read_bytes(path)!).hex()
 }
 commands := [
  ['/Users/alex/code/v/v_old', '-nocache', '-cc', 'cc', '-path', '@vlib|build-support/android', 'test', 'build-support/android/modulestream'],
  ['/Users/alex/code/v/v_old', '-nocache', '-cc', 'cc', '-path', '@vlib|build-support/android', '-o', b + 'suite-stream-production', 'tests/native-android-ws/suite.v']
 ]
 mut logs := ''
 for args in commands {
  result := os.exec(args)
  logs += json2.encode(args) + '\n' + result.output + '\nexit=' + result.exit_code.str() + '\n'
  os.write_file(b + 'stream238/production-proof.log', logs)!
  assert result.exit_code == 0, result.output
 }
 for path, sum in hashes { assert sha256.sum(os.read_bytes(path)!).hex() == sum }
 os.write_file(b + 'stream238/production-sources-sha256.json', json2.encode(hashes, prettify: true) + '\n')!
 identity := json2.decode[map[string]string](os.read_file(b + 'identity239-inputs/pre-run-sha256.json')!)!
 assert sha256.sum(os.read_bytes(b + 'suite239-stream')!).hex() == identity[b + 'suite239-stream']
 println('MODULE STREAM PRODUCTION PASS private FAT regression, suite build, unchanged frozen239 binary')
}
