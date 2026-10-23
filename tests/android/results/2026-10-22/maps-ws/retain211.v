import os
import json2
import crypto.sha256
import compress.gzip
const base='build/android-maps/'
const root='tests/android/results/2026-10-22/maps-ws/'
fn hash(path string)!string{return sha256.sum(os.read_bytes(path)!).hex()}
fn main(){
 mut artifacts:=map[string]json2.Any{}
 for name in ['prepare209.v','build-native209.v','prepare210.v','prepare211.v','short211.v','diagnose.v','retain211.v','native209-sources.json']{
  os.cp(base+name,root+name)!;artifacts[name]=hash(root+name)!
 }
 for path in ['native209-build.log','framework210-build.log','framework211-build.log']{
  name:=path+'.gz';os.write_file_array(root+name,gzip.compress(os.read_bytes(base+path)!)!)!;artifacts[name]=hash(root+name)!
 }
 archive:=root+'native209-sources.tar.gz'
 r:=os.exec(['tar','-czf',os.abs_path(archive),'-C',base+'native','atlframework'])
 assert r.exit_code==0,r.output
 artifacts[os.base(archive)]=hash(archive)!
 for n in ['210','211']{
  for cls in ['View','ViewGroup']{
   name:='framework'+n+'-'+cls+'.smali.gz'
   os.write_file_array(root+name,gzip.compress(os.read_bytes(base+'framework'+n+'/smali/android/view/'+cls+'.smali')!)!)!
   artifacts[name]=hash(root+name)!
  }
 }
 mut frameworks:=map[string]json2.Any{}
 for n in ['208','210','211']{frameworks[n]=hash(base+'framework'+n+'/api-impl.jar')!}
 receipt:={
  'artifacts_sha256':json2.Any(artifacts),'framework_sha256':json2.Any(frameworks),
  'native209_sha256':json2.Any(hash(base+'libnative209.so')!),
  'native204_sha256':json2.Any(hash(base+'libnative204.so')!),
  'launcher200_sha256':json2.Any(hash(base+'launcher200')!),
  'parent_receipt':json2.Any('runtime208-build.json'),
  'scope':json2.Any('Diagnostic builds only. Native209 logs completed frames and pointer dispatch without changing application code or invoking extra app callbacks. Framework210 logs touch dispatch and click listener classes; framework211 additionally reads the listener map before the real callOnClick. Framework208 otherwise unchanged. Signed Maps APK unchanged. These probes do not implement a runtime feature and are not functional Maps passes.')
 }
 os.write_file(root+'runtime211-diagnostics-build.json',json2.encode(receipt,prettify:true)+'\n')!
 mut doc:=json2.decode[map[string]json2.Any](os.read_file(root+'results.json')!)!
 mut rows:=doc['applications']!.as_array().clone()
 for n in ['209','210','211']{
  run:='attempt'+n
  assert !rows.any(it.as_map()['run']!.str()==run)
  batch:=base+run
  mut row:=json2.decode[[]json2.Any](os.read_file(batch+'/results.json')!)![0].as_map().clone()
  id:=row['id']!.str();state:=batch+'/'+id+'/'
  serial:=gzip.decompress(os.read_bytes(state+'serial.log.gz')!)!
  assert sha256.sum(serial).hex()==row['serial_sha256']!.str()
  row['run']=run;row['runtime_sha256']=json2.decode[json2.Any](os.read_file(batch+'/runtime-sha256.json')!)!
  row['kernel_sha256']='f8d86366353da19545fa6814b7b54d53973e59fdbafe2575c96c13594284b352'
  row['kernel_build_receipt']='arp-kernels.json';row['boot_base_receipt']='boot-base161.json';row['build_receipt']='runtime211-diagnostics-build.json'
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
