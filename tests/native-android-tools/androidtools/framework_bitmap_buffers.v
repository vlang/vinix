// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_bitmap_buffers_source(original string) !string {
	for declaration in ['.method public copyPixelsToBuffer(Ljava/nio/Buffer;)V',
		'.method public recycle()V',
		'.method private static native native_copy_to_buffer(JLjava/nio/Buffer;II)V'] {
		if original.split_into_lines().filter(it == declaration).len != 1 {
			return error('expected original Bitmap declaration: ' + declaration)
		}
	}
	for marker in ['vinixCopyPixelsToBuffer', 'vinixRecycle'] {
		if original.contains(marker) { return error('bitmap monitor helper already present') }
	}
	mut text := framework_replace_method(original, 'copyPixelsToBuffer(Ljava/nio/Buffer;)V', bitmap_buffer_copy)!
	// DEX managed methods need explicit monitor instructions. The declared
	// synchronized flag alone does not provide their locking semantics.
	text = text.replace('.method public recycle()V', '.method private vinixRecycle()V')
	text += bitmap_buffer_monitor('copyPixelsToBuffer', 'vinixCopyPixelsToBuffer', true)
	text += bitmap_buffer_monitor('recycle', 'vinixRecycle', false)
	return text
}

fn bitmap_buffer_monitor(name string, helper string, buffer bool) string {
	argument := if buffer { 'Ljava/nio/Buffer;' } else { '' }
	registers := if buffer { 'p0, p1' } else { 'p0' }
	return '\n.method public declared-synchronized ${name}(${argument})V\n.locals 1\nmonitor-enter p0\n:begin\ninvoke-direct {${registers}}, Landroid/graphics/Bitmap;->${helper}(${argument})V\n:end\nmonitor-exit p0\nreturn-void\n.catchall {:begin .. :end} :failed\n:failed\nmove-exception v0\nmonitor-exit p0\nthrow v0\n.end method\n'
}

pub fn framework_bitmap_buffers(smali string) ! {
	path := smali + '/android/graphics/Bitmap.smali'
	os.write_file(path, framework_bitmap_buffers_source(os.read_file(path)!)!)!
}

const bitmap_buffer_copy = r'
.method private vinixCopyPixelsToBuffer(Ljava/nio/Buffer;)V
.locals 13
invoke-virtual {p0}, Landroid/graphics/Bitmap;->isRecycled()Z
move-result v0
if-eqz v0, :active
new-instance v0, Ljava/lang/IllegalStateException;
const-string v1, "Bitmap is recycled"
invoke-direct {v0, v1}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/String;)V
throw v0
:active
if-nez p1, :present
new-instance v0, Ljava/lang/NullPointerException;
const-string v1, "Bitmap buffer"
invoke-direct {v0, v1}, Ljava/lang/NullPointerException;-><init>(Ljava/lang/String;)V
throw v0
:present
instance-of v0, p1, Ljava/nio/ByteBuffer;
if-nez v0, :bytes
instance-of v0, p1, Ljava/nio/ShortBuffer;
if-nez v0, :shorts
instance-of v0, p1, Ljava/nio/IntBuffer;
if-nez v0, :ints
new-instance v0, Ljava/lang/RuntimeException;
const-string v1, "Unsupported bitmap buffer subclass"
invoke-direct {v0, v1}, Ljava/lang/RuntimeException;-><init>(Ljava/lang/String;)V
throw v0
:bytes
const/4 v5, 0
goto :size
:shorts
const/4 v5, 1
goto :size
:ints
const/4 v5, 2
:size
invoke-virtual {p1}, Ljava/nio/Buffer;->remaining()I
move-result v0
int-to-long v8, v0
shl-long/2addr v8, v5
invoke-virtual {p0}, Landroid/graphics/Bitmap;->getAllocationByteCount()I
move-result v6
if-ltz v6, :too_small
int-to-long v10, v6
cmp-long v0, v8, v10
if-ltz v0, :too_small
invoke-virtual {p1}, Ljava/nio/Buffer;->position()I
move-result v7
if-ltz v7, :too_small
invoke-virtual {p0}, Landroid/graphics/Bitmap;->getTexture()J
move-result-wide v0
move-object v2, p1
iget-object v3, p0, Landroid/graphics/Bitmap;->config:Landroid/graphics/Bitmap$Config;
invoke-static {v3}, Landroid/graphics/Bitmap$Config;->access$100(Landroid/graphics/Bitmap$Config;)I
move-result v3
invoke-virtual {p0}, Landroid/graphics/Bitmap;->getRowBytes()I
move-result v4
invoke-static/range {v0 .. v4}, Landroid/graphics/Bitmap;->native_copy_to_buffer(JLjava/nio/Buffer;II)V
shr-int v0, v6, v5
add-int/2addr v0, v7
invoke-virtual {p1, v0}, Ljava/nio/Buffer;->position(I)Ljava/nio/Buffer;
return-void
:too_small
new-instance v0, Ljava/lang/RuntimeException;
const-string v1, "Bitmap buffer is too small"
invoke-direct {v0, v1}, Ljava/lang/RuntimeException;-><init>(Ljava/lang/String;)V
throw v0
.end method
'
