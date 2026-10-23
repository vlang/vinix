module main

import os
import crypto.sha256

fn main() {
	root := os.getwd()
	dir := root + '/build/android-maps/path228'
	mode := if os.args.len > 1 { os.args[1] } else { 'raw' }
	assert mode in ['raw', 'counted']
	out := dir + '/' + mode
	os.mkdir_all(out)!
	if !os.exists(dir + '/baseline-source') {
		os.cp_all(dir + '/source', dir + '/baseline-source', false)!
	}
	os.mkdir_all(dir + '/source')!
	mut hashes := []string{}
	for name in ['path_clipping.v', 'graphics.v', 'affine.v', 'paths.v', 'canvases.v'] {
		body := os.read_file(root + '/build-support/android/nativews/' + name)!
		os.write_file(dir + '/source/' + name, body)!
		hashes << sha256.sum(body.bytes()).hex() + '  ' + name
	}
	os.write_file(dir + '/source/SHA256SUMS', hashes.join('\n') + '\n')!
	mut clip := os.read_file(dir + '/source/path_clipping.v')!
	clip = clip.replace('module atlframework', 'module main')
	if mode == 'counted' {
		clip = clip.replace('C.calloc(', 'host_clip_calloc(').replace('C.malloc(', 'host_clip_malloc(').replace('C.free(', 'host_clip_free(')
	}
	os.write_file(out + '/path_clipping.v', clip)!
	graphics := os.read_file(dir + '/source/graphics.v')!
	affine := os.read_file(dir + '/source/affine.v')!
	paths := os.read_file(dir + '/source/paths.v')!
	defs := 'module main\n' +
		'struct WsTransform {' + graphics.all_after('struct WsTransform {').all_before('\nstruct WsPaint {') +
		'\nstruct WsClipQuad {' + affine.all_after('struct WsClipQuad {').all_before('\nfn ws_scale(') +
		'\nstruct WsVertex {' + paths.all_after('struct WsVertex {').all_before('\nstruct WsCrossing {') +
		'\nfn ws_save() {' + graphics.all_after('fn ws_save() {').all_before('\nfn ws_translate(')
	os.write_file(out + '/actual_support.v', defs)!
	mut harness := os.read_file(dir + '/harness.v.txt')!
	harness = harness.replace('const counted = false', 'const counted = ' + (mode == 'counted').str())
	os.write_file(out + '/main.v', harness)!
	println('Prepared ' + mode + ' from path_clipping SHA256 ' + sha256.sum(os.read_bytes(dir + '/source/path_clipping.v')!).hex())
}
