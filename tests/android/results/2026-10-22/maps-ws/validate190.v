import os
import compress.gzip

fn main() {
	log := gzip.decompress(os.read_bytes('build/android-maps/fixture-diagnostics190/bootstrap-fixture/serial.log.gz')!)!.bytestr()
	for marker in ['CLIPPING', 'TRANSLATED-VISIBLE', 'TRANSLATED-LOCATION', 'GEOMETRY', 'TRANSLATIONS', 'SCROLL', 'EDITOR', 'WINDOW', 'DRAWABLE', 'PATH-BOUNDS', 'MATRIX-RECT', 'MATRIX-INVERSE', 'MATRIX-FIT', 'PICTURE', 'TEXT-METRICS', 'FONT-METRICS', 'CHARACTER-STYLES', 'SHADOW-COLORS', 'CHILD-STATES', 'FRAME-BOUNDS', 'LAYOUT-SUPPRESSION', 'NDK', 'EGL-COMPOSITION', 'TOUCH', 'TRAVERSAL', 'SCROLL-FRAMES', 'TIME-ANIMATOR', 'PATH-ANIMATOR-FRAMES', 'CONNECTIVITY'] {
		assert log.contains('BOOTSTRAP-${marker}-PASS'), marker
	}
	mut traces := 0
	mut frames := 0
	for line in log.split_into_lines() {
		if line.starts_with('ANDROID-WS-VIEW-ADD class=') {
			if traces > 0 { assert frames == 8 }
			traces++
			frames = 0
			assert line.contains('class=android.widget.TextView')
			assert line.ends_with('trace=${traces}')
		} else if line.starts_with('ANDROID-WS-VIEW-CALLER ') {
			frames++
		}
	}
	assert traces == 3 && frames == 8
	assert !log.contains('ANDROID-WS-VIEW-ADD unavailable')
	assert !log.contains('java.lang.AssertionError')
	assert !log.contains('APK-SUITE-EXIT id=')
	for line in log.split_into_lines().filter(it.starts_with('BOOTSTRAP-') && it.contains('-PASS')) { println(line) }
	println('VIEW-ADDITION-DIAGNOSTIC-PASS: exactly three inserted TextViews, eight frames each, no diagnostic exception or process exit')
}
