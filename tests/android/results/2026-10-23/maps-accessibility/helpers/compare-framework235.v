import os
import json2
import compress.gzip
import crypto.sha256
fn main() {
	mut maps := []map[string]string{}
	for path in ['framework234-interpolators', 'framework235-accessibility'] {
		maps << json2.decode[map[string]string](gzip.decompress(os.read_bytes('build/android-maps/' + path + '/exact-sources.json.gz')!)!.bytestr())!
	}
	assert maps[0].len == maps[1].len
	for path, source in maps[1] { if source != maps[0][path] { println(path + ' ' + sha256.sum(maps[0][path].bytes()).hex() + ' -> ' + sha256.sum(source.bytes()).hex()) } }
}
