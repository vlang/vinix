// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

// Verify every pixel of asymmetric shapes, so accepting concat while dropping
// its off-diagonal entries cannot pass. Coordinates are device pixel centers.
fn install_affine_probe(dir string) ! {
	mut source := '.class public Lorg/vinix/bootstrap/AffineProbe;\n.super Ljava/lang/Object;\n'
	mut check := ''
	for test in 0..7 {
		mut body := '
const/16 v0, 32
sget-object v1, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;
invoke-static {v0, v0, v1}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;
move-result-object v8
new-instance v6, Landroid/graphics/Canvas;
invoke-direct {v6, v8}, Landroid/graphics/Canvas;-><init>(Landroid/graphics/Bitmap;)V
invoke-virtual {v6}, Landroid/graphics/Canvas;->save()I
new-instance v7, Landroid/graphics/Paint;
invoke-direct {v7}, Landroid/graphics/Paint;-><init>()V
const v0, 0xffff0000
invoke-virtual {v7, v0}, Landroid/graphics/Paint;->setColor(I)V
new-instance v9, Landroid/graphics/Matrix;
invoke-direct {v9}, Landroid/graphics/Matrix;-><init>()V
const/16 v0, 9
new-array v0, v0, [F
'
		matrix := if test in [1, 5] { [1,1,2,0,1,3,0,0,1] } else if test == 2 { [-1,0,24,0,1,2,0,0,1] } else { [0,-1,24,1,0,2,0,0,1] }
		for i, value in matrix {
			body += 'const/16 v1, ${value}\nint-to-float v1, v1\nconst/16 v2, ${i}\naput v1, v0, v2\n'
		}
		body += 'invoke-virtual {v9, v0}, Landroid/graphics/Matrix;->setValues([F)V\ninvoke-virtual {v6, v9}, Landroid/graphics/Canvas;->concat(Landroid/graphics/Matrix;)V\n'
		if test == 3 {
			body += 'new-instance v0, Landroid/graphics/Path;\ninvoke-direct {v0}, Landroid/graphics/Path;-><init>()V\nconst/4 v1, 0\nconst/high16 v2, 0x41000000\nconst/high16 v3, 0x40a00000\ninvoke-virtual {v0, v1, v1}, Landroid/graphics/Path;->moveTo(FF)V\ninvoke-virtual {v0, v2, v1}, Landroid/graphics/Path;->lineTo(FF)V\ninvoke-virtual {v0, v1, v3}, Landroid/graphics/Path;->lineTo(FF)V\ninvoke-virtual {v0}, Landroid/graphics/Path;->close()V\ninvoke-virtual {v6, v0, v7}, Landroid/graphics/Canvas;->drawPath(Landroid/graphics/Path;Landroid/graphics/Paint;)V\n'
		} else if test == 4 {
			body += 'const/16 v0, 8\nconst/4 v1, 5\nsget-object v2, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;\ninvoke-static {v0, v1, v2}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;\nmove-result-object v9\nconst v0, 0xffff0000\ninvoke-virtual {v9, v0}, Landroid/graphics/Bitmap;->eraseColor(I)V\nconst/4 v0, 0\ninvoke-virtual {v6, v9, v0, v0, v7}, Landroid/graphics/Canvas;->drawBitmap(Landroid/graphics/Bitmap;FFLandroid/graphics/Paint;)V\ninvoke-virtual {v9}, Landroid/graphics/Bitmap;->recycle()V\n'
		} else {
			body += 'move-object v0, v6\nconst/4 v1, 0\nconst/4 v2, 0\nconst/high16 v3, 0x41000000\nconst/high16 v4, 0x40a00000\nmove-object v5, v7\n'
			if test == 5 {
				body += 'invoke-virtual {v0, v1, v2, v3, v4}, Landroid/graphics/Canvas;->clipRect(FFFF)Z\nconst/high16 v1, -0x3d380000\nconst/high16 v2, -0x3d380000\nconst/high16 v3, 0x42c80000\nconst/high16 v4, 0x42c80000\n'
			}
			if test == 6 {
				// Translation and scale must postmultiply the rotated matrix.
				body += 'const/high16 v1, 0x40000000\nconst/high16 v2, 0x40400000\ninvoke-virtual {v6, v1, v2}, Landroid/graphics/Canvas;->translate(FF)V\nconst/high16 v1, 0x40000000\nconst/high16 v2, 0x3f800000\ninvoke-virtual {v6, v1, v2}, Landroid/graphics/Canvas;->scale(FF)V\nconst/4 v1, 0\nconst/4 v2, 0\n'
			}
			body += 'invoke-virtual/range {v0 .. v5}, Landroid/graphics/Canvas;->drawRect(FFFFLandroid/graphics/Paint;)V\n'
		}
		body += 'invoke-virtual {v6}, Landroid/graphics/Canvas;->restore()V\nconst/16 v0, 1024\nnew-array v1, v0, [I\nmove-object v0, v8\nconst/4 v2, 0\nconst/16 v3, 32\nconst/4 v4, 0\nconst/4 v5, 0\nconst/16 v6, 32\nconst/16 v7, 32\ninvoke-virtual/range {v0 .. v7}, Landroid/graphics/Bitmap;->getPixels([IIIIIII)V\n'
		for y in 0..32 {
			for x in 0..32 {
				u, v := f32(y) - 1.5, 23.5 - f32(x)
				inside := match test {
					1, 5 { y >= 3 && y < 8 && x - y + 1 >= 0 && x - y + 1 < 8 }
					2 { x >= 16 && x < 24 && y >= 2 && y < 7 }
					3 { u >= 0 && v >= 0 && u / 8 + v / 5 < 1 }
					6 { x >= 16 && x < 21 && y >= 4 && y < 20 }
					else { x >= 19 && x < 24 && y >= 2 && y < 10 }
				}
				body += 'const/16 v2, ${y*32+x}\naget v2, v1, v2\nconst v3, ${if inside { '0xffff0000' } else { '0' }}\nif-ne v2, v3, :bad\n'
			}
		}
		body += 'invoke-virtual {v8}, Landroid/graphics/Bitmap;->recycle()V\nreturn-void\n:bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "Canvas affine case ${test}"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
		source += method('private static case${test}()V', body)
		check += 'invoke-static {}, Lorg/vinix/bootstrap/AffineProbe;->case${test}()V\n'
	}
	check += 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-AFFINE-PASS rotation shear reflection path bitmap clip translate scale all-pixels"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void'
	os.write_file(dir + '/AffineProbe.smali', source + method('public static check()V', check))!
}
