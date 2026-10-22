// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_path_probe(dir string) ! {
 mut check := '
new-instance v0, Landroid/graphics/Path;
invoke-direct {v0}, Landroid/graphics/Path;-><init>()V
'
 // Pass integer coordinates to helpers; this keeps expected bounds readable.
 for item in [
  'bounds,0,0,0,0', 'moveTo,4,6', 'bounds,0,0,0,0',
  'lineTo,-3,20', 'bounds,-3,6,4,20', 'reset',
  'moveTo,0,0', 'quadTo,100,-40,20,10', 'bounds,0,-40,100,10',
 ] {
  values := item.split(',')
  for i := 1; i < values.len; i++ {
   check += 'const/16 v${i}, ${values[i]}\n'
   if values[0] != 'bounds' { check += 'int-to-float v${i}, v${i}\n' }
  }
  if values[0] == 'bounds' {
   check += 'invoke-static {v0, v1, v2, v3, v4}, Lorg/vinix/bootstrap/PathProbe;->bounds(Landroid/graphics/Path;IIII)V\n'
  } else {
   mut registers := ['v0']
   for i := 1; i < values.len; i++ { registers << 'v${i}' }
   args := registers.join(', ')
   signature := 'F'.repeat(values.len - 1)
   check += 'invoke-virtual {${args}}, Landroid/graphics/Path;->${values[0]}(${signature})V\n'
  }
 }
 check += '
new-instance v5, Landroid/graphics/Path;
invoke-direct {v5, v0}, Landroid/graphics/Path;-><init>(Landroid/graphics/Path;)V
const/16 v1, -10
int-to-float v1, v1
const/16 v2, 30
int-to-float v2, v2
invoke-virtual {v5, v1, v2}, Landroid/graphics/Path;->lineTo(FF)V
const/16 v1, -10
const/16 v2, -40
const/16 v3, 100
const/16 v4, 30
invoke-static {v5, v1, v2, v3, v4}, Lorg/vinix/bootstrap/PathProbe;->bounds(Landroid/graphics/Path;IIII)V
const/4 v1, 0
const/16 v4, 10
invoke-static {v0, v1, v2, v3, v4}, Lorg/vinix/bootstrap/PathProbe;->bounds(Landroid/graphics/Path;IIII)V
new-instance v6, Landroid/graphics/Matrix;
invoke-direct {v6}, Landroid/graphics/Matrix;-><init>()V
const/4 v1, 2
int-to-float v1, v1
const/4 v2, 3
int-to-float v2, v2
invoke-virtual {v6, v1, v2}, Landroid/graphics/Matrix;->setScale(FF)V
const/4 v1, 7
int-to-float v1, v1
const/16 v2, 11
int-to-float v2, v2
invoke-virtual {v6, v1, v2}, Landroid/graphics/Matrix;->postTranslate(FF)Z
new-instance v5, Landroid/graphics/Path;
invoke-direct {v5}, Landroid/graphics/Path;-><init>()V
invoke-virtual {v0, v6, v5}, Landroid/graphics/Path;->transform(Landroid/graphics/Matrix;Landroid/graphics/Path;)V
const/4 v1, 7
const/16 v2, -109
const/16 v3, 207
const/16 v4, 41
invoke-static {v5, v1, v2, v3, v4}, Lorg/vinix/bootstrap/PathProbe;->bounds(Landroid/graphics/Path;IIII)V
invoke-virtual {v0}, Landroid/graphics/Path;->rewind()V
move-object v0, v5
const/4 v7, 0
:null_start
invoke-virtual {v0, v7, v7}, Landroid/graphics/Path;->computeBounds(Landroid/graphics/RectF;Z)V
:null_end
.catch Ljava/lang/NullPointerException; {:null_start .. :null_end} :null_ok
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "null Path bounds"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:null_ok
move-exception v7
invoke-static {}, Lorg/vinix/bootstrap/PathProbe;->cubic()V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-PATH-BOUNDS-PASS empty move lines quadratic-controls cubic-controls copy transform add null"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void'
 mut bounds := '
new-instance v0, Landroid/graphics/RectF;
invoke-direct {v0}, Landroid/graphics/RectF;-><init>()V
const/4 v1, 0
invoke-virtual {p0, v0, v1}, Landroid/graphics/Path;->computeBounds(Landroid/graphics/RectF;Z)V
'
 for i, name in ['left', 'top', 'right', 'bottom'] {
  bounds += 'iget v1, v0, Landroid/graphics/RectF;->${name}:F\nint-to-float v2, p${i + 1}\ncmpl-float v1, v1, v2\nif-nez v1, :bad\n'
 }
 bounds += 'return-void\n:bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "Path control bounds"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
 mut cubic := 'new-instance v0, Landroid/graphics/Path;\ninvoke-direct {v0}, Landroid/graphics/Path;-><init>()V\nconst/16 v1, 10\nint-to-float v1, v1\nconst/16 v2, 20\nint-to-float v2, v2\ninvoke-virtual {v0, v1, v2}, Landroid/graphics/Path;->moveTo(FF)V\n'
 for i, coordinate in [-20, -50, 80, 90, 30, -10] {
  cubic += 'const/16 v${i + 1}, ${coordinate}\nint-to-float v${i + 1}, v${i + 1}\n'
 }
 cubic += '
invoke-virtual/range {v0 .. v6}, Landroid/graphics/Path;->rCubicTo(FFFFFF)V
const/16 v1, -10
const/16 v2, -30
const/16 v3, 90
const/16 v4, 110
invoke-static {v0, v1, v2, v3, v4}, Lorg/vinix/bootstrap/PathProbe;->bounds(Landroid/graphics/Path;IIII)V
new-instance v5, Landroid/graphics/Path;
invoke-direct {v5}, Landroid/graphics/Path;-><init>()V
const/4 v1, 2
int-to-float v1, v1
const/4 v2, 3
int-to-float v2, v2
invoke-virtual {v5, v0, v1, v2}, Landroid/graphics/Path;->addPath(Landroid/graphics/Path;FF)V
const/16 v1, -8
const/16 v2, -27
const/16 v3, 92
const/16 v4, 113
invoke-static {v5, v1, v2, v3, v4}, Lorg/vinix/bootstrap/PathProbe;->bounds(Landroid/graphics/Path;IIII)V
return-void'
 os.write_file(dir + '/PathProbe.smali', '.class public Lorg/vinix/bootstrap/PathProbe;\n.super Ljava/lang/Object;\n' +
  method('public static check()V', check) + method('private static bounds(Landroid/graphics/Path;IIII)V', bounds) +
  method('private static cubic()V', cubic))!
}
