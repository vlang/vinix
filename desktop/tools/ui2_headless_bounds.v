// SPDX-License-Identifier: GPL-2.0-or-later
// `$vml` always starts from ui2.bounds(). A hosted headless application gives
// the root explicit model-backed dimensions, but the generated call must still
// exist on Linux/Vinix where no platform window backend is compiled.
module ui2

$if linux && ui2_headless ? {
	pub fn bounds() Rect {
		return Rect{
			width: 800
			height: 600
		}
	}
}
