// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// WS uses a software Canvas. Hardware layer requests therefore use Android's
// software fallback, while getLayerType retains the application's requested type.
fn framework_view_layers(smali string) ! {
	path := smali + '/android/view/View.smali'
	// Clearing the cached Canvas on NONE lets ART finalize its retained native
	// target after any in-progress draw has stopped using it.
	mut text := os.read_file(path)! + '
.field private vinixLayerType:I
.field private vinixLayerPaint:Landroid/graphics/Paint;
.field private vinixLayerBitmap:Landroid/graphics/Bitmap;
.field private vinixLayerCanvas:Landroid/graphics/Canvas;
'
	for signature, body in {
		'getLayerType()I': 'iget v0, p0, Landroid/view/View;->vinixLayerType:I\nreturn v0'
		'setLayerType(ILandroid/graphics/Paint;)V': '
if-ltz p1, :invalid
const/4 v0, 2
if-gt p1, v0, :invalid
iput p1, p0, Landroid/view/View;->vinixLayerType:I
if-eqz p1, :release
iput-object p2, p0, Landroid/view/View;->vinixLayerPaint:Landroid/graphics/Paint;
goto :invalidate
:release
const/4 v0, 0
iput-object v0, p0, Landroid/view/View;->vinixLayerPaint:Landroid/graphics/Paint;
iget-object v1, p0, Landroid/view/View;->vinixLayerCanvas:Landroid/graphics/Canvas;
if-eqz v1, :bitmap
invoke-virtual {v1, v0}, Landroid/graphics/Canvas;->setBitmap(Landroid/graphics/Bitmap;)V
iput-object v0, p0, Landroid/view/View;->vinixLayerCanvas:Landroid/graphics/Canvas;
:bitmap
iget-object v1, p0, Landroid/view/View;->vinixLayerBitmap:Landroid/graphics/Bitmap;
iput-object v0, p0, Landroid/view/View;->vinixLayerBitmap:Landroid/graphics/Bitmap;
if-eqz v1, :invalidate
invoke-virtual {v1}, Landroid/graphics/Bitmap;->recycle()V
:invalidate
invoke-virtual {p0}, Landroid/view/View;->invalidate()V
return-void
:invalid
new-instance v0, Ljava/lang/IllegalArgumentException;
const-string v1, "Layer type must be NONE, SOFTWARE or HARDWARE"
invoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V
throw v0'
		'setLayerPaint(Landroid/graphics/Paint;)V': '
iget v0, p0, Landroid/view/View;->vinixLayerType:I
if-eqz v0, :done
iput-object p1, p0, Landroid/view/View;->vinixLayerPaint:Landroid/graphics/Paint;
invoke-virtual {p0}, Landroid/view/View;->invalidate()V
:done
return-void'
	} {
		text = framework_replace_method(text, signature, touch_method('public ' + signature, body))!
	}
	// Called by the parent around virtual draw(), so subclass backgrounds,
	// children and drawing overrides all enter the same layer. Repaint each
	// frame until WS has subtree invalidation suitable for a drawing cache.
	text += touch_method('public final vinixDrawLayer(Landroid/graphics/Canvas;)V', '
iget v0, p0, Landroid/view/View;->vinixLayerType:I
if-eqz v0, :direct
invoke-virtual {p0}, Landroid/view/View;->getWidth()I
move-result v0
invoke-virtual {p0}, Landroid/view/View;->getHeight()I
move-result v1
if-lez v0, :direct
if-lez v1, :direct
iget-object v2, p0, Landroid/view/View;->vinixLayerBitmap:Landroid/graphics/Bitmap;
if-eqz v2, :allocate
invoke-virtual {v2}, Landroid/graphics/Bitmap;->getWidth()I
move-result v3
if-ne v0, v3, :resize
invoke-virtual {v2}, Landroid/graphics/Bitmap;->getHeight()I
move-result v3
if-eq v1, v3, :canvas
:resize
const/4 v3, 0
iput-object v3, p0, Landroid/view/View;->vinixLayerBitmap:Landroid/graphics/Bitmap;
invoke-virtual {v2}, Landroid/graphics/Bitmap;->recycle()V
:allocate
sget-object v3, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;
invoke-static {v0, v1, v3}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;
move-result-object v2
iput-object v2, p0, Landroid/view/View;->vinixLayerBitmap:Landroid/graphics/Bitmap;
:canvas
iget-object v3, p0, Landroid/view/View;->vinixLayerCanvas:Landroid/graphics/Canvas;
if-nez v3, :bind
new-instance v3, Landroid/graphics/Canvas;
invoke-direct {v3}, Landroid/graphics/Canvas;-><init>()V
iput-object v3, p0, Landroid/view/View;->vinixLayerCanvas:Landroid/graphics/Canvas;
:bind
invoke-virtual {v3, v2}, Landroid/graphics/Canvas;->setBitmap(Landroid/graphics/Bitmap;)V
const/4 v0, 0
invoke-virtual {v2, v0}, Landroid/graphics/Bitmap;->eraseColor(I)V
invoke-virtual {v3}, Landroid/graphics/Canvas;->save()I
move-result v4
:start
invoke-virtual {p0, v3}, Landroid/view/View;->draw(Landroid/graphics/Canvas;)V
:end
.catchall {:start .. :end} :failed
invoke-virtual {v3, v4}, Landroid/graphics/Canvas;->restoreToCount(I)V
iget-object v1, p0, Landroid/view/View;->vinixLayerPaint:Landroid/graphics/Paint;
invoke-virtual {p1, v2, v0, v0, v1}, Landroid/graphics/Canvas;->drawBitmap(Landroid/graphics/Bitmap;FFLandroid/graphics/Paint;)V
return-void
:failed
move-exception v5
invoke-virtual {v3, v4}, Landroid/graphics/Canvas;->restoreToCount(I)V
throw v5
:direct
invoke-virtual {p0, p1}, Landroid/view/View;->draw(Landroid/graphics/Canvas;)V
return-void')
	os.write_file(path, text)!
}
