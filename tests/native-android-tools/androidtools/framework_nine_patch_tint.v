// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Keep filters on each drawable's Paint instead of altering its shared bitmap.
// The raster backend currently applies SRC_IN filters. Other modes retain the
// existing Paint backend's behavior; nine-patch stretch regions are unchanged.
fn framework_nine_patch_tint(smali string) ! {
	path := smali + '/android/graphics/drawable/NinePatchDrawable.smali'
	mut text := os.read_file(path)!
	if text.contains('vinixTint') { return error('NinePatchDrawable tint API already present') }
	constructor := 'invoke-direct {p0}, Landroid/graphics/drawable/Drawable;-><init>()V'
	if text.count(constructor) != 2 { return error('unexpected NinePatchDrawable constructors') }
	text = text.replace(constructor, constructor + '
sget-object v0, Landroid/graphics/PorterDuff$Mode;->SRC_IN:Landroid/graphics/PorterDuff$Mode;
iput-object v0, p0, Landroid/graphics/drawable/NinePatchDrawable;->vinixTintMode:Landroid/graphics/PorterDuff$Mode;')
	text += '
.field private vinixPaint:Landroid/graphics/Paint;
.field private vinixTint:Landroid/content/res/ColorStateList;
.field private vinixTintMode:Landroid/graphics/PorterDuff$Mode;
.field private vinixTintFilter:Landroid/graphics/PorterDuffColorFilter;

.method private static native nativeDraw(JLandroid/graphics/Canvas;IIIIJ)V
.end method

.method public getPaint()Landroid/graphics/Paint;
.locals 1
iget-object v0, p0, Landroid/graphics/drawable/NinePatchDrawable;->vinixPaint:Landroid/graphics/Paint;
if-nez v0, :done
new-instance v0, Landroid/graphics/Paint;
invoke-direct {v0}, Landroid/graphics/Paint;-><init>()V
iput-object v0, p0, Landroid/graphics/drawable/NinePatchDrawable;->vinixPaint:Landroid/graphics/Paint;
:done
return-object v0
.end method

.method public draw(Landroid/graphics/Canvas;)V
.locals 11
invoke-virtual {p0}, Landroid/graphics/drawable/NinePatchDrawable;->getPaint()Landroid/graphics/Paint;
move-result-object v9
invoke-virtual {v9}, Landroid/graphics/Paint;->getColorFilter()Ljava/lang/Object;
move-result-object v10
check-cast v10, Landroid/graphics/ColorFilter;
:try_start
if-nez v10, :arguments
iget-object v0, p0, Landroid/graphics/drawable/NinePatchDrawable;->vinixTintFilter:Landroid/graphics/PorterDuffColorFilter;
if-eqz v0, :arguments
invoke-virtual {v9, v0}, Landroid/graphics/Paint;->setColorFilter(Landroid/graphics/ColorFilter;)Landroid/graphics/ColorFilter;
:arguments
iget-wide v7, v9, Landroid/graphics/Paint;->paint:J
iget-wide v0, p0, Landroid/graphics/drawable/Drawable;->paintable:J
invoke-virtual {p1}, Landroid/graphics/Canvas;->vinixNativeCanvas()Landroid/atl/GskCanvas;
move-result-object v2
invoke-virtual {p0}, Landroid/graphics/drawable/NinePatchDrawable;->getBounds()Landroid/graphics/Rect;
move-result-object v9
iget v3, v9, Landroid/graphics/Rect;->left:I
iget v4, v9, Landroid/graphics/Rect;->top:I
invoke-virtual {v9}, Landroid/graphics/Rect;->width()I
move-result v5
invoke-virtual {v9}, Landroid/graphics/Rect;->height()I
move-result v6
invoke-static/range {v0 .. v8}, Landroid/graphics/drawable/NinePatchDrawable;->nativeDraw(JLandroid/graphics/Canvas;IIIIJ)V
:try_end
invoke-virtual {p0}, Landroid/graphics/drawable/NinePatchDrawable;->getPaint()Landroid/graphics/Paint;
move-result-object v9
invoke-virtual {v9, v10}, Landroid/graphics/Paint;->setColorFilter(Landroid/graphics/ColorFilter;)Landroid/graphics/ColorFilter;
return-void
:restore_on_throw
move-exception v0
invoke-virtual {p0}, Landroid/graphics/drawable/NinePatchDrawable;->getPaint()Landroid/graphics/Paint;
move-result-object v9
invoke-virtual {v9, v10}, Landroid/graphics/Paint;->setColorFilter(Landroid/graphics/ColorFilter;)Landroid/graphics/ColorFilter;
throw v0
.catchall {:try_start .. :try_end} :restore_on_throw
.end method

.method public setAlpha(I)V
.locals 1
invoke-virtual {p0}, Landroid/graphics/drawable/NinePatchDrawable;->getPaint()Landroid/graphics/Paint;
move-result-object v0
invoke-virtual {v0, p1}, Landroid/graphics/Paint;->setAlpha(I)V
invoke-virtual {p0}, Landroid/graphics/drawable/NinePatchDrawable;->invalidateSelf()V
return-void
.end method

.method public getAlpha()I
.locals 1
invoke-virtual {p0}, Landroid/graphics/drawable/NinePatchDrawable;->getPaint()Landroid/graphics/Paint;
move-result-object v0
invoke-virtual {v0}, Landroid/graphics/Paint;->getAlpha()I
move-result v0
return v0
.end method

.method public setColorFilter(Landroid/graphics/ColorFilter;)V
.locals 1
invoke-virtual {p0}, Landroid/graphics/drawable/NinePatchDrawable;->getPaint()Landroid/graphics/Paint;
move-result-object v0
invoke-virtual {v0, p1}, Landroid/graphics/Paint;->setColorFilter(Landroid/graphics/ColorFilter;)Landroid/graphics/ColorFilter;
invoke-virtual {p0}, Landroid/graphics/drawable/NinePatchDrawable;->invalidateSelf()V
return-void
.end method

.method public getColorFilter()Landroid/graphics/ColorFilter;
.locals 1
invoke-virtual {p0}, Landroid/graphics/drawable/NinePatchDrawable;->getPaint()Landroid/graphics/Paint;
move-result-object v0
invoke-virtual {v0}, Landroid/graphics/Paint;->getColorFilter()Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/graphics/ColorFilter;
return-object v0
.end method

.method public setTintList(Landroid/content/res/ColorStateList;)V
.locals 1
iput-object p1, p0, Landroid/graphics/drawable/NinePatchDrawable;->vinixTint:Landroid/content/res/ColorStateList;
invoke-direct {p0}, Landroid/graphics/drawable/NinePatchDrawable;->vinixUpdateTint()Z
invoke-virtual {p0}, Landroid/graphics/drawable/NinePatchDrawable;->invalidateSelf()V
return-void
.end method

.method public setTintMode(Landroid/graphics/PorterDuff$Mode;)V
.locals 1
iput-object p1, p0, Landroid/graphics/drawable/NinePatchDrawable;->vinixTintMode:Landroid/graphics/PorterDuff$Mode;
invoke-direct {p0}, Landroid/graphics/drawable/NinePatchDrawable;->vinixUpdateTint()Z
invoke-virtual {p0}, Landroid/graphics/drawable/NinePatchDrawable;->invalidateSelf()V
return-void
.end method

.method public isStateful()Z
.locals 1
iget-object v0, p0, Landroid/graphics/drawable/NinePatchDrawable;->vinixTint:Landroid/content/res/ColorStateList;
if-eqz v0, :no
invoke-virtual {v0}, Landroid/content/res/ColorStateList;->isStateful()Z
move-result v0
return v0
:no
const/4 v0, 0
return v0
.end method

.method protected onStateChange([I)Z
.locals 1
invoke-direct {p0}, Landroid/graphics/drawable/NinePatchDrawable;->vinixUpdateTint()Z
move-result v0
if-eqz v0, :done
invoke-virtual {p0}, Landroid/graphics/drawable/NinePatchDrawable;->invalidateSelf()V
:done
return v0
.end method

.method private vinixUpdateTint()Z
.locals 5
iget-object v0, p0, Landroid/graphics/drawable/NinePatchDrawable;->vinixTintFilter:Landroid/graphics/PorterDuffColorFilter;
iget-object v1, p0, Landroid/graphics/drawable/NinePatchDrawable;->vinixTint:Landroid/content/res/ColorStateList;
iget-object v2, p0, Landroid/graphics/drawable/NinePatchDrawable;->vinixTintMode:Landroid/graphics/PorterDuff$Mode;
if-eqz v1, :clear
if-eqz v2, :clear
invoke-virtual {p0}, Landroid/graphics/drawable/NinePatchDrawable;->getState()[I
move-result-object v3
const/4 v4, 0
invoke-virtual {v1, v3, v4}, Landroid/content/res/ColorStateList;->getColorForState([II)I
move-result v1
if-eqz v0, :create
invoke-virtual {v0}, Landroid/graphics/PorterDuffColorFilter;->getColor()I
move-result v3
if-ne v1, v3, :create
invoke-virtual {v0}, Landroid/graphics/PorterDuffColorFilter;->getMode()Landroid/graphics/PorterDuff$Mode;
move-result-object v3
if-eq v2, v3, :unchanged
:create
new-instance v3, Landroid/graphics/PorterDuffColorFilter;
invoke-direct {v3, v1, v2}, Landroid/graphics/PorterDuffColorFilter;-><init>(ILandroid/graphics/PorterDuff$Mode;)V
goto :store
:clear
if-eqz v0, :unchanged
const/4 v3, 0
:store
iput-object v3, p0, Landroid/graphics/drawable/NinePatchDrawable;->vinixTintFilter:Landroid/graphics/PorterDuffColorFilter;
const/4 v0, 1
return v0
:unchanged
const/4 v0, 0
return v0
.end method
'
	text = framework_replace_method(text, 'setTint(I)V', '.method public setTint(I)V
.locals 1
invoke-static {p1}, Landroid/content/res/ColorStateList;->valueOf(I)Landroid/content/res/ColorStateList;
move-result-object v0
invoke-virtual {p0, v0}, Landroid/graphics/drawable/NinePatchDrawable;->setTintList(Landroid/content/res/ColorStateList;)V
return-void
.end method')!
	os.write_file(path, text)!
}
