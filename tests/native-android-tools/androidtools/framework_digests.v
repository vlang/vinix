// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Keep the JCA contract in the framework; the native WS runtime registers the
// streaming EVP implementation before loading any APK or application Context.
fn framework_native_digests(smali string) ! {
	base := 'Landroid/atl/VinixNativeDigest;'
	mut code := '.class public ' + base + '\n.super Ljava/security/MessageDigestSpi;\n' +
		'.implements Ljava/lang/Cloneable;\n.field private handle:J\n.field private size:I\n'
	for declaration in ['create(I)J', 'update(J[BII)V', 'finish(J)[B', 'reset(J)V', 'copy(J)J', 'destroy(J)V'] {
		code += '.method private static native ' + declaration + '\n.end method\n'
	}
	code += signature_method('protected constructor <init>(I)V', '
invoke-direct {p0}, Ljava/security/MessageDigestSpi;-><init>()V
div-int/lit8 v0, p1, 8
iput v0, p0, ' + base + '->size:I
invoke-static {p1}, ' + base + '->create(I)J
move-result-wide v0
iput-wide v0, p0, ' + base + '->handle:J
return-void')
	code += signature_method('protected engineGetDigestLength()I', 'iget v0, p0, ' + base + '->size:I\nreturn v0')
	code += signature_method('protected engineUpdate(B)V', '
const/4 v0, 1
new-array v0, v0, [B
const/4 v1, 0
aput-byte p1, v0, v1
const/4 v2, 1
invoke-virtual {p0, v0, v1, v2}, ' + base + '->engineUpdate([BII)V
return-void')
	code += signature_method('protected engineUpdate([BII)V', '
iget-wide v0, p0, ' + base + '->handle:J
move-object v2, p1
move v3, p2
move v4, p3
invoke-static {v0, v1, v2, v3, v4}, ' + base + '->update(J[BII)V
return-void')
	code += signature_method('protected engineDigest()[B', '
iget-wide v0, p0, ' + base + '->handle:J
invoke-static {v0, v1}, ' + base + '->finish(J)[B
move-result-object v0
return-object v0')
	code += signature_method('protected engineReset()V', '
iget-wide v0, p0, ' + base + '->handle:J
invoke-static {v0, v1}, ' + base + '->reset(J)V
return-void')
	code += signature_method('public clone()Ljava/lang/Object;', '
invoke-super {p0}, Ljava/security/MessageDigestSpi;->clone()Ljava/lang/Object;
move-result-object v0
check-cast v0, ' + base + '
const-wide/16 v1, 0
iput-wide v1, v0, ' + base + '->handle:J
iget-wide v1, p0, ' + base + '->handle:J
invoke-static {v1, v2}, ' + base + '->copy(J)J
move-result-wide v1
iput-wide v1, v0, ' + base + '->handle:J
return-object v0')
	code += signature_method('protected finalize()V', '
iget-wide v0, p0, ' + base + '->handle:J
const-wide/16 v2, 0
iput-wide v2, p0, ' + base + '->handle:J
invoke-static {v0, v1}, ' + base + '->destroy(J)V
return-void')
	os.write_file(smali + '/android/atl/VinixNativeDigest.smali', code)!
	provider := 'Landroid/atl/VinixDigestProvider;'
	mut body := '
const-string v1, "VinixNative"
const-wide/high16 v2, 0x3ff0000000000000L
const-string v4, "Vinix streaming native SHA-2"
move-object v0, p0
invoke-direct {v0, v1, v2, v3, v4}, Ljava/security/Provider;-><init>(Ljava/lang/String;DLjava/lang/String;)V
'
	for bits, oid in {256: '1', 384: '2', 512: '3'} {
		name := 'VinixNativeDigest$SHA${bits}'
		os.write_file(smali + '/android/atl/' + name + '.smali', '.class public final Landroid/atl/' +
			name + ';\n.super ' + base + '\n' + signature_method('public constructor <init>()V',
			'const/16 v0, ${bits}\ninvoke-direct {p0, v0}, ' + base + '-><init>(I)V\nreturn-void'))!
		for key, value in {
			'MessageDigest.SHA-${bits}': 'android.atl.' + name
			'Alg.Alias.MessageDigest.SHA${bits}': 'SHA-${bits}'
			'Alg.Alias.MessageDigest.2.16.840.1.101.3.4.2.${oid}': 'SHA-${bits}'
			'Alg.Alias.MessageDigest.OID.2.16.840.1.101.3.4.2.${oid}': 'SHA-${bits}'
		} {
			body += 'const-string v0, "' + key + '"\nconst-string v1, "' + value +
				'"\ninvoke-virtual {p0, v0, v1}, Ljava/security/Provider;->put(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;\n'
		}
	}
	os.write_file(smali + '/android/atl/VinixDigestProvider.smali', '.class public final ' +
		provider + '\n.super Ljava/security/Provider;\n' + signature_method('public constructor <init>()V', body + 'return-void'))!
}
