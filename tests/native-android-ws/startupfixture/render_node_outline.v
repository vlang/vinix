// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_render_node_outline_probe(dir string) ! {
	probe := 'Lorg/vinix/bootstrap/RenderNodeOutlineProbe;'
	node := 'Landroid/graphics/RenderNode;'
	canvas := 'Landroid/graphics/Canvas;'
	bitmap := 'Landroid/graphics/Bitmap;'
	outline := 'Landroid/graphics/Outline;'
	path := 'Landroid/graphics/Path;'
	bad := '\n:bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "Outline/path clipping pixels or saved state"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
	mut text := '.class public ${probe}\n.super Ljava/lang/Object;\n'
	text += method('private static create()${node}', '
new-instance v0, ${node}
const-string v1, "outline pixels"
invoke-direct {v0, v1}, ${node}-><init>(Ljava/lang/String;)V
const/4 v1, 0
const/16 v2, 8
invoke-virtual {v0, v1, v1, v2, v2}, ${node}->setPosition(IIII)Z
invoke-virtual {v0}, ${node}->beginRecording()Landroid/graphics/RecordingCanvas;
move-result-object v1
const v2, 0xffff0000
invoke-virtual {v1, v2}, ${canvas}->drawColor(I)V
invoke-virtual {v0}, ${node}->endRecording()V
return-object v0')
	for index in 0 .. 10 {
		mut body := 'invoke-static {}, ${probe}->create()${node}\nmove-result-object v8\nconst/4 v0, 2\nconst/4 v1, 3\nconst/16 v2, 10\nconst/16 v3, 11\ninvoke-virtual {v8, v0, v1, v2, v3}, ${node}->setPosition(IIII)Z\nnew-instance v6, ${outline}\ninvoke-direct {v6}, ${outline}-><init>()V\n'
		if index == 1 || index == 9 {
			body += outline_probe_triangle('v5')
			if index == 1 {
				body += 'invoke-virtual {v6, v5}, ${outline}->setPath(${path})V\ninvoke-virtual {v5}, ${path}->reset()V\n'
			} else {
				body += 'invoke-virtual {v8}, ${node}->beginRecording()Landroid/graphics/RecordingCanvas;\nmove-result-object v4\ninvoke-virtual {v4, v5}, ${canvas}->clipPath(${path})Z\ninvoke-virtual {v5}, ${path}->reset()V\nconst v0, 0xffff0000\ninvoke-virtual {v4, v0}, ${canvas}->drawColor(I)V\ninvoke-virtual {v8}, ${node}->endRecording()V\n'
			}
		} else if index == 7 {
			body += 'const/4 v0, 1\nconst/4 v1, 2\nconst/4 v2, 7\nconst/4 v3, 6\ninvoke-virtual {v6, v0, v1, v2, v3}, ${outline}->setRect(IIII)V\n'
		} else if index == 8 {
			body += 'const/4 v0, 0\nconst/16 v1, 8\nconst/4 v2, 6\ninvoke-virtual {v6, v0, v0, v1, v2}, ${outline}->setOval(IIII)V\n'
		} else if index != 5 {
			body += 'move-object v0, v6\nconst/4 v1, 0\nconst/4 v2, 0\nconst/16 v3, 8\nconst/16 v4, 8\nconst/high16 v5, 0x40400000\ninvoke-virtual/range {v0 .. v5}, ${outline}->setRoundRect(IIIIF)V\n'
		}
		if index == 6 || index == 9 {
			body += 'const/4 v6, 0\n'
		} else {
			// Outline alpha is an opacity hint and must not alter the clip.
			body += 'const/4 v0, 0\ninvoke-virtual {v6, v0}, ${outline}->setAlpha(F)V\n'
		}
		body += 'invoke-virtual {v8, v6}, ${node}->setOutline(${outline})Z\n'
		if index == 0 {
			// setOutline snapshots its input; changing it cannot change the node.
			body += 'invoke-virtual {v6}, ${outline}->setEmpty()V\n'
		}
		body += 'const/4 v0, ' + if index == 4 { '0' } else { '1' } + '\ninvoke-virtual {v8, v0}, ${node}->setClipToOutline(Z)Z\n'
		if index == 2 {
			body += 'const/high16 v0, 0x3f000000\ninvoke-virtual {v8, v0}, ${node}->setAlpha(F)Z\n'
		}
		if index == 3 {
			body += 'const/4 v0, 0\ninvoke-virtual {v8, v0}, ${node}->setPivotX(F)Z\ninvoke-virtual {v8, v0}, ${node}->setPivotY(F)Z\nconst/high16 v0, 0x40000000\ninvoke-virtual {v8, v0}, ${node}->setScaleX(F)Z\n'
		}
		body += outline_probe_target()
		if index == 3 {
			body += 'const/high16 v0, 0x3f800000\nconst/high16 v1, 0x40000000\ninvoke-virtual {v7, v0, v1}, ${canvas}->translate(FF)V\n'
		}
		body += 'invoke-virtual {v7}, ${canvas}->getMatrix()Landroid/graphics/Matrix;\nmove-result-object v6\ninvoke-virtual {v7, v8}, ${canvas}->drawRenderNode(${node})V\ninvoke-virtual {v7}, ${canvas}->getSaveCount()I\nmove-result v0\nconst/4 v1, 1\nif-ne v0, v1, :bad\ninvoke-virtual {v7}, ${canvas}->getMatrix()Landroid/graphics/Matrix;\nmove-result-object v0\ninvoke-static {v6, v0}, ${probe}->sameMatrix(Landroid/graphics/Matrix;Landroid/graphics/Matrix;)Z\nmove-result v0\nif-eqz v0, :bad\n'
		mut rows := []u32{len: 20}
		for y in 0 .. 20 {
			for x in 0 .. 20 {
				lx := (f32(x) + 0.5 - if index == 3 { f32(3) } else { f32(2) }) / if index == 3 {
					f32(2)
				} else {
					f32(1)
				}
				ly := f32(y) + 0.5 - if index == 3 { f32(5) } else { f32(3) }
				bounds := lx >= 0 && ly >= 0 && lx < 8 && ly < 8
				inside := match index {
					1, 9 { bounds && lx + ly < 8 }
					4, 6 { bounds }
					5 { false }
					7 { lx >= 1 && ly >= 2 && lx < 7 && ly < 6 }
					8 { (lx - 4) * (lx - 4) / 16 + (ly - 3) * (ly - 3) / 9 < 1 }
					else {
						cx := if lx < 3 {
							f32(3)
						} else if lx > 5 {
							f32(5)
						} else {
							lx
						}
						cy := if ly < 3 {
							f32(3)
						} else if ly > 5 {
							f32(5)
						} else {
							ly
						}
						bounds && (lx - cx) * (lx - cx) + (ly - cy) * (ly - cy) < 9
					}
				}
				if inside { rows[y] |= u32(1) << x }
			}
		}
		body += outline_probe_scan(rows, if index == 2 { '0x80ff0000' } else { '0xffff0000' })
		// A later draw outside the outline checks that the node restored its clip.
		body += 'const v0, 0xff0000ff\ninvoke-virtual {v7, v0}, ${canvas}->drawColor(I)V\nconst/16 v0, 19\nconst v1, 0xff0000ff\ninvoke-static {v9, v0, v0, v1}, ${probe}->pixel(${bitmap}III)V\ninvoke-virtual {v9}, ${bitmap}->recycle()V\nreturn-void'
		text += method('private static node${index}()V', body + bad)
	}
	for index, fill in ['WINDING', 'EVEN_ODD', 'INVERSE_WINDING', 'INVERSE_EVEN_ODD'] {
		mut body := outline_probe_target()
		body += 'invoke-virtual {v7}, ${canvas}->save()I\nnew-instance v6, ${path}\ninvoke-direct {v6}, ${path}-><init>()V\n'
		for rect in [[1, 1, 11, 11], [4, 4, 8, 8]] {
			body += 'move-object v0, v6\n'
			for i, coordinate in rect {
				body += 'const/16 v${i + 1}, ${coordinate}\nint-to-float v${i + 1}, v${i + 1}\n'
			}
			body += 'sget-object v5, Landroid/graphics/Path$Direction;->CW:Landroid/graphics/Path$Direction;\ninvoke-virtual/range {v0 .. v5}, ${path}->addRect(FFFFLandroid/graphics/Path$Direction;)V\n'
		}
		body += 'sget-object v0, Landroid/graphics/Path$FillType;->${fill}:Landroid/graphics/Path$FillType;\ninvoke-virtual {v6, v0}, ${path}->setFillType(Landroid/graphics/Path$FillType;)V\n'
		// More than 64 path intersections must not silently empty the clip.
		body += 'const/16 v8, 70\n:clip_again\ninvoke-virtual {v7, v6}, ${canvas}->clipPath(${path})Z\nmove-result v0\nif-eqz v0, :bad\nadd-int/lit8 v8, v8, -1\nif-nez v8, :clip_again\ninvoke-virtual {v6}, ${path}->reset()V\n'
		// Restoring an inner path clip retains the immutable outer prefix.
		body += 'invoke-virtual {v7}, ${canvas}->save()I\n' + outline_probe_triangle('v6')
		body += 'invoke-virtual {v7, v6}, ${canvas}->clipPath(${path})Z\ninvoke-virtual {v7}, ${canvas}->restore()V\nconst/high16 v0, 0x3f800000\ninvoke-virtual {v7, v0, v0}, ${canvas}->translate(FF)V\n'
		// Explicit covering geometry keeps this clip test independent of the
		// inherited drawColor implementation's transformed positive rectangle.
		body += outline_probe_cover()
		mut rows := []u32{len: 20}
		for y in 0 .. 20 {
			for x in 0 .. 20 {
				outer := x >= 1 && y >= 1 && x < 11 && y < 11
				inner := x >= 4 && y >= 4 && x < 8 && y < 8
				inside := if index & 1 == 0 { outer } else { outer && !inner }
				if inside != (index >= 2) { rows[y] |= u32(1) << x }
			}
		}
		body += outline_probe_scan(rows, '0xffff0000')
		body += 'invoke-virtual {v7}, ${canvas}->restore()V\nconst v0, 0xff0000ff\ninvoke-virtual {v7, v0}, ${canvas}->drawColor(I)V\nconst/4 v0, 0\nconst v1, 0xff0000ff\ninvoke-static {v9, v0, v0, v1}, ${probe}->pixel(${bitmap}III)V\nconst/4 v0, 5\ninvoke-static {v9, v0, v0, v1}, ${probe}->pixel(${bitmap}III)V\ninvoke-virtual {v9}, ${bitmap}->recycle()V\nreturn-void'
		text += method('private static fill${index}()V', body + bad)
	}
	text += method('private static pixel(${bitmap}III)V', 'move-object v0, p0\nconst/4 v2, 1\nnew-array v1, v2, [I\nconst/4 v2, 0\nconst/4 v3, 1\nmove v4, p1\nmove v5, p2\nconst/4 v6, 1\nconst/4 v7, 1\ninvoke-virtual/range {v0 .. v7}, ${bitmap}->getPixels([IIIIIII)V\nconst/4 v2, 0\naget v1, v1, v2\nif-eq v1, p3, :ok\nsget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\ninvoke-virtual {v0, p1}, Ljava/io/PrintStream;->println(I)V\ninvoke-virtual {v0, p2}, Ljava/io/PrintStream;->println(I)V\ninvoke-virtual {v0, p3}, Ljava/io/PrintStream;->println(I)V\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(I)V\ngoto :bad\n:ok\nreturn-void' + bad)
	text += method('private static sameMatrix(Landroid/graphics/Matrix;Landroid/graphics/Matrix;)Z', 'const/16 v0, 9\nnew-array v1, v0, [F\nnew-array v2, v0, [F\ninvoke-virtual {p0, v1}, Landroid/graphics/Matrix;->getValues([F)V\ninvoke-virtual {p1, v2}, Landroid/graphics/Matrix;->getValues([F)V\ninvoke-static {v1, v2}, Ljava/util/Arrays;->equals([F[F)Z\nmove-result v0\nreturn v0')
	mut check := ''
	for index in 0 .. 10 { check += 'invoke-static {}, ${probe}->node${index}()V\n' }
	for index in 0 .. 4 { check += 'invoke-static {}, ${probe}->fill${index}()V\n' }
	check += 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-RENDER-NODE-OUTLINE-PASS 5600-pixels rounded path oval rect empty null disabled alpha transforms snapshot recorded-path fill-rules inverse nesting restore 70-intersections"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void'
	text += method('public static check()V', check)
	os.write_file(dir + '/RenderNodeOutlineProbe.smali', text)!
}

