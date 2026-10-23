import crypto.sha256
import json2
import os

const area = '/Users/alex/.cache/vinix-linux-compat/semwait-20261022'

fn add(path string, expected string, mut origins map[string]json2.Any, mut files map[string]json2.Any,
 mut aliases map[string]json2.Any, mut inputs map[string]json2.Any) {
 bytes := os.read_bytes(path) or { panic(err) }
 assert sha256.sum(bytes).hex() == expected, 'Actual native copy changed: ' + path
 relative := 'objects/' + expected
 if existing := origins[relative] {
  assert (os.read_bytes(existing.str()) or { panic(err) }) == bytes, 'Full-byte alias mismatch'
  aliases[path] = relative
 } else {
  origins[relative] = path
  files[relative] = expected
 }
 if previous := inputs[path] { assert previous.str() == expected, 'Conflicting historical pin' }
 inputs[path] = expected
}

fn main() {
 assert os.args.len == 3
 assert !os.exists(os.args[2]), 'Fresh plan required'
 mut document := json2.decode[map[string]json2.Any](os.read_file(os.args[1]) or { panic(err) }) or { panic(err) }
 mut origins := (document['origins'] or { panic('Missing origins') }).as_map()
 mut files := (document['files'] or { panic('Missing files') }).as_map()
 mut aliases := (document['source_aliases'] or { panic('Missing aliases') }).as_map()
 mut inputs := (document['source_inputs'] or { panic('Missing inputs') }).as_map()
 selected := (document['selected'] or { panic('Missing selected') }).as_map()
 sources := json2.decode[map[string]string](os.read_file(area + '/source-manifest.json') or { panic(err) }) or { panic(err) }
 mut added := 0
 for role, item in selected {
  if role.ends_with('-reference') { continue }
  record := item.as_map()
  state := (record['state'] or { panic('Missing state') }).str()
  receipt := json2.decode[map[string]json2.Any](os.read_file(state + '/receipt.json') or { panic(err) }) or { panic(err) }
  for name, field in {'probe': 'probe_sha256', 'init': 'init_sha256', 'kernel/bin/vinix': 'kernel_sha256', 'serial.log': 'serial_sha256'} {
   expected := (receipt[field] or { panic('Missing native digest') }).str()
   add(state + '/' + name, expected, mut origins, mut files, mut aliases, mut inputs)
   added++
  }
  mut copied := 0
  for path, expected in sources {
   if !path.starts_with(area + '/frozen-draft2/') { continue }
   destination := state + '/sources/' + path.all_after(area + '/frozen-draft2/')
   add(destination, expected, mut origins, mut files, mut aliases, mut inputs)
   copied++
   added++
  }
  assert copied == 7
 }
 for tag in ['publish-final-g2', 'native-alias-compile'] {
  wanted := if tag == 'publish-final-g2' { '1' } else { '0' }
  assert (os.read_file(area + '/' + tag + '.status') or { panic(err) }).trim_space() == wanted
  for suffix in ['.command.json', '.log', '.status'] {
   path := area + '/' + tag + suffix
   add(path, sha256.sum(os.read_bytes(path) or { panic(err) }).hex(), mut origins, mut files, mut aliases, mut inputs)
  }
 }
 for path in [@FILE, area + '/complete-native-aliases', os.args[1]] {
  add(path, sha256.sum(os.read_bytes(path) or { panic(err) }).hex(), mut origins, mut files, mut aliases, mut inputs)
 }
 document['origins'] = origins
 document['files'] = files
 document['source_aliases'] = aliases
 document['source_inputs'] = inputs
 os.write_file(os.args[2], json2.encode(document, prettify: true) + '\n') or { panic(err) }
 failed := '/Users/alex/code/vinix/tests/linux-compat/results/2026-10-23/semwait-evidence'
 archive := area + '/publication-failed-g2'
 assert os.exists(failed + '/evidence.json') && !os.exists(archive), 'Preserve actual failed publication'
 os.rename(failed, archive) or { panic(err) }
 println('Native copied-kernel/probe/frozen-source aliases sealed: PASS (' + added.str() + ' exact pin comparisons); failed publication retained separately')
}
