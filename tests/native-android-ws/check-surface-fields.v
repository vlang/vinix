// SPDX-License-Identifier: GPL-2.0-or-later
// Validate real guest observations from the bootstrap SurfaceView diagnostic.
import compress.gzip
import os

fn read_log(path string) !string {
	data := os.read_bytes(path)!
	return if path.ends_with('.gz') { gzip.decompress(data)!.bytestr() } else { data.bytestr() }
}

fn main() {
	assert os.args.len in [3, 4], 'usage: check-surface-fields.v enabled.log[.gz] disabled.log[.gz] [indexed|depth]'
	depth := os.args.len == 4 && os.args[3] == 'depth'
	indexed := depth || (os.args.len == 4 && os.args[3] == 'indexed')
	log := read_log(os.args[1])!
	for expected in [
		'path=mSurface value=android.view.Surface@',
		'path=mSurfaceHolder value=android.view.SurfaceView$1@',
		'path=left value=0',
		'path=mCallbacks value=[]',
		'path=missing unavailable',
		'path=left.noSuch unavailable',
		'path=mSurfaceHolder.this$0.left value=0',
		'path=mSurface.mNativeObject unavailable',
	] {
		assert log.contains('ANDROID-WS-SURFACE-FIELD ' + expected), expected
	}
	// The successful nested read follows two failed queries; later application
	// callbacks must still execute with no diagnostic exception left pending.
	failed_query := log.index('path=left.noSuch unavailable') or { panic('missing failed query') }
	recovered_query := log.index('path=mSurfaceHolder.this$0.left value=0') or { panic('missing recovered query') }
	mut last_query := log.index('path=mSurface.mNativeObject unavailable') or { panic('missing last query') }
	assert failed_query < recovered_query
	if indexed {
		for expected in ['path=ENABLED_STATE_SET.0 value=16842910',
			'path=ENABLED_STATE_SET.99 unavailable', 'path=mCallbacks.0 unavailable'] {
			assert log.contains('ANDROID-WS-SURFACE-FIELD ' + expected), expected
		}
		array_failure := log.index('path=ENABLED_STATE_SET.99 unavailable') or { panic('missing array failure') }
		list_failure := log.index('path=mCallbacks.0 unavailable') or { panic('missing list failure') }
		last_query = log.last_index('path=left value=0') or { panic('missing index recovery') }
		assert array_failure < list_failure && list_failure < last_query
	}
	if depth {
		path := ['mSurfaceHolder.this$0'].repeat(8).join('.')
		assert log.contains('path=' + path + ' value=android.view.SurfaceView@')
		too_deep := log.index('path=' + path + '.left unavailable') or { panic('missing depth limit') }
		last_query = log.last_index('path=left value=0') or { panic('missing depth recovery') }
		assert too_deep < last_query
	}
	for marker in ['BOOTSTRAP-TRAVERSAL-PASS', 'BOOTSTRAP-PATH-ANIMATOR-FRAMES-PASS'] {
		callback := log.index(marker) or { panic('missing callback ' + marker) }
		assert last_query < callback, marker
	}
	for marker in ['BOOTSTRAP-LAYOUT-SUPPRESSION-PASS', 'BOOTSTRAP-EGL-COMPOSITION-PASS'] {
		assert log.contains(marker), marker
	}
	assert log.split_into_lines().filter(it.starts_with('ANDROID-WS-SURFACE-FIELD ')).len <= if depth {
		45
	} else if indexed {
		36
	} else {
		24
	}
	for failure in ['ANDROID-WS-FAIL', 'JNI DETECTED ERROR', 'APK-SUITE-EXIT id='] {
		assert !log.contains(failure), failure
	}
	disabled := read_log(os.args[2])!
	assert disabled.contains('BOOTSTRAP-EGL-COMPOSITION-PASS')
	assert !disabled.contains('ANDROID-WS-SURFACE-FIELD ')
	println('SURFACE-FIELDS-PASS private inherited boxed nested missing recovery opt-in indexed=${indexed} depth=${depth}')
}
