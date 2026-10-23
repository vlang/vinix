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
  'build-framework208.v':'framework208-build.v','framework208/framework-manifest.json':'framework208-manifest.json',
  'prepare208.v':'prepare208.v','prepare-retain208.v':'prepare-retain208.v','layout208-apk-build.log':'layout208-apk-build.log','run-layout208.v':'run-layout208.v','run208.v':'run208.v','stage-aux208.v':'stage-aux208.v',
  'validate208.v':'validate208.v','validate208.log':'validate208.log','retain208.v':'retain208.v',
  'attempt208/launcher-runtime-sha256.json':'attempt208-launcher-runtime-sha256.json',
  'attempt208-harness.log':'attempt208-harness.log','interact208.log':'attempt208-interaction.log',
  'fixture-layout208-baseline-host.log':'fixture-layout208-baseline-harness.log','fixture-layout208-fixed-host.log':'fixture-layout208-fixed-harness.log'
 }{os.cp(base+src,root+name)!;artifacts[name]=hash(root+name)!}
 for kind in ['framework']{
  src:=base+kind+'208-build.log'
  name:=kind+'208-build.log.gz'
  os.write_file_array(root+name,gzip.compress(os.read_bytes(src)!)!)!
  artifacts[name]=hash(root+name)!
 }
 r:=os.exec(['tar','-czf',os.abs_path(root+'layout208-fixture-source.tar.gz'),'-C',base+'layout208-apk','smali','res'])
 assert r.exit_code==0,r.output
 artifacts['layout208-fixture-source.tar.gz']=hash(root+'layout208-fixture-source.tar.gz')!
 mut sources:=map[string]json2.Any{}
 for file in ['tests/native-android-tools/androidtools/framework_layout_canvas.v','tests/native-android-tools/androidtools/framework_classes.v','tests/native-android-ws/startupfixture/layout_canvas.v','tests/native-android-ws/startupfixture/startup.v']{
  s:=os.exec(['git','show','a68ef53f9:'+file]);assert s.exit_code==0
  sources[file]=sha256.sum(s.output.bytes()).hex()
 }
 receipt:={
  'artifacts_sha256':json2.Any(artifacts),'committed_sources_sha256':json2.Any({'a68ef53f9':json2.Any(sources)}),
  'framework208_sha256':json2.Any(hash(base+'framework208/api-impl.jar')!),
  'native204_sha256':json2.Any(hash(base+'libnative204.so')!),
  'native_build_receipt':json2.Any('runtime204-build.json'),
  'fixture_apk_sha256':json2.Any(hash(base+'layout208-apk/bootstrap.apk')!),
  'scope':json2.Any('Draw native WS text layouts through the supplied Canvas virtual drawText method. Picture and RenderNode record text and Paint snapshots; replay honors the destination bitmap, transform and clip. Same signed APK fails framework207 and passes framework208/native204: UTF16 supplementary character, multiline, wrap, empty text/lines, independent baselines and 12288 pixel comparisons. All 91 prior pass markers retained. Uses existing WS line metrics; shaping, styled runs, paragraph alignment and selection/highlight rendering remain outside this change. Native204 and launcher200 unchanged. Actual Maps reviewed separately.'),
  'references':json2.Any([json2.Any('https://developer.android.com/reference/android/text/Layout'),json2.Any('https://android.googlesource.com/platform/frameworks/base/+/master/core/java/android/text/Layout.java')])
 }
 os.write_file(root+'runtime208-build.json',json2.encode(receipt,prettify:true)+'\n')!
 mut doc:=json2.decode[map[string]json2.Any](os.read_file(root+'results.json')!)!
 mut rows:=doc['applications']!.as_array().clone()
 for run in ['fixture-layout208-baseline','fixture-layout208-fixed','attempt208']{
  assert !rows.any(it.as_map()['run']!.str()==run),'already retained '+run
  batch:=base+run
  mut row:=json2.decode[[]json2.Any](os.read_file(batch+'/results.json')!)![0].as_map().clone()
  id:=row['id']!.str();state:=batch+'/'+id+'/'
  serial:=gzip.decompress(os.read_bytes(state+'serial.log.gz')!)!
  assert sha256.sum(serial).hex()==row['serial_sha256']!.str(),run
  row['run']=run;row['runtime_sha256']=json2.decode[json2.Any](os.read_file(batch+'/runtime-sha256.json')!)!
  row['kernel_sha256']='f8d86366353da19545fa6814b7b54d53973e59fdbafe2575c96c13594284b352'
  row['kernel_build_receipt']='arp-kernels.json';row['boot_base_receipt']='boot-base161.json';row['build_receipt']='runtime208-build.json'
  row['startup_ui_passed']=false;row['search_passed']=false
  row['harness_binary_sha256']=hash(base+'suite159')!
  row['harness_source_verified']=true
  row['manual_review']=match run{
   'fixture-layout208-baseline'{'EXPECTED FAIL: same signed fixture stops at missing Layout.native_draw_custom_canvas on framework207/native204 after the RenderNode checks pass.'}
   'fixture-layout208-fixed'{'PASS synthetic regression: virtual Canvas dispatch, UTF16 supplementary character, multiline, wrapping, empty text/lines and independent baselines; 12288 pixels for Picture/RenderNode recording, Paint snapshots and translated/clipped bitmap targets. All 91 earlier pass markers retained. Native WS ready, GTK/X11 absent.'}
   else{os.read_file(base+'attempt208-review.txt')!.trim_space()}
  }
  for file,field in {'serial.log.gz':'serial_log','application.png':'screenshot','initial.png':'initial_screenshot','skip.png':'skip_screenshot','pan.png':'pan_screenshot','zoom.png':'zoom_screenshot','search-typed.png':'typed_screenshot','search.png':'search_screenshot','search-later.png':'later_screenshot','sheet.png':'sheet_screenshot','network.pcap':'network_capture'}{
   if !os.is_file(state+file){continue}
   name:=run+'-'+id+'-'+file;os.cp(state+file,root+name)!;row[field]=name
   if file!='serial.log.gz'{row[field+'_sha256']=hash(root+name)!}
  }
  mut saved:=map[string]json2.Any{}
  mut scripts:={run+'-configuration.json':batch+'.json',run+'-suite.v':base+'suite-low-disk.v',run+'-launcher.v':base+'trace200-launcher.v'}
  if run=='attempt208'{scripts[run+'-interaction.v']=base+'interact208.v'}
  for name,path in scripts{os.cp(path,root+name)!;saved[name]=hash(root+name)!}
  row['harness_artifacts_sha256']=json2.Any(saved);rows<<json2.Any(row)
 }
 doc['applications']=json2.Any(rows)
 os.write_file(root+'results.json',json2.encode(doc,prettify:true)+'\n')!
 println('Retained '+rows.len.str()+' runs')
}
