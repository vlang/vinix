// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_layout_canvas_probe(dir string) ! {
 probe := 'Lorg/vinix/bootstrap/LayoutCanvasProbe;'
 spy := 'Lorg/vinix/bootstrap/LayoutProbeCanvas;'
 paint := 'Landroid/text/TextPaint;'
 layout := 'Landroid/text/Layout;'
 canvas := 'Landroid/graphics/Canvas;'
 bitmap := 'Landroid/graphics/Bitmap;'
 bad := '\n:bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "Layout custom canvas text, baseline or pixels"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
 mut text := '.class public ${probe}\n.super Ljava/lang/Object;\n'
 text += method('private static paint()${paint}', 'new-instance v0, ${paint}\ninvoke-direct {v0}, ${paint}-><init>()V\nconst v1, -0x10000\ninvoke-virtual {v0, v1}, Landroid/graphics/Paint;->setColor(I)V\nconst/high16 v1, 0x41800000\ninvoke-virtual {v0, v1}, Landroid/graphics/Paint;->setTextSize(F)V\nreturn-object v0')
 text += method('private static layout(Ljava/lang/String;${paint}I)${layout}', 'new-instance v0, Landroid/text/StaticLayout;\nmove-object v1, p0\nmove-object v2, p1\nmove v3, p2\nsget-object v4, Landroid/text/Layout$Alignment;->ALIGN_NORMAL:Landroid/text/Layout$Alignment;\nconst/high16 v5, 0x3f800000\nconst/4 v6, 0\nconst/4 v7, 0\ninvoke-direct/range {v0 .. v7}, Landroid/text/StaticLayout;-><init>(Ljava/lang/CharSequence;${paint}ILandroid/text/Layout$Alignment;FFZ)V\nreturn-object v0')
 text += method('private static bitmap()${bitmap}', 'const/16 v0, 64\nsget-object v1, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;\ninvoke-static {v0, v0, v1}, ${bitmap}->createBitmap(IILandroid/graphics/Bitmap$Config;)${bitmap}\nmove-result-object v0\nconst/4 v1, 0\ninvoke-virtual {v0, v1}, ${bitmap}->eraseColor(I)V\nreturn-object v0')
 // Both source strings and baselines are independent of Layout's getters.
 mut calls := 'invoke-static {}, ${probe}->paint()${paint}\nmove-result-object v7\n'
 for i, source in ['A\\ud83d\\ude00\\nB\\n', 'AAAA', '\\n\\n', ''] {
  expected := if i == 0 { 2 } else if i == 1 { 4 } else { 0 }
  calls += 'const-string v0, "${source}"\nconst/16 v1, ' + if i == 1 { '1' } else { '64' } + '\ninvoke-static {v0, v7, v1}, ${probe}->layout(Ljava/lang/String;${paint}I)${layout}\nmove-result-object v0\nnew-instance v1, ${spy}\ninvoke-direct {v1}, ${spy}-><init>()V\nconst/4 v2, ' + if i == 1 { '1' } else { '0' } + '\niput-boolean v2, v1, ${spy}->wrapped:Z\ninvoke-virtual {v0, v1}, ${layout}->draw(${canvas})V\niget v2, v1, ${spy}->calls:I\nconst/4 v3, ${expected}\nif-ne v2, v3, :bad\n'
 }
 text += method('private static calls()V', calls + 'return-void' + bad)
 mut custom := '.class public ${spy}\n.super ${canvas}\n.field public calls:I\n.field public wrapped:Z\n'
 custom += method('public constructor <init>()V', 'invoke-direct {p0}, ${canvas}-><init>()V\nreturn-void')
 custom += method('public drawText(Ljava/lang/String;FFLandroid/graphics/Paint;)V', '
iget v0, p0, ${spy}->calls:I
iget-boolean v1, p0, ${spy}->wrapped:Z
if-eqz v1, :multiline
const-string v1, "A"
goto :compare
:multiline
if-nez v0, :second
const-string v1, "A\\ud83d\\ude00"
goto :compare
:second
const-string v1, "B"
:compare
invoke-virtual {v1, p1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :bad
const/4 v1, 0
cmpl-float v1, p2, v1
if-nez v1, :bad
mul-int/lit8 v1, v0, 20
add-int/lit8 v1, v1, 16
int-to-float v1, v1
cmpl-float v1, p3, v1
if-nez v1, :bad
invoke-virtual {p4}, Landroid/graphics/Paint;->getColor()I
move-result v1
const v2, -0x10000
if-ne v1, v2, :bad
add-int/lit8 v0, v0, 1
iput v0, p0, ${spy}->calls:I
return-void' + bad)
 os.write_file(dir + '/LayoutProbeCanvas.smali', custom)!
 for mode in 0..3 {
  mut body := 'invoke-static {}, ${probe}->paint()${paint}\nmove-result-object v7\nconst-string v0, "A\\nB"\nconst/16 v2, 64\ninvoke-static {v0, v7, v2}, ${probe}->layout(Ljava/lang/String;${paint}I)${layout}\nmove-result-object v8\n'
  if mode < 2 {
   body += 'new-instance v9, Landroid/graphics/Picture;\ninvoke-direct {v9}, Landroid/graphics/Picture;-><init>()V\ninvoke-virtual {v9, v2, v2}, Landroid/graphics/Picture;->beginRecording(II)${canvas}\nmove-result-object v0\ninvoke-virtual {v8, v0}, ${layout}->draw(${canvas})V\ninvoke-virtual {v9}, Landroid/graphics/Picture;->endRecording()V\n'
  } else {
   body += 'new-instance v9, Landroid/graphics/RenderNode;\nconst-string v0, "text"\ninvoke-direct {v9, v0}, Landroid/graphics/RenderNode;-><init>(Ljava/lang/String;)V\nconst/4 v0, 0\ninvoke-virtual {v9, v0, v0, v2, v2}, Landroid/graphics/RenderNode;->setPosition(IIII)Z\ninvoke-virtual {v9}, Landroid/graphics/RenderNode;->beginRecording()Landroid/graphics/RecordingCanvas;\nmove-result-object v0\ninvoke-virtual {v8, v0}, ${layout}->draw(${canvas})V\ninvoke-virtual {v9}, Landroid/graphics/RenderNode;->endRecording()V\n'
  }
  body += 'const v0, -0xffff01\ninvoke-virtual {v7, v0}, Landroid/graphics/Paint;->setColor(I)V\nconst/high16 v0, 0x42000000\ninvoke-virtual {v7, v0}, Landroid/graphics/Paint;->setTextSize(F)V\ninvoke-static {}, ${probe}->bitmap()${bitmap}\nmove-result-object v5\nnew-instance v0, ${canvas}\ninvoke-direct {v0, v5}, ${canvas}-><init>(${bitmap})V\n'
  transform := if mode == 0 { '' } else { 'const/high16 v1, 0x40400000\nconst/high16 v2, 0x40800000\ninvoke-virtual {v0, v1, v2}, ${canvas}->translate(FF)V\nconst/4 v1, 0\nconst/16 v2, 20\nconst/16 v3, 50\ninvoke-virtual {v0, v1, v1, v2, v3}, ${canvas}->clipRect(IIII)Z\n' }
  body += transform
  body += if mode < 2 { 'invoke-virtual {v0, v9}, ${canvas}->drawPicture(Landroid/graphics/Picture;)V\n' } else { 'invoke-virtual {v0, v9}, ${canvas}->drawRenderNode(Landroid/graphics/RenderNode;)V\n' }
  body += 'invoke-static {}, ${probe}->bitmap()${bitmap}\nmove-result-object v6\nnew-instance v0, ${canvas}\ninvoke-direct {v0, v6}, ${canvas}-><init>(${bitmap})V\n' + transform + 'invoke-static {}, ${probe}->paint()${paint}\nmove-result-object v4\nconst-string v1, "A"\nconst/4 v2, 0\nconst/high16 v3, 0x41800000\ninvoke-virtual {v0, v1, v2, v3, v4}, ${canvas}->drawText(Ljava/lang/String;FFLandroid/graphics/Paint;)V\nconst-string v1, "B"\nconst/high16 v3, 0x42100000\ninvoke-virtual {v0, v1, v2, v3, v4}, ${canvas}->drawText(Ljava/lang/String;FFLandroid/graphics/Paint;)V\ninvoke-static {v5, v6}, ${probe}->compare(${bitmap}${bitmap})V\ninvoke-virtual {v5}, ${bitmap}->recycle()V\ninvoke-virtual {v6}, ${bitmap}->recycle()V\nreturn-void'
  text += method('private static pixels${mode}()V', body)
 }
 text += method('private static pixels(${bitmap})[I', 'move-object v0, p0\nconst/16 v1, 4096\nnew-array v1, v1, [I\nconst/4 v2, 0\nconst/16 v3, 64\nconst/4 v4, 0\nconst/4 v5, 0\nconst/16 v6, 64\nconst/16 v7, 64\ninvoke-virtual/range {v0 .. v7}, ${bitmap}->getPixels([IIIIIII)V\nreturn-object v1')
 text += method('private static compare(${bitmap}${bitmap})V', 'invoke-static {p0}, ${probe}->pixels(${bitmap})[I\nmove-result-object v0\ninvoke-static {p1}, ${probe}->pixels(${bitmap})[I\nmove-result-object v1\ninvoke-static {v0, v1}, Ljava/util/Arrays;->equals([I[I)Z\nmove-result v2\nif-eqz v2, :bad\nconst/4 v2, 0\nconst/4 v3, 0\n:pixel\nconst/16 v4, 4096\nif-ge v2, v4, :count\naget v4, v0, v2\nif-eqz v4, :next\nadd-int/lit8 v3, v3, 1\n:next\nadd-int/lit8 v2, v2, 1\ngoto :pixel\n:count\nif-lez v3, :bad\nreturn-void' + bad)
 text += method('public static check()V', 'invoke-static {}, ${probe}->calls()V\ninvoke-static {}, ${probe}->pixels0()V\ninvoke-static {}, ${probe}->pixels1()V\ninvoke-static {}, ${probe}->pixels2()V\nsget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-LAYOUT-CANVAS-PASS virtual-text utf16 multiline wrap empty baselines 12288-pixels picture render-node paint-snapshot target transform clip"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void')
 os.write_file(dir + '/LayoutCanvasProbe.smali', text)!
}
