import os
import json2
import crypto.sha256
import compress.gzip

const base = 'build/android-maps/'
const root = 'tests/android/results/2026-10-22/maps-ws/'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn retain(src string, name string, mut artifacts map[string]json2.Any) ! {
 os.cp(base+src,root+name)!
 artifacts[name]=hash(root+name)!
}
fn main() {
 mut artifacts:=map[string]json2.Any{}
 mut compressed:=map[string]json2.Any{}
 for version in ['186','187','188','189','193','195','196','197','198','200'] {
  for suffix in ['-sources.json','-build.log'] {
   src:='native'+version+suffix
   if !os.is_file(base+src) {continue}
   if suffix.ends_with('.log') {
    data:=os.read_bytes(base+src)!
    os.write_file_array(root+src+'.gz',gzip.compress(data)!)!
    compressed[src+'.gz']=sha256.sum(data).hex()
   } else {retain(src,src,mut artifacts)!}
  }
  retain('build-native'+version+'.v','native'+version+'-build.v',mut artifacts)!
  snapshot:='native'+version+'-source-snapshot.tar.gz'
  if os.is_file(root+snapshot) {artifacts[snapshot]=hash(root+snapshot)!}
 }
 for version in ['193','198'] {
  retain('build-framework'+version+'.v','framework'+version+'-build.v',mut artifacts)!
  retain('framework'+version+'/framework-manifest.json','framework'+version+'-manifest.json',mut artifacts)!
  data:=os.read_bytes(base+'framework'+version+'-build.log')!
  name:='framework'+version+'-build.log.gz'
  os.write_file_array(root+name,gzip.compress(data)!)!
  compressed[name]=sha256.sum(data).hex()
 }
 for file in ['graph187.v','graph188.v','graph189.v','diagnostic-views186.v','diagnostic-views187.v','ws-attachment186.v','visibility197.v','visibility200.v','framework193-lifecycle-source.v','lifecycle193-fixture-source.v','save-native-snapshot.v','prepare195.v','prepare200.v','run-lifecycle194.v','run-lifecycle198.v','run200.v','validate190.v','validate190.log','validate196.v','validate196.log','validate198.v','validate198.log'] {
  retain(file,file,mut artifacts)!
 }
 mut changes:=map[string]json2.Any{}
 for commit,paths in {
  '720657029':['build-support/android/nativews/diagnostic_views.v','build-support/android/nativews/bindings.txt']
  'fe89456bc':['build-support/android/nativews/affine.v','build-support/android/nativews/graphics.v','build-support/android/nativews/canvases.v','build-support/android/nativews/paths.v','build-support/android/nativews/bitmaps.v','build-support/android/nativews/bindings.txt','tests/native-android-ws/startupfixture/affine.v','tests/native-android-ws/startupfixture/startup.v']
  'ee7cfd0f1':['tests/native-android-tools/androidtools/framework_lifecycle.v','tests/native-android-tools/androidtools/framework.v','build-support/android/atlframework/recreate.v','build-support/android/nativews/runtime.v','tests/native-android-ws/lifecycle-fixture.v']
 } {
  mut sources:=map[string]json2.Any{}
  for path in paths {
   r:=os.exec(['git','show',commit+':'+path])
   assert r.exit_code==0,r.output
   sources[path]=sha256.sum(r.output.bytes()).hex()
  }
  changes[commit]=json2.Any(sources)
 }
 mut native_hashes:=map[string]json2.Any{}
 for version in ['186','187','188','189','193','195','196','197','198','200'] {
  path:=base+'libnative'+version+'.so'
  if os.is_file(path) {native_hashes[version]=hash(path)!}
 }
 receipt:={
  'artifacts_sha256':json2.Any(artifacts)
  'compressed_artifacts_uncompressed_sha256':json2.Any(compressed)
  'committed_sources_sha256':json2.Any(changes)
  'native_libraries_sha256':json2.Any(native_hashes)
  'framework193_sha256':json2.Any(hash(base+'framework193/api-impl.jar')!)
  'framework198_sha256':json2.Any(hash(base+'framework198/api-impl.jar')!)
  'affine_fixture_apk_sha256':json2.Any(hash(base+'affine196-apk/bootstrap.apk')!)
  'lifecycle193_fixture_apk_sha256':json2.Any(hash(base+'lifecycle193-apk/lifecycle.apk')!)
  'lifecycle198_fixture_apk_sha256':json2.Any(hash(base+'lifecycle198-apk/lifecycle.apk')!)
  'lifecycle_reference':json2.Any('https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android10-release/core/java/android/app/Activity.java')
  'scope':json2.Any('Synthetic affine/lifecycle/diagnostic regressions pass; Google Maps remains functionally failed. Native diagnostic variants and exact source manifests are retained. Framework193 and lifecycle193 are intermediate sources retained separately from the final lifecycle commit. Native source archives are verified file by file against their manifests; early diagnostic runs retain build helpers, source manifests and diagnostic variants, without a claim that every generated source was archived.')
 }
 os.write_file(root+'runtime199-build.json',json2.encode(receipt,prettify:true)+'\n')!
 mut doc:=json2.decode[map[string]json2.Any](os.read_file(root+'results.json')!)!
 mut rows:=doc['applications']!.as_array().clone()
 for run,launcher in {
  'attempt186':'186','attempt187':'187','attempt188':'188','attempt189':'189',
  'fixture-diagnostics190':'190','attempt191':'191','attempt192':'192','attempt193':'193',
  'fixture-lifecycle194-baseline':'193','fixture-lifecycle194':'193','fixture-lifecycle195':'193','attempt195':'193',
  'fixture-affine196-baseline':'193','fixture-affine196-fixed':'193','attempt197':'197',
  'fixture-lifecycle198-baseline':'197','fixture-lifecycle198-fixed':'197','attempt199':'199','attempt200':'200'
 } {
  if rows.any(it.as_map()['run']!.str()==run) {continue}
  batch:=base+run
  if !os.is_file(batch+'/runtime-sha256.json') {continue}
  mut row:=json2.decode[[]json2.Any](os.read_file(batch+'/results.json')!)![0].as_map().clone()
  id:=row['id']!.str()
  state:=batch+'/'+id+'/'
  log:=gzip.decompress(os.read_bytes(state+'serial.log.gz')!)!.bytestr()
  assert sha256.sum(log.bytes()).hex()==row['serial_sha256']!.str(),run
  row['run']=run
  row['runtime_sha256']=json2.decode[json2.Any](os.read_file(batch+'/runtime-sha256.json')!)!
  row['kernel_sha256']='f8d86366353da19545fa6814b7b54d53973e59fdbafe2575c96c13594284b352'
  row['kernel_build_receipt']='arp-kernels.json'
  row['boot_base_receipt']='boot-base161.json'
  row['build_receipt']='runtime199-build.json'
  row['startup_ui_passed']=false
  row['search_passed']=false
  row['harness_binary_sha256']=hash(base+'suite159')!
  row['harness_source_verified']=true
  row['harness_provenance']='suite159 compiled from retained suite-low-disk source; QEMU network capture enabled.'
  row['manual_review']=match run {
   'attempt186' {'FAIL: map rendering and interaction retained; result sheet remains empty. View and model diagnostics locate loading controller avht beneath avhw. Diagnostic child scanning may retrace siblings; this is corrected in native189.'}
   'attempt187' {'FAIL: activity-root object walk reaches its traversal budget before the search presenter; no search UI pass. Collection element traversal is absent in this diagnostic version.'}
   'attempt188' {'FAIL: targeted model traversal finds avpv and avhu but place details remain blank.'}
   'attempt189' {'FAIL: exact inserted-view caller tracing and targeted search controller traversal; map interaction does not establish place details.'}
   'fixture-diagnostics190' {'PASS synthetic controls: 29 bootstrap markers and exactly three selected TextView insertion traces with eight frames each. No assertion or app exit. This does not establish Maps functionality.'}
   'attempt191' {'FAIL: search model contains one result and a successful query state, while the visible result sheet remains empty.'}
   'attempt192' {'FAIL: provider aron is reached through avhw.G.c and its activity is not finished/destroyed. Lifecycle enum state was not traversed; no claim that STARTED was observed. Result UI remains blank.'}
   'attempt193' {'FAIL: lifecycle callbacks advance application initialization, then startup exits on unsupported Canvas concat while drawing an SVG. No interaction captures.'}
   'fixture-lifecycle194-baseline','fixture-lifecycle194' {'INCOMPLETE synthetic test: no full pass marker. Child finish is blocked by a missing secondary window token. These are not expected-assertion baselines or passing lifecycle controls.'}
   'fixture-lifecycle195' {'INTERMEDIATE synthetic PASS for original expectations only: restart/recreation progresses after secondary window token fix. This fixture did not verify teardown pre-callback ordering or onPostResume placement; use lifecycle198 for final lifecycle claims.'}
   'attempt195' {'FAIL: map intentionally hidden during onboarding initialization; final window is white. Live process and caught optional gRPC class diagnostic do not establish functioning Maps.'}
   'fixture-affine196-baseline' {'EXPECTED FAIL: same signed affine fixture reaches unsupported Canvas concat; no affine pass marker.'}
   'fixture-affine196-fixed' {'PASS synthetic pixel regression: seven 32x32 all-pixel affine cases verify rotation, shear, reflection, transformed path/bitmap/clip and transform concatenation, alongside 29 prior controls.'}
   'attempt197' {'FAIL: APK calls MapViewContainer.setVisibility(INVISIBLE) from MainLayout.V during onboarding. The populated Make it your map view is also invisible and later removed. Final window is white.'}
   'fixture-lifecycle198-baseline' {'EXPECTED FAIL: final signed fixture asserts against previous lifecycle ordering and onPostResume timing.'}
   'fixture-lifecycle198-fixed' {'PASS synthetic lifecycle regression: all 21 phases, Application/Activity order, reverse Activity teardown, snapshot mutation, default methods, child finish/restart, recreation, main thread and onPostResume before postResumed. Same signed APK fails the baseline.'}
   'attempt199' {'FAIL: final corrected lifecycle and affine backend remain alive but display a white window. APK hides map and onboarding root remains invisible; search and place details have not passed.'}
   else {'FAIL: diagnostic run traces LinearLayout visibility and frame_main child removal. Raw startup verdict and framebuffer captures are retained; no functional Maps pass.'}
  }
  for file,field in {'serial.log.gz':'serial_log','application.png':'screenshot','initial.png':'initial_screenshot','pan.png':'pan_screenshot','zoom.png':'zoom_screenshot','search.png':'search_screenshot','search-typed.png':'search_typed_screenshot','search-later.png':'search_later_screenshot','sheet.png':'sheet_screenshot','network.pcap':'network_capture'} {
   if !os.is_file(state+file) {continue}
   name:=run+'-'+id+'-'+file
   os.cp(state+file,root+name)!
   row[field]=name
   if file!='serial.log.gz' {row[field+'_sha256']=hash(state+file)!}
  }
  mut saved:=map[string]json2.Any{}
  mut scripts:={run+'-configuration.json':batch+'.json',run+'-suite.v':base+'suite-low-disk.v',run+'-launcher.v':base+'trace'+launcher+'-launcher.v'}
  if id=='google-maps' && run!='attempt193' {scripts[run+'-interaction.v']=base+'interact'+run.all_after('attempt')+'.v'}
  for name,path in scripts {os.cp(path,root+name)!;saved[name]=hash(path)!}
  row['harness_artifacts_sha256']=json2.Any(saved)
  rows<<json2.Any(row)
 }
 doc['applications']=json2.Any(rows)
 os.write_file(root+'results.json',json2.encode(doc,prettify:true)+'\n')!
 println('Retained '+rows.len.str()+' runs; historical records copied unchanged')
}
