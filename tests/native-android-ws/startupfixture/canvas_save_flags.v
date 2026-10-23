// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_canvas_save_flags_probe(dir string) ! {
	probe := 'Lorg/vinix/bootstrap/CanvasSaveFlagsProbe;'
	forward := 'Lorg/vinix/bootstrap/SaveLayerForwardCanvas;'
	canvas := 'Landroid/graphics/Canvas;'
	paint := 'Landroid/graphics/Paint;'
	bitmap := 'Landroid/graphics/Bitmap;'
	bad := ':bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "Canvas saveLayer flags forwarding or saved state"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
	mut text := '.class public ${probe}\n.super Ljava/lang/Object;\n'
	mut check := 'new-instance v8, ${paint}\ninvoke-direct {v8}, ${paint}-><init>()V\nnew-instance v9, ${forward}\ninvoke-direct {v9}, ${forward}-><init>()V\n'
	// Flags are intentionally ignored by this compatibility wrapper. These cases
	// check forwarding only; native state/playback below uses the normal mask 31.
	for i, flags in [0, 31, -1] {
		result := [37, -2147483647, -1][i]
		check += 'move-object v0, v9\nconst v1, 0x80000000\nconst v2, 0xbf400000\nconst v3, 0x41220000\nconst v4, 0x7fc01234\n'
		check += if i == 1 { 'const/4 v5, 0\n' } else { 'move-object v5, v8\n' }
		check += 'iput-object v5, v9, ${forward}->expectedPaint:${paint}\nconst v6, ${flags}\nconst v7, ${result}\niput v7, v9, ${forward}->result:I\ninvoke-virtual/range {v0 .. v6}, ${canvas}->saveLayer(FFFF${paint}I)I\nmove-result v0\nif-ne v0, v7, :bad\niget v0, v9, ${forward}->calls:I\nconst/4 v1, ${i + 1}\nif-ne v0, v1, :bad\n'
	}
	for mode in 0 .. 3 {
		check += 'const/16 v0, 8\nsget-object v1, Landroid/graphics/Bitmap\$Config;->ARGB_8888:Landroid/graphics/Bitmap\$Config;\ninvoke-static {v0, v0, v1}, ${bitmap}->createBitmap(IILandroid/graphics/Bitmap\$Config;)${bitmap}\nmove-result-object v8\nconst/4 v0, 0\ninvoke-virtual {v8, v0}, ${bitmap}->eraseColor(I)V\nnew-instance v9, ${canvas}\ninvoke-direct {v9, v8}, ${canvas}-><init>(${bitmap})V\n'
		if mode == 0 {
			check += 'invoke-static {v9}, ${probe}->state(${canvas})V\n'
		} else if mode == 1 {
			check += 'new-instance v7, Landroid/graphics/Picture;\ninvoke-direct {v7}, Landroid/graphics/Picture;-><init>()V\nconst/16 v0, 8\ninvoke-virtual {v7, v0, v0}, Landroid/graphics/Picture;->beginRecording(II)${canvas}\nmove-result-object v0\ninvoke-static {v0}, ${probe}->state(${canvas})V\ninvoke-virtual {v7}, Landroid/graphics/Picture;->endRecording()V\ninvoke-virtual {v9, v7}, ${canvas}->drawPicture(Landroid/graphics/Picture;)V\n'
		} else {
			check += 'new-instance v7, Landroid/graphics/RenderNode;\nconst-string v0, "saveLayer flags inherited API"\ninvoke-direct {v7, v0}, Landroid/graphics/RenderNode;-><init>(Ljava/lang/String;)V\nconst/4 v0, 0\nconst/16 v1, 8\ninvoke-virtual {v7, v0, v0, v1, v1}, Landroid/graphics/RenderNode;->setPosition(IIII)Z\ninvoke-virtual {v7}, Landroid/graphics/RenderNode;->beginRecording()Landroid/graphics/RecordingCanvas;\nmove-result-object v0\ninvoke-static {v0}, ${probe}->state(${canvas})V\ninvoke-virtual {v7}, Landroid/graphics/RenderNode;->endRecording()V\ninvoke-virtual {v9, v7}, ${canvas}->drawRenderNode(Landroid/graphics/RenderNode;)V\n'
		}
		check += 'invoke-static {v8}, ${probe}->pixels(${bitmap})V\ninvoke-virtual {v8}, ${bitmap}->recycle()V\n'
	}
	check += 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-CANVAS-SAVE-FLAGS-PASS exact-float-bits paint-null virtual-forward return flags-ignored nested-depth transforms clip-restore bitmap Picture RecordingCanvas 192-pixels"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void\n' + bad
	text += method('public static check()V', check)
	mut state := 'move-object v8, p0\ninvoke-virtual {v8}, ${canvas}->getSaveCount()I\nmove-result v0\nconst/4 v1, 1\nif-ne v0, v1, :bad\ninvoke-virtual {v8}, ${canvas}->save()I\nmove-result v0\nif-ne v0, v1, :bad\nconst/high16 v0, 0x3f800000\ninvoke-virtual {v8, v0, v0}, ${canvas}->translate(FF)V\nconst/4 v0, 0\nconst/4 v1, 6\ninvoke-virtual {v8, v0, v0, v1, v1}, ${canvas}->clipRect(IIII)Z\nmove-result v0\nif-eqz v0, :bad\n'
	for i in 0 .. 2 {
		state += 'move-object v0, v8\nconst/4 v1, 0\nconst/4 v2, 0\nconst/high16 v3, 0x41000000\nconst/high16 v4, 0x41000000\nconst/4 v5, 0\nconst/16 v6, 31\ninvoke-virtual/range {v0 .. v6}, ${canvas}->saveLayer(FFFF${paint}I)I\nmove-result v0\nconst/4 v1, ${i + 2}\nif-ne v0, v1, :bad\n'
		if i == 0 {
			state += 'move v7, v0\nconst/high16 v0, 0x40000000\nconst/high16 v1, 0x3f800000\ninvoke-virtual {v8, v0, v1}, ${canvas}->translate(FF)V\nconst/4 v0, 0\nconst/4 v1, 2\ninvoke-virtual {v8, v0, v0, v1, v1}, ${canvas}->clipRect(IIII)Z\nconst v0, 0xffff0000\ninvoke-virtual {v8, v0}, ${canvas}->drawColor(I)V\n'
		} else {
			state += 'const/high16 v0, 0x40800000\ninvoke-virtual {v8, v0, v0}, ${canvas}->translate(FF)V\ninvoke-virtual {v8}, ${canvas}->getSaveCount()I\nmove-result v0\nconst/4 v1, 4\nif-ne v0, v1, :bad\n'
		}
	}
	state += 'invoke-virtual {v8, v7}, ${canvas}->restoreToCount(I)V\ninvoke-virtual {v8}, ${canvas}->getSaveCount()I\nmove-result v0\nconst/4 v1, 2\nif-ne v0, v1, :bad\nnew-instance v9, ${paint}\ninvoke-direct {v9}, ${paint}-><init>()V\nconst v0, 0xff00ff00\ninvoke-virtual {v9, v0}, ${paint}->setColor(I)V\n'
	state += 'move-object v0, v8\nconst/4 v1, 0\nconst/4 v2, 0\nconst/high16 v3, 0x3f800000\nconst/high16 v4, 0x3f800000\nmove-object v5, v9\ninvoke-virtual/range {v0 .. v5}, ${canvas}->drawRect(FFFF${paint})V\nconst/4 v0, 1\ninvoke-virtual {v8, v0}, ${canvas}->restoreToCount(I)V\ninvoke-virtual {v8}, ${canvas}->getSaveCount()I\nmove-result v0\nconst/4 v1, 1\nif-ne v0, v1, :bad\nconst v0, 0xff0000ff\ninvoke-virtual {v9, v0}, ${paint}->setColor(I)V\nmove-object v0, v8\nconst/4 v1, 0\nconst/4 v2, 0\nconst/high16 v3, 0x3f800000\nconst/high16 v4, 0x3f800000\nmove-object v5, v9\ninvoke-virtual/range {v0 .. v5}, ${canvas}->drawRect(FFFF${paint})V\nreturn-void\n' + bad
	text += method('private static state(${canvas})V', state)
	mut pixels := ''
	for y in 0 .. 8 {
		for x in 0 .. 8 {
			color := if x == 0 && y == 0 {
				'0xff0000ff'
			} else if x == 1 && y == 1 {
				'0xff00ff00'
			} else if x in [3, 4] && y in [2, 3] {
				'0xffff0000'
			} else {
				'0'
			}
			pixels += 'const/16 v0, ${x}\nconst/16 v1, ${y}\nconst v2, ${color}\ninvoke-static {p0, v0, v1, v2}, ${probe}->pixel(${bitmap}III)V\n'
		}
	}
	text += method('private static pixels(${bitmap})V', pixels + 'return-void')
	text += method('private static pixel(${bitmap}III)V', 'move-object v0, p0\nconst/4 v2, 1\nnew-array v1, v2, [I\nconst/4 v2, 0\nconst/4 v3, 1\nmove v4, p1\nmove v5, p2\nconst/4 v6, 1\nconst/4 v7, 1\ninvoke-virtual/range {v0 .. v7}, ${bitmap}->getPixels([IIIIIII)V\nconst/4 v2, 0\naget v1, v1, v2\nif-ne v1, p3, :bad\nreturn-void\n' + bad)
	os.write_file(dir + '/CanvasSaveFlagsProbe.smali', text)!
	mut override := 'iget v0, p0, ${forward}->calls:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, ${forward}->calls:I\n'
	for i, bits in ['0x80000000', '0xbf400000', '0x41220000', '0x7fc01234'] {
		override += 'invoke-static {p${i + 1}}, Ljava/lang/Float;->floatToRawIntBits(F)I\nmove-result v0\nconst v1, ${bits}\nif-ne v0, v1, :bad\n'
	}
	override += 'iget-object v0, p0, ${forward}->expectedPaint:${paint}\nif-ne v0, p5, :bad\niget v0, p0, ${forward}->result:I\nreturn v0\n' + bad
	os.write_file(dir + '/SaveLayerForwardCanvas.smali', '.class public ${forward}\n.super ${canvas}\n.field public expectedPaint:${paint}\n.field public calls:I\n.field public result:I\n.method public constructor <init>()V\n.locals 0\ninvoke-direct {p0}, ${canvas}-><init>()V\nreturn-void\n.end method\n' + method('public saveLayer(FFFF${paint})I', override).replace('.locals 10', '.locals 2'))!
}
