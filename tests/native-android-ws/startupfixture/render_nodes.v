// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_render_node_probe(dir string) ! {
 probe := 'Lorg/vinix/bootstrap/RenderNodeProbe;'
 node := 'Landroid/graphics/RenderNode;'
 canvas := 'Landroid/graphics/Canvas;'
 bitmap := 'Landroid/graphics/Bitmap;'
 bad := '\n:bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "RenderNode recording, properties or pixels"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
 mut text := '.class public ${probe}\n.super Ljava/lang/Object;\n'
 text += method('private static rectangle(${canvas}I)V', 'move-object v0, p0\nconst/4 v1, 0\nconst/4 v2, 0\nconst/high16 v3, 0x41000000\nconst/high16 v4, 0x41000000\nnew-instance v5, Landroid/graphics/Paint;\ninvoke-direct {v5}, Landroid/graphics/Paint;-><init>()V\ninvoke-virtual {v5, p1}, Landroid/graphics/Paint;->setColor(I)V\ninvoke-virtual/range {v0 .. v5}, ${canvas}->drawRect(FFFFLandroid/graphics/Paint;)V\nconst/high16 v1, 0x40800000\nconst/high16 v2, 0x40800000\nconst/high16 v3, 0x41400000\nconst/high16 v4, 0x41400000\ninvoke-virtual/range {v0 .. v5}, ${canvas}->drawRect(FFFFLandroid/graphics/Paint;)V\nconst v0, -0xff0100\ninvoke-virtual {v5, v0}, Landroid/graphics/Paint;->setColor(I)V\nreturn-void')
 text += method('private static create()${node}', 'new-instance v0, ${node}\nconst-string v1, "WS layer"\ninvoke-direct {v0, v1}, ${node}-><init>(Ljava/lang/String;)V\nconst/4 v1, 0\nconst/16 v2, 16\ninvoke-virtual {v0, v1, v1, v2, v2}, ${node}->setPosition(IIII)Z\ninvoke-virtual {v0}, ${node}->beginRecording()Landroid/graphics/RecordingCanvas;\nmove-result-object v1\nconst v2, -0x10000\ninvoke-static {v1, v2}, ${probe}->rectangle(${canvas}I)V\ninvoke-virtual {v0}, ${node}->endRecording()V\nreturn-object v0')
 // Compare every pixel against independently specified integer rectangles.
 cases := [
  [[3,5,11,13],[7,9,15,17]],
  [[3,5,11,13],[7,9,15,17]],
  [[3,5,11,13],[7,9,15,17]],
  [[5,5,21,13],[13,9,29,17]],
  [[3,5,9,11]],
  [[5,8,11,13],[7,9,13,16]],
  [[7,5,15,13],[11,9,19,17]],
  [[7,5,19,21]],
  [][]int{},
  [[15,5,23,13],[11,9,19,17]],
  [[5,6,13,14],[9,10,17,18]],
  [[4,7,10,13],[7,9,10,15]],
  [[3,5,11,13],[7,9,15,17]],
 ]
 for index, rects in cases {
  mut body := 'invoke-static {}, ${probe}->create()${node}\nmove-result-object v0\nconst/4 v1, 3\nconst/4 v2, 5\nconst/16 v3, 19\nconst/16 v4, 21\ninvoke-virtual {v0, v1, v2, v3, v4}, ${node}->setPosition(IIII)Z\n'
  if index in [1, 2] { body += 'const/high16 v1, 0x3f000000\ninvoke-virtual {v0, v1}, ${node}->setAlpha(F)Z\n' }
  if index == 2 {
   body += 'new-instance v1, Landroid/graphics/Paint;\ninvoke-direct {v1}, Landroid/graphics/Paint;-><init>()V\nconst/16 v2, 128\ninvoke-virtual {v1, v2}, Landroid/graphics/Paint;->setAlpha(I)V\nconst/4 v2, 1\ninvoke-virtual {v0, v2, v1}, ${node}->setUseCompositingLayer(ZLandroid/graphics/Paint;)Z\nconst/4 v2, 0\ninvoke-virtual {v1, v2}, Landroid/graphics/Paint;->setAlpha(I)V\n'
  }
  if index in [3, 9] {
   body += 'const/4 v1, 0\ninvoke-virtual {v0, v1}, ${node}->setPivotX(F)Z\ninvoke-virtual {v0, v1}, ${node}->setPivotY(F)Z\n'
   body += if index == 3 { 'const/high16 v1, 0x40000000\ninvoke-virtual {v0, v1}, ${node}->setScaleX(F)Z\ninvoke-virtual {v0, v1}, ${node}->setTranslationX(F)Z\n' } else { 'const/high16 v1, 0x42b40000\ninvoke-virtual {v0, v1}, ${node}->setRotationZ(F)Z\nconst/high16 v1, 0x41a00000\ninvoke-virtual {v0, v1}, ${node}->setTranslationX(F)Z\n' }
  }
  if index == 4 { body += 'const/16 v1, 9\ninvoke-virtual {v0, v1}, ${node}->setRight(I)Z\nconst/16 v1, 11\ninvoke-virtual {v0, v1}, ${node}->setBottom(I)Z\n' }
  if index == 5 { body += 'new-instance v1, Landroid/graphics/Outline;\ninvoke-direct {v1}, Landroid/graphics/Outline;-><init>()V\nconst/4 v2, 2\nconst/4 v3, 3\nconst/16 v4, 10\nconst/16 v5, 11\ninvoke-virtual {v1, v2, v3, v4, v5}, Landroid/graphics/Outline;->setRect(IIII)V\ninvoke-virtual {v0, v1}, ${node}->setOutline(Landroid/graphics/Outline;)Z\ninvoke-virtual {v1}, Landroid/graphics/Outline;->setEmpty()V\nconst/4 v1, 1\ninvoke-virtual {v0, v1}, ${node}->setClipToOutline(Z)Z\n' }
  if index == 11 { body += 'new-instance v1, Landroid/graphics/Rect;\nconst/4 v2, 1\nconst/4 v3, 2\nconst/4 v4, 7\nconst/16 v5, 10\ninvoke-direct {v1, v2, v3, v4, v5}, Landroid/graphics/Rect;-><init>(IIII)V\ninvoke-virtual {v0, v1}, ${node}->setClipRect(Landroid/graphics/Rect;)Z\ninvoke-virtual {v1}, Landroid/graphics/Rect;->setEmpty()V\n' }
  if index == 12 { body += 'const/16 v1, 9\ninvoke-virtual {v0, v1}, ${node}->setRight(I)Z\nconst/16 v1, 11\ninvoke-virtual {v0, v1}, ${node}->setBottom(I)Z\nconst/4 v1, 0\ninvoke-virtual {v0, v1}, ${node}->setClipToBounds(Z)Z\n' }
  if index in [6, 7, 8] {
   body += 'invoke-static {}, ${probe}->create()${node}\nmove-result-object v6\ninvoke-virtual {v0}, ${node}->beginRecording()Landroid/graphics/RecordingCanvas;\nmove-result-object v1\ninvoke-virtual {v1, v6}, ${canvas}->drawRenderNode(${node})V\ninvoke-virtual {v0}, ${node}->endRecording()V\nconst/high16 v1, 0x40800000\ninvoke-virtual {v6, v1}, ${node}->setTranslationX(F)Z\n'
   if index == 7 { body += 'invoke-virtual {v6}, ${node}->beginRecording()Landroid/graphics/RecordingCanvas;\nmove-result-object v1\nconst v2, -0xffff01\ninvoke-virtual {v1, v2}, ${canvas}->drawColor(I)V\ninvoke-virtual {v6}, ${node}->endRecording()V\n' }
   if index == 8 { body += 'invoke-virtual {v6}, ${node}->discardDisplayList()V\n' }
  }
  body += 'const/16 v1, 32\nsget-object v2, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;\ninvoke-static {v1, v1, v2}, ${bitmap}->createBitmap(IILandroid/graphics/Bitmap$Config;)${bitmap}\nmove-result-object v1\nconst/4 v2, 0\ninvoke-virtual {v1, v2}, ${bitmap}->eraseColor(I)V\nnew-instance v2, ${canvas}\ninvoke-direct {v2, v1}, ${canvas}-><init>(${bitmap})V\n'
  if index == 10 { body += 'const/high16 v3, 0x40000000\nconst/high16 v4, 0x3f800000\ninvoke-virtual {v2, v3, v4}, ${canvas}->translate(FF)V\nconst/4 v3, 0\nconst/16 v4, 20\ninvoke-virtual {v2, v3, v3, v4, v4}, ${canvas}->clipRect(IIII)Z\n' }
  body += 'invoke-virtual {v2}, ${canvas}->getSaveCount()I\nmove-result v7\ninvoke-virtual {v2}, ${canvas}->getMatrix()Landroid/graphics/Matrix;\nmove-result-object v8\ninvoke-virtual {v2, v0}, ${canvas}->drawRenderNode(${node})V\ninvoke-virtual {v2}, ${canvas}->getSaveCount()I\nmove-result v3\nif-ne v3, v7, :bad\ninvoke-virtual {v2}, ${canvas}->getMatrix()Landroid/graphics/Matrix;\nmove-result-object v3\ninvoke-static {v8, v3}, Lorg/vinix/bootstrap/RenderNodeProbe;->sameMatrix(Landroid/graphics/Matrix;Landroid/graphics/Matrix;)Z\nmove-result v3\nif-eqz v3, :bad\nconst/4 v2, 0\n:y\nconst/16 v3, 32\nif-ge v2, v3, :done\nconst/4 v3, 0\n:x\nconst/16 v4, 32\nif-ge v3, v4, :next_y\nconst/4 v4, 0\n'
  color := match index { 1 { '0x80ff0000' } 2 { '0x40ff0000' } 7 { '-0xffff01' } else { '-0x10000' } }
  for ri, rect in rects {
   body += 'const/16 v5, ${rect[0]}\nif-lt v3, v5, :rect${ri}\nconst/16 v5, ${rect[2]}\nif-ge v3, v5, :rect${ri}\nconst/16 v5, ${rect[1]}\nif-lt v2, v5, :rect${ri}\nconst/16 v5, ${rect[3]}\nif-ge v2, v5, :rect${ri}\nconst v4, ${color}\ngoto :pixel\n:rect${ri}\n'
  }
  body += ':pixel\ninvoke-static {v1, v3, v2, v4}, ${probe}->pixel(${bitmap}III)V\nadd-int/lit8 v3, v3, 1\ngoto :x\n:next_y\nadd-int/lit8 v2, v2, 1\ngoto :y\n:done\ninvoke-virtual {v1}, ${bitmap}->recycle()V\nreturn-void'
  text += method('private static pixels${index}()V', body + bad)
 }
 text += method('private static pixel(${bitmap}III)V', 'move-object v0, p0\nconst/4 v2, 1\nnew-array v1, v2, [I\nconst/4 v2, 0\nconst/4 v3, 1\nmove v4, p1\nmove v5, p2\nconst/4 v6, 1\nconst/4 v7, 1\ninvoke-virtual/range {v0 .. v7}, ${bitmap}->getPixels([IIIIIII)V\nconst/4 v2, 0\naget v1, v1, v2\nif-eq v1, p3, :ok\nsget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\ninvoke-virtual {v0, p1}, Ljava/io/PrintStream;->println(I)V\ninvoke-virtual {v0, p2}, Ljava/io/PrintStream;->println(I)V\ninvoke-virtual {v0, p3}, Ljava/io/PrintStream;->println(I)V\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(I)V\ngoto :bad\n:ok\nreturn-void' + bad)
 mut check := 'invoke-static {p0}, ${probe}->state(Landroid/content/Context;)V\ninvoke-static {}, ${probe}->failure()V\n'
 for index in 0..cases.len { check += 'invoke-static {}, ${probe}->pixels${index}()V\n' }
 check += 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-RENDER-NODE-PASS recording-state stable-identity 13312-pixels paint-snapshot transforms bounds clip-rect outline group-alpha live-child replace discard canvas-state cycle-recovery"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void'
 text += method('public static check(Landroid/content/Context;)V', check)
 text += method('private static state(Landroid/content/Context;)V', render_node_state_checks() + bad)
 text += method('private static failure()V', render_node_failure_checks() + bad)
 text += method('private static sameMatrix(Landroid/graphics/Matrix;Landroid/graphics/Matrix;)Z', 'const/16 v0, 9\nnew-array v1, v0, [F\nnew-array v2, v0, [F\ninvoke-virtual {p0, v1}, Landroid/graphics/Matrix;->getValues([F)V\ninvoke-virtual {p1, v2}, Landroid/graphics/Matrix;->getValues([F)V\ninvoke-static {v1, v2}, Ljava/util/Arrays;->equals([F[F)Z\nmove-result v0\nreturn v0')
 os.write_file(dir + '/RenderNodeProbe.smali', text)!
}

