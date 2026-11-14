// SPDX-License-Identifier: GPL-2.0-or-later
module bitmapbufferprobe
import os

pub fn install(root string) ! {
 mut code := r'
.class public final Lorg/vinix/bootstrap/BitmapBufferProbe;
.super Ljava/lang/Object;
.method public static check()V
.locals 12
const/4 v0, 2
const/4 v1, 1
sget-object v2, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;
invoke-static {v0, v1, v2}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;
move-result-object v0
const v1, -0xeeddcd
invoke-virtual {v0, v1}, Landroid/graphics/Bitmap;->eraseColor(I)V
'
 // Both primitive heap arrays and typed byte-buffer views, with slices.
 for mode in 0 .. 9 {
  type_name := if mode % 3 == 0 { 'ByteBuffer' } else if mode % 3 == 1 { 'ShortBuffer' } else { 'IntBuffer' }
  element := if mode % 3 == 0 { 'B' } else if mode % 3 == 1 { 'S' } else { 'I' }
  expected := if mode % 3 == 0 { '0x11' } else if mode % 3 == 1 { '0x2211' } else { '-0xccddef' }
  advance := if mode % 3 == 0 { 10 } else if mode % 3 == 1 { 6 } else { 4 }
  // Modes 0..2 allocate native arrays; 3..5 direct views; 6..8 heap views.
  if mode < 3 {
   code += '\nconst/16 v1, 32\ninvoke-static {v1}, Ljava/nio/${type_name};->allocate(I)Ljava/nio/${type_name};\nmove-result-object v2\n'
  } else {
   allocator := if mode < 6 { 'allocateDirect' } else { 'allocate' }
   code += '\nconst/16 v1, 128\ninvoke-static {v1}, Ljava/nio/ByteBuffer;->${allocator}(I)Ljava/nio/ByteBuffer;\nmove-result-object v2\n'
   code += r'
invoke-static {}, Ljava/nio/ByteOrder;->nativeOrder()Ljava/nio/ByteOrder;
move-result-object v3
invoke-virtual {v2, v3}, Ljava/nio/ByteBuffer;->order(Ljava/nio/ByteOrder;)Ljava/nio/ByteBuffer;
const/4 v3, 4
invoke-virtual {v2, v3}, Ljava/nio/Buffer;->position(I)Ljava/nio/Buffer;
invoke-virtual {v2}, Ljava/nio/ByteBuffer;->slice()Ljava/nio/ByteBuffer;
move-result-object v2
invoke-static {}, Ljava/nio/ByteOrder;->nativeOrder()Ljava/nio/ByteOrder;
move-result-object v3
invoke-virtual {v2, v3}, Ljava/nio/ByteBuffer;->order(Ljava/nio/ByteOrder;)Ljava/nio/ByteBuffer;
'
   if mode % 3 != 0 { code += 'invoke-virtual {v2}, Ljava/nio/ByteBuffer;->as${type_name}()Ljava/nio/${type_name};\nmove-result-object v2\n' }
  }
  code += '\nconst/4 v3, 2\ninvoke-virtual {v2, v3}, Ljava/nio/Buffer;->position(I)Ljava/nio/Buffer;\ninvoke-virtual {v0, v2}, Landroid/graphics/Bitmap;->copyPixelsToBuffer(Ljava/nio/Buffer;)V\ninvoke-virtual {v2}, Ljava/nio/Buffer;->position()I\nmove-result v3\nconst/16 v4, ${advance}\ninvoke-static {v3, v4}, Lorg/vinix/bootstrap/Main;->expect(II)V\n'
  code += 'const/4 v3, 2\ninvoke-virtual {v2, v3}, Ljava/nio/${type_name};->get(I)${element}\nmove-result v3\nconst v4, ${expected}\ninvoke-static {v3, v4}, Lorg/vinix/bootstrap/Main;->expect(II)V\n'
  code += 'const/4 v3, 1\ninvoke-virtual {v2, v3}, Ljava/nio/${type_name};->get(I)${element}\nmove-result v3\nconst/4 v4, 0\ninvoke-static {v3, v4}, Lorg/vinix/bootstrap/Main;->expect(II)V\n'
  code += 'const/16 v3, ${advance}\ninvoke-virtual {v2, v3}, Ljava/nio/${type_name};->get(I)${element}\nmove-result v3\nconst/4 v4, 0\ninvoke-static {v3, v4}, Lorg/vinix/bootstrap/Main;->expect(II)V\n'
 }
 for index, failure in ['small', 'readonly', 'unsupported', 'null', 'recycled'] {
  code += '\nconst/16 v1, ${if failure == 'small' { 7 } else { 32 }}\ninvoke-static {v1}, Ljava/nio/ByteBuffer;->allocate(I)Ljava/nio/ByteBuffer;\nmove-result-object v2\n'
  if failure == 'readonly' { code += 'invoke-virtual {v2}, Ljava/nio/ByteBuffer;->asReadOnlyBuffer()Ljava/nio/ByteBuffer;\nmove-result-object v2\n' }
  if failure == 'unsupported' { code += 'const/16 v1, 8\ninvoke-static {v1}, Ljava/nio/LongBuffer;->allocate(I)Ljava/nio/LongBuffer;\nmove-result-object v2\n' }
  if failure == 'null' { code += 'const/4 v2, 0\n' }
  if failure == 'recycled' { code += 'invoke-virtual {v0}, Landroid/graphics/Bitmap;->recycle()V\n' }
  exception := match failure { 'readonly' { 'java/nio/ReadOnlyBufferException' } 'null' { 'java/lang/NullPointerException' } 'recycled' { 'java/lang/IllegalStateException' } else { 'java/lang/RuntimeException' } }
  code += ':begin${index}\ninvoke-virtual {v0, v2}, Landroid/graphics/Bitmap;->copyPixelsToBuffer(Ljava/nio/Buffer;)V\n:end${index}\ngoto :bad\n.catch L${exception}; {:begin${index} .. :end${index}} :caught${index}\n:caught${index}\nmove-exception v3\n'
  if failure != 'null' { code += 'invoke-virtual {v2}, Ljava/nio/Buffer;->position()I\nmove-result v3\nconst/4 v4, 0\ninvoke-static {v3, v4}, Lorg/vinix/bootstrap/Main;->expect(II)V\n' }
 }
 code += r'
const/4 v0, 3
const/4 v1, 2
sget-object v2, Landroid/graphics/Bitmap$Config;->ALPHA_8:Landroid/graphics/Bitmap$Config;
invoke-static {v0, v1, v2}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;
move-result-object v0
const v1, 0x7f000000
invoke-virtual {v0, v1}, Landroid/graphics/Bitmap;->eraseColor(I)V
const/16 v1, 16
invoke-static {v1}, Ljava/nio/ByteBuffer;->allocate(I)Ljava/nio/ByteBuffer;
move-result-object v2
const/4 v1, 1
invoke-virtual {v2, v1}, Ljava/nio/Buffer;->position(I)Ljava/nio/Buffer;
invoke-virtual {v0, v2}, Landroid/graphics/Bitmap;->copyPixelsToBuffer(Ljava/nio/Buffer;)V
invoke-virtual {v2}, Ljava/nio/Buffer;->position()I
move-result v3
const/16 v4, 9
invoke-static {v3, v4}, Lorg/vinix/bootstrap/Main;->expect(II)V
const/4 v1, 0
:alpha_loop
invoke-virtual {v2, v1}, Ljava/nio/ByteBuffer;->get(I)B
move-result v3
const/4 v4, 0
if-eqz v1, :alpha_expect
const/16 v4, 9
if-eq v1, v4, :alpha_zero
const/16 v4, 0x7f
goto :alpha_expect
:alpha_zero
const/4 v4, 0
:alpha_expect
invoke-static {v3, v4}, Lorg/vinix/bootstrap/Main;->expect(II)V
add-int/lit8 v1, v1, 1
const/16 v4, 10
if-lt v1, v4, :alpha_loop
invoke-virtual {v0}, Landroid/graphics/Bitmap;->recycle()V
invoke-static {}, Lorg/vinix/bootstrap/BitmapBufferProbe;->locking()V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BITMAP-BUFFER-PASS direct heap typed views slices padding bounds readonly recycled"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Bitmap buffer copy"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
.end method
'
 code += locking
 os.write_file(root + '/smali/BitmapBufferProbe.smali', code)!
 os.write_file(root + '/smali/BitmapBufferWorker.smali', worker)!
}

