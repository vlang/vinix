// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn style_probe_method(signature string, body string) string {
 return method(signature, body + '
return-void
:bad
new-instance v8, Ljava/lang/AssertionError;
const-string v9, "CharacterStyle wrapper identity, delegation or text ranges"
invoke-direct {v8, v9}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v8')
}

fn install_character_style_probe(dir string) ! {
 style := 'Landroid/text/style/CharacterStyle;'
 metric := 'Landroid/text/style/MetricAffectingSpan;'
 probe := 'Lorg/vinix/bootstrap/CharacterStyleProbe;'
 // App subclasses distinguish draw/measure calls and remember exact argument
 // identity. Mutating their state after wrapping must still affect delegation.
 for name in ['Draw', 'Metric'] {
  owner := 'Lorg/vinix/bootstrap/Wrapped${name};'
  base := if name == 'Metric' { metric } else { style }
  mut text := '.class public ${owner}\n.super ${base}\n.field public drawCalls:I\n.field public measureCalls:I\n.field public value:I\n.field public paint:Landroid/text/TextPaint;\n.field public failure:Ljava/lang/RuntimeException;\n' +
   method('public constructor <init>()V', 'invoke-direct {p0}, ${base}-><init>()V\nreturn-void')
  for operation in if name == 'Metric' { ['Draw', 'Measure'] } else { ['Draw'] } {
   field := operation.to_lower() + 'Calls'
   mut body := 'iget-object v0, p0, ${owner}->failure:Ljava/lang/RuntimeException;\nif-eqz v0, :go\nthrow v0\n:go\n' +
    'iput-object p1, p0, ${owner}->paint:Landroid/text/TextPaint;\niget v0, p0, ${owner}->${field}:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, ${owner}->${field}:I\nif-eqz p1, :done\niget v0, p0, ${owner}->value:I\n'
   body += if operation == 'Draw' { 'invoke-virtual {p1, v0}, Landroid/graphics/Paint;->setColor(I)V\n' } else { 'int-to-float v0, v0\ninvoke-virtual {p1, v0}, Landroid/graphics/Paint;->setTextSize(F)V\n' }
   text += method('public update${operation}State(Landroid/text/TextPaint;)V', body + ':done\nreturn-void')
  }
  os.write_file(dir + '/Wrapped${name}.smali', text)!
 }
 mut text := '.class public ${probe}\n.super Ljava/lang/Object;\n' + method('public static check()V', '
invoke-static {}, ${probe}->draw()V
invoke-static {}, ${probe}->metrics()V
invoke-static {}, ${probe}->ranges()V
invoke-static {}, ${probe}->nulls()V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-CHARACTER-STYLES-PASS distinct nested covariant virtual draw measure live-state paint-identity exceptions null ranges real-size-span"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void')
 // Independent wrappers and a nested wrapper must all retain the same target.
 for name in ['Draw', 'Metric'] {
  owner := 'Lorg/vinix/bootstrap/Wrapped${name};'
  mut body := 'new-instance v0, ${owner}\ninvoke-direct {v0}, ${owner}-><init>()V\n' +
   'invoke-virtual {v0}, ${style}->getUnderlying()${style}\nmove-result-object v5\nif-ne v0, v5, :bad\n'
  for register in ['v1', 'v2', 'v3'] {
   source := if register == 'v3' { 'v1' } else { 'v0' }
   body += 'invoke-static {${source}}, ${style}->wrap(${style})${style}\nmove-result-object ${register}\n' +
    'if-eq ${register}, ${source}, :bad\ninvoke-virtual {${register}}, ${style}->getUnderlying()${style}\nmove-result-object v5\nif-ne v0, v5, :bad\n'
  }
  body += 'if-eq v1, v2, :bad\ninstance-of v5, v3, ${metric}\n' + if name == 'Metric' {
   'if-eqz v5, :bad\ncheck-cast v3, ${metric}\ninvoke-virtual {v3}, ${metric}->getUnderlying()${metric}\nmove-result-object v5\nif-ne v0, v5, :bad\ninstance-of v5, v3, Landroid/text/style/UpdateLayout;\nif-eqz v5, :bad\n'
  } else { 'if-nez v5, :bad\n' }
  body += 'new-instance v4, Landroid/text/TextPaint;\ninvoke-direct {v4}, Landroid/text/TextPaint;-><init>()V\n'
  for i, value in ['0xff336699', '0xffaabbcc'] {
   body += 'const v5, ${value}\niput v5, v0, ${owner}->value:I\ninvoke-virtual {v3, v4}, ${style}->updateDrawState(Landroid/text/TextPaint;)V\n' +
    'invoke-virtual {v4}, Landroid/graphics/Paint;->getColor()I\nmove-result v6\nif-ne v5, v6, :bad\n' +
    'iget-object v5, v0, ${owner}->paint:Landroid/text/TextPaint;\nif-ne v5, v4, :bad\niget v5, v0, ${owner}->drawCalls:I\nconst/4 v6, ${i + 1}\nif-ne v5, v6, :bad\n'
  }
  if name == 'Metric' {
   body += 'const/16 v5, 37\niput v5, v0, ${owner}->value:I\ninvoke-virtual {v3, v4}, ${metric}->updateMeasureState(Landroid/text/TextPaint;)V\n' +
    'invoke-virtual {v4}, Landroid/graphics/Paint;->getTextSize()F\nmove-result v5\nconst v6, 0x42140000\ncmpl-float v5, v5, v6\nif-nez v5, :bad\n' +
    'iget v5, v0, ${owner}->measureCalls:I\nconst/4 v6, 1\nif-ne v5, v6, :bad\niget-object v5, v0, ${owner}->paint:Landroid/text/TextPaint;\nif-ne v5, v4, :bad\n'
  }
  // A null Paint is passed to the subclass unchanged; wrappers do not reject it.
  body += 'const/4 v5, 0\ninvoke-virtual {v3, v5}, ${style}->updateDrawState(Landroid/text/TextPaint;)V\niget-object v5, v0, ${owner}->paint:Landroid/text/TextPaint;\nif-nez v5, :bad\n' +
   'new-instance v5, Ljava/lang/RuntimeException;\ninvoke-direct {v5}, Ljava/lang/RuntimeException;-><init>()V\niput-object v5, v0, ${owner}->failure:Ljava/lang/RuntimeException;\n' +
   ':try\ninvoke-virtual {v3, v4}, ${style}->updateDrawState(Landroid/text/TextPaint;)V\n:end\ngoto :bad\n.catch Ljava/lang/RuntimeException; {:try .. :end} :caught\n:caught\nmove-exception v6\nif-ne v5, v6, :bad\n'
  if name == 'Metric' {
   body += ':measure_try\ninvoke-virtual {v3, v4}, ${metric}->updateMeasureState(Landroid/text/TextPaint;)V\n:measure_end\ngoto :bad\n.catch Ljava/lang/RuntimeException; {:measure_try .. :measure_end} :measure_caught\n:measure_caught\nmove-exception v6\nif-ne v5, v6, :bad\n' +
    'new-instance v0, Landroid/text/style/AbsoluteSizeSpan;\nconst/16 v1, 29\ninvoke-direct {v0, v1}, Landroid/text/style/AbsoluteSizeSpan;-><init>(I)V\n' +
    'invoke-static {v0}, ${style}->wrap(${style})${style}\nmove-result-object v1\ncheck-cast v1, ${metric}\n' +
    'invoke-virtual {v1, v4}, ${metric}->updateMeasureState(Landroid/text/TextPaint;)V\ninvoke-virtual {v4}, Landroid/graphics/Paint;->getTextSize()F\nmove-result v5\nconst v6, 0x41e80000\ncmpl-float v5, v5, v6\nif-nez v5, :bad\n'
  }
  text += style_probe_method('private static ${if name == 'Metric' { 'metrics' } else { 'draw' }}()V', body)
 }
 // Wrapping null is allowed by Android 15; dereferencing the wrapper fails later.
 mut nulls := 'const/4 v0, 0\ninvoke-static {v0}, ${style}->wrap(${style})${style}\nmove-result-object v1\nif-eqz v1, :bad\n'
 for i, call in ['invoke-virtual {v1}, ${style}->getUnderlying()${style}', 'invoke-virtual {v1, v0}, ${style}->updateDrawState(Landroid/text/TextPaint;)V'] {
  nulls += ':try_${i}\n${call}\n:end_${i}\ngoto :bad\n.catch Ljava/lang/NullPointerException; {:try_${i} .. :end_${i}} :caught_${i}\n:caught_${i}\nmove-exception v2\n'
 }
 text += style_probe_method('private static nulls()V', nulls)
 mut ranges := 'new-instance v0, Lorg/vinix/bootstrap/WrappedDraw;\ninvoke-direct {v0}, Lorg/vinix/bootstrap/WrappedDraw;-><init>()V\n' +
  'invoke-static {v0}, ${style}->wrap(${style})${style}\nmove-result-object v1\ninvoke-static {v0}, ${style}->wrap(${style})${style}\nmove-result-object v2\n' +
  'new-instance v3, Landroid/text/SpannableString;\nconst-string v4, "abcdef"\ninvoke-direct {v3, v4}, Landroid/text/SpannableString;-><init>(Ljava/lang/CharSequence;)V\n'
 for i in 0 .. 3 {
  ranges += 'const/4 v4, ${i * 2}\nconst/4 v5, ${i * 2 + 1}\nconst/16 v6, 33\ninvoke-virtual {v3, v${i}, v4, v5, v6}, Landroid/text/SpannableString;->setSpan(Ljava/lang/Object;III)V\n'
 }
 for i in 0 .. 3 {
  for j, accessor in ['getSpanStart', 'getSpanEnd', 'getSpanFlags'] {
   expected := if j == 2 { 33 } else { i * 2 + j }
   ranges += 'invoke-virtual {v3, v${i}}, Landroid/text/SpannableString;->${accessor}(Ljava/lang/Object;)I\nmove-result v4\nconst/16 v5, ${expected}\nif-ne v4, v5, :bad\n'
  }
 }
 ranges += 'invoke-virtual {v3, v1}, Landroid/text/SpannableString;->removeSpan(Ljava/lang/Object;)V\ninvoke-virtual {v3, v1}, Landroid/text/SpannableString;->getSpanStart(Ljava/lang/Object;)I\nmove-result v4\nconst/4 v5, -1\nif-ne v4, v5, :bad\n' +
  'invoke-virtual {v3, v2}, Landroid/text/SpannableString;->getSpanStart(Ljava/lang/Object;)I\nmove-result v4\nconst/4 v5, 4\nif-ne v4, v5, :bad\n'
 text += style_probe_method('private static ranges()V', ranges)
 os.write_file(dir + '/CharacterStyleProbe.smali', text)!
}
