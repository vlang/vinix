// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_canvas_z_probe(dir string) ! {
 probe := 'Lorg/vinix/bootstrap/CanvasZProbe;'
 canvas := 'Landroid/graphics/Canvas;'
 bitmap := 'Landroid/graphics/Bitmap;'
 bad := '\n:bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "Canvas software Z toggles changed state or pixels"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
 mut text := '.class public ${probe}\n.super Ljava/lang/Object;\n'
 text += method('public static check()V', '
const/4 v0, 4
sget-object v1, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;
invoke-static {v0, v0, v1}, ${bitmap}->createBitmap(IILandroid/graphics/Bitmap$Config;)${bitmap}
move-result-object v8
const v0, 0xff000000
invoke-virtual {v8, v0}, ${bitmap}->eraseColor(I)V
new-instance v9, ${canvas}
invoke-direct {v9, v8}, ${canvas}-><init>(${bitmap})V
invoke-virtual {v9}, ${canvas}->save()I
const/high16 v0, 0x3f800000
invoke-virtual {v9, v0, v0}, ${canvas}->translate(FF)V
const/4 v0, 0
const/4 v1, 2
invoke-virtual {v9, v0, v0, v1, v1}, ${canvas}->clipRect(IIII)Z
# Neither repeated toggles nor save/restore may change matrix, clip or depth.
invoke-virtual {v9}, ${canvas}->enableZ()V
invoke-virtual {v9}, ${canvas}->enableZ()V
invoke-virtual {v9}, ${canvas}->save()I
invoke-virtual {v9}, ${canvas}->disableZ()V
invoke-virtual {v9}, ${canvas}->disableZ()V
invoke-virtual {v9}, ${canvas}->restore()V
invoke-virtual {v9}, ${canvas}->getSaveCount()I
move-result v0
const/4 v1, 2
if-ne v0, v1, :bad
const v0, 0xffff0000
invoke-virtual {v9, v0}, ${canvas}->drawColor(I)V
invoke-virtual {v9}, ${canvas}->restore()V
invoke-virtual {v9}, ${canvas}->disableZ()V
invoke-virtual {v9}, ${canvas}->getSaveCount()I
move-result v0
const/4 v1, 1
if-ne v0, v1, :bad
const/4 v0, 0
:y
const/4 v1, 4
if-ge v0, v1, :recording
const/4 v1, 0
:x
const/4 v2, 4
if-ge v1, v2, :next_y
const v2, 0xff000000
const/4 v3, 1
if-lt v0, v3, :pixel
if-lt v1, v3, :pixel
const/4 v3, 3
if-ge v0, v3, :pixel
if-ge v1, v3, :pixel
const v2, 0xffff0000
:pixel
invoke-static {v8, v1, v0, v2}, ${probe}->pixel(${bitmap}III)V
add-int/lit8 v1, v1, 1
goto :x
:next_y
add-int/lit8 v0, v0, 1
goto :y
:recording
# The current command recorder inherits the APIs; this does not test Z sorting.
new-instance v0, Landroid/graphics/RenderNode;
const-string v1, "Z API availability"
invoke-direct {v0, v1}, Landroid/graphics/RenderNode;-><init>(Ljava/lang/String;)V
const/4 v1, 0
const/4 v2, 4
invoke-virtual {v0, v1, v1, v2, v2}, Landroid/graphics/RenderNode;->setPosition(IIII)Z
invoke-virtual {v0}, Landroid/graphics/RenderNode;->beginRecording()Landroid/graphics/RecordingCanvas;
move-result-object v1
invoke-virtual {v1}, Landroid/graphics/RecordingCanvas;->enableZ()V
const v2, 0xff0000ff
invoke-virtual {v1, v2}, ${canvas}->drawColor(I)V
invoke-virtual {v1}, Landroid/graphics/RecordingCanvas;->disableZ()V
invoke-virtual {v0}, Landroid/graphics/RenderNode;->endRecording()V
invoke-virtual {v9, v0}, ${canvas}->drawRenderNode(Landroid/graphics/RenderNode;)V
const/4 v0, 3
const v1, 0xff0000ff
invoke-static {v8, v0, v0, v1}, ${probe}->pixel(${bitmap}III)V
invoke-virtual {v8}, ${bitmap}->recycle()V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-CANVAS-Z-PASS software-noop repeated-toggles save-restore translated-clip 16-pixels recording-inherited-api playback"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void' + bad)
 text += method('private static pixel(${bitmap}III)V', '
move-object v0, p0
const/4 v2, 1
new-array v1, v2, [I
const/4 v2, 0
const/4 v3, 1
move v4, p1
move v5, p2
const/4 v6, 1
const/4 v7, 1
invoke-virtual/range {v0 .. v7}, ${bitmap}->getPixels([IIIIIII)V
const/4 v2, 0
aget v1, v1, v2
if-ne v1, p3, :bad
return-void' + bad)
 os.write_file(dir + '/CanvasZProbe.smali', text)!
}
