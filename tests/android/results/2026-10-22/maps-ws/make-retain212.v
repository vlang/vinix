import os
fn main(){
 b:='build/android-maps/'
 mut s:=os.read_file(b+'retain211.v')!
 s=s.replace("['209','210','211']", "['212']")
 start:=s.index(' mut artifacts:=') or {panic('start')}
 end:=s.index(' mut doc:=') or {panic('end')}
 s=s[..start]+" mut artifacts:=map[string]json2.Any{}\n for name in ['prepare212.v','build-native212.v','graph212.v','objects.v','retain212.v','make-retain212.v','reset212.v','clean-archived.v','native212-sources.json','native212-sources.tar.gz','attempt212-stage-failure.json','attempt212-stage-failures.json']{os.cp(base+name,root+name)!;artifacts[name]=hash(root+name)!}\n os.write_file_array(root+'native212-build.log.gz',gzip.compress(os.read_bytes(base+'native212-build.log')!)!)!\n artifacts['native212-build.log.gz']=hash(root+'native212-build.log.gz')!\n receipt:={'artifacts_sha256':json2.Any(artifacts),'framework_sha256':json2.Any(hash(base+'framework212/api-impl.jar')!),'native_sha256':json2.Any(hash(base+'libnative212.so')!),'launcher_sha256':json2.Any(hash(base+'launcher200')!),'parent_receipt':json2.Any('runtime211-diagnostics-build.json'),'scope':json2.Any('Read-only diagnostic rooted at the Skip listener; bounded reflection reads instance fields and map values without invoking app handlers. afql.b.j is a valid akls. No application code modified. Host staging failures preceded QEMU boot and are retained separately. No functional Maps pass.')}\n os.write_file(root+'runtime212-diagnostics-build.json',json2.encode(receipt,prettify:true)+'\\n')!\n"+s[end..]
 s=s.replace("row['build_receipt']='runtime211-diagnostics-build.json'", "row['build_receipt']='runtime212-diagnostics-build.json'")
 os.write_file(b+'attempt212-review.txt','FAIL functional review: manually inspected skip-later.png; real Maps remains on Make it your map onboarding. Other captured frames retained without individual visual review. No map, search, directions or location pass. Application code unchanged.\n')!
 os.write_file(b+'retain212.v',s)!
}
