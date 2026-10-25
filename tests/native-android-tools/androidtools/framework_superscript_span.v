// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Store Android's baseline adjustment in the existing TextPaint field. Native
// text rendering remains responsible for consuming that field when drawing.
pub fn framework_superscript_span(smali string) ! {
 owner := 'Landroid/text/style/SuperscriptSpan;'
 path := smali + '/android/text/style/SuperscriptSpan.smali'
 if os.exists(path) { return error('SuperscriptSpan already exists') }
 mut text := '.class public ${owner}\n.super Landroid/text/style/MetricAffectingSpan;\n.implements Landroid/text/ParcelableSpan;\n.implements Landroid/os/Parcelable;\n'
 for signature, body in {
  'constructor <init>()V': 'invoke-direct {p0}, Landroid/text/style/MetricAffectingSpan;-><init>()V\nreturn-void'
  'constructor <init>(Landroid/os/Parcel;)V': 'invoke-direct {p0}, Landroid/text/style/MetricAffectingSpan;-><init>()V\nreturn-void'
  'getSpanTypeId()I': 'invoke-virtual {p0}, ${owner}->getSpanTypeIdInternal()I\nmove-result v0\nreturn v0'
  'getSpanTypeIdInternal()I': 'const/16 v0, 14\nreturn v0'
  'describeContents()I': 'const/4 v0, 0\nreturn v0'
  'writeToParcel(Landroid/os/Parcel;I)V': 'invoke-virtual {p0, p1, p2}, ${owner}->writeToParcelInternal(Landroid/os/Parcel;I)V\nreturn-void'
  'writeToParcelInternal(Landroid/os/Parcel;I)V': 'return-void'
  'toString()Ljava/lang/String;': 'const-string v0, "SuperscriptSpan{}"\nreturn-object v0'
 } {
  text += '.method public ${signature}\n.locals 1\n${body}\n.end method\n'
 }
 for name in ['updateDrawState', 'updateMeasureState'] {
  text += '.method public ${name}(Landroid/text/TextPaint;)V\n.locals 3\niget v1, p1, Landroid/text/TextPaint;->baselineShift:I\ninvoke-virtual {p1}, Landroid/graphics/Paint;->ascent()F\nmove-result v0\nconst/high16 v2, 0x40000000\ndiv-float/2addr v0, v2\nfloat-to-int v0, v0\nadd-int/2addr v0, v1\niput v0, p1, Landroid/text/TextPaint;->baselineShift:I\nreturn-void\n.end method\n'
 }
 os.write_file(path, text)!
}
