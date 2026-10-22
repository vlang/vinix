// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_character_styles(smali string) ! {
 style := 'Landroid/text/style/CharacterStyle;'
 metric := 'Landroid/text/style/MetricAffectingSpan;'
 os.write_file(smali + '/android/text/style/CharacterStyle.smali', '.class public abstract ${style}\n.super Ljava/lang/Object;\n' +
  '.method public constructor <init>()V\n.locals 0\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void\n.end method\n' +
  '.method public abstract updateDrawState(Landroid/text/TextPaint;)V\n.end method\n' +
  '.method public getUnderlying()${style}\n.locals 0\nreturn-object p0\n.end method\n' +
  '.method public static wrap(${style})${style}\n.locals 1\n' +
  'instance-of v0, p0, ${metric}\nif-eqz v0, :draw\n' +
  'check-cast p0, ${metric}\nnew-instance v0, Landroid/text/style/MetricAffectingSpan$VinixWrapper;\n' +
  'invoke-direct {v0, p0}, Landroid/text/style/MetricAffectingSpan$VinixWrapper;-><init>(${metric})V\nreturn-object v0\n' +
  ':draw\nnew-instance v0, Landroid/text/style/CharacterStyle$VinixWrapper;\n' +
  'invoke-direct {v0, p0}, Landroid/text/style/CharacterStyle$VinixWrapper;-><init>(${style})V\nreturn-object v0\n.end method\n')!
 os.write_file(smali + '/android/text/style/MetricAffectingSpan.smali', '.class public abstract ${metric}\n.super ${style}\n.implements Landroid/text/style/UpdateLayout;\n' +
  '.method public constructor <init>()V\n.locals 0\ninvoke-direct {p0}, ${style}-><init>()V\nreturn-void\n.end method\n' +
  '.method public abstract updateMeasureState(Landroid/text/TextPaint;)V\n.end method\n' +
  '.method public getUnderlying()${metric}\n.locals 0\nreturn-object p0\n.end method\n' + character_style_bridge())!
 for owner in ['CharacterStyle', 'MetricAffectingSpan'] {
  base := 'Landroid/text/style/${owner};'
  wrapper := 'Landroid/text/style/${owner}$VinixWrapper;'
  mut text := '.class final ${wrapper}\n.super ${base}\n.field private final style:${base}\n' +
   '.method public constructor <init>(${base})V\n.locals 0\ninvoke-direct {p0}, ${base}-><init>()V\niput-object p1, p0, ${wrapper}->style:${base}\nreturn-void\n.end method\n' +
   '.method public getUnderlying()${base}\n.locals 1\niget-object v0, p0, ${wrapper}->style:${base}\ninvoke-virtual {v0}, ${base}->getUnderlying()${base}\nmove-result-object v0\nreturn-object v0\n.end method\n'
  for name in if owner == 'MetricAffectingSpan' { ['updateDrawState', 'updateMeasureState'] } else { ['updateDrawState'] } {
   text += '.method public ${name}(Landroid/text/TextPaint;)V\n.locals 1\niget-object v0, p0, ${wrapper}->style:${base}\ninvoke-virtual {v0, p1}, ${base}->${name}(Landroid/text/TextPaint;)V\nreturn-void\n.end method\n'
  }
  if owner == 'MetricAffectingSpan' { text += character_style_bridge() }
  os.write_file(smali + '/android/text/style/${owner}$VinixWrapper.smali', text)!
 }
}

fn character_style_bridge() string {
 return '.method public bridge synthetic getUnderlying()Landroid/text/style/CharacterStyle;\n.locals 1\ninvoke-virtual {p0}, Landroid/text/style/MetricAffectingSpan;->getUnderlying()Landroid/text/style/MetricAffectingSpan;\nmove-result-object v0\nreturn-object v0\n.end method\n'
}
