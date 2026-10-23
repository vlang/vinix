import os
import json2
import crypto.sha256
fn hash(path string)!string{return sha256.sum(os.read_bytes(path)!).hex()}
fn main(){
 root:='tests/android/results/2026-10-22/maps-ws/'
 doc:=json2.decode[map[string]json2.Any](os.read_file(root+'runtime208-build.json')!)!
 for file,expected in doc['artifacts_sha256']!.as_map(){assert hash(root+file)! ==expected.str(),file}
 for commit,files in doc['committed_sources_sha256']!.as_map(){for file,expected in files.as_map(){r:=os.exec(['git','show',commit+':'+file]);assert r.exit_code==0;assert sha256.sum(r.output.bytes()).hex()==expected.str(),file}}
 rows:=json2.decode[map[string]json2.Any](os.read_file(root+'results.json')!)!['applications']!.as_array()
 for item in rows{
  row:=item.as_map()
  if row['build_receipt'] or {json2.Any('')} != json2.Any('runtime208-build.json'){continue}
  for file,expected in row['harness_artifacts_sha256']!.as_map(){assert hash(root+file)! ==expected.str(),file}
 }
 println('BUILD-AUDIT PASS runtime208 artifacts, committed sources and run harness hashes')
}
