import crypto.sha256
import json2
import os

const area = '/Users/alex/.cache/vinix-linux-compat/priochange-20261023'
const root = '/Users/alex/code/vinix'
const bundle = root + '/tests/linux-compat/results/2026-10-23/priochange-evidence'

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn main() {
 destination := bundle + '/completion'
 assert !os.exists(destination), 'Fresh completion directory required'
 os.mkdir_all(destination)!
 mut files := map[string]string{}
 mut origins := map[string]string{}
 for pair in [[area + '/states/evidence-audit-first', 'audit'], [area + '/states/publish-second', 'publish'],
  [area + '/states/evidence-controls-third', 'checker-controls']] {
  assert os.read_file(pair[0] + '.status')!.trim_space() == '0'
  for suffix in ['.log', '.status', '.command.json'] {
   source := pair[0] + suffix
   target := destination + '/' + pair[1] + suffix
   os.cp(source, target)!
   pin := digest(source)!
   assert digest(target)! == pin
   files[os.file_name(target)] = pin
   origins[source] = os.file_name(target)
  }
 }
 for pair in [[area + '/evidence-third', 'evidence-check'], [@FILE, 'finalize.v']] {
  os.cp(pair[0], destination + '/' + pair[1])!
  files[pair[1]] = digest(destination + '/' + pair[1])!
  origins[pair[0]] = pair[1]
 }
 for name in ['priochange-reference.v', 'priochange-evidence.v', 'run.v'] {
  assert digest(root + '/tests/linux-compat/' + name)! == digest(bundle + '/tooling/' + name)!
 }

 for name in ["proc/nice.v", "syscall/table/linux_common.v"] {
  assert digest(root + "/kernel/" + name)! == digest(bundle + "/source/kernel/" + name)!
 }
 for name in ["priochangefixture", "priochangereferenceinit", "prioqueryfixture", "threadnicefixture", "niceabifixture", "niceadmitfixture", "attrnicefixture", "groupabifixture", "grouptidfixture"] {
  assert digest(root + "/tests/linux-compat/" + name + "/core.v")! == digest(bundle + "/source/fixture/" + name + "/core.v")!
 }
 os.write_file(destination + '/receipt.json', json2.encode({
  'manifest_sha256': json2.Any(digest(bundle + '/manifest.json')!),
  'checker_source_sha256': json2.Any(digest(bundle + '/tooling/priochange-evidence.v')!),
  'files': json2.decode[json2.Any](json2.encode(files))!,
  'origins': json2.decode[json2.Any](json2.encode(origins))!,
  'source_verified': true,
  'audit_exit_code': 0,
  'publish_exit_code': 0,
 }, prettify: true) + '\n')!
 println('Published evidence audit and source identity: PASS')
}
