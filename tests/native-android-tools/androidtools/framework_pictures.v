// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn picture_method(signature string, body string) string {
 return '.method public ' + signature + '\n.locals 4\n' + body + '\n.end method\n'
}

fn picture_types(descriptor string) []string {
 mut types := []string{}
 mut at := 0
 for at < descriptor.len {
  start := at
  for descriptor[at] == `[` { at++ }
  if descriptor[at] == `L` {
   for descriptor[at] != `;` { at++ }
  }
  at++
  types << descriptor[start..at]
 }
 return types
}

// Keep drawing commands, rather than a raster at the recording dimensions.
// Mutable value arguments are captured at the time of each call. Playback
// consequently uses the destination Canvas's scale, matrix and clip.
fn framework_pictures(smali string) ! {
 canvas_path := smali + '/android/graphics/Canvas.smali'
 mut canvas := os.read_file(canvas_path)!
 canvas = framework_replace_method(canvas, 'drawPicture(Landroid/graphics/Picture;)V', picture_method('drawPicture(Landroid/graphics/Picture;)V',
  'invoke-virtual {p1, p0}, Landroid/graphics/Picture;->draw(Landroid/graphics/Canvas;)V\nreturn-void'))!
 for rect in ['Rect', 'RectF'] {
  mut body := 'invoke-virtual {p0}, Landroid/graphics/Canvas;->save()I\nmove-result v0\n:begin\n'
  for i, name in ['left', 'top', 'right', 'bottom'] {
   body += 'iget v${i}, p2, Landroid/graphics/${rect};->${name}:' + if rect == 'Rect' { 'I\nint-to-float v${i}, v${i}\n' } else { 'F\n' }
  }
  body += 'sub-float/2addr v2, v0\nsub-float/2addr v3, v1\ninvoke-virtual {p0, v0, v1}, Landroid/graphics/Canvas;->translate(FF)V\n' +
   'invoke-virtual {p1}, Landroid/graphics/Picture;->getWidth()I\nmove-result v0\nif-eqz v0, :draw\nint-to-float v0, v0\ndiv-float/2addr v2, v0\n' +
   'invoke-virtual {p1}, Landroid/graphics/Picture;->getHeight()I\nmove-result v0\nif-eqz v0, :draw\nint-to-float v0, v0\ndiv-float/2addr v3, v0\n' +
   'invoke-virtual {p0, v2, v3}, Landroid/graphics/Canvas;->scale(FF)V\n:draw\ninvoke-virtual {p0, p1}, Landroid/graphics/Canvas;->drawPicture(Landroid/graphics/Picture;)V\n:end\n' +
   'invoke-virtual {p0}, Landroid/graphics/Canvas;->restore()V\nreturn-void\n:failed\nmove-exception v0\ninvoke-virtual {p0}, Landroid/graphics/Canvas;->restore()V\nthrow v0\n.catchall {:begin .. :end} :failed'
  canvas = framework_replace_method(canvas, 'drawPicture(Landroid/graphics/Picture;Landroid/graphics/${rect};)V',
   picture_method('drawPicture(Landroid/graphics/Picture;Landroid/graphics/${rect};)V', body))!
 }
 os.write_file(canvas_path, canvas)!
 object_init := picture_method('constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void')
 os.write_file(smali + '/android/graphics/VinixPictureCommand.smali',
  '.class public abstract Landroid/graphics/VinixPictureCommand;\n.super Ljava/lang/Object;\n' + object_init +
  '.method public abstract apply(Landroid/graphics/Canvas;Landroid/graphics/Matrix;I)V\n.end method\n')!
 mut recording := '.class public Landroid/graphics/VinixPictureCanvas;\n.super Landroid/graphics/Canvas;\n' +
  '.field public owner:Landroid/graphics/Picture;\n.field private nested:Z\n' +
  picture_method('constructor <init>(Landroid/graphics/Picture;Landroid/graphics/Bitmap;)V',
   'invoke-direct {p0, p2}, Landroid/graphics/Canvas;-><init>(Landroid/graphics/Bitmap;)V\niput-object p1, p0, Landroid/graphics/VinixPictureCanvas;->owner:Landroid/graphics/Picture;\nreturn-void')
 states := ['clipPath', 'clipRect', 'concat', 'restore', 'restoreToCount', 'rotate', 'save', 'saveLayer', 'scale', 'setMatrix', 'translate']
 mut index := 0
 for line in canvas.split_into_lines() {
  if !line.starts_with('.method public ') || line.contains(' final ') { continue }
  signature := line.all_after('.method public ')
  name := signature.all_before('(')
  state := name in states
  if !name.starts_with('draw') && !state { continue }
  types := picture_types(signature.all_after('(').all_before(')'))
  if types.len > 10 || types.any(it in ['J', 'D']) { return error('unsupported Picture command: ' + signature) }
  result := signature.all_after(')')
  class := 'Landroid/graphics/VinixPictureCommand${index};'
  index++
  mut command := '.class public final ' + class + '\n.super Landroid/graphics/VinixPictureCommand;\n' +
   picture_method('constructor <init>()V', 'invoke-direct {p0}, Landroid/graphics/VinixPictureCommand;-><init>()V\nreturn-void')
  mut body := 'iget-object v1, p0, Landroid/graphics/VinixPictureCanvas;->owner:Landroid/graphics/Picture;\nif-nez v1, :valid\nnew-instance v0, Ljava/lang/IllegalStateException;\nconst-string v1, "Picture recording has ended"\ninvoke-direct {v0, v1}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/String;)V\nthrow v0\n:valid\n'
  if state { body += 'iget-boolean v1, p0, Landroid/graphics/VinixPictureCanvas;->nested:Z\nif-nez v1, :nested\n' }
  if name == 'drawPicture' {
   body += 'if-ne p1, v1, :not_self\nnew-instance v0, Ljava/lang/IllegalArgumentException;\nconst-string v1, "A Picture cannot record itself"\ninvoke-direct {v0, v1}, Ljava/lang/IllegalArgumentException;-><init>(Ljava/lang/String;)V\nthrow v0\n:not_self\n'
  }
  body += 'new-instance v0, ${class}\ninvoke-direct {v0}, ${class}-><init>()V\n'
  mut apply := 'move-object v0, p1\n'
  for i, kind in types {
   object := kind.starts_with('L') || kind.starts_with('[')
   suffix := if object { '-object' } else if kind == 'Z' { '-boolean' } else { '' }
   command += '.field public a${i}:${kind}\n'
   body += 'move' + if object { '-object' } else { '' } + ' v2, p${i + 1}\n'
   if kind in ['Landroid/graphics/Paint;', 'Landroid/graphics/Path;', 'Landroid/graphics/Matrix;',
    'Landroid/graphics/Rect;', 'Landroid/graphics/RectF;', 'Landroid/graphics/Picture;'] {
    body += 'if-eqz v2, :captured${i}\nnew-instance v3, ${kind}\ninvoke-direct {v3, v2}, ${kind}-><init>(${kind})V\nmove-object v2, v3\n:captured${i}\n'
   } else if kind.starts_with('[') {
    body += 'if-eqz v2, :captured${i}\ninvoke-virtual {v2}, ${kind}->clone()Ljava/lang/Object;\nmove-result-object v2\ncheck-cast v2, ${kind}\n:captured${i}\n'
   } else if kind == 'Ljava/lang/CharSequence;' {
    body += 'if-eqz v2, :captured${i}\ninvoke-interface {v2}, Ljava/lang/CharSequence;->toString()Ljava/lang/String;\nmove-result-object v2\n:captured${i}\n'
   }
   body += 'iput${suffix} v2, v0, ${class}->a${i}:${kind}\n'
   apply += 'iget${suffix} v${i + 1}, p0, ${class}->a${i}:${kind}\n'
  }
  if state {
   body += 'const/4 v1, 1\niput-boolean v1, p0, Landroid/graphics/VinixPictureCanvas;->nested:Z\n:super_begin\ninvoke-super/range {p0 .. p${types.len}}, Landroid/graphics/Canvas;->${signature}\n'
   if result != 'V' { body += 'move-result v3\n' }
   body += ':super_end\nconst/4 v1, 0\niput-boolean v1, p0, Landroid/graphics/VinixPictureCanvas;->nested:Z\n'
  }
  body += 'iget-object v1, p0, Landroid/graphics/VinixPictureCanvas;->owner:Landroid/graphics/Picture;\niget-object v1, v1, Landroid/graphics/Picture;->commands:Ljava/util/ArrayList;\ninvoke-virtual {v1, v0}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z\n' +
   if result == 'V' { 'return-void\n' } else { 'return v3\n' }
  if state {
   body += ':nested\ninvoke-super/range {p0 .. p${types.len}}, Landroid/graphics/Canvas;->${signature}\n' +
    if result == 'V' { 'return-void\n' } else { 'move-result v3\nreturn v3\n' }
   body += ':super_failed\nmove-exception v0\nconst/4 v1, 0\niput-boolean v1, p0, Landroid/graphics/VinixPictureCanvas;->nested:Z\nthrow v0\n.catchall {:super_begin .. :super_end} :super_failed\n'
  }
  if name == 'restoreToCount' { apply += 'add-int/2addr v1, p3\nadd-int/lit8 v1, v1, -1\n' }
  if name == 'setMatrix' {
   apply += 'new-instance v2, Landroid/graphics/Matrix;\ninvoke-direct {v2, p2}, Landroid/graphics/Matrix;-><init>(Landroid/graphics/Matrix;)V\nif-eqz v1, :identity\ninvoke-virtual {v2, v1}, Landroid/graphics/Matrix;->preConcat(Landroid/graphics/Matrix;)Z\n:identity\nmove-object v1, v2\n'
  }
  apply += 'invoke-virtual/range {v0 .. v${types.len}}, Landroid/graphics/Canvas;->${signature}\nreturn-void\n'
  command += '.method public apply(Landroid/graphics/Canvas;Landroid/graphics/Matrix;I)V\n.locals 12\n' + apply + '.end method\n'
  os.write_file(smali + '/android/graphics/VinixPictureCommand${index - 1}.smali', command)!
  recording += picture_method(signature, body)
 }
 recording += picture_method('setBitmap(Landroid/graphics/Bitmap;)V', 'new-instance v0, Ljava/lang/IllegalStateException;\nconst-string v1, "Picture canvas storage cannot be replaced"\ninvoke-direct {v0, v1}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/String;)V\nthrow v0')
 os.write_file(smali + '/android/graphics/VinixPictureCanvas.smali', recording)!
 framework_picture_class(smali)!
}

