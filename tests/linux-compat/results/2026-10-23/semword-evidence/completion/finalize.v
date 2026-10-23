import crypto.sha256
import json2
import os

const area = '/Users/alex/.cache/vinix-linux-compat/semword-20261023'
const root = '/Users/alex/code/vinix'
const bundle = root + '/tests/linux-compat/results/2026-10-23/semword-evidence'

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn main() {
 destination := bundle + '/completion'
 assert !os.exists(destination), 'Fresh completion directory required'
 os.mkdir_all(destination)!
 mut files := map[string]string{}
 mut origins := map[string]string{}
 for pair in [[area + '/evidence-audit-final1', 'audit'], [area + '/publish-run1', 'publish']] {
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
 for pair in [[area + '/evidence-check', 'evidence-check'], [@FILE, 'finalize.v']] {
  os.cp(pair[0], destination + '/' + pair[1])!
  files[pair[1]] = digest(destination + '/' + pair[1])!
  origins[pair[0]] = pair[1]
 }
 for name in ['cleanup-media.v', 'removed-media-pins.json',
  'cleanup-media1.log', 'cleanup-media1.status', 'cleanup-media1.command.json',
  'cleanup-media2.log', 'cleanup-media2.status', 'cleanup-media2.command.json'] {
  os.cp(area + '/' + name, destination + '/' + name)!
  files[name] = digest(destination + '/' + name)!
  origins[area + '/' + name] = name
 }
 for name in ['semword-reference.v', 'semword-evidence.v', 'run.v'] {
  assert digest(root + '/tests/linux-compat/' + name)! == digest(bundle + '/tooling/' + name)!
 }
 assert digest(root + '/kernel/sysvsem/sysvsem.v')! == digest(bundle + '/source/sysvsem.v')!
 for name in ['semwordfixture', 'semwordreferenceinit', 'semabifixture'] {
  assert digest(root + '/tests/linux-compat/' + name + '/core.v')! ==
   digest(bundle + '/source/fixture/' + name + '/core.v')!
 }
 os.write_file(destination + '/receipt.json', json2.encode({
  'manifest_sha256': json2.Any(digest(bundle + '/manifest.json')!),
  'files': json2.decode[json2.Any](json2.encode(files))!,
  'origins': json2.decode[json2.Any](json2.encode(origins))!,
  'source_verified': true,
  'audit_exit_code': 0,
  'publish_exit_code': 0,
 }, prettify: true) + '\n')!
 println('Published evidence audit and source identity: PASS')
}
