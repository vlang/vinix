// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Compose uses BlendModeColorFilter for the same SRC_IN mask tint that the
// raster backend already implements for PorterDuffColorFilter.
fn framework_paint_filters(smali string) ! {
	path := smali + '/android/graphics/Paint.smali'
	mut text := os.read_file(path)!
	text = framework_replace_method(text, 'setColorFilter(Landroid/graphics/ColorFilter;)Landroid/graphics/ColorFilter;', '.method public setColorFilter(Landroid/graphics/ColorFilter;)Landroid/graphics/ColorFilter;
.locals 4
instance-of v0, p1, Landroid/graphics/PorterDuffColorFilter;
if-eqz v0, :blend_mode
move-object v0, p1
check-cast v0, Landroid/graphics/PorterDuffColorFilter;
invoke-virtual {v0}, Landroid/graphics/PorterDuffColorFilter;->getMode()Landroid/graphics/PorterDuff$Mode;
move-result-object v1
invoke-virtual {v1}, Landroid/graphics/PorterDuff$Mode;->ordinal()I
move-result v1
invoke-virtual {v0}, Landroid/graphics/PorterDuffColorFilter;->getColor()I
move-result v0
goto :apply
:blend_mode
instance-of v0, p1, Landroid/graphics/BlendModeColorFilter;
if-eqz v0, :clear
move-object v0, p1
check-cast v0, Landroid/graphics/BlendModeColorFilter;
invoke-virtual {v0}, Landroid/graphics/BlendModeColorFilter;->getMode()Landroid/graphics/BlendMode;
move-result-object v1
sget-object v2, Landroid/graphics/BlendMode;->SRC_IN:Landroid/graphics/BlendMode;
if-ne v1, v2, :clear
invoke-virtual {v0}, Landroid/graphics/BlendModeColorFilter;->getColor()I
move-result v0
const/4 v1, 5
goto :apply
:clear
const/4 v0, 0
const/4 v1, -1
:apply
iget-wide v2, p0, Landroid/graphics/Paint;->paint:J
invoke-static {v2, v3, v1, v0}, Landroid/graphics/Paint;->native_set_color_filter(JII)V
iput-object p1, p0, Landroid/graphics/Paint;->color_filter:Landroid/graphics/ColorFilter;
return-object p1
.end method')!
	os.write_file(path, text)!
}
