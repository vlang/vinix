import os
import json2

fn pins(path string) !map[string]string {
 mut result := map[string]string{}
 for line in os.read_lines(path)! {
  parts := line.split('  ')
  assert parts.len == 2 && parts[1] !in result
  result[parts[1]] = parts[0]
 }
 return result
}

fn main() {
 area := '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
 old := pins(area + '/qf-x86-audit-json-correction/qf-x86-inputs.sha256')!
 new := pins(area + '/qf-x86-inputs.sha256')!
 assert old.len == 142 && new.len == 142
 mut changed := []string{}
 for path, hash in old {
  assert path in new
  if new[path] != hash { changed << path }
 }
 changed.sort()
 expected := [area + '/qf-x86-audit', area + '/qf-x86-audit-tail.v', area + '/qf-x86-audit.v']
 assert changed == expected, 'unexpected guest/tool input change after launch: ' + changed.str()
 assert os.read_file(area + '/qf-x86-audit.v')!.contains(".as_array().filter('report' !in it.as_map())")
 assert os.read_file(area + '/qf-x86-audit-status.txt')!.trim_space() == '0'
 assert os.read_file(area + '/curl-closure-review.log.status')!.trim_space() == '0'
 note := 'PASS: launch and final142-input manifests have identical path sets; only the3 independent audit source/binary inputs changed. Kernel, guest wrapper, init source, modules, emulator, firmware, base archive, desktop, probe and genuine curl closure stayed byte-identical. Audit selection now accepts combined structured report JSON while retaining exact two desktop rows and raw/JSON equality. Original pre-correction source/binary/manifest/tooling and initial missing-curl failure are preserved. Final full qxo/qxd producer, harness and strict audit outcomes are actual0.\n'
 os.write_file(area + '/qf-x86-auditor-revision-audit.txt', note)!
 map_path := area + '/queue-desktop-publication-inputs.json'
 mut publication := json2.decode[map[string]string](os.read_file(map_path)!)!
 for suffix, source in {
  'queue-x86-curl-closure-review.v': area + '/curl-closure-review.v'
  'queue-x86-curl-closure-review.log': area + '/curl-closure-review.log'
  'queue-x86-curl-closure-review.status': area + '/curl-closure-review.log.status'
  'queue-x86-audit-correction.v': area + '/qf-x86-correct-audit.v'
  'queue-x86-audit-correction-records.json': area + '/qf-x86-audit-json-correction/records.json'
  'queue-x86-audit-correction-notes.txt': area + '/qf-x86-audit-json-correction/notes.txt'
  'queue-x86-audit-correction-launch-inputs.sha256': area + '/qf-x86-audit-json-correction/qf-x86-inputs.sha256'
  'queue-x86-audit-correction-launch-tooling.tar.gz': area + '/qf-x86-audit-json-correction/qf-x86-tooling.tar.gz'
  'queue-x86-audit-correction-launch-audit.v': area + '/qf-x86-audit-json-correction/qf-x86-audit.v'
  'queue-x86-auditor-revision-audit.txt': area + '/qf-x86-auditor-revision-audit.txt'
  'queue-x86-finalize.v': area + '/qf-x86-finalize.v'
 } {
  assert os.is_file(source), suffix
  publication[suffix] = source
 }
 for _, source in publication { assert os.is_file(source), source }
 os.write_file(map_path, json2.encode(publication, prettify: true) + '\n')!
 print(note)
 println('PASS: final x86 Q2 publication map ' + publication.len.str() + ' existing evidence paths.')
}
