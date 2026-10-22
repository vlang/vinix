// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn hardware_buffer_locked(signature string, body string) string {
	// DEX bytecode methods need explicit monitors; the synchronized flag alone
	// is reserved for native methods and does not protect these field accesses.
	guarded := body.replace('return-wide v0', 'monitor-exit p0\nreturn-wide v0')
		.replace('return v0', 'monitor-exit p0\nreturn v0')
		.replace('return-void', 'monitor-exit p0\nreturn-void')
	return '.method public ' + signature + '\n.locals 5\nmonitor-enter p0\n:locked_start\n' + guarded +
		'\n:locked_end\n.catchall {:locked_start .. :locked_end} :failed\n:failed\nmove-exception v4\nmonitor-exit p0\nthrow v4\n.end method\n'
}

fn framework_hardware_buffer(smali string) ! {
	// CPU buffers share their NDK storage and own a reference until close/GC.
	// Parcel transport and GPU buffer imports are not implemented by this backend.
	mut text := '.class public final Landroid/hardware/HardwareBuffer;\n.super Ljava/lang/Object;\n.implements Ljava/lang/AutoCloseable;\n.field private vinixBuffer:J\n'
	text += '.field public static final RGBA_8888:I = 1\n'
	for name, value in {'CPU_READ_RARELY': 2, 'CPU_READ_OFTEN': 3, 'CPU_WRITE_RARELY': 32, 'CPU_WRITE_OFTEN': 48, 'GPU_SAMPLED_IMAGE': 256, 'GPU_COLOR_OUTPUT': 512} {
		text += '.field public static final USAGE_' + name + ':J = ' + value.str() + 'L\n'
	}
	text += '.method private constructor <init>(J)V\n.locals 0\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-wide p1, p0, Landroid/hardware/HardwareBuffer;->vinixBuffer:J\nreturn-void\n.end method\n'
	text += '.method public static native create(IIIIJ)Landroid/hardware/HardwareBuffer;\n.end method\n'
	text += '.method public static native isSupported(IIIIJ)Z\n.end method\n'
	text += '.method private static native vinixRelease(J)V\n.end method\n'
	text += '.method private static native vinixProperty(JI)J\n.end method\n'
	text += '.method private requireOpen()J\n.locals 4\niget-wide v0, p0, Landroid/hardware/HardwareBuffer;->vinixBuffer:J\nconst-wide/16 v2, 0\ncmp-long v2, v0, v2\nif-nez v2, :open\nnew-instance v0, Ljava/lang/IllegalStateException;\nconst-string v1, "HardwareBuffer is closed"\ninvoke-direct {v0, v1}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/String;)V\nthrow v0\n:open\nreturn-wide v0\n.end method\n'
	for index, name in ['Width', 'Height', 'Format', 'Layers', 'Usage'] {
		wide := name == 'Usage'
		body := 'invoke-direct {p0}, Landroid/hardware/HardwareBuffer;->requireOpen()J\nmove-result-wide v0\nconst/4 v2, ' + index.str() + '\ninvoke-static {v0, v1, v2}, Landroid/hardware/HardwareBuffer;->vinixProperty(JI)J\nmove-result-wide v0\n' +
			if wide { 'return-wide v0' } else { 'long-to-int v0, v0\nreturn v0' }
		text += hardware_buffer_locked('get' + name + '()' + if wide { 'J' } else { 'I' }, body)
	}
	text += hardware_buffer_locked('isClosed()Z', 'iget-wide v0, p0, Landroid/hardware/HardwareBuffer;->vinixBuffer:J\nconst-wide/16 v2, 0\ncmp-long v0, v0, v2\nif-nez v0, :open\nconst/4 v0, 1\nreturn v0\n:open\nconst/4 v0, 0\nreturn v0')
	text += hardware_buffer_locked('close()V', 'iget-wide v0, p0, Landroid/hardware/HardwareBuffer;->vinixBuffer:J\nconst-wide/16 v2, 0\niput-wide v2, p0, Landroid/hardware/HardwareBuffer;->vinixBuffer:J\ninvoke-static {v0, v1}, Landroid/hardware/HardwareBuffer;->vinixRelease(J)V\nreturn-void')
	text += '.method protected finalize()V\n.locals 0\ninvoke-virtual {p0}, Landroid/hardware/HardwareBuffer;->close()V\nreturn-void\n.end method\n'
	os.mkdir_all(smali + '/android/hardware')!
	os.write_file(smali + '/android/hardware/HardwareBuffer.smali', text)!
}
