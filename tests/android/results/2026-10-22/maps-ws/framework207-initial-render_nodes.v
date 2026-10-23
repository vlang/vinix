// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Reuse the command recorder for native WS display lists. Child RenderNodes
// remain live references: changing their properties or replacing their display
// lists must not require recording the parent again. Software compositing is
// needed only for group opacity or an explicitly requested compositing layer.
fn framework_render_nodes(smali string) ! {
 node := 'Landroid/graphics/RenderNode;'
 canvas := 'Landroid/graphics/Canvas;'
 picture := 'Landroid/graphics/Picture;'
 path := smali + '/android/graphics/Canvas.smali'
 os.write_file(path, os.read_file(path)! + touch_method('public drawRenderNode(${node})V', 'invoke-virtual {p1, p0}, ${node}->vinixDraw(${canvas})V\nreturn-void'))!
 os.write_file(smali + '/android/graphics/RecordingCanvas.smali',
  '.class public final Landroid/graphics/RecordingCanvas;\n.super Landroid/graphics/VinixPictureCanvas;\n' +
  touch_method('public constructor <init>(${picture}Landroid/graphics/Bitmap;)V', 'invoke-direct {p0, p1, p2}, Landroid/graphics/VinixPictureCanvas;-><init>(${picture}Landroid/graphics/Bitmap;)V\nreturn-void') +
  touch_method('public isHardwareAccelerated()Z', 'const/4 v0, 1\nreturn v0'))!
 os.write_file(smali + '/android/graphics/VinixRenderPicture.smali',
  '.class public final Landroid/graphics/VinixRenderPicture;\n.super ${picture}\n' +
  touch_method('public constructor <init>()V', 'invoke-direct {p0}, ${picture}-><init>()V\nreturn-void') +
  touch_method('public vinixCreateRecordingCanvas(Landroid/graphics/Bitmap;)Landroid/graphics/VinixPictureCanvas;', 'new-instance v0, Landroid/graphics/RecordingCanvas;\ninvoke-direct {v0, p0, p1}, Landroid/graphics/RecordingCanvas;-><init>(${picture}Landroid/graphics/Bitmap;)V\nreturn-object v0'))!
 mut text := '.class public final ${node}\n.super Ljava/lang/Object;\n.field private uniqueId:J\n.field private displayList:${picture}\n.field private recording:${picture}\n.field private drawing:Z\n.field private layerPaint:Landroid/graphics/Paint;\n.field private outline:Landroid/graphics/Outline;\n.field private clipRect:Landroid/graphics/Rect;\n.field private pivotExplicit:Z\n'
 floats := ['Alpha', 'ScaleX', 'ScaleY', 'TranslationX', 'TranslationY', 'TranslationZ', 'RotationX', 'RotationY', 'RotationZ', 'PivotX', 'PivotY', 'Elevation', 'CameraDistance']
 bools := ['ClipToBounds', 'ClipToOutline', 'HasOverlappingRendering', 'UseCompositingLayer', 'ForceDarkAllowed']
 ints := ['Left', 'Top', 'Right', 'Bottom', 'AmbientShadowColor', 'SpotShadowColor']
 for name in floats { text += '.field private ${name}:F\n' }
 for name in bools { text += '.field private ${name}:Z\n' }
 for name in ints { text += '.field private ${name}:I\n' }
 mut init := 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\ninvoke-static {}, Landroid/view/View;->vinixAllocateDrawingId()J\nmove-result-wide v0\niput-wide v0, p0, ${node}->uniqueId:J\nconst/high16 v0, 0x3f800000\n'
 for name in ['Alpha', 'ScaleX', 'ScaleY'] { init += 'iput v0, p0, ${node}->${name}:F\n' }
 init += 'const/high16 v0, 0x44000000\niput v0, p0, ${node}->CameraDistance:F\nconst/4 v0, 1\n'
 for name in ['ClipToBounds', 'HasOverlappingRendering', 'ForceDarkAllowed'] { init += 'iput-boolean v0, p0, ${node}->${name}:Z\n' }
 init += 'const/high16 v0, -0x1000000\n'
 for name in ['AmbientShadowColor', 'SpotShadowColor'] { init += 'iput v0, p0, ${node}->${name}:I\n' }
 text += touch_method('public constructor <init>(Ljava/lang/String;)V', init + 'return-void')
 text += touch_method('public getUniqueId()J', 'iget-wide v0, p0, ${node}->uniqueId:J\nreturn-wide v0')
 for name in floats {
  mut get := 'iget v0, p0, ${node}->${name}:F\nreturn v0'
  if name in ['PivotX', 'PivotY'] {
   dimension := if name == 'PivotX' { 'Width' } else { 'Height' }
   get = 'iget-boolean v0, p0, ${node}->pivotExplicit:Z\nif-nez v0, :explicit\ninvoke-virtual {p0}, ${node}->get${dimension}()I\nmove-result v0\nint-to-float v0, v0\nconst/high16 v1, 0x40000000\ndiv-float/2addr v0, v1\nreturn v0\n:explicit\n' + get
  }
  text += touch_method('public get${name}()F', get)
  mut set := ''
  if name in ['PivotX', 'PivotY'] {
   set += 'iget-boolean v0, p0, ${node}->pivotExplicit:Z\nif-nez v0, :compare\ninvoke-virtual {p0}, ${node}->getPivotX()F\nmove-result v0\niput v0, p0, ${node}->PivotX:F\ninvoke-virtual {p0}, ${node}->getPivotY()F\nmove-result v0\niput v0, p0, ${node}->PivotY:F\nconst/4 v0, 1\niput-boolean v0, p0, ${node}->pivotExplicit:Z\niput p1, p0, ${node}->${name}:F\nreturn v0\n:compare\n'
  }
  set += 'iget v0, p0, ${node}->${name}:F\ncmpl-float v0, v0, p1\nif-eqz v0, :same\niput p1, p0, ${node}->${name}:F\nconst/4 v0, 1\nreturn v0\n:same\nconst/4 v0, 0\nreturn v0'
  text += touch_method('public set${name}(F)Z', set)
 }
 for name in bools {
  if name == 'UseCompositingLayer' { continue }
  getter := if name == 'HasOverlappingRendering' { 'hasOverlappingRendering' } else if name == 'ForceDarkAllowed' { 'isForceDarkAllowed' } else { 'get' + name }
  text += touch_method('public ${getter}()Z', 'iget-boolean v0, p0, ${node}->${name}:Z\nreturn v0')
  text += touch_method('public set${name}(Z)Z', 'iget-boolean v0, p0, ${node}->${name}:Z\nif-eq v0, p1, :same\niput-boolean p1, p0, ${node}->${name}:Z\nconst/4 v0, 1\nreturn v0\n:same\nconst/4 v0, 0\nreturn v0')
 }
 for name in ints {
  text += touch_method('public get${name}()I', 'iget v0, p0, ${node}->${name}:I\nreturn v0')
  text += touch_method('public set${name}(I)Z', 'iget v0, p0, ${node}->${name}:I\nif-eq v0, p1, :same\niput p1, p0, ${node}->${name}:I\nconst/4 v0, 1\nreturn v0\n:same\nconst/4 v0, 0\nreturn v0')
 }
 for dimension, sides in {'Width': ['Right', 'Left'], 'Height': ['Bottom', 'Top']} {
  text += touch_method('public get${dimension}()I', 'iget v0, p0, ${node}->${sides[0]}:I\niget v1, p0, ${node}->${sides[1]}:I\nsub-int/2addr v0, v1\nreturn v0')
  text += touch_method('public offset${sides[1]}And${sides[0]}(I)Z', 'if-eqz p1, :same\niget v0, p0, ${node}->${sides[0]}:I\nadd-int/2addr v0, p1\niput v0, p0, ${node}->${sides[0]}:I\niget v0, p0, ${node}->${sides[1]}:I\nadd-int/2addr v0, p1\niput v0, p0, ${node}->${sides[1]}:I\nconst/4 v0, 1\nreturn v0\n:same\nconst/4 v0, 0\nreturn v0')
 }
 mut position := 'const/4 v0, 0\n'
 for i, side in ['Left', 'Top', 'Right', 'Bottom'] {
  position += 'invoke-virtual {p0, p${i + 1}}, ${node}->set${side}(I)Z\nmove-result v1\nor-int/2addr v0, v1\n'
 }
 text += touch_method('public setPosition(IIII)Z', position + 'return v0')
 text += touch_method('public setPosition(Landroid/graphics/Rect;)Z', 'iget v0, p1, Landroid/graphics/Rect;->left:I\niget v1, p1, Landroid/graphics/Rect;->top:I\niget v2, p1, Landroid/graphics/Rect;->right:I\niget v3, p1, Landroid/graphics/Rect;->bottom:I\ninvoke-virtual {p0, v0, v1, v2, v3}, ${node}->setPosition(IIII)Z\nmove-result v0\nreturn v0')
 text += touch_method('public isPivotExplicitlySet()Z', 'iget-boolean v0, p0, ${node}->pivotExplicit:Z\nreturn v0')
 text += touch_method('public resetPivot()Z', 'iget-boolean v0, p0, ${node}->pivotExplicit:Z\nconst/4 v1, 0\niput-boolean v1, p0, ${node}->pivotExplicit:Z\nreturn v0')
 text += touch_method('public setUseCompositingLayer(ZLandroid/graphics/Paint;)Z', 'iget-boolean v1, p0, ${node}->UseCompositingLayer:Z\nxor-int/2addr v1, p1\niget-object v0, p0, ${node}->layerPaint:Landroid/graphics/Paint;\nif-nez v0, :changed\nif-eqz p2, :copy\n:changed\nconst/4 v1, 1\n:copy\niput-boolean p1, p0, ${node}->UseCompositingLayer:Z\nmove-object v0, p2\nif-eqz v0, :store\nnew-instance v0, Landroid/graphics/Paint;\ninvoke-direct {v0, p2}, Landroid/graphics/Paint;-><init>(Landroid/graphics/Paint;)V\n:store\niput-object v0, p0, ${node}->layerPaint:Landroid/graphics/Paint;\nreturn v1')
 for kind, member in {'Outline': 'outline', 'Rect': 'clipRect'} {
  name := if kind == 'Rect' { 'ClipRect' } else { 'Outline' }
  text += touch_method('public set${name}(Landroid/graphics/${kind};)Z', 'iget-object v0, p0, ${node}->${member}:Landroid/graphics/${kind};\nif-nez v0, :copy\nif-nez p1, :copy\nconst/4 v0, 0\nreturn v0\n:copy\nmove-object v0, p1\nif-eqz p1, :store\nnew-instance v0, Landroid/graphics/${kind};\ninvoke-direct {v0, p1}, Landroid/graphics/${kind};-><init>(Landroid/graphics/${kind};)V\n:store\niput-object v0, p0, ${node}->${member}:Landroid/graphics/${kind};\nconst/4 v0, 1\nreturn v0')
 }
 text += touch_method('public beginRecording()Landroid/graphics/RecordingCanvas;', 'invoke-virtual {p0}, ${node}->getWidth()I\nmove-result v0\ninvoke-virtual {p0}, ${node}->getHeight()I\nmove-result v1\ninvoke-virtual {p0, v0, v1}, ${node}->beginRecording(II)Landroid/graphics/RecordingCanvas;\nmove-result-object v0\nreturn-object v0')
 text += touch_method('public beginRecording(II)Landroid/graphics/RecordingCanvas;', 'iget-object v0, p0, ${node}->recording:${picture}\nif-nez v0, :bad\nnew-instance v0, Landroid/graphics/VinixRenderPicture;\ninvoke-direct {v0}, Landroid/graphics/VinixRenderPicture;-><init>()V\ninvoke-virtual {v0, p1, p2}, ${picture}->beginRecording(II)${canvas}\nmove-result-object v1\niput-object v0, p0, ${node}->recording:${picture}\ncheck-cast v1, Landroid/graphics/RecordingCanvas;\nreturn-object v1\n:bad\n' + render_node_illegal_state('Recording already in progress'))
 text += touch_method('public endRecording()V', 'iget-object v0, p0, ${node}->recording:${picture}\nif-eqz v0, :bad\ninvoke-virtual {v0}, ${picture}->endRecording()V\niput-object v0, p0, ${node}->displayList:${picture}\nconst/4 v0, 0\niput-object v0, p0, ${node}->recording:${picture}\nreturn-void\n:bad\n' + render_node_illegal_state('No recording in progress'))
 text += touch_method('public hasDisplayList()Z', 'iget-object v0, p0, ${node}->displayList:${picture}\nif-eqz v0, :no\nconst/4 v0, 1\nreturn v0\n:no\nconst/4 v0, 0\nreturn v0')
 text += touch_method('public discardDisplayList()V', 'const/4 v0, 0\niput-object v0, p0, ${node}->displayList:${picture}\nreturn-void')
 text += touch_method('public getMatrix(Landroid/graphics/Matrix;)V', '
iget v0, p0, ${node}->RotationX:F
const/4 v1, 0
cmpl-float v0, v0, v1
if-nez v0, :unsupported
iget v0, p0, ${node}->RotationY:F
cmpl-float v0, v0, v1
if-nez v0, :unsupported
invoke-virtual {p1}, Landroid/graphics/Matrix;->reset()V
invoke-virtual {p0}, ${node}->getPivotX()F
move-result v3
invoke-virtual {p0}, ${node}->getPivotY()F
move-result v4
iget v1, p0, ${node}->ScaleX:F
iget v2, p0, ${node}->ScaleY:F
invoke-virtual {p1, v1, v2, v3, v4}, Landroid/graphics/Matrix;->setScale(FFFF)V
iget v1, p0, ${node}->RotationZ:F
invoke-virtual {p1, v1, v3, v4}, Landroid/graphics/Matrix;->postRotate(FFF)Z
iget v1, p0, ${node}->TranslationX:F
iget v2, p0, ${node}->TranslationY:F
invoke-virtual {p1, v1, v2}, Landroid/graphics/Matrix;->postTranslate(FF)Z
return-void
:unsupported
new-instance v0, Ljava/lang/UnsupportedOperationException;
const-string v1, "Native WS RenderNode does not support perspective rotation"
invoke-direct {v0, v1}, Ljava/lang/UnsupportedOperationException;-><init>(Ljava/lang/String;)V
throw v0')
 text += touch_method('public getInverseMatrix(Landroid/graphics/Matrix;)V', 'new-instance v0, Landroid/graphics/Matrix;\ninvoke-direct {v0}, Landroid/graphics/Matrix;-><init>()V\ninvoke-virtual {p0, v0}, ${node}->getMatrix(Landroid/graphics/Matrix;)V\ninvoke-virtual {v0, p1}, Landroid/graphics/Matrix;->invert(Landroid/graphics/Matrix;)Z\nreturn-void')
 text += touch_method('public hasIdentityMatrix()Z', 'new-instance v0, Landroid/graphics/Matrix;\ninvoke-direct {v0}, Landroid/graphics/Matrix;-><init>()V\ninvoke-virtual {p0, v0}, ${node}->getMatrix(Landroid/graphics/Matrix;)V\ninvoke-virtual {v0}, Landroid/graphics/Matrix;->isIdentity()Z\nmove-result v0\nreturn v0')
 text += touch_method('private vinixDrawContents(${canvas})V', render_node_draw_contents())
 text += touch_method('public vinixDraw(${canvas})V', render_node_draw())
 os.write_file(smali + '/android/graphics/RenderNode.smali', text)!
}

fn render_node_illegal_state(message string) string {
 return 'new-instance v0, Ljava/lang/IllegalStateException;\nconst-string v1, "${message}"\ninvoke-direct {v0, v1}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/String;)V\nthrow v0'
}

fn render_node_draw_contents() string {
 return '
invoke-virtual {p1}, Landroid/graphics/Canvas;->save()I
move-result v0
:start
iget v1, p0, Landroid/graphics/RenderNode;->Left:I
iget v2, p0, Landroid/graphics/RenderNode;->Top:I
int-to-float v1, v1
int-to-float v2, v2
invoke-virtual {p1, v1, v2}, Landroid/graphics/Canvas;->translate(FF)V
new-instance v1, Landroid/graphics/Matrix;
invoke-direct {v1}, Landroid/graphics/Matrix;-><init>()V
invoke-virtual {p0, v1}, Landroid/graphics/RenderNode;->getMatrix(Landroid/graphics/Matrix;)V
invoke-virtual {p1, v1}, Landroid/graphics/Canvas;->concat(Landroid/graphics/Matrix;)V
iget-boolean v1, p0, Landroid/graphics/RenderNode;->ClipToBounds:Z
if-eqz v1, :extra_clip
invoke-virtual {p0}, Landroid/graphics/RenderNode;->getWidth()I
move-result v3
invoke-virtual {p0}, Landroid/graphics/RenderNode;->getHeight()I
move-result v4
const/4 v1, 0
invoke-virtual {p1, v1, v1, v3, v4}, Landroid/graphics/Canvas;->clipRect(IIII)Z
:extra_clip
iget-object v1, p0, Landroid/graphics/RenderNode;->clipRect:Landroid/graphics/Rect;
if-eqz v1, :outline
invoke-virtual {p1, v1}, Landroid/graphics/Canvas;->clipRect(Landroid/graphics/Rect;)Z
:outline
iget-boolean v1, p0, Landroid/graphics/RenderNode;->ClipToOutline:Z
if-eqz v1, :draw
iget-object v1, p0, Landroid/graphics/RenderNode;->outline:Landroid/graphics/Outline;
if-eqz v1, :draw
iget v2, v1, Landroid/graphics/Outline;->mMode:I
const/4 v3, 1
if-ne v2, v3, :path_outline
new-instance v2, Landroid/graphics/Path;
invoke-direct {v2}, Landroid/graphics/Path;-><init>()V
iget-object v3, v1, Landroid/graphics/Outline;->mRect:Landroid/graphics/Rect;
new-instance v4, Landroid/graphics/RectF;
invoke-direct {v4, v3}, Landroid/graphics/RectF;-><init>(Landroid/graphics/Rect;)V
iget v5, v1, Landroid/graphics/Outline;->mRadius:F
sget-object v6, Landroid/graphics/Path$Direction;->CW:Landroid/graphics/Path$Direction;
invoke-virtual {v2, v4, v5, v5, v6}, Landroid/graphics/Path;->addRoundRect(Landroid/graphics/RectF;FFLandroid/graphics/Path$Direction;)V
invoke-virtual {p1, v2}, Landroid/graphics/Canvas;->clipPath(Landroid/graphics/Path;)Z
goto :draw
:path_outline
const/4 v3, 2
if-ne v2, v3, :draw
iget-object v2, v1, Landroid/graphics/Outline;->mPath:Landroid/graphics/Path;
if-eqz v2, :draw
invoke-virtual {p1, v2}, Landroid/graphics/Canvas;->clipPath(Landroid/graphics/Path;)Z
:draw
iget-object v1, p0, Landroid/graphics/RenderNode;->displayList:Landroid/graphics/Picture;
invoke-virtual {v1, p1}, Landroid/graphics/Picture;->draw(Landroid/graphics/Canvas;)V
:end
invoke-virtual {p1, v0}, Landroid/graphics/Canvas;->restoreToCount(I)V
return-void
:failed
move-exception v1
invoke-virtual {p1, v0}, Landroid/graphics/Canvas;->restoreToCount(I)V
throw v1
.catchall {:start .. :end} :failed'
}

fn render_node_draw() string {
 return '
iget-object v0, p0, Landroid/graphics/RenderNode;->displayList:Landroid/graphics/Picture;
if-eqz v0, :return
iget-boolean v0, p0, Landroid/graphics/RenderNode;->drawing:Z
if-nez v0, :cycle
iget v0, p0, Landroid/graphics/RenderNode;->Alpha:F
const/4 v1, 0
cmpg-float v1, v0, v1
if-lez v1, :return
const/4 v1, 1
iput-boolean v1, p0, Landroid/graphics/RenderNode;->drawing:Z
const/4 v1, 0
const/4 v2, 0
:start
const/high16 v3, 0x3f800000
cmpl-float v3, v0, v3
if-nez v3, :layer
iget-boolean v3, p0, Landroid/graphics/RenderNode;->UseCompositingLayer:Z
if-nez v3, :layer
invoke-direct {p0, p1}, Landroid/graphics/RenderNode;->vinixDrawContents(Landroid/graphics/Canvas;)V
goto :done
:layer
invoke-virtual {p1}, Landroid/graphics/Canvas;->getWidth()I
move-result v3
invoke-virtual {p1}, Landroid/graphics/Canvas;->getHeight()I
move-result v4
if-lez v3, :done
if-lez v4, :done
sget-object v5, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;
invoke-static {v3, v4, v5}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;
move-result-object v1
const/4 v3, 0
invoke-virtual {v1, v3}, Landroid/graphics/Bitmap;->eraseColor(I)V
new-instance v2, Landroid/graphics/Canvas;
invoke-direct {v2, v1}, Landroid/graphics/Canvas;-><init>(Landroid/graphics/Bitmap;)V
invoke-virtual {p1}, Landroid/graphics/Canvas;->getMatrix()Landroid/graphics/Matrix;
move-result-object v3
invoke-virtual {v2, v3}, Landroid/graphics/Canvas;->setMatrix(Landroid/graphics/Matrix;)V
invoke-direct {p0, v2}, Landroid/graphics/RenderNode;->vinixDrawContents(Landroid/graphics/Canvas;)V
iget-boolean v3, p0, Landroid/graphics/RenderNode;->UseCompositingLayer:Z
if-eqz v3, :default_paint
iget-object v3, p0, Landroid/graphics/RenderNode;->layerPaint:Landroid/graphics/Paint;
if-eqz v3, :default_paint
new-instance v4, Landroid/graphics/Paint;
invoke-direct {v4, v3}, Landroid/graphics/Paint;-><init>(Landroid/graphics/Paint;)V
goto :alpha
:default_paint
new-instance v4, Landroid/graphics/Paint;
invoke-direct {v4}, Landroid/graphics/Paint;-><init>()V
:alpha
invoke-virtual {v4}, Landroid/graphics/Paint;->getAlpha()I
move-result v3
int-to-float v3, v3
iget v0, p0, Landroid/graphics/RenderNode;->Alpha:F
mul-float/2addr v3, v0
invoke-static {v3}, Ljava/lang/Math;->round(F)I
move-result v3
const/16 v5, 255
invoke-static {v3, v5}, Ljava/lang/Math;->min(II)I
move-result v3
invoke-virtual {v4, v3}, Landroid/graphics/Paint;->setAlpha(I)V
invoke-virtual {p1}, Landroid/graphics/Canvas;->save()I
move-result v5
:composite
const/4 v3, 0
invoke-virtual {p1, v3}, Landroid/graphics/Canvas;->setMatrix(Landroid/graphics/Matrix;)V
invoke-virtual {p1, v1, v3, v3, v4}, Landroid/graphics/Canvas;->drawBitmap(Landroid/graphics/Bitmap;FFLandroid/graphics/Paint;)V
:composite_end
invoke-virtual {p1, v5}, Landroid/graphics/Canvas;->restoreToCount(I)V
goto :done
:composite_failed
move-exception v4
invoke-virtual {p1, v5}, Landroid/graphics/Canvas;->restoreToCount(I)V
throw v4
.catchall {:composite .. :composite_end} :composite_failed
:done
const/4 v3, 0
if-eqz v2, :bitmap
invoke-virtual {v2, v3}, Landroid/graphics/Canvas;->setBitmap(Landroid/graphics/Bitmap;)V
:bitmap
if-eqz v1, :reset
invoke-virtual {v1}, Landroid/graphics/Bitmap;->recycle()V
:reset
iput-boolean v3, p0, Landroid/graphics/RenderNode;->drawing:Z
:return
return-void
:failed
move-exception v4
const/4 v3, 0
if-eqz v2, :failed_bitmap
invoke-virtual {v2, v3}, Landroid/graphics/Canvas;->setBitmap(Landroid/graphics/Bitmap;)V
:failed_bitmap
if-eqz v1, :failed_reset
invoke-virtual {v1}, Landroid/graphics/Bitmap;->recycle()V
:failed_reset
iput-boolean v3, p0, Landroid/graphics/RenderNode;->drawing:Z
throw v4
.catchall {:start .. :composite} :failed
.catchall {:composite_end .. :done} :failed
:cycle
' + render_node_illegal_state('RenderNode display list contains a cycle')
}
