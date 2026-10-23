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
	}
	for attempt in ['218', '219', '220', '221'] {
		row := json2.decode[[]json2.Any](os.read_file(root + 'attempt' + attempt + '-results.json')!)![0].as_map()
		serial := gzip.decompress(os.read_bytes(root + row['serial_log']!.str())!)!
		assert sha256.sum(serial).hex() == row['serial_sha256']!.str()
		assert row['outcome']!.str() == 'startup_failed'
		assert !row['startup_ui_passed']!.bool() && !row['search_passed']!.bool()
	}
	for attempt in ['220', '221'] {
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
	println('MAPS218-221-RETAINED PASS ${checked} artifact hashes;4 serial/result identities;2 native archives/160 sources;${sources.len} exact framework sources + explicit1 missing-source limitation;actualDEX getter+lock evidence')
}