fn render_node_failure_checks() string {
 mut text := ''
 for mode in 0..2 {
  text += 'invoke-static {}, Lorg/vinix/bootstrap/RenderNodeProbe;->create()Landroid/graphics/RenderNode;\nmove-result-object v0\n'
  if mode == 1 { text += 'const/high16 v1, 0x3f000000\ninvoke-virtual {v0, v1}, Landroid/graphics/RenderNode;->setAlpha(F)Z\n' }
  text += 'invoke-virtual {v0}, Landroid/graphics/RenderNode;->beginRecording()Landroid/graphics/RecordingCanvas;\nmove-result-object v1\ninvoke-virtual {v1, v0}, Landroid/graphics/Canvas;->drawRenderNode(Landroid/graphics/RenderNode;)V\ninvoke-virtual {v0}, Landroid/graphics/RenderNode;->endRecording()V\nconst/16 v1, 32\nsget-object v2, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;\ninvoke-static {v1, v1, v2}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;\nmove-result-object v1\nconst/4 v2, 0\ninvoke-virtual {v1, v2}, Landroid/graphics/Bitmap;->eraseColor(I)V\nnew-instance v2, Landroid/graphics/Canvas;\ninvoke-direct {v2, v1}, Landroid/graphics/Canvas;-><init>(Landroid/graphics/Bitmap;)V\nconst/high16 v3, 0x40000000\nconst/high16 v4, 0x3f800000\ninvoke-virtual {v2, v3, v4}, Landroid/graphics/Canvas;->translate(FF)V\ninvoke-virtual {v2}, Landroid/graphics/Canvas;->getSaveCount()I\nmove-result v6\ninvoke-virtual {v2}, Landroid/graphics/Canvas;->getMatrix()Landroid/graphics/Matrix;\nmove-result-object v7\n:cycle${mode}\ninvoke-virtual {v2, v0}, Landroid/graphics/Canvas;->drawRenderNode(Landroid/graphics/RenderNode;)V\n:cycle_end${mode}\ngoto :bad\n.catch Ljava/lang/IllegalStateException; {:cycle${mode} .. :cycle_end${mode}} :expected${mode}\n:expected${mode}\nmove-exception v3\ninvoke-virtual {v2}, Landroid/graphics/Canvas;->getSaveCount()I\nmove-result v3\nif-ne v3, v6, :bad\ninvoke-virtual {v2}, Landroid/graphics/Canvas;->getMatrix()Landroid/graphics/Matrix;\nmove-result-object v3\ninvoke-static {v7, v3}, Lorg/vinix/bootstrap/RenderNodeProbe;->sameMatrix(Landroid/graphics/Matrix;Landroid/graphics/Matrix;)Z\nmove-result v3\nif-eqz v3, :bad\ninvoke-virtual {v0}, Landroid/graphics/RenderNode;->beginRecording()Landroid/graphics/RecordingCanvas;\nmove-result-object v3\nconst v4, -0x10000\ninvoke-static {v3, v4}, Lorg/vinix/bootstrap/RenderNodeProbe;->rectangle(Landroid/graphics/Canvas;I)V\ninvoke-virtual {v0}, Landroid/graphics/RenderNode;->endRecording()V\ninvoke-virtual {v2, v0}, Landroid/graphics/Canvas;->drawRenderNode(Landroid/graphics/RenderNode;)V\nconst/4 v3, 2\nconst/4 v4, 1\nconst v5, ' + if mode == 0 { '-0x10000' } else { '0x80ff0000' } + '\ninvoke-static {v1, v3, v4, v5}, Lorg/vinix/bootstrap/RenderNodeProbe;->pixel(Landroid/graphics/Bitmap;III)V\ninvoke-virtual {v1}, Landroid/graphics/Bitmap;->recycle()V\n'
 }
 return text + 'return-void'
}

