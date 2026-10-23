import os

fn main() {
	from := 'tests/android/results/2026-10-23/maps-interpolators/'
	out := 'tests/android/results/2026-10-23/maps-accessibility/'
	os.mkdir_all(out)!
	for name in ['retain.v', 'validate.v'] {
		mut source := os.read_file(from + name)!.replace('234', '235')
		source = source.replace('framework235-interpolators', 'framework235-accessibility')
		source = source.replace('643d292a4c862ca09bcf1f9c0579ad9c077ad8d1b477ed3a33d3ff1ac8300c13', '6810384e4ccc548adcf16a9d9cbc57d70c3250b50bda912fa32edf2af5874dfd')
		if name == 'retain.v' {
			source = source.replace("const framework = 'framework235-accessibility/'", "const framework = 'framework235-accessibility/'")
			source = source.replace("'../maps-input-latency/receipt.json'", "'../maps-interpolators/receipt.json'")
			source = source.replace("'interpolator-resources235'", "'interpolator-resources234'")
			source = source.replace("'build-framework235-interpolators.v'", "'build-framework235-accessibility.v'")
			source = source.replace("'snapshot-framework235.v', 'prepare235.v'", "'snapshot-framework235.v', 'prepare-framework235.v.generated', 'prepare235.v'")
			source = source.replace("'keys235.v', 'zoom235.v', 'identity235.v', 'extract-interpolators235.v', 'audit235-classes.v',", "'keys235.v', 'zoom235.v', 'identity235.v',")
			source = source.replace("'native233-build.log', 'framework235-build.log', 'audit235-classes.log'", "'native233-build.log', 'framework235-build.log'")
			source = source.replace("'android/animation/VinixPathValues.smali', 'android/graphics/drawable/PathParser.smali'", "'android/animation/VinixPathValues.smali', 'android/graphics/drawable/PathParser.smali', 'android/view/View.smali'")
			source = source.replace("framework235. Exact V archives", "framework235 accessibility traversal state and XML support. Exact V archives")
			source = source.replace("'attempt235-harness.log', 'interact235.log', 'attempt235-timeline.log', 'pan235.log'", "'attempt235-harness.log', 'run235.log', 'interact235.log', 'attempt235-timeline.log', 'pan235.log', 'map-wait235.log'")
		} else {
			source = source.replace('assert smali.len == 14', 'assert smali.len == 15')
			source = source.replace("assert smali['android/graphics/drawable/PathParser.smali'].starts_with('.class public ')", "assert smali['android/graphics/drawable/PathParser.smali'].starts_with('.class public ')\n\tview := smali['android/view/View.smali']\n\tfor method in ['getAccessibilityTraversalBefore()I', 'getAccessibilityTraversalAfter()I', 'setAccessibilityTraversalBefore(I)V', 'setAccessibilityTraversalAfter(I)V', 'vinixInitAccessibilityTraversal(Landroid/content/Context;Landroid/util/AttributeSet;II)V'] { assert view.contains(method), method }")
		}
		os.write_file(out + name, source)!
	}
	println('MAPS235 receipt templates prepared; no staging or result reads')
}
