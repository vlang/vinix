// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_rect_parcel_probe(dir string) ! {
 mut check := ''
 mut helpers := ''
 for name in ['Rect', 'RectF'] {
  class := 'Landroid/graphics/${name};'
  kind := if name == 'Rect' { 'I' } else { 'F' }
  check += 'new-instance v0, ${class}\n'
  values := if name == 'Rect' { ['-2', '3', '2147483647', '-2147483648'] } else { ['0x80000000', '0x3fc00000', '0x7f800000', '0x7fc00000'] }
  for i, value in values { check += 'const v${i + 1}, ${value}\n' }
  check += 'invoke-direct {v0, v1, v2, v3, v4}, ${class}-><init>(${kind}${kind}${kind}${kind})V\n' +
   'invoke-virtual {v0}, ${class}->describeContents()I\nmove-result v1\nif-nez v1, :bad\n' +
   'invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;\nmove-result-object v1\nconst/4 v2, 0\n' +
   'invoke-interface {v0, v1, v2}, Landroid/os/Parcelable;->writeToParcel(Landroid/os/Parcel;I)V\n' +
   'invoke-virtual {v1}, Landroid/os/Parcel;->dataPosition()I\nmove-result v3\nconst/16 v4, 16\nif-ne v3, v4, :bad\n' +
   'invoke-virtual {v1, v2}, Landroid/os/Parcel;->setDataPosition(I)V\n' +
   'sget-object v3, ${class}->CREATOR:Landroid/os/Parcelable\$Creator;\n' +
   'invoke-interface {v3, v1}, Landroid/os/Parcelable\$Creator;->createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;\nmove-result-object v4\ncheck-cast v4, ${class}\n' +
   'invoke-static {v0, v4}, Lorg/vinix/bootstrap/RectParcelProbe;->expect${name}(${class}${class})V\n' +
   'invoke-virtual {v4}, ${class}->setEmpty()V\ninvoke-virtual {v1, v2}, Landroid/os/Parcel;->setDataPosition(I)V\n' +
   'invoke-virtual {v4, v1}, ${class}->readFromParcel(Landroid/os/Parcel;)V\n' +
   'invoke-static {v0, v4}, Lorg/vinix/bootstrap/RectParcelProbe;->expect${name}(${class}${class})V\n' +
   'const/4 v4, 2\ninvoke-interface {v3, v4}, Landroid/os/Parcelable\$Creator;->newArray(I)[Ljava/lang/Object;\nmove-result-object v3\ncheck-cast v3, [${class}\n' +
   'array-length v5, v3\nif-ne v5, v4, :bad\naput-object v0, v3, v2\n' +
   'invoke-virtual {v1, v2}, Landroid/os/Parcel;->setDataPosition(I)V\n' +
   'invoke-virtual {v1, v3, v2}, Landroid/os/Parcel;->writeTypedArray([Landroid/os/Parcelable;I)V\n' +
   'invoke-virtual {v1, v2}, Landroid/os/Parcel;->setDataPosition(I)V\nsget-object v3, ${class}->CREATOR:Landroid/os/Parcelable\$Creator;\n' +
   'invoke-virtual {v1, v3}, Landroid/os/Parcel;->createTypedArray(Landroid/os/Parcelable\$Creator;)[Ljava/lang/Object;\nmove-result-object v3\ncheck-cast v3, [${class}\n' +
   'array-length v5, v3\nif-ne v5, v4, :bad\naget-object v4, v3, v2\ninvoke-static {v0, v4}, Lorg/vinix/bootstrap/RectParcelProbe;->expect${name}(${class}${class})V\n' +
   'const/4 v2, 1\naget-object v4, v3, v2\nif-nez v4, :bad\ninvoke-virtual {v1}, Landroid/os/Parcel;->recycle()V\n'
  mut expect := ''
  for field in ['left', 'top', 'right', 'bottom'] {
   expect += 'iget v0, p0, ${class}->${field}:${kind}\niget v1, p1, ${class}->${field}:${kind}\n'
   if kind == 'F' {
    for reg in ['v0', 'v1'] { expect += 'invoke-static {${reg}}, Ljava/lang/Float;->floatToRawIntBits(F)I\nmove-result ${reg}\n' }
   }
   expect += 'if-ne v0, v1, :bad\n'
  }
  expect += 'return-void\n:bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "${name} parcel coordinates"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
  helpers += method('private static expect${name}(${class}${class})V', expect)
 }
 check += 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-RECT-PARCEL-PASS Rect RectF interface creator update typed-array null extrema special-floats"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void\n:bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "rectangle parcel metadata"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
 os.write_file(dir + '/RectParcelProbe.smali', '.class public Lorg/vinix/bootstrap/RectParcelProbe;\n.super Ljava/lang/Object;\n' + method('public static check()V', check) + helpers)!
}
