// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_font_metrics(smali string) ! {
	path := smali + '/android/graphics/Paint.smali'
	mut text := os.read_file(path)!
	for signature in ['getFontMetrics(Landroid/graphics/Paint$FontMetrics;)F',
		'getFontMetricsInt(Landroid/graphics/Paint$FontMetricsInt;)I', 'ascent()F', 'descent()F'] {
		text = framework_replace_method(text, signature, '.method public native ${signature}\n.end method')!
	}
	for kind in ['FontMetrics', 'FontMetricsInt'] {
		class := 'Landroid/graphics/Paint$${kind};'
		text = framework_replace_method(text, 'get${kind}()${class}', touch_method('public get${kind}()${class}', '
new-instance v0, ${class}
invoke-direct {v0}, ${class}-><init>()V
invoke-virtual {p0, v0}, Landroid/graphics/Paint;->get${kind}(${class})' + if kind == 'FontMetrics' { 'F' } else { 'I' } + '
return-object v0'))!
	}
	text = framework_replace_method(text, 'getFontSpacing()F', touch_method('public getFontSpacing()F', '
const/4 v0, 0
invoke-virtual {p0, v0}, Landroid/graphics/Paint;->getFontMetrics(Landroid/graphics/Paint$FontMetrics;)F
move-result v0
return v0'))!
	os.write_file(path, text)!
}
