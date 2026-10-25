// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn codec_exception_method(signature string, body string) string {
	return '.method ' + signature + '\n.locals 3\n' + body + '\n.end method\n'
}

fn codec_exception_nested(name string, parent string) string {
	return '.class public final Landroid/media/MediaCodec$' + name + ';\n.super ' + parent + '\n' +
		'.annotation system Ldalvik/annotation/EnclosingClass;\nvalue = Landroid/media/MediaCodec;\n.end annotation\n' +
		'.annotation system Ldalvik/annotation/InnerClass;\naccessFlags = 0x19\nname = "' + name + '"\n.end annotation\n'
}

// These Java exception values let applications link codec error handlers. They
// describe caller-supplied errors and do not add codec or DRM capabilities.
pub fn framework_media_codec_exceptions(smali string) ! {
	for name in ['MediaCodec$CodecException', 'MediaCodec$CryptoException', 'MediaCryptoException'] {
		if os.exists(smali + '/android/media/' + name + '.smali') {
			return error(name + ' already exists')
		}
	}
	path := smali + '/android/media/MediaCodec.smali'
	mut codec := os.read_file(path)!
	member := '.annotation system Ldalvik/annotation/MemberClasses;\n    value = {\n'
	if codec.count(member) != 1 {
		return error('expected one MediaCodec member-class annotation')
	}
	codec = codec.replace(member, member + '        Landroid/media/MediaCodec$CodecException;,\n' +
		'        Landroid/media/MediaCodec$CryptoException;,\n')

	owner := 'Landroid/media/MediaCodec$CodecException;'
	mut text := codec_exception_nested('CodecException', 'Ljava/lang/IllegalStateException;') +
		'.field private final mErrorCode:I\n.field private final mActionCode:I\n.field private final mDiagnosticInfo:Ljava/lang/String;\n' +
		'.field public static final ERROR_INSUFFICIENT_RESOURCE:I = 0x44c\n' +
		'.field public static final ERROR_RECLAIMED:I = 0x44d\n'
	text += codec_exception_method('constructor <init>(IILjava/lang/String;)V',
		'invoke-direct {p0, p3}, Ljava/lang/IllegalStateException;-><init>(Ljava/lang/String;)V\n' +
		'iput p1, p0, ' + owner + '->mErrorCode:I\niput p2, p0, ' + owner + '->mActionCode:I\n' +
		'new-instance v0, Ljava/lang/StringBuilder;\ninvoke-direct {v0}, Ljava/lang/StringBuilder;-><init>()V\n' +
		'const-string v1, "android.media.MediaCodec.error_"\n' +
		'invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n' +
		'if-gez p1, :number\nconst-string v1, "neg_"\n' +
		'invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\n' +
		':number\ninvoke-static {p1}, Ljava/lang/Math;->abs(I)I\nmove-result v1\n' +
		'invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;\n' +
		'invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;\nmove-result-object v0\n' +
		'iput-object v0, p0, ' + owner + '->mDiagnosticInfo:Ljava/lang/String;\nreturn-void')
	text += codec_exception_method('public getErrorCode()I', 'iget v0, p0, ' + owner + '->mErrorCode:I\nreturn v0')
	text += codec_exception_method('public getDiagnosticInfo()Ljava/lang/String;',
		'iget-object v0, p0, ' + owner + '->mDiagnosticInfo:Ljava/lang/String;\nreturn-object v0')
	for name, action in {'isTransient': 1, 'isRecoverable': 2} {
		text += codec_exception_method('public ' + name + '()Z',
			'iget v0, p0, ' + owner + '->mActionCode:I\nconst/4 v1, ' + action.str() + '\n' +
			'if-ne v0, v1, :no\nconst/4 v0, 1\nreturn v0\n:no\nconst/4 v0, 0\nreturn v0')
	}
	os.write_file(smali + '/android/media/MediaCodec$CodecException.smali', text)!

	crypto := 'Landroid/media/MediaCodec$CryptoException;'
	mut crypto_text := codec_exception_nested('CryptoException', 'Ljava/lang/RuntimeException;') +
		'.field private final mErrorCode:I\n'
	for index, name in ['NO_KEY', 'KEY_EXPIRED', 'RESOURCE_BUSY', 'INSUFFICIENT_OUTPUT_PROTECTION',
		'SESSION_NOT_OPENED', 'UNSUPPORTED_OPERATION', 'INSUFFICIENT_SECURITY', 'FRAME_TOO_LARGE', 'LOST_STATE'] {
		crypto_text += '.field public static final ERROR_' + name + ':I = ' + (index + 1).str() + '\n'
	}
	crypto_text += codec_exception_method('public constructor <init>(ILjava/lang/String;)V',
		'invoke-direct {p0, p2}, Ljava/lang/RuntimeException;-><init>(Ljava/lang/String;)V\n' +
		'iput p1, p0, ' + crypto + '->mErrorCode:I\nreturn-void')
	crypto_text += codec_exception_method('public getErrorCode()I', 'iget v0, p0, ' + crypto + '->mErrorCode:I\nreturn v0')
	os.write_file(smali + '/android/media/MediaCodec$CryptoException.smali', crypto_text)!

	os.write_file(smali + '/android/media/MediaCryptoException.smali',
		'.class public final Landroid/media/MediaCryptoException;\n.super Ljava/lang/Exception;\n' +
		codec_exception_method('public constructor <init>(Ljava/lang/String;)V',
			'invoke-direct {p0, p1}, Ljava/lang/Exception;-><init>(Ljava/lang/String;)V\nreturn-void'))!
	os.write_file(path, codec)!
}
