import os
import json2
import crypto.sha256
import compress.gzip
const base='build/android-maps/'
const root='tests/android/results/2026-10-22/maps-ws/'
fn hash(path string)!string{return sha256.sum(os.read_bytes(path)!).hex()}
fn main(){
 mut artifacts:=map[string]json2.Any{}
 for name in ['prepare212.v','build-native212.v','graph212.v','objects.v','retain212.v','make-retain212.v','reset212.v','clean-archived.v','native212-sources.json','native212-sources.tar.gz','attempt212-stage-failure.json','attempt212-stage-failures.json']{os.cp(base+name,root+name)!;artifacts[name]=hash(root+name)!}
 os.write_file_array(root+'native212-build.log.gz',gzip.compress(os.read_bytes(base+'native212-build.log')!)!)!
 artifacts['native212-build.log.gz']=hash(root+'native212-build.log.gz')!
 receipt:={'artifacts_sha256':json2.Any(artifacts),'framework_sha256':json2.Any(hash(base+'framework212/api-impl.jar')!),'native_sha256':json2.Any(hash(base+'libnative212.so')!),'launcher_sha256':json2.Any(hash(base+'launcher200')!),'parent_receipt':json2.Any('runtime211-diagnostics-build.json'),'scope':json2.Any('Read-only diagnostic rooted at the Skip listener; bounded reflection reads instance fields and map values without invoking app handlers. afql.b.j is a valid akls. No application code modified. Host staging failures preceded QEMU boot and are retained separately. No functional Maps pass.')}
 os.write_file(root+'runtime212-diagnostics-build.json',json2.encode(receipt,prettify:true)+'\n')!
 mut doc:=json2.decode[map[string]json2.Any](os.read_file(root+'results.json')!)!
 mut rows:=doc['applications']!.as_array().clone()
 for n in ['212']{
  run:='attempt'+n
  assert !rows.any(it.as_map()['run']!.str()==run)
  batch:=base+run
  mut row:=json2.decode[[]json2.Any](os.read_file(batch+'/results.json')!)![0].as_map().clone()
  id:=row['id']!.str();state:=batch+'/'+id+'/'
  serial:=gzip.decompress(os.read_bytes(state+'serial.log.gz')!)!
  assert sha256.sum(serial).hex()==row['serial_sha256']!.str()
  row['run']=run;row['runtime_sha256']=json2.decode[json2.Any](os.read_file(batch+'/runtime-sha256.json')!)!
  row['kernel_sha256']='f8d86366353da19545fa6814b7b54d53973e59fdbafe2575c96c13594284b352'
  row['kernel_build_receipt']='arp-kernels.json';row['boot_base_receipt']='boot-base161.json';row['build_receipt']='runtime212-diagnostics-build.json'
  row['startup_ui_passed']=false;row['search_passed']=false
  row['harness_binary_sha256']=hash(base+'suite159')!;row['harness_source_verified']=true
  row['manual_review']=os.read_file(base+run+'-review.txt')!.trim_space()
  for file,field in {'serial.log.gz':'serial_log','application.png':'screenshot','initial.png':'initial_screenshot','skip.png':'skip_screenshot','skip-later.png':'later_screenshot','pan.png':'pan_screenshot','zoom.png':'zoom_screenshot','search-typed.png':'typed_screenshot','search.png':'search_screenshot','search-later.png':'later_screenshot','sheet.png':'sheet_screenshot','network.pcap':'network_capture'}{
   if !os.is_file(state+file){continue}
   name:=run+'-'+id+'-'+file;os.cp(state+file,root+name)!;row[field]=name
   if file!='serial.log.gz'{row[field+'_sha256']=hash(root+name)!}
  }
  mut saved:=map[string]json2.Any{}
  for name,path in {run+'-configuration.json':batch+'.json',run+'-suite.v':base+'suite-low-disk.v',run+'-launcher.v':base+'trace200-launcher.v',run+'-interaction.v':base+'interact'+n+'.v',run+'-run.v':base+'run'+n+'.v',run+'-stage-aux.v':base+'stage-aux'+n+'.v',run+'-launcher-runtime-sha256.json':batch+'/launcher-runtime-sha256.json',run+'-harness.log':base+run+'-harness.log',run+'-interaction.log':base+'interact'+n+'.log'}{
   os.cp(path,root+name)!;saved[name]=hash(root+name)!
  }
  row['harness_artifacts_sha256']=json2.Any(saved);rows<<json2.Any(row)
 }
 doc['applications']=json2.Any(rows)
 os.write_file(root+'results.json',json2.encode(doc,prettify:true)+'\n')!
 println('Retained '+rows.len.str()+' runs')
}