fn render_node_state_checks() string {
 return '
new-instance v0, Landroid/graphics/RenderNode;
const/4 v1, 0
invoke-direct {v0, v1}, Landroid/graphics/RenderNode;-><init>(Ljava/lang/String;)V
invoke-virtual {v0}, Landroid/graphics/RenderNode;->hasDisplayList()Z
move-result v1
if-nez v1, :bad
invoke-virtual {v0}, Landroid/graphics/RenderNode;->getUniqueId()J
move-result-wide v2
new-instance v1, Landroid/view/View;
invoke-direct {v1, p0}, Landroid/view/View;-><init>(Landroid/content/Context;)V
invoke-virtual {v1}, Landroid/view/View;->getUniqueDrawingId()J
move-result-wide v4
cmp-long v1, v2, v4
if-eqz v1, :bad
const/4 v1, 0
const/16 v4, 16
invoke-virtual {v0, v1, v1, v4, v4}, Landroid/graphics/RenderNode;->setPosition(IIII)Z
move-result v1
if-eqz v1, :bad
const/4 v1, 0
invoke-virtual {v0, v1, v1, v4, v4}, Landroid/graphics/RenderNode;->setPosition(IIII)Z
move-result v1
if-nez v1, :bad
invoke-virtual {v0}, Landroid/graphics/RenderNode;->getPivotX()F
move-result v1
const/high16 v4, 0x41000000
cmpl-float v1, v1, v4
if-nez v1, :bad
:no_recording
invoke-virtual {v0}, Landroid/graphics/RenderNode;->endRecording()V
:no_recording_end
goto :bad
.catch Ljava/lang/IllegalStateException; {:no_recording .. :no_recording_end} :expected_end
:expected_end
move-exception v1
const/4 v1, 4
invoke-virtual {v0, v1, v1}, Landroid/graphics/RenderNode;->beginRecording(II)Landroid/graphics/RecordingCanvas;
move-result-object v1
invoke-virtual {v1}, Landroid/graphics/Canvas;->isHardwareAccelerated()Z
move-result v4
if-eqz v4, :bad
invoke-virtual {v0}, Landroid/graphics/RenderNode;->getWidth()I
move-result v4
const/16 v5, 16
if-ne v4, v5, :bad
:nested
invoke-virtual {v0}, Landroid/graphics/RenderNode;->beginRecording()Landroid/graphics/RecordingCanvas;
:nested_end
goto :bad
.catch Ljava/lang/IllegalStateException; {:nested .. :nested_end} :expected_begin
:expected_begin
move-exception v4
invoke-virtual {v0}, Landroid/graphics/RenderNode;->endRecording()V
invoke-virtual {v0}, Landroid/graphics/RenderNode;->hasDisplayList()Z
move-result v4
if-eqz v4, :bad
:stale
const/4 v4, 0
invoke-virtual {v1, v4}, Landroid/graphics/Canvas;->drawColor(I)V
:stale_end
goto :bad
.catch Ljava/lang/IllegalStateException; {:stale .. :stale_end} :expected_stale
:expected_stale
move-exception v1
invoke-virtual {v0}, Landroid/graphics/RenderNode;->discardDisplayList()V
invoke-virtual {v0}, Landroid/graphics/RenderNode;->hasDisplayList()Z
move-result v1
if-nez v1, :bad
invoke-virtual {v0}, Landroid/graphics/RenderNode;->getUniqueId()J
move-result-wide v4
cmp-long v1, v2, v4
if-nez v1, :bad
return-void'
}
