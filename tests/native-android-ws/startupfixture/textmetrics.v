// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_text_metrics_probe(dir string) ! {
 mut body := '
new-instance v0, Landroid/graphics/Paint;
invoke-direct {v0}, Landroid/graphics/Paint;-><init>()V
const/high16 v1, 0x42000000
invoke-virtual {v0, v1}, Landroid/graphics/Paint;->setTextSize(F)V
const-string v1, "W"
invoke-virtual {v0, v1}, Landroid/graphics/Paint;->measureText(Ljava/lang/String;)F
move-result v5
const-string v1, "I"
invoke-virtual {v0, v1}, Landroid/graphics/Paint;->measureText(Ljava/lang/String;)F
move-result v6
cmpl-float v7, v5, v6
if-lez v7, :bad
const-string v1, "WIW"
const/4 v2, 0
const/4 v3, 1
invoke-virtual {v0, v1, v2, v3}, Landroid/graphics/Paint;->measureText(Ljava/lang/String;II)F
move-result v6
cmpl-float v7, v5, v6
if-nez v7, :bad
invoke-virtual {v1}, Ljava/lang/String;->toCharArray()[C
move-result-object v4
invoke-virtual {v0, v4, v2, v3}, Landroid/graphics/Paint;->measureText([CII)F
move-result v6
cmpl-float v7, v5, v6
if-nez v7, :bad
const/4 v2, 2
# Array uses count, String uses end.
invoke-virtual {v0, v4, v2, v3}, Landroid/graphics/Paint;->measureText([CII)F
move-result v6
cmpl-float v7, v5, v6
if-nez v7, :bad
const/4 v3, 3
invoke-virtual {v0, v1, v2, v3}, Landroid/graphics/Paint;->measureText(Ljava/lang/String;II)F
move-result v6
cmpl-float v7, v5, v6
if-nez v7, :bad
new-instance v1, Ljava/lang/StringBuilder;
const-string v6, "WIW"
invoke-direct {v1, v6}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V
invoke-virtual {v0, v1, v2, v3}, Landroid/graphics/Paint;->measureText(Ljava/lang/CharSequence;II)F
move-result v6
cmpl-float v7, v5, v6
if-nez v7, :bad
const-string v1, "WIW"
const/4 v2, 3
const/4 v3, 3
invoke-virtual {v0, v1, v2, v3}, Landroid/graphics/Paint;->measureText(Ljava/lang/String;II)F
move-result v6
const/4 v7, 0
cmpl-float v7, v7, v6
if-nez v7, :bad
const/4 v3, 0
invoke-virtual {v0, v4, v2, v3}, Landroid/graphics/Paint;->measureText([CII)F
move-result v6
const/4 v7, 0
cmpl-float v7, v7, v6
if-nez v7, :bad
# Both APIs must decode a supplementary pair as one codepoint.
const-string v1, "\\ud83d\\ude00"
invoke-virtual {v0, v1}, Landroid/graphics/Paint;->measureText(Ljava/lang/String;)F
move-result v5
invoke-virtual {v1}, Ljava/lang/String;->toCharArray()[C
move-result-object v4
const/4 v2, 0
const/4 v3, 2
invoke-virtual {v0, v4, v2, v3}, Landroid/graphics/Paint;->measureText([CII)F
move-result v6
cmpl-float v7, v5, v6
if-nez v7, :bad
const-string v1, "\\ufffd\\ufffd"
invoke-virtual {v0, v1}, Landroid/graphics/Paint;->measureText(Ljava/lang/String;)F
move-result v6
cmpl-float v7, v5, v6
if-eqz v7, :bad
# NUL is measured rather than truncating the rest of the string.
const-string v1, "II"
invoke-virtual {v0, v1}, Landroid/graphics/Paint;->measureText(Ljava/lang/String;)F
move-result v5
const-string v1, "I\\u0000I"
invoke-virtual {v0, v1}, Landroid/graphics/Paint;->measureText(Ljava/lang/String;)F
move-result v6
cmpl-float v7, v5, v6
if-gez v7, :bad
'
 // Every call must throw the specified exception; no linkage errors or silent
 // return values can satisfy these checks. Include overflowing array ranges.
 for i, spec in [
  ['const/4 v1, 0', 'Ljava/lang/String;', '', 'Ljava/lang/IllegalArgumentException;'],
  ['const/4 v1, 0', 'Ljava/lang/String;II', 'const/4 v2, 0\nconst/4 v3, 0', 'Ljava/lang/IllegalArgumentException;'],
  ['const/4 v1, 0', '[CII', 'const/4 v2, 0\nconst/4 v3, 0', 'Ljava/lang/IllegalArgumentException;'],
  ['const/4 v1, 0', 'Ljava/lang/CharSequence;II', 'const/4 v2, 0\nconst/4 v3, 0', 'Ljava/lang/IllegalArgumentException;'],
  ['const-string v1, "abc"', 'Ljava/lang/String;II', 'const/4 v2, -1\nconst/4 v3, 1', 'Ljava/lang/IndexOutOfBoundsException;'],
  ['const-string v1, "abc"', 'Ljava/lang/String;II', 'const/4 v2, 2\nconst/4 v3, 1', 'Ljava/lang/IndexOutOfBoundsException;'],
  ['const-string v1, "abc"', 'Ljava/lang/String;II', 'const/4 v2, 0\nconst/4 v3, 4', 'Ljava/lang/IndexOutOfBoundsException;'],
  ['move-object v1, v4', '[CII', 'const/4 v2, 0\nconst/4 v3, -1', 'Ljava/lang/ArrayIndexOutOfBoundsException;'],
  ['move-object v1, v4', '[CII', 'const/4 v2, 1\nconst v3, 0x7fffffff', 'Ljava/lang/ArrayIndexOutOfBoundsException;'],
 ] {
  registers := if spec[1] == 'Ljava/lang/String;' { 'v0, v1' } else { 'v0, v1, v2, v3' }
  body += '${spec[0]}\n${spec[2]}\n:try_${i}\ninvoke-virtual {${registers}}, Landroid/graphics/Paint;->measureText(${spec[1]})F\n:end_${i}\n.catch ${spec[3]} {:try_${i} .. :end_${i}} :caught_${i}\ngoto :bad\n:caught_${i}\nmove-exception v7\n'
 }
 body += '
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-TEXT-METRICS-PASS proportional range array-count charsequence utf16 nul null bounds overflow"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "real font text metrics"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
 os.write_file(dir + '/TextMetricsProbe.smali', '.class public Lorg/vinix/bootstrap/TextMetricsProbe;\n.super Ljava/lang/Object;\n' + method('public static check()V', body))!
}
