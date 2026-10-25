// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

pub fn install_media_codec_exceptions_probe(dir string) ! {
 verifier := 'Lorg/vinix/bootstrap/MapsMediaVerifier;'
 os.write_file(dir + '/MapsMediaVerifier.smali', '.class public ${verifier}\n.super Ljava/lang/Object;\n' +
  method('public static check(Landroid/content/Context;)V', '
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "MAPS-PLAYER-VERIFY-BEGIN"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
new-instance v0, Ldalvik/system/DexClassLoader;
const-string v1, "/opt/android-test/maps-application.apk"
invoke-virtual {p0}, Landroid/content/Context;->getCacheDir()Ljava/io/File;
move-result-object v2
invoke-virtual {v2}, Ljava/io/File;->getAbsolutePath()Ljava/lang/String;
move-result-object v2
const/4 v3, 0
invoke-virtual {p0}, Ljava/lang/Object;->getClass()Ljava/lang/Class;
move-result-object v4
invoke-virtual {v4}, Ljava/lang/Class;->getClassLoader()Ljava/lang/ClassLoader;
move-result-object v4
invoke-direct {v0, v1, v2, v3, v4}, Ldalvik/system/DexClassLoader;-><init>(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/ClassLoader;)V
const-string v1, "hqa"
const/4 v2, 1
invoke-static {v1, v2, v0}, Ljava/lang/Class;->forName(Ljava/lang/String;ZLjava/lang/ClassLoader;)Ljava/lang/Class;
move-result-object v3
sget-object v5, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v6, "MAPS-PLAYER-HQA-VERIFY-PASS"
invoke-virtual {v5, v6}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
const-string v1, "hwv"
invoke-static {v1, v2, v0}, Ljava/lang/Class;->forName(Ljava/lang/String;ZLjava/lang/ClassLoader;)Ljava/lang/Class;
move-result-object v4
sget-object v5, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v6, "MAPS-PLAYER-HWV-VERIFY-PASS"
invoke-virtual {v5, v6}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v4}, Ljava/lang/Class;->getSuperclass()Ljava/lang/Class;
move-result-object v5
if-ne v3, v5, :bad
invoke-virtual {v3}, Ljava/lang/Class;->getClassLoader()Ljava/lang/ClassLoader;
move-result-object v5
if-ne v0, v5, :bad
invoke-virtual {v4}, Ljava/lang/Class;->getClassLoader()Ljava/lang/ClassLoader;
move-result-object v5
if-ne v0, v5, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "MAPS-PLAYER-VERIFY-PASS"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "original Maps hqa/hwv loader or hierarchy"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'))!

 c := 'Lorg/vinix/bootstrap/MediaCodecExceptionProbe;'
 crypto := 'Landroid/media/MediaCodec$CryptoException;'
 codec := 'Landroid/media/MediaCodec$CodecException;'
 drm := 'Landroid/media/MediaCryptoException;'
 mut text := '.class public ${c}\n.super Ljava/lang/Object;\n'
 text += method('private static fail()V', 'new-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "media codec exception contract"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0')
 text += method('private static hierarchy(Ljava/lang/Class;Ljava/lang/Class;I)V', '
invoke-virtual {p0}, Ljava/lang/Class;->getSuperclass()Ljava/lang/Class;
move-result-object v0
if-ne v0, p1, :bad
invoke-virtual {p0}, Ljava/lang/Class;->getModifiers()I
move-result v0
if-ne v0, p2, :bad
return-void
:bad
invoke-static {}, ${c}->fail()V
return-void')
 mut metadata := '
const-class v0, ${crypto}
const-class v1, Ljava/lang/RuntimeException;
const/16 v2, 0x19
invoke-static {v0, v1, v2}, ${c}->hierarchy(Ljava/lang/Class;Ljava/lang/Class;I)V
const-class v0, ${codec}
const-class v1, Ljava/lang/IllegalStateException;
invoke-static {v0, v1, v2}, ${c}->hierarchy(Ljava/lang/Class;Ljava/lang/Class;I)V
const-class v0, ${drm}
const-class v1, Ljava/lang/Exception;
const/16 v2, 0x11
invoke-static {v0, v1, v2}, ${c}->hierarchy(Ljava/lang/Class;Ljava/lang/Class;I)V
const-class v0, ${crypto}
invoke-virtual {v0}, Ljava/lang/Class;->getEnclosingClass()Ljava/lang/Class;
move-result-object v1
const-class v2, Landroid/media/MediaCodec;
if-ne v1, v2, :bad
const-class v0, ${codec}
invoke-virtual {v0}, Ljava/lang/Class;->getEnclosingClass()Ljava/lang/Class;
move-result-object v1
if-ne v1, v2, :bad
invoke-virtual {v2}, Ljava/lang/Class;->getDeclaredClasses()[Ljava/lang/Class;
move-result-object v3
array-length v4, v3
const/4 v5, 5
if-ne v4, v5, :bad
const/4 v4, 0
const/4 v5, 0
:members
array-length v6, v3
if-ge v4, v6, :members_done
aget-object v6, v3, v4
const-class v7, ${crypto}
if-ne v6, v7, :check_codec
or-int/lit8 v5, v5, 1
:check_codec
const-class v7, ${codec}
if-ne v6, v7, :next_member
or-int/lit8 v5, v5, 2
:next_member
add-int/lit8 v4, v4, 1
goto :members
:members_done
const/4 v4, 3
if-ne v5, v4, :bad
'
 for index, name in ['NO_KEY', 'KEY_EXPIRED', 'RESOURCE_BUSY', 'INSUFFICIENT_OUTPUT_PROTECTION',
  'SESSION_NOT_OPENED', 'UNSUPPORTED_OPERATION', 'INSUFFICIENT_SECURITY', 'FRAME_TOO_LARGE', 'LOST_STATE'] {
  metadata += 'sget v0, ${crypto}->ERROR_${name}:I\nconst/16 v1, ${(index + 1)}\nif-ne v0, v1, :bad\n'
 }
 for name, value in {'INSUFFICIENT_RESOURCE': 1100, 'RECLAIMED': 1101} {
  metadata += 'sget v0, ${codec}->ERROR_${name}:I\nconst/16 v1, ${value}\nif-ne v0, v1, :bad\n'
 }
 metadata += 'return-void\n:bad\ninvoke-static {}, ${c}->fail()V\nreturn-void'
 text += method('private static metadata()V', metadata)
 text += method('private static crypto()V', '
new-instance v0, ${crypto}
const/16 v1, -19
const-string v2, "crypto failure"
invoke-direct {v0, v1, v2}, ${crypto}-><init>(ILjava/lang/String;)V
invoke-virtual {v0}, ${crypto}->getErrorCode()I
move-result v3
if-ne v1, v3, :bad
invoke-virtual {v0}, Ljava/lang/Throwable;->getMessage()Ljava/lang/String;
move-result-object v3
if-ne v2, v3, :bad
new-instance v4, ${crypto}
const/4 v5, 0
invoke-direct {v4, v5, v5}, ${crypto}-><init>(ILjava/lang/String;)V
invoke-virtual {v4}, ${crypto}->getErrorCode()I
move-result v3
if-nez v3, :bad
invoke-virtual {v4}, Ljava/lang/Throwable;->getMessage()Ljava/lang/String;
move-result-object v3
if-nez v3, :bad
invoke-virtual {v0}, ${crypto}->getErrorCode()I
move-result v3
if-ne v1, v3, :bad
:crypto_throw
throw v0
:crypto_end
.catch Ljava/lang/RuntimeException; {:crypto_throw .. :crypto_end} :crypto_caught
:crypto_caught
move-exception v3
if-ne v3, v0, :bad
new-instance v4, ${drm}
const-string v5, "drm failure"
invoke-direct {v4, v5}, ${drm}-><init>(Ljava/lang/String;)V
invoke-virtual {v4}, Ljava/lang/Throwable;->getMessage()Ljava/lang/String;
move-result-object v6
if-ne v6, v5, :bad
:drm_throw
throw v4
:drm_end
.catch Ljava/lang/Exception; {:drm_throw .. :drm_end} :drm_caught
:drm_caught
move-exception v6
if-ne v6, v4, :bad
new-instance v4, ${drm}
const/4 v5, 0
invoke-direct {v4, v5}, ${drm}-><init>(Ljava/lang/String;)V
invoke-virtual {v4}, Ljava/lang/Throwable;->getMessage()Ljava/lang/String;
move-result-object v6
if-nez v6, :bad
return-void
:bad
invoke-static {}, ${c}->fail()V
return-void')
 text += method('private static codec(IILjava/lang/String;)${codec}', '
const-class v0, ${codec}
const/4 v1, 3
new-array v1, v1, [Ljava/lang/Class;
sget-object v2, Ljava/lang/Integer;->TYPE:Ljava/lang/Class;
const/4 v3, 0
aput-object v2, v1, v3
const/4 v3, 1
aput-object v2, v1, v3
const-class v2, Ljava/lang/String;
const/4 v3, 2
aput-object v2, v1, v3
invoke-virtual {v0, v1}, Ljava/lang/Class;->getDeclaredConstructor([Ljava/lang/Class;)Ljava/lang/reflect/Constructor;
move-result-object v0
invoke-virtual {v0}, Ljava/lang/reflect/Constructor;->getModifiers()I
move-result v1
and-int/lit8 v1, v1, 7
if-nez v1, :bad
const/4 v1, 1
invoke-virtual {v0, v1}, Ljava/lang/reflect/Constructor;->setAccessible(Z)V
const/4 v1, 3
new-array v1, v1, [Ljava/lang/Object;
invoke-static {p0}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;
move-result-object v2
const/4 v3, 0
aput-object v2, v1, v3
invoke-static {p1}, Ljava/lang/Integer;->valueOf(I)Ljava/lang/Integer;
move-result-object v2
const/4 v3, 1
aput-object v2, v1, v3
const/4 v3, 2
aput-object p2, v1, v3
invoke-virtual {v0, v1}, Ljava/lang/reflect/Constructor;->newInstance([Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v0
check-cast v0, ${codec}
return-object v0
:bad
invoke-static {}, ${c}->fail()V
const/4 v0, 0
return-object v0')
 text += method('private static codecCase(IILjava/lang/String;Ljava/lang/String;)${codec}', '
invoke-static {p0, p1, p2}, ${c}->codec(IILjava/lang/String;)${codec}
move-result-object v0
invoke-virtual {v0}, ${codec}->getErrorCode()I
move-result v1
if-ne v1, p0, :bad
invoke-virtual {v0}, Ljava/lang/Throwable;->getMessage()Ljava/lang/String;
move-result-object v1
if-ne v1, p2, :bad
invoke-virtual {v0}, ${codec}->getDiagnosticInfo()Ljava/lang/String;
move-result-object v1
invoke-virtual {p3, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :bad
invoke-virtual {v0}, ${codec}->isTransient()Z
move-result v1
const/4 v2, 0
const/4 v3, 1
if-ne p1, v3, :transient_expected
const/4 v2, 1
:transient_expected
if-ne v1, v2, :bad
invoke-virtual {v0}, ${codec}->isRecoverable()Z
move-result v1
const/4 v2, 0
const/4 v3, 2
if-ne p1, v3, :recoverable_expected
const/4 v2, 1
:recoverable_expected
if-ne v1, v2, :bad
return-object v0
:bad
invoke-static {}, ${c}->fail()V
const/4 v0, 0
return-object v0')
 mut cases := ''
 for values in [['1100', '1', 'codec positive', 'android.media.MediaCodec.error_1100'],
  ['-1101', '2', 'codec negative', 'android.media.MediaCodec.error_neg_1101'],
  ['0', '0', '', 'android.media.MediaCodec.error_0'],
  ['-2147483648', '3', 'minimum int', 'android.media.MediaCodec.error_neg_-2147483648'],
  ['2147483647', '-1', 'maximum int', 'android.media.MediaCodec.error_2147483647']] {
  cases += 'const v0, ${values[0]}\nconst v1, ${values[1]}\n'
  cases += if values[2] == '' { 'const/4 v2, 0\n' } else { 'const-string v2, "${values[2]}"\n' }
  cases += 'const-string v3, "${values[3]}"\ninvoke-static {v0, v1, v2, v3}, ${c}->codecCase(IILjava/lang/String;Ljava/lang/String;)${codec}\n'
  if values[0] == '1100' { cases += 'move-result-object v4\n' }
 }
 cases += '
# Other constructors must not change an existing instance.
invoke-virtual {v4}, ${codec}->getErrorCode()I
move-result v0
const/16 v1, 1100
if-ne v0, v1, :bad
invoke-virtual {v4}, ${codec}->isTransient()Z
move-result v0
if-eqz v0, :bad
invoke-virtual {v4}, ${codec}->getDiagnosticInfo()Ljava/lang/String;
move-result-object v0
const-string v1, "android.media.MediaCodec.error_1100"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
:codec_throw
throw v4
:codec_end
.catch Ljava/lang/IllegalStateException; {:codec_throw .. :codec_end} :codec_caught
:codec_caught
move-exception v0
if-ne v0, v4, :bad
return-void
:bad
invoke-static {}, ${c}->fail()V
return-void'
 text += method('private static codecCases()V', cases)
 mut check := ''
 for part in ['metadata', 'crypto', 'codecCases'] {
  check += 'invoke-static {}, ${c}->${part}()V\nsget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "MEDIA-CODEC-EXCEPTIONS-${part.to_upper()}-PASS"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\n'
 }
 check += 'const-string v1, "MEDIA-CODEC-EXCEPTIONS-PASS"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void'
 text += method('public static check()V', check)
 os.write_file(dir + '/MediaCodecExceptionProbe.smali', text)!
}