const locking = r'
.method private static locking()V
.locals 10
const/4 v8, 0
:again
const/4 v0, 2
const/4 v1, 1
sget-object v2, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;
invoke-static {v0, v1, v2}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;
move-result-object v0
new-instance v1, Lorg/vinix/bootstrap/BitmapBufferWorker;
invoke-direct {v1}, Lorg/vinix/bootstrap/BitmapBufferWorker;-><init>()V
iput-object v0, v1, Lorg/vinix/bootstrap/BitmapBufferWorker;->bitmap:Landroid/graphics/Bitmap;
iput-boolean v8, v1, Lorg/vinix/bootstrap/BitmapBufferWorker;->recycle:Z
new-instance v2, Ljava/lang/Thread;
invoke-direct {v2, v1}, Ljava/lang/Thread;-><init>(Ljava/lang/Runnable;)V
monitor-enter v0
:locked
invoke-virtual {v2}, Ljava/lang/Thread;->start()V
iget-object v3, v1, Lorg/vinix/bootstrap/BitmapBufferWorker;->started:Ljava/util/concurrent/CountDownLatch;
const-wide/16 v4, 3
sget-object v6, Ljava/util/concurrent/TimeUnit;->SECONDS:Ljava/util/concurrent/TimeUnit;
invoke-virtual {v3, v4, v5, v6}, Ljava/util/concurrent/CountDownLatch;->await(JLjava/util/concurrent/TimeUnit;)Z
move-result v3
const/4 v7, 1
invoke-static {v3, v7}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-wide/16 v4, 100
invoke-static {v4, v5}, Ljava/lang/Thread;->sleep(J)V
iget-boolean v3, v1, Lorg/vinix/bootstrap/BitmapBufferWorker;->done:Z
const/4 v7, 0
invoke-static {v3, v7}, Lorg/vinix/bootstrap/Main;->expect(II)V
:unlock
monitor-exit v0
const-wide/16 v4, 3000
invoke-virtual {v2, v4, v5}, Ljava/lang/Thread;->join(J)V
iget-boolean v3, v1, Lorg/vinix/bootstrap/BitmapBufferWorker;->done:Z
const/4 v7, 1
invoke-static {v3, v7}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v0}, Landroid/graphics/Bitmap;->recycle()V
add-int/lit8 v8, v8, 1
const/4 v7, 2
if-lt v8, v7, :again
return-void
.catchall {:locked .. :unlock} :failed
:failed
move-exception v1
monitor-exit v0
throw v1
.end method
'