fn outline_probe_triangle(register string) string {
	return 'new-instance ${register}, Landroid/graphics/Path;\ninvoke-direct {${register}}, Landroid/graphics/Path;-><init>()V\nconst/4 v0, 0\ninvoke-virtual {${register}, v0, v0}, Landroid/graphics/Path;->moveTo(FF)V\nconst/high16 v1, 0x41000000\ninvoke-virtual {${register}, v1, v0}, Landroid/graphics/Path;->lineTo(FF)V\ninvoke-virtual {${register}, v0, v1}, Landroid/graphics/Path;->lineTo(FF)V\n'
}

fn outline_probe_target() string {
	return 'const/16 v0, 20\nsget-object v1, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;\ninvoke-static {v0, v0, v1}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;\nmove-result-object v9\nconst/4 v0, 0\ninvoke-virtual {v9, v0}, Landroid/graphics/Bitmap;->eraseColor(I)V\nnew-instance v7, Landroid/graphics/Canvas;\ninvoke-direct {v7, v9}, Landroid/graphics/Canvas;-><init>(Landroid/graphics/Bitmap;)V\n'
}

fn outline_probe_cover() string {
	return 'new-instance v5, Landroid/graphics/Paint;\ninvoke-direct {v5}, Landroid/graphics/Paint;-><init>()V\nconst v0, 0xffff0000\ninvoke-virtual {v5, v0}, Landroid/graphics/Paint;->setColor(I)V\nmove-object v0, v7\nconst/high16 v1, 0xc1a00000\nmove v2, v1\nconst/high16 v3, 0x42200000\nmove v4, v3\ninvoke-virtual/range {v0 .. v5}, Landroid/graphics/Canvas;->drawRect(FFFFLandroid/graphics/Paint;)V\n'
}