fn framework_picture_class(smali string) ! {
 mut picture := '.class public Landroid/graphics/Picture;\n.super Ljava/lang/Object;\n.field public commands:Ljava/util/ArrayList;\n.field private recording:Landroid/graphics/VinixPictureCanvas;\n.field private width:I\n.field private height:I\n'
 picture += picture_method('constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nnew-instance v0, Ljava/util/ArrayList;\ninvoke-direct {v0}, Ljava/util/ArrayList;-><init>()V\niput-object v0, p0, Landroid/graphics/Picture;->commands:Ljava/util/ArrayList;\nreturn-void')
 picture += picture_method('constructor <init>(Landroid/graphics/Picture;)V', 'invoke-direct {p0}, Landroid/graphics/Picture;-><init>()V\nif-eqz p1, :done\nnew-instance v0, Ljava/util/ArrayList;\niget-object v1, p1, Landroid/graphics/Picture;->commands:Ljava/util/ArrayList;\ninvoke-direct {v0, v1}, Ljava/util/ArrayList;-><init>(Ljava/util/Collection;)V\niput-object v0, p0, Landroid/graphics/Picture;->commands:Ljava/util/ArrayList;\niget v0, p1, Landroid/graphics/Picture;->width:I\niput v0, p0, Landroid/graphics/Picture;->width:I\niget v0, p1, Landroid/graphics/Picture;->height:I\niput v0, p0, Landroid/graphics/Picture;->height:I\n:done\nreturn-void')
 picture += picture_method('vinixCreateRecordingCanvas(Landroid/graphics/Bitmap;)Landroid/graphics/VinixPictureCanvas;', 'new-instance v0, Landroid/graphics/VinixPictureCanvas;\ninvoke-direct {v0, p0, p1}, Landroid/graphics/VinixPictureCanvas;-><init>(Landroid/graphics/Picture;Landroid/graphics/Bitmap;)V\nreturn-object v0')
 picture += picture_method('beginRecording(II)Landroid/graphics/Canvas;', 'invoke-virtual {p0}, Landroid/graphics/Picture;->endRecording()V\nnew-instance v0, Ljava/util/ArrayList;\ninvoke-direct {v0}, Ljava/util/ArrayList;-><init>()V\niput-object v0, p0, Landroid/graphics/Picture;->commands:Ljava/util/ArrayList;\niput p1, p0, Landroid/graphics/Picture;->width:I\niput p2, p0, Landroid/graphics/Picture;->height:I\nconst/4 v0, 1\ninvoke-static {p1, v0}, Ljava/lang/Math;->max(II)I\nmove-result v1\ninvoke-static {p2, v0}, Ljava/lang/Math;->max(II)I\nmove-result v2\nsget-object v3, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;\ninvoke-static {v1, v2, v3}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;\nmove-result-object v1\ninvoke-virtual {p0, v1}, Landroid/graphics/Picture;->vinixCreateRecordingCanvas(Landroid/graphics/Bitmap;)Landroid/graphics/VinixPictureCanvas;\nmove-result-object v0\niput-object v0, p0, Landroid/graphics/Picture;->recording:Landroid/graphics/VinixPictureCanvas;\nreturn-object v0')
 picture += picture_method('endRecording()V', 'iget-object v0, p0, Landroid/graphics/Picture;->recording:Landroid/graphics/VinixPictureCanvas;\nif-eqz v0, :done\nconst/4 v1, 0\niput-object v1, v0, Landroid/graphics/VinixPictureCanvas;->owner:Landroid/graphics/Picture;\niput-object v1, p0, Landroid/graphics/Picture;->recording:Landroid/graphics/VinixPictureCanvas;\n:done\nreturn-void')
 for name in ['width', 'height'] {
  picture += picture_method('get' + name.capitalize() + '()I', 'iget v0, p0, Landroid/graphics/Picture;->${name}:I\nreturn v0')
 }
 picture += picture_method('requiresHardwareAcceleration()Z', 'const/4 v0, 0\nreturn v0')
 // More locals for the playback loop and the enclosing save/restore guard.
 picture += '.method public draw(Landroid/graphics/Canvas;)V\n.locals 8\n' +
  'invoke-virtual {p0}, Landroid/graphics/Picture;->endRecording()V\ninvoke-virtual {p1}, Landroid/graphics/Canvas;->getMatrix()Landroid/graphics/Matrix;\nmove-result-object v2\ninvoke-virtual {p1}, Landroid/graphics/Canvas;->save()I\nmove-result v0\ninvoke-virtual {p1}, Landroid/graphics/Canvas;->getSaveCount()I\nmove-result v3\n:begin\niget-object v1, p0, Landroid/graphics/Picture;->commands:Ljava/util/ArrayList;\ninvoke-virtual {v1}, Ljava/util/ArrayList;->iterator()Ljava/util/Iterator;\nmove-result-object v1\n:loop\ninvoke-interface {v1}, Ljava/util/Iterator;->hasNext()Z\nmove-result v4\nif-eqz v4, :end\ninvoke-interface {v1}, Ljava/util/Iterator;->next()Ljava/lang/Object;\nmove-result-object v4\ncheck-cast v4, Landroid/graphics/VinixPictureCommand;\ninvoke-virtual {v4, p1, v2, v3}, Landroid/graphics/VinixPictureCommand;->apply(Landroid/graphics/Canvas;Landroid/graphics/Matrix;I)V\ngoto :loop\n:end\ninvoke-virtual {p1, v0}, Landroid/graphics/Canvas;->restoreToCount(I)V\nreturn-void\n:failed\nmove-exception v1\ninvoke-virtual {p1, v0}, Landroid/graphics/Canvas;->restoreToCount(I)V\nthrow v1\n.catchall {:begin .. :end} :failed\n.end method\n'
 os.write_file(smali + '/android/graphics/Picture.smali', picture)!
}
