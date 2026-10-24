import os
import json2

fn main() {
	out := 'tests/android/results/2026-10-23/maps-action-provider/'
	observations := {
		'reviewed_by': 'Root agent drove all QMP input and reviewed the live workflow. maps_evidence independently inspected Paris place tiles, the full origin query, route estimates, Preview, next and previous steps, overflow menus, and post-selection layer screenshots.'
		'map': 'Automatic Skip completed. MAP-COLOR-DETECTED was recorded at 19:02:05 UTC+3, and map-before-input.png shows the North America map.'
		'search': 'Opened search at 19:02:16 UTC+3 and typed Paris at 19:02:30. Paris-results.png at 19:02:43 records the suggestions.'
		'place_selection': 'Selected the first Paris suggestion at 19:02:49 UTC+3. Paris-place.png at 19:02:56 and paris-place-tiles.png at 19:03:14 show the Paris/France place panel, photos and detailed map tiles.'
		'directions': 'Clicked Directions at 19:03:19 UTC+3 and typed the full Versailles, France query at 19:03:29. Origin-query.png at 19:03:37 shows that query. Selected the first Versailles/France suggestion at 19:03:46. Route-estimates.png at 19:03:58 shows Versailles to Paris, Drive 1 hr 4 min (23 km), transit 25 min, walking 4 hr 25, and Preview/Add stops/Share controls.'
		'preview': 'Opened Preview at 19:04:06 UTC+3. Route-preview.png at 19:04:10 shows Head toward Av. de Paris/D186 and detailed street tiles. Next at 19:04:16 changes the instruction to 300 m, Turn right onto Av. de Saint-Cloud/D185, with lane arrows and a different map view (route-preview-next.png at 19:04:19). Previous at 19:05:40 returns to the initial instruction and map (route-preview-previous.png at 19:05:46).'
		'overflow': 'Opened the Preview overflow at 19:04:29 UTC+3. Preview-overflow.png at 19:04:37 shows All traffic, Satellite and Terrain. Selected Satellite at 19:04:43; the popup dismissed and Preview remained responsive. Reopened overflow at 19:06:27 (preview-overflow-again.png at 19:06:30) and selected Terrain at 19:06:39; the popup again dismissed. The screenshots preview-satellite.png at 19:05:13 and preview-terrain.png at 19:06:51 still show vector road tiles; they do not verify satellite imagery or terrain rendering.'
		'return_to_routes': 'Clicked the Preview back arrow at 19:07:29 UTC+3. Route-after-preview.png at 19:07:34 shows the Versailles-to-Paris route overview with the Preview/Add stops/Share controls.'
		'qualification': 'Both Maps244 and Maps245 were interrupted by the headless session ending before their final harness results. Maps245 completed the recorded UI workflow but did not complete the configured 900-second observation. It reuses the actual Maps244 prepared boot image after a read-only full-image hash and streamed archive proof. The resumed suite checks preflight trust, image size/mtime and staged file hashes rather than independently rehashing the image. Framework244 adds only ActionProvider and its framework_classes hook relative to Maps243; native236, APKs and launcher are unchanged. Overflow now displays without the earlier missing-ActionProvider crash. UI icons and map labels remain incomplete, some bottom details are clipped, and the menu uses the framework popup presentation. No performance, live location, zoom, estimate accuracy, complete route geometry or live-navigation claim is made.'
		'raw_outcome': 'unavailable; Maps245 was interrupted before final results.json or harness/interaction logs were written. The configured 900-second observation did not complete. The retained partial serial contains BEGIN and READY, with no application-exit or framework-failure marker; those absences do not establish a final classifier or stability result.'
	}
	if os.exists(out + 'results.json') {
		panic('Final result now exists: review it before recording interruption')
	}
	os.write_file(out + 'observations.json', json2.encode(observations, prettify: true))!
	if os.abs_path(@FILE) != os.abs_path(out + 'helpers/observe245.v') {
		os.cp(@FILE, out + 'helpers/observe245.v')!
	}
	println('Maps245 observed workflow recorded; interrupted before final raw outcome and 900-second completion')
}
