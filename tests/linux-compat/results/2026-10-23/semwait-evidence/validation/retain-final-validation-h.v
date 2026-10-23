import crypto.sha256
import json2
import os

fn main() {
 assert os.args.len == 2
 area := '/Users/alex/.cache/vinix-linux-compat/semwait-20261022'
 target := os.args[1] + '/validation'
 assert !os.exists(target), 'Keep prior validation immutable'
 os.mkdir(target) or { panic(err) }
 mut files := map[string]string{}
 mut statuses := map[string]string{}
 for tag in ['publish-final-h', 'native-alias-completion-g3', 'publication-seal-fast-g2',
  'finish-index-h', 'integrated-checker-compile', 'verify-integrated-compile',
  'final-validation-h-compile', 'integrated-checker-assertion',
  'integrated-evidence-check', 'integrated-source-check'] {
  wanted := if tag == 'integrated-checker-assertion' { '1' } else { '0' }
  actual := (os.read_file(area + '/' + tag + '.status') or { panic(err) }).trim_space()
  assert actual == wanted, 'Unexpected final validation status: ' + tag
  statuses[tag] = actual
  for suffix in ['.command.json', '.log', '.status'] {
   name := tag + suffix
   bytes := os.read_bytes(area + '/' + name) or { panic(err) }
   os.write_file_array(target + '/' + name, bytes) or { panic(err) }
   files[name] = sha256.sum(bytes).hex()
  }
 }
 for name in ['retain-final-validation-h.v', 'verify-integrated-h.v', 'complete-native-aliases.v'] {
  bytes := os.read_bytes(area + '/' + name) or { panic(err) }
  os.write_file_array(target + '/' + name, bytes) or { panic(err) }
  files[name] = sha256.sum(bytes).hex()
 }
 checker := '/Users/alex/code/vinix/tests/linux-compat/semwait-evidence.v'
 source_hash := sha256.sum(os.read_bytes(checker) or { panic(err) }).hex()
 assert source_hash == sha256.sum(os.read_bytes(area + '/semwait-evidence-h.v') or { panic(err) }).hex()
 assert (os.read_file(target + '/integrated-checker-assertion.log') or { panic(err) }).contains('SEMWAIT CHECKER ASSERTION CONTROL')
 assert (os.read_file(target + '/integrated-evidence-check.log') or { panic(err) }).contains('LINUX SEMWAIT EVIDENCE: PASS')
 command := json2.decode[[]string](os.read_file(target + '/integrated-checker-compile.command.json') or { panic(err) }) or { panic(err) }
 assert '-prod' !in command && '-nocache' in command && command.last() == checker
 os.write_file(target + '/manifest.json', json2.encode({
  'result': 'PASS'
  'scope': 'Actual final publication and exact maintained-source compile/check; assertion control must exit 1. Extra validation records do not mutate content-addressed evidence objects.'
  'checker_source_sha256': source_hash
  'statuses': json2.encode(statuses)
  'files': json2.encode(files)
 }, prettify: true) + '\n') or { panic(err) }
 readme := os.args[1] + '/README.md'
 text := os.read_file(readme) or { panic(err) }
 os.write_file(readme, text + '\nFinal maintained-source compile, enabled-assertion control, offline evidence audit and exact source integration check all pass; see the [validation manifest](validation/manifest.json) and [offline audit output](validation/integrated-evidence-check.log).\n') or { panic(err) }
 println('Final actual validation records retained: PASS')
}