const worker = r'
.class public final Lorg/vinix/bootstrap/BitmapBufferWorker;
.super Ljava/lang/Object;
.implements Ljava/lang/Runnable;
.field public bitmap:Landroid/graphics/Bitmap;
.field public recycle:Z
.field public volatile done:Z
.field public started:Ljava/util/concurrent/CountDownLatch;
.method public constructor <init>()V
.locals 2
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
new-instance v0, Ljava/util/concurrent/CountDownLatch;
const/4 v1, 1
invoke-direct {v0, v1}, Ljava/util/concurrent/CountDownLatch;-><init>(I)V
iput-object v0, p0, Lorg/vinix/bootstrap/BitmapBufferWorker;->started:Ljava/util/concurrent/CountDownLatch;
return-void
.end method
.method public run()V
.locals 3
iget-object v0, p0, Lorg/vinix/bootstrap/BitmapBufferWorker;->started:Ljava/util/concurrent/CountDownLatch;
invoke-virtual {v0}, Ljava/util/concurrent/CountDownLatch;->countDown()V
iget-object v0, p0, Lorg/vinix/bootstrap/BitmapBufferWorker;->bitmap:Landroid/graphics/Bitmap;
iget-boolean v1, p0, Lorg/vinix/bootstrap/BitmapBufferWorker;->recycle:Z
if-nez v1, :recycle
const/16 v1, 8
invoke-static {v1}, Ljava/nio/ByteBuffer;->allocate(I)Ljava/nio/ByteBuffer;
move-result-object v1
invoke-virtual {v0, v1}, Landroid/graphics/Bitmap;->copyPixelsToBuffer(Ljava/nio/Buffer;)V
goto :done
:recycle
invoke-virtual {v0}, Landroid/graphics/Bitmap;->recycle()V
:done
const/4 v0, 1
iput-boolean v0, p0, Lorg/vinix/bootstrap/BitmapBufferWorker;->done:Z
return-void
.end method
'
