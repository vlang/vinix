import os
import json2
import crypto.sha256
import compress.gzip

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn main() {
	root := os.dir(@FILE) + '/'
	mut checked := 0
	for filename in os.ls(root)! {
		if !filename.ends_with('-identities.json') { continue }
		receipt := json2.decode[map[string]json2.Any](os.read_file(root + filename)!)!
		for name, digest in receipt['artifacts_sha256']!.as_map() {
			assert hash(root + name)! == digest.str(), name
			checked++
		}
		if 'input_identity_receipt_sha256' in receipt {
			assert hash(root + receipt['input_identity_receipt']!.str())! == receipt['input_identity_receipt_sha256']!.str()
		}
		if 'framework_input_identity_receipt_sha256' in receipt {
			assert hash(root + receipt['framework_input_identity_receipt']!.str())! == receipt['framework_input_identity_receipt_sha256']!.str()
		}
	}
	for attempt in ['218', '219', '220', '221', '222', '223', '225', '227'] {
		row := json2.decode[[]json2.Any](os.read_file(root + 'attempt' + attempt + '-results.json')!)![0].as_map()
		serial := gzip.decompress(os.read_bytes(root + row['serial_log']!.str())!)!
		assert sha256.sum(serial).hex() == row['serial_sha256']!.str()
		assert row['outcome']!.str() == 'startup_failed'
		assert !row['startup_ui_passed']!.bool() && !row['search_passed']!.bool()
	}
	for attempt in ['220', '221', '225'] {
		manifest := json2.decode[map[string]string](os.read_file(root + 'native' + attempt + '-sources.json')!)!
		sources := json2.decode[map[string]string](gzip.decompress(os.read_bytes(root + 'attempt' + attempt + '-native-sources.json.gz')!)!.bytestr())!
		assert sources.len == 80 && sources.len == manifest.len
		for name, source in sources { assert sha256.sum(source.bytes()).hex() == manifest[name]! }
	}
	manifest := json2.decode[map[string]json2.Any](os.read_file(root + 'attempt221-framework-manifest.json')!)!
	sources := json2.decode[map[string]string](gzip.decompress(os.read_bytes(root + 'attempt221-framework-sources.json.gz')!)!.bytestr())!
	expected := manifest['sources']!.as_map()
	assert sources.len + 1 == expected.len
	assert 'tests/native-android-tools/androidtools/framework_application.v' !in sources
	for path, source in sources { assert sha256.sum(source.bytes()).hex() == expected[path]!.str() }
	view := gzip.decompress(os.read_bytes(root + 'attempt221-View.dex-smali.gz')!)!.bytestr()
	assert view.contains('.method public getContentCaptureSession()Landroid/view/contentcapture/ContentCaptureSession;')
	loaded := gzip.decompress(os.read_bytes(root + 'attempt221-ATLLoadedApp.dex-smali.gz')!)!.bytestr()
	assert loaded.contains('->init_lock:Ljava/lang/Object;') && loaded.contains('monitor-enter')
	for attempt in ['222', '223'] {
		manifest_full := json2.decode[map[string]json2.Any](os.read_file(root + 'attempt' + attempt + '-framework-manifest.json')!)!
		sources_full := json2.decode[map[string]string](gzip.decompress(os.read_bytes(root + 'attempt' + attempt + '-framework-sources.json.gz')!)!.bytestr())!
		expected_full := manifest_full['sources']!.as_map()
		assert sources_full.len == 102 && sources_full.len == expected_full.len
		for path, source in sources_full { assert sha256.sum(source.bytes()).hex() == expected_full[path]!.str() }
		autofill := gzip.decompress(os.read_bytes(root + 'attempt' + attempt + '-AutofillValue.dex-smali.gz')!)!.bytestr()
		assert autofill.contains('.method public static forToggle(Z)Landroid/view/autofill/AutofillValue;')
	}
	manager := gzip.decompress(os.read_bytes(root + 'attempt223-AutofillManager.dex-smali.gz')!)!.bytestr()
	assert manager.contains('.method public notifyViewVisibilityChanged(Landroid/view/View;IZ)V')
	alpha := json2.decode[map[string]string](gzip.decompress(os.read_bytes(root + 'attempt225-native-sources.json.gz')!)!.bytestr())!
	assert alpha['bitmaps.v']!.contains('row_bytes: stride') && alpha['bitmaps.v']!.contains('format == 24')
	assert alpha['glutils.v']!.contains('bitmap.alpha_only') && alpha['glutils.v']!.contains('i32(0x1906)')
	canvas_manifest := json2.decode[map[string]json2.Any](os.read_file(root + 'attempt227-framework-manifest.json')!)!
	canvas_sources := json2.decode[map[string]string](gzip.decompress(os.read_bytes(root + 'attempt227-framework-sources.json.gz')!)!.bytestr())!
	assert canvas_sources.len == 103
	for path, source in canvas_sources { assert sha256.sum(source.bytes()).hex() == canvas_manifest['sources']!.as_map()[path]!.str(), path }
	canvas := gzip.decompress(os.read_bytes(root + 'attempt227-Canvas.smali.gz')!)!.bytestr()
	assert canvas.contains('.method public enableZ()V') && canvas.contains('.method public disableZ()V')
	serial227 := gzip.decompress(os.read_bytes(root + 'attempt227-google-maps-serial.log.gz')!)!.bytestr()
	assert serial227.contains('Native WS RenderNode supports rectangular outline clipping only')
	assert serial227.contains('in call to NewLocalRef') && serial227.contains('APK-SUITE-EXIT id=google-maps code=134')
	row228 := json2.decode[[]json2.Any](os.read_file(root + 'attempt228-results.json')!)![0].as_map()
	serial228_bytes := gzip.decompress(os.read_bytes(root + row228['serial_log']!.str())!)!
	assert sha256.sum(serial228_bytes).hex() == row228['serial_sha256']!.str()
	serial228 := serial228_bytes.bytestr()
	assert row228['outcome']!.str() == 'startup_failed' && row228['backend_ready']!.bool()
	assert !row228['process_exited']!.bool() && row228['startup_ui_passed']!.bool()
	assert row228['search_suggestions_passed']!.bool() && !row228['search_passed']!.bool()
	assert row228['retained_screenshots']!.as_array().len == 10
	assert !serial228.contains('ANDROID-WS-FAIL') && !serial228.contains('JNI DETECTED ERROR IN APPLICATION')
	assert !serial228.contains('APK-SUITE-EXIT id=google-maps')
	assert row228['failure_markers']!.as_array().len == 4
	for marker in row228['failure_markers']!.as_array() {
		assert marker.str().contains('ClassNotFoundException: io.grpc.internal.JndiResourceResolverFactory') || marker.str().contains('ClassNotFoundException: io.grpc.override.ContextStorageOverride')
	}
	native228_manifest := json2.decode[map[string]string](os.read_file(root + 'native228-sources.json')!)!
	native228_sources := json2.decode[map[string]string](gzip.decompress(os.read_bytes(root + 'attempt228-native-sources.json.gz')!)!.bytestr())!
	assert native228_sources.len == 81 && native228_sources.len == native228_manifest.len
	for path, source in native228_sources { assert sha256.sum(source.bytes()).hex() == native228_manifest[path]!, path }
	outline_manifest := json2.decode[map[string]json2.Any](os.read_file(root + 'attempt228-framework-manifest.json')!)!['sources']!.as_map()
	outline_sources := json2.decode[map[string]string](gzip.decompress(os.read_bytes(root + 'attempt228-framework-sources.json.gz')!)!.bytestr())!
	assert outline_sources.len == 104 && outline_sources.len == outline_manifest.len
	for path, source in outline_sources { assert sha256.sum(source.bytes()).hex() == outline_manifest[path]!.str(), path }
	println('MAPS218-228-RETAINED PASS ${checked} artifact hashes;9 serial/result identities;4 native archives/321 sources;framework221 ${sources.len} exact sources + explicit1 missing-source limitation;framework222+223+227+228 411 exact sources;actualDEX+native evidence; no attempt224 boot claimed;227 failed outline/JNI abort134;228 visible map and search suggestions with raw startup_failed classification retained')
}
