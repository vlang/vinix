import os
import json2
import crypto.sha256
fn main() {
 root:='tests/android/results/2026-10-22/maps-ws/'
 d:=json2.decode[map[string]json2.Any](os.read_file(root+'results.json')!)!
 for a in d['applications']!.as_array() {
  r:=a.as_map()
  if r['run']!.str() !in ['attempt209','attempt210','attempt211','attempt212','attempt213'] {continue}
  println('${r['run']}: ${r['verdict']} ${r['manual_review']}')
  for name,h in r['harness_artifacts_sha256']!.as_map() {assert sha256.sum(os.read_bytes(root+name)!).hex()==h.str(),name}
 }
 for name in ['runtime211-diagnostics-build.json','runtime212-diagnostics-build.json','runtime213-diagnostics-build.json'] {
  r:=json2.decode[map[string]json2.Any](os.read_file(root+name)!)!
  for artifact,h in r['artifacts_sha256']!.as_map() {assert sha256.sum(os.read_bytes(root+artifact)!).hex()==h.str(),artifact}
  println(name+': '+r['scope']!.str())
 }
 diff:=os.exec(['git','diff','--',root+'results.json'])
 assert diff.exit_code==0
 os.write_file('build/android-maps/review213-diff.txt',diff.output.split_into_lines().map(if it.len>1024 {it[..160]+' … [long APK manifest/signature metadata]'} else {it}).join('\n'))!
 println('AUDIT-ARTIFACTS-PASS all new receipt and harness hashes')
}
