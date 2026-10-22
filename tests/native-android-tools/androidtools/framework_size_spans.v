// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_absolute_size_span(smali string) ! {
 owner := 'Landroid/text/style/AbsoluteSizeSpan;'
 mut text := '.class public ${owner}\n.super Landroid/text/style/MetricAffectingSpan;\n.implements Landroid/text/ParcelableSpan;\n.implements Landroid/os/Parcelable;\n.field private final vinixSize:I\n.field private final vinixDip:Z\n'
 for signature, body in {
  'constructor <init>()V': 'const/4 v0, 0\ninvoke-direct {p0, v0}, ${owner}-><init>(I)V\nreturn-void'
  'constructor <init>(I)V': 'const/4 v0, 0\ninvoke-direct {p0, p1, v0}, ${owner}-><init>(IZ)V\nreturn-void'
  'constructor <init>(IZ)V': 'invoke-direct {p0}, Landroid/text/style/MetricAffectingSpan;-><init>()V\niput p1, p0, ${owner}->vinixSize:I\niput-boolean p2, p0, ${owner}->vinixDip:Z\nreturn-void'
  'constructor <init>(Landroid/os/Parcel;)V': 'invoke-direct {p0}, Landroid/text/style/MetricAffectingSpan;-><init>()V\ninvoke-virtual {p1}, Landroid/os/Parcel;->readInt()I\nmove-result v0\niput v0, p0, ${owner}->vinixSize:I\ninvoke-virtual {p1}, Landroid/os/Parcel;->readInt()I\nmove-result v0\nif-eqz v0, :dip\nconst/4 v0, 1\n:dip\niput-boolean v0, p0, ${owner}->vinixDip:Z\nreturn-void'
  'getSize()I': 'iget v0, p0, ${owner}->vinixSize:I\nreturn v0'
  'getDip()Z': 'iget-boolean v0, p0, ${owner}->vinixDip:Z\nreturn v0'
  'getSpanTypeId()I': 'invoke-virtual {p0}, ${owner}->getSpanTypeIdInternal()I\nmove-result v0\nreturn v0'
  'getSpanTypeIdInternal()I': 'const/16 v0, 16\nreturn v0'
  'describeContents()I': 'const/4 v0, 0\nreturn v0'
  'writeToParcel(Landroid/os/Parcel;I)V': 'invoke-virtual {p0, p1, p2}, ${owner}->writeToParcelInternal(Landroid/os/Parcel;I)V\nreturn-void'
  'writeToParcelInternal(Landroid/os/Parcel;I)V': 'iget v0, p0, ${owner}->vinixSize:I\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeInt(I)V\niget-boolean v0, p0, ${owner}->vinixDip:Z\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeInt(I)V\nreturn-void'
 } {
  text += '.method public ${signature}\n.locals 2\n${body}\n.end method\n'
 }
 for name in ['updateDrawState', 'updateMeasureState'] {
  text += '.method public ${name}(Landroid/text/TextPaint;)V\n.locals 2\n
iget v0, p0, ${owner}->vinixSize:I
int-to-float v0, v0
iget-boolean v1, p0, ${owner}->vinixDip:Z
if-eqz v1, :apply
iget v1, p1, Landroid/text/TextPaint;->density:F
mul-float/2addr v0, v1
:apply
invoke-virtual {p1, v0}, Landroid/graphics/Paint;->setTextSize(F)V
return-void
.end method\n'
 }
 os.write_file(smali + '/android/text/style/AbsoluteSizeSpan.smali', text)!
}