// Independent geometric masks are emitted as row bits, then every pixel is read
// back. Samples avoid the flattened curve boundary; no native rasterizer is used
// to calculate the expected image.
fn outline_probe_scan(rows []u32, color string) string {
	mut body := 'const/4 v0, 0\n:y\nconst/16 v1, 20\nif-ge v0, v1, :scan_done\nconst/4 v2, 0\n'
	for y, mask in rows {
		if mask == 0 { continue }
		body += 'const/16 v3, ${y}\nif-ne v0, v3, :row${y}\nconst v2, ${mask}\ngoto :row_ready\n:row${y}\n'
	}
	body += ':row_ready\nconst/4 v1, 0\n:x\nconst/16 v3, 20\nif-ge v1, v3, :next_y\nushr-int v3, v2, v1\nand-int/lit8 v3, v3, 1\nif-eqz v3, :transparent\nconst v3, ${color}\ngoto :pixel\n:transparent\nconst/4 v3, 0\n:pixel\ninvoke-static {v9, v1, v0, v3}, Lorg/vinix/bootstrap/RenderNodeOutlineProbe;->pixel(Landroid/graphics/Bitmap;III)V\nadd-int/lit8 v1, v1, 1\ngoto :x\n:next_y\nadd-int/lit8 v0, v0, 1\ngoto :y\n:scan_done\n'
	return body
}
