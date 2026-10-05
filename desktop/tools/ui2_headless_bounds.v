// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// `$vml` always starts from ui2.bounds(). A hosted headless application gives
// the root explicit model-backed dimensions, but the generated call must still
// exist on Linux/Vinix where no platform window backend is compiled.
module ui2

$if (linux || vinix) && ui2_headless ? {
	pub fn bounds() Rect {
		return Rect{
			width: 800
			height: 600
		}
	}
}
