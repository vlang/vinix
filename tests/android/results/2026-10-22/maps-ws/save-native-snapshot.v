import os
import json2
import crypto.sha256
fn main() {
 assert os.args.len==2
 version:=os.args[1]
 src:='build/android-maps/native/atlframework/'
 root:='tests/android/results/2026-10-22/maps-ws/'
 sources:=json2.decode[map[string]string](os.read_file('build/android-maps/native'+version+'-sources.json')!)!
 mut files:=[]string{}
 for name,hash in sources { assert sha256.sum(os.read_bytes(src+name)!).hex()==hash,name; files<<name }
 files.sort()
 r:=os.exec(['tar','-czf',os.abs_path(root+'native'+version+'-source-snapshot.tar.gz'),'-C',os.abs_path(src),...files])
 assert r.exit_code==0,r.output
 println('Saved verified native'+version+' source snapshot')
}
