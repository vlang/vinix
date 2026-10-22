// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// The native raster backend stores sRGB ARGB8. Android's sRGB color-long
// encoding has those same bits in the upper word; the lower word is padding.
// Do not reinterpret the half-float components of other color spaces as ARGB.
fn framework_paint_color_longs(smali string) ! {
 path := smali + '/android/graphics/Paint.smali'
 mut text := os.read_file(path)!
 text = framework_replace_method(text, 'setColor(J)V', '.method public setColor(J)V
.locals 4
const-wide/16 v0, 0x3f
and-long/2addr v0, p1
const-wide/16 v2, 0
cmp-long v0, v0, v2
if-nez v0, :unsupported
const/16 v0, 32
ushr-long v0, p1, v0
long-to-int v0, v0
invoke-virtual {p0, v0}, Landroid/graphics/Paint;->setColor(I)V
return-void
:unsupported
new-instance v0, Ljava/lang/UnsupportedOperationException;
const-string v1, "Native WS Paint requires an sRGB color long"
invoke-direct {v0, v1}, Ljava/lang/UnsupportedOperationException;-><init>(Ljava/lang/String;)V
throw v0
.end method')!
 text = framework_replace_method(text, 'getColorLong()J', '.method public getColorLong()J
.locals 3
invoke-virtual {p0}, Landroid/graphics/Paint;->getColor()I
move-result v0
int-to-long v0, v0
const/16 v2, 32
shl-long/2addr v0, v2
return-wide v0
.end method')!
 os.write_file(path, text)!
}
