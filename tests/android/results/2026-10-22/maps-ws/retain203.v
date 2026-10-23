import os
import json2
import crypto.sha256
import compress.gzip
const base='build/android-maps/'
const root='tests/android/results/2026-10-22/maps-ws/'
fn hash(path string)!string{return sha256.sum(os.read_bytes(path)!).hex()}
fn main(){
 mut artifacts:=map[string]json2.Any{}
 for src,name in {
  'build-framework201.v':'framework201-build.v','framework201/framework-manifest.json':'framework201-manifest.json',
  'prepare201.v':'prepare201.v','prepare202.v':'prepare202.v','prepare-order203.v':'prepare-order203.v',
  'run-order203.v':'run-order203.v','prepare203.v':'prepare203.v','run203.v':'run203.v','stage-aux203.v':'stage-aux203.v',
  'validate203.v':'validate203.v','validate203.log':'validate203.log',
  'retain199.v':'retain199.v','retain203.v':'retain203.v','audit185.v':'audit201.v','audit201.log':'audit201.log',
  'audit-builds201.v':'audit-builds201.v','audit-builds201.log':'audit-builds201.log',
  'attempt203/launcher-runtime-sha256.json':'attempt203-launcher-runtime-sha256.json',
  'attempt203-harness.log':'attempt203-harness.log','interact203.log':'attempt203-interaction.log'
 }{os.cp(base+src,root+name)!;artifacts[name]=hash(root+name)!}
 data:=os.read_bytes(base+'framework201-build.log')!
 os.write_file_array(root+'framework201-build.log.gz',gzip.compress(data)!)!
 artifacts['framework201-build.log.gz']=hash(root+'framework201-build.log.gz')!
 mut apks:=map[string]json2.Any{}
 for version in ['201','202','203']{
  dir:=base+'order'+version+'-apk'
  apks[version]=hash(dir+'/bootstrap.apk')!
  name:='order'+version+'-smali.tar.gz'
  r:=os.exec(['tar','-czf',os.abs_path(root+name),'-C',dir,'smali']);assert r.exit_code==0,r.output
  artifacts[name]=hash(root+name)!
 }
 mut sources:=map[string]json2.Any{}
 for file in ['tests/native-android-tools/androidtools/framework_child_order.v','tests/native-android-tools/androidtools/framework_classes.v','tests/native-android-ws/startupfixture/child_order.v','tests/native-android-ws/startupfixture/startup.v']{
  r:=os.exec(['git','show','e81aae0a1:'+file]);assert r.exit_code==0
  sources[file]=sha256.sum(r.output.bytes()).hex()
 }
 receipt:={
  'artifacts_sha256':json2.Any(artifacts),'committed_sources_sha256':json2.Any({'e81aae0a1':json2.Any(sources)}),
  'framework201_sha256':json2.Any(hash(base+'framework201/api-impl.jar')!),
  'native200_sha256':json2.Any(hash(base+'libnative200.so')!), 'native_source_receipt':json2.Any('runtime199-build.json'),
  'fixture_apks_sha256':json2.Any(apks),
  'scope':json2.Any('Same signed final child-order fixture fails against framework198 and passes framework201. Initial 201/202 fixture setups are incomplete controls. Maps203 visibly displays onboarding; Skip crashes on missing Font$Builder. Harness startup_failed and QMP disconnect are retained. Launcher200 source is retained for orchestration; staged launcher binary hash independently captured only for Maps203, not asserted from older runtime archives.'),
  'reference':json2.Any('https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android10-release/core/java/android/view/ViewGroup.java')
 }
 os.write_file(root+'runtime203-build.json',json2.encode(receipt,prettify:true)+'\n')!
 mut doc:=json2.decode[map[string]json2.Any](os.read_file(root+'results.json')!)!
 mut rows:=doc['applications']!.as_array().clone()
 for run in ['fixture-order201-baseline','fixture-order202-baseline','fixture-order203-baseline','fixture-order203-fixed','attempt203']{
  if rows.any(it.as_map()['run']!.str()==run){continue}
  batch:=base+run
  mut row:=json2.decode[[]json2.Any](os.read_file(batch+'/results.json')!)![0].as_map().clone()
  id:=row['id']!.str();state:=batch+'/'+id+'/'
  serial:=gzip.decompress(os.read_bytes(state+'serial.log.gz')!)!
  assert sha256.sum(serial).hex()==row['serial_sha256']!.str(),run
  row['run']=run;row['runtime_sha256']=json2.decode[json2.Any](os.read_file(batch+'/runtime-sha256.json')!)!
  row['kernel_sha256']='f8d86366353da19545fa6814b7b54d53973e59fdbafe2575c96c13594284b352'
  row['kernel_build_receipt']='arp-kernels.json';row['boot_base_receipt']='boot-base161.json';row['build_receipt']='runtime203-build.json'
  row['startup_ui_passed']=false;row['search_passed']=false
  row['harness_binary_sha256']=hash(base+'suite159')!
  row['harness_source_verified']=true
  row['manual_review']=match run{
   'fixture-order201-baseline'{'INCOMPLETE: fixture asserted layout-parameter identity after FrameLayout legitimately converted generic parameters. Fails before reordering; not a runtime baseline.'}
   'fixture-order202-baseline'{'INCOMPLETE: corrected parameter fixture stops at unavailable Bitmap.getPixel before reordering. Final fixture uses supported getPixels; not a runtime baseline.'}
   'fixture-order203-baseline'{'EXPECTED FAIL: final signed APK asserts child stacking order against framework198.'}
   'fixture-order203-fixed'{'PASS synthetic regression: same signed APK verifies stable child order, four 1024-pixel and touch cases, preserved parent/params/token/attachment, hierarchy silence, layout/invalidate and foreign/orphan no-ops; 30 earlier controls pass.'}
   else{'FAIL: onboarding Make it your map is visibly drawn with working Skip hit target. Skip exits on missing android.graphics.fonts.Font$Builder. Capture shows Android APK has exited. No map/search/directions pass; interaction harness disconnect is retained.'}
  }
  for file,field in {'serial.log.gz':'serial_log','application.png':'screenshot','initial.png':'initial_screenshot','skip.png':'skip_screenshot','network.pcap':'network_capture'}{
   if !os.is_file(state+file){continue}
   name:=run+'-'+id+'-'+file;os.cp(state+file,root+name)!;row[field]=name
   if file!='serial.log.gz'{row[field+'_sha256']=hash(root+name)!}
  }
  mut saved:=map[string]json2.Any{}
  mut scripts:={run+'-configuration.json':batch+'.json',run+'-suite.v':base+'suite-low-disk.v',run+'-launcher.v':base+'trace200-launcher.v'}
  if run=='attempt203'{scripts[run+'-interaction.v']=base+'interact203.v'}
  for name,path in scripts{os.cp(path,root+name)!;saved[name]=hash(root+name)!}
  row['harness_artifacts_sha256']=json2.Any(saved);rows<<json2.Any(row)
 }
 doc['applications']=json2.Any(rows)
 os.write_file(root+'results.json',json2.encode(doc,prettify:true)+'\n')!
 println('Retained '+rows.len.str()+' runs')
}
