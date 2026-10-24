// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_paths(smali string) ! {
 path := smali + '/android/graphics/Path.smali'
 mut text := os.read_file(path)!
 // Native WS transfers the builder into the immutable path. Keeping both
 // fields aliased makes a later mutation append a path to itself forever.
 text = framework_replace_method(text, 'getGskPath()J', '.method public getGskPath()J
.locals 4
iget-wide v0, p0, Landroid/graphics/Path;->path:J
const-wide/16 v2, 0
cmp-long v0, v0, v2
if-nez v0, :done
iget-wide v0, p0, Landroid/graphics/Path;->builder:J
invoke-static {v0, v1}, Landroid/graphics/Path;->native_create_path(J)J
move-result-wide v0
iput-wide v0, p0, Landroid/graphics/Path;->path:J
iput-wide v2, p0, Landroid/graphics/Path;->builder:J
:done
iget-wide v0, p0, Landroid/graphics/Path;->path:J
return-wide v0
.end method')!
 text = framework_replace_method(text, 'transform(Landroid/graphics/Matrix;Landroid/graphics/Path;)V', '.method public transform(Landroid/graphics/Matrix;Landroid/graphics/Path;)V
.locals 1
if-eqz p2, :in_place
if-eq p0, p2, :in_place
invoke-virtual {p2}, Landroid/graphics/Path;->reset()V
invoke-virtual {p2, p0, p1}, Landroid/graphics/Path;->addPath(Landroid/graphics/Path;Landroid/graphics/Matrix;)V
invoke-virtual {p0}, Landroid/graphics/Path;->getFillType()Landroid/graphics/Path$FillType;
move-result-object v0
invoke-virtual {p2, v0}, Landroid/graphics/Path;->setFillType(Landroid/graphics/Path$FillType;)V
return-void
:in_place
invoke-virtual {p0, p1}, Landroid/graphics/Path;->transform(Landroid/graphics/Matrix;)V
return-void
.end method')!
 text = framework_replace_method(text, '<init>(Landroid/graphics/Path;)V', '.method public constructor <init>(Landroid/graphics/Path;)V
.locals 2
invoke-direct {p0}, Landroid/graphics/Path;-><init>()V
if-eqz p1, :done
invoke-virtual {p1}, Landroid/graphics/Path;->getFillType()Landroid/graphics/Path$FillType;
move-result-object v0
iput-object v0, p0, Landroid/graphics/Path;->fillType:Landroid/graphics/Path$FillType;
invoke-virtual {p1}, Landroid/graphics/Path;->getGskPath()J
move-result-wide v0
invoke-static {v0, v1}, Landroid/graphics/Path;->native_ref_path(J)J
move-result-wide v0
iput-wide v0, p0, Landroid/graphics/Path;->path:J
:done
return-void
.end method')!
 text = framework_replace_method(text, 'set(Landroid/graphics/Path;)V', '.method public set(Landroid/graphics/Path;)V
.locals 1
if-eq p0, p1, :done
invoke-virtual {p1}, Landroid/graphics/Path;->getFillType()Landroid/graphics/Path$FillType;
move-result-object v0
invoke-virtual {p0}, Landroid/graphics/Path;->reset()V
invoke-virtual {p0, p1}, Landroid/graphics/Path;->addPath(Landroid/graphics/Path;)V
iput-object v0, p0, Landroid/graphics/Path;->fillType:Landroid/graphics/Path$FillType;
:done
return-void
.end method')!
 text = framework_replace_method(text, 'setFillType(Landroid/graphics/Path$FillType;)V', '.method public setFillType(Landroid/graphics/Path$FillType;)V
.locals 0
invoke-virtual {p1}, Ljava/lang/Enum;->ordinal()I
iput-object p1, p0, Landroid/graphics/Path;->fillType:Landroid/graphics/Path$FillType;
return-void
.end method')!
 os.write_file(path, text)!
 // Match clipPath: geometry may be shared while each Java Path has its own rule.
 canvas_path := smali + '/android/atl/GskCanvas.smali'
 mut canvas := os.read_file(canvas_path)!
 old_native := '.method protected native native_drawPath(JJJ)V'
 if canvas.count(old_native) != 1 { return error('unexpected Canvas path draw declaration') }
 canvas = canvas.replace(old_native, '.method protected native native_drawPath(JJJI)V')
 canvas = framework_replace_method(canvas, 'drawPath(Landroid/graphics/Path;Landroid/graphics/Paint;)V', '.method public drawPath(Landroid/graphics/Path;Landroid/graphics/Paint;)V
.locals 8
if-eqz p1, :done
move-object v0, p0
iget-wide v1, p0, Landroid/atl/GskCanvas;->snapshot:J
invoke-virtual {p1}, Landroid/graphics/Path;->getGskPath()J
move-result-wide v3
if-nez p2, :paint
sget-object p2, Landroid/atl/GskCanvas;->default_paint:Landroid/graphics/Paint;
:paint
iget-wide v5, p2, Landroid/graphics/Paint;->paint:J
invoke-virtual {p1}, Landroid/graphics/Path;->getFillType()Landroid/graphics/Path$FillType;
move-result-object v7
invoke-virtual {v7}, Ljava/lang/Enum;->ordinal()I
move-result v7
invoke-virtual/range {v0 .. v7}, Landroid/atl/GskCanvas;->native_drawPath(JJJI)V
:done
return-void
.end method')!
 os.write_file(canvas_path, canvas)!
}
