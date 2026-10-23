import os
import json2
import crypto.sha256
import compress.gzip
fn hash(path string)!string{return sha256.sum(os.read_bytes(path)!).hex()}
fn main(){
 root:='tests/android/results/2026-10-22/maps-ws/'
 doc:=json2.decode[map[string]json2.Any](os.read_file(root+'runtime199-build.json')!)!
 for file,expected in doc['artifacts_sha256']!.as_map(){assert hash(root+file)! ==expected.str(),file}
 for file,expected in doc['compressed_artifacts_uncompressed_sha256']!.as_map(){assert sha256.sum(gzip.decompress(os.read_bytes(root+file)!)!).hex()==expected.str(),file}
 for commit,files in doc['committed_sources_sha256']!.as_map(){
  for file,expected in files.as_map(){r:=os.exec(['git','show',commit+':'+file]);assert r.exit_code==0;assert sha256.sum(r.output.bytes()).hex()==expected.str(),file}
 }
 for version in ['189','195','196','197','198','200']{
  temp:=os.join_path(os.temp_dir(),'vinix-map-audit-'+version+'-'+os.getpid().str())
  os.mkdir_all(temp)!
  r:=os.exec(['tar','-xzf',os.abs_path(root+'native'+version+'-source-snapshot.tar.gz'),'-C',temp]);assert r.exit_code==0,r.output
  sources:=json2.decode[map[string]string](os.read_file(root+'native'+version+'-sources.json')!)!
  for file,expected in sources{assert hash(temp+'/'+file)! ==expected,version+' '+file}
  os.rmdir_all(temp)!
  println('SOURCE-AUDIT PASS native'+version+' '+sources.len.str()+' files')
 }
 println('BUILD-AUDIT PASS runtime199 artifact hashes, compressed logs and committed sources')
}
