import os
import json2

fn main() {
	dir := 'tests/android/results/2026-10-23/maps-blur-styles/'
	observations := {
		'reviewed_by': 'Root agent drove QMP and reported the completed failure. transition_review visually inspected paris-selected.png and origin-query.png and checked the manual timeline and fatal serial trace.'
		'map': 'The map-before-input.png capture was retained at 2026-10-23 17:33:08 UTC+3 after the helper detected map-colored pixels.'
		'search': 'Clicked search at 17:33:11 UTC+3 and typed Paris at 17:33:32. The search-paris.png capture was taken at 17:33:54 before clicking the first suggestion.'
		'place_selection': 'Clicked the first Paris suggestion at 17:33:54 UTC+3. Paris-selected.png at 17:34:18 visibly shows Paris map tiles, the Paris / France place panel, photographs and Directions.'
		'directions': 'Clicked Directions at 17:34:18 UTC+3. Directions-opened.png was captured at 17:34:35, followed by standard Versailles, France input. Origin-query.png at 17:35:01 visibly shows the exact query and Versailles / France as the first suggestion. Clicked that first origin at 17:35:01. The app then exited on a missing Canvas.saveLayer(float,float,float,float,Paint,int) overload during drawing. The route-selected.png capture at 17:35:25 failed because QMP had exited. No rendered route, duration, distance or navigation is verified.'
		'raw_outcome': 'startup_failed; APK-SUITE-EXIT id=google-maps code=1 native_observed=true gtk_x11_absent=true. The raw classifier is preserved separately from the observed map/search/place/origin-picker behavior.'
		'fatal': 'Serial lines 192622–192623: ANDROID-WS-FAIL input or render; NoSuchMethodError: No virtual method saveLayer(FFFFLandroid/graphics/Paint;I)I in android.graphics.Canvas, reached through els.o, luy.a and ekd.mA during drawing after origin selection. APK exit 1 is recorded at line 192732.'
		'qualification': 'Only framework_blur_styles.v and its framework_startup.v hook differ from Maps240; the Maps/GMS/Store APKs, launcher, native235 and frozen suite239-stream binary are identical. Exact framework110/native83 source archives, seven pre-run identities and seven staged runtime hashes are retained. The four Blur enum values and native integer state are present, and the prior OUTER field error does not recur. Advancing to the next draw call does not establish correct blur rendering or route calculation. UI processing remains slow and several icons render as boxes or black circles. No performance, zoom, location, blur appearance, media-surface or navigation claim is made.'
	}
	os.write_file(dir + 'observations.json', json2.encode(observations, prettify: true) + '\n')!
	os.write_file(dir + 'README.md', 'Maps241 displays the Paris place view with map tiles, photographs and Directions. The origin picker accepts `Versailles, France` and displays matching suggestions. Selecting the first origin advances past the prior missing `BlurMaskFilter$Blur.OUTER` field, then exits on the missing `Canvas.saveLayer(float,float,float,float,Paint,int)` overload during drawing. The attempted route screenshot failed after the app exited. No rendered route, duration, distance or navigation is verified.\n\nThis run uses framework241 (110 exact V sources), unchanged native235 (83 sources), and the unchanged frozen suite239-stream binary. Relative to [Maps240](../maps-date-ranges/README.md), only the BlurMaskFilter style enum generator and its framework hook change. The Maps/GMS/Store APKs, launcher and six staged runtime files other than the framework JAR are identical. Seven pre-run kernel/image/EFI/QEMU/suite hashes and seven staged runtime hashes identify the inputs; exact V archives and selected generated Smali are retained.\n\nThe receipt preserves the raw `startup_failed` classifier, APK exit code 1, complete serial output, screenshots and manual timeline. `observations.json` records screenshot interpretation separately. UI processing remains slow, and some icons appear as boxes or black circles. The independently verified [native235 interpolator precision](../interpolators/README.md) and [streaming staging implementation](../maps-window-insets/README.md) remain unchanged. Presence of the enum values and reaching a later draw call do not establish correct blur rendering. No performance, zoom, location or navigation claim is made.\n\nFrom the repository root, run `/Users/alex/code/v/v_old -nocache -cc cc run tests/android/results/2026-10-23/maps-blur-styles/validate.v result`. Capture `retain.v inputs` while the completed staged module exists, then `retain.v result` after completion; refresh `retain.v manifest` after recording reviewed observations. The validator checks exact source deltas, unchanged binary inputs, staging provenance and the fatal result separately from screenshot interpretation.\n')!
	mut validator := os.read_file(dir + 'validate.v')!
	old := "\t\tassert log.contains('APK-SUITE-EXIT id=google-maps'), 'Require completed run'"
	assert validator.count(old) == 1
	validator = validator.replace(old, "\t\tassert result['outcome']!.str() == 'startup_failed'\n\t\tassert log.contains('ANDROID-WS-FAIL input or render')\n\t\tassert log.contains('java.lang.NoSuchMethodError: No virtual method saveLayer(FFFFLandroid/graphics/Paint;I)I')\n\t\tassert log.contains('APK-SUITE-EXIT id=google-maps code=1 native_observed=true gtk_x11_absent=true')\n\t\tassert !log.contains('NoSuchFieldError: No field OUTER of type Landroid/graphics/BlurMaskFilter\$Blur;'), 'Prior enum field blocker must be reported if it recurs'")
	old_print := "\t\tprintln('MAPS241-INTEGRITY PASS"
	assert validator.count(old_print) == 1
	validator = validator.replace(old_print, "\t\tfor name in ['map-before-input.png', 'search-paris.png', 'paris-selected.png',\n\t\t\t'directions-opened.png', 'origin-query.png'] {\n\t\t\tassert os.exists(out + '/run/' + name), name\n\t\t}\n\t\tassert !os.exists(out + '/run/route-selected.png'), 'Route capture failed after app exit'\n" + old_print)
	os.write_file(dir + 'validate.v', validator)!
	os.cp(@FILE, dir + 'helpers/finalize-maps241.v')!
	for args in ['retain.v manifest', 'validate.v result'] {
		parts := args.split(' ')
		result := os.execute('/Users/alex/code/v/v_old -nocache -cc cc run ' + dir + parts[0] + ' ' + parts[1])
		if parts[0] == 'validate.v' {
			os.write_file(dir + 'validation.log', result.output.trim_right('\r\n') + '\n')!
		}
		print(result.output)
		assert result.exit_code == 0, args
	}
}
