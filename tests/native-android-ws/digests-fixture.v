// SPDX-License-Identifier: GPL-2.0-or-later
// Build after bootstrap-fixture.v. Exercise the real JCA provider in guest ART.
module main

import os
import crypto.sha256
import crypto.sha512

fn checked(args []string) {
	r := os.exec(args)
	if r.exit_code != 0 { panic(r.output) }
}

fn method(name string, body string) string {
	return '.method ' + name + '\n.locals 10\n' + body + '\n.end method\n'
}

fn expected(bits int, data []u8) string {
	return match bits {
		256 { sha256.sum(data).hex() }
		384 { sha512.sum384(data).hex() }
		else { sha512.sum512(data).hex() }
	}
}

fn main() {
	if os.args.len != 6 { panic('OUTPUT FIXTURE_DIR SMALI_TOOLS JAVA APKSIGNER') }
	out, fixture, tools := os.abs_path(os.args[1]), os.abs_path(os.args[2]), os.abs_path(os.args[3])
	java, signer := os.args[4], os.abs_path(os.args[5])
	os.mkdir_all(out + '/smali/org/vinix/bootstrap')!
	base := 'Lorg/vinix/bootstrap/Main;'
	md := 'Ljava/security/MessageDigest;'
	mut source := '.class public ' + base + '\n.super Landroid/app/Activity;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void')
	mut body := 'invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V\n'
	for bits in [256, 384, 512] {
		body += 'const-string v0, "SHA-${bits}"\n'
		for size in [0, 1, 55, 56, 63, 64, 111, 112, 127, 128, 129, 1024, 65535, 65536, 65537] {
			body += 'const v1, ${size}\ninvoke-static {v0, v1}, ' + base + '->compare(Ljava/lang/String;I)V\n'
		}
		for size in [3, 1000000] {
			data := if size == 3 { 'abc'.bytes() } else { []u8{len: size, init: `a`} }
			body += 'const v1, ${size}\nconst-string v2, "' + expected(bits, data) +
				'"\ninvoke-static {v0, v1, v2}, ' + base + '->vector(Ljava/lang/String;ILjava/lang/String;)V\n'
		}
		body += 'invoke-static {v0}, ' + base + '->contracts(Ljava/lang/String;)V\n'
		body += 'const-string v0, "SHA${bits}"\ninvoke-static {v0}, ' + md +
			'->getInstance(Ljava/lang/String;)Ljava/security/MessageDigest;\nmove-result-object v0\n' +
			'invoke-static {v0}, ' + base + '->provider(Ljava/security/MessageDigest;)V\n'
	}
	body += '
invoke-static {}, Lorg/vinix/bootstrap/TestDigest;->check()V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "DIGEST-FIXTURE-PASS sha256 sha384 sha512 known-vectors million-a streaming bc-crosscheck clone reset bytebuffer bounds stale-handles destroy"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Native SHA-2 checks passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
return-void'
	source += method('public onCreate(Landroid/os/Bundle;)V', body)
	source += method('public static equal([B[B)V', '
invoke-static {p0, p1}, Ljava/util/Arrays;->equals([B[B)Z
move-result v0
if-nez v0, :ok
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Digest bytes differ"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:ok
return-void')
	source += method('public static provider(Ljava/security/MessageDigest;)V', '
invoke-virtual {p0}, ' + md + '->getProvider()Ljava/security/Provider;
move-result-object v0
invoke-virtual {v0}, Ljava/security/Provider;->getName()Ljava/lang/String;
move-result-object v0
const-string v1, "VinixNative"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-nez v0, :ok
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Native provider not selected"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:ok
return-void')
	source += method('public static compare(Ljava/lang/String;I)V', '
invoke-static {p0}, ' + md + '->getInstance(Ljava/lang/String;)Ljava/security/MessageDigest;
move-result-object v0
invoke-static {v0}, ' + base + '->provider(Ljava/security/MessageDigest;)V
const-string v1, "BC"
invoke-static {p0, v1}, ' + md + '->getInstance(Ljava/lang/String;Ljava/lang/String;)Ljava/security/MessageDigest;
move-result-object v1
new-array v2, p1, [B
const/4 v3, 0
:fill
if-ge v3, p1, :hash
mul-int/lit8 v4, v3, 31
aput-byte v4, v2, v3
add-int/lit8 v3, v3, 1
goto :fill
:hash
invoke-virtual {v1, v2}, ' + md + '->digest([B)[B
move-result-object v1
const/4 v3, 0
:chunk
if-ge v3, p1, :done
sub-int v4, p1, v3
const/16 v5, 137
if-le v4, v5, :small
move v4, v5
:small
invoke-virtual {v0, v2, v3, v4}, ' + md + '->update([BII)V
add-int/2addr v3, v4
goto :chunk
:done
invoke-virtual {v0}, ' + md + '->digest()[B
move-result-object v0
invoke-static {v0, v1}, ' + base + '->equal([B[B)V
return-void')
	source += method('public static vector(Ljava/lang/String;ILjava/lang/String;)V', '
invoke-static {p0}, ' + md + '->getInstance(Ljava/lang/String;)Ljava/security/MessageDigest;
move-result-object v0
new-array v1, p1, [B
const/16 v2, 97
invoke-static {v1, v2}, Ljava/util/Arrays;->fill([BB)V
const/4 v2, 3
if-ne p1, v2, :hash
const/4 v2, 1
const/16 v3, 98
aput-byte v3, v1, v2
const/4 v2, 2
const/16 v3, 99
aput-byte v3, v1, v2
:hash
invoke-virtual {v0, v1}, ' + md + '->digest([B)[B
move-result-object v0
new-instance v1, Ljava/math/BigInteger;
const/4 v2, 1
invoke-direct {v1, v2, v0}, Ljava/math/BigInteger;-><init>(I[B)V
const/16 v0, 16
invoke-virtual {v1, v0}, Ljava/math/BigInteger;->toString(I)Ljava/lang/String;
move-result-object v0
:pad
invoke-virtual {v0}, Ljava/lang/String;->length()I
move-result v1
invoke-virtual {p2}, Ljava/lang/String;->length()I
move-result v2
if-ge v1, v2, :compare
const-string v1, "0"
invoke-virtual {v1, v0}, Ljava/lang/String;->concat(Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
goto :pad
:compare
invoke-virtual {p2, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-nez v0, :ok
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:ok
return-void')
	source += method('public static contracts(Ljava/lang/String;)V', '
invoke-static {p0}, ' + md + '->getInstance(Ljava/lang/String;)Ljava/security/MessageDigest;
move-result-object v0
const-string v1, "ab"
invoke-virtual {v1}, Ljava/lang/String;->getBytes()[B
move-result-object v1
invoke-virtual {v0, v1}, ' + md + '->update([B)V
invoke-virtual {v0}, ' + md + '->clone()Ljava/lang/Object;
move-result-object v2
check-cast v2, ' + md + '
const/16 v3, 99
invoke-virtual {v0, v3}, ' + md + '->update(B)V
const/16 v3, 100
invoke-virtual {v2, v3}, ' + md + '->update(B)V
const-string v3, "BC"
invoke-static {p0, v3}, ' + md + '->getInstance(Ljava/lang/String;Ljava/lang/String;)Ljava/security/MessageDigest;
move-result-object v3
const-string v4, "abc"
invoke-virtual {v4}, Ljava/lang/String;->getBytes()[B
move-result-object v4
invoke-virtual {v3, v4}, ' + md + '->digest([B)[B
move-result-object v5
invoke-virtual {v0}, ' + md + '->digest()[B
move-result-object v6
invoke-static {v5, v6}, ' + base + '->equal([B[B)V
const-string v6, "abd"
invoke-virtual {v6}, Ljava/lang/String;->getBytes()[B
move-result-object v6
invoke-virtual {v3, v6}, ' + md + '->digest([B)[B
move-result-object v6
invoke-virtual {v2}, ' + md + '->digest()[B
move-result-object v7
invoke-static {v6, v7}, ' + base + '->equal([B[B)V
invoke-virtual {v0}, ' + md + '->digest()[B
move-result-object v6
invoke-virtual {v3}, ' + md + '->digest()[B
move-result-object v7
invoke-static {v6, v7}, ' + base + '->equal([B[B)V
invoke-virtual {v0, v1}, ' + md + '->update([B)V
invoke-virtual {v0}, ' + md + '->reset()V
const/16 v6, 5
invoke-static {v6}, Ljava/nio/ByteBuffer;->allocateDirect(I)Ljava/nio/ByteBuffer;
move-result-object v6
const/16 v7, 88
invoke-virtual {v6, v7}, Ljava/nio/ByteBuffer;->put(B)Ljava/nio/ByteBuffer;
invoke-virtual {v6, v4}, Ljava/nio/ByteBuffer;->put([B)Ljava/nio/ByteBuffer;
const/4 v7, 1
invoke-virtual {v6, v7}, Ljava/nio/Buffer;->position(I)Ljava/nio/Buffer;
const/4 v7, 4
invoke-virtual {v6, v7}, Ljava/nio/Buffer;->limit(I)Ljava/nio/Buffer;
invoke-virtual {v6}, Ljava/nio/ByteBuffer;->asReadOnlyBuffer()Ljava/nio/ByteBuffer;
move-result-object v6
invoke-virtual {v0, v6}, ' + md + '->update(Ljava/nio/ByteBuffer;)V
invoke-virtual {v6}, Ljava/nio/Buffer;->remaining()I
move-result v6
if-nez v6, :bad
invoke-virtual {v0}, ' + md + '->digest()[B
move-result-object v6
invoke-static {v5, v6}, ' + base + '->equal([B[B)V
invoke-static {v4}, Ljava/nio/ByteBuffer;->wrap([B)Ljava/nio/ByteBuffer;
move-result-object v6
invoke-virtual {v0, v6}, ' + md + '->update(Ljava/nio/ByteBuffer;)V
invoke-virtual {v0}, ' + md + '->digest()[B
move-result-object v6
invoke-static {v5, v6}, ' + base + '->equal([B[B)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "ByteBuffer position"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0')
	os.write_file(out + '/smali/org/vinix/bootstrap/Main.smali', source)!
	os.write_file(out + '/smali/org/vinix/bootstrap/TestDigest.smali', digest_bounds())!
	for name in ['App', 'High', 'Low'] {
		os.cp(fixture + '/smali/org/vinix/bootstrap/' + name + '.smali', out + '/smali/org/vinix/bootstrap/' + name + '.smali')!
	}
	// Smali may exit zero after an assembly error. Never reuse an old DEX.
	dex := out + '/classes.dex'
	if os.exists(dex) { os.rm(dex)! }
	checked([java, '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', out + '/smali', '-o', dex])
	if !os.is_file(dex) { panic('Smali did not produce a new classes.dex') }
	os.cp(fixture + '/unsigned.apk', out + '/unsigned.apk')!
	checked(['zip', '-q', '-j', out + '/unsigned.apk', out + '/classes.dex'])
	checked([java, '-jar', signer, 'sign', '--ks', fixture + '/fixture.p12', '--ks-key-alias',
		'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk', out + '/unsigned.apk'])
	println('DIGEST-FIXTURE-APK ' + out + '/probe.apk')
}

fn digest_bounds() string {
	mut source := '.class public Lorg/vinix/bootstrap/TestDigest;\n.super Landroid/atl/VinixNativeDigest;\n' +
		method('public constructor <init>()V', 'const/16 v0, 256\ninvoke-direct {p0, v0}, Landroid/atl/VinixNativeDigest;-><init>(I)V\nreturn-void')
	mut body := 'new-instance v0, Lorg/vinix/bootstrap/TestDigest;\ninvoke-direct {v0}, Lorg/vinix/bootstrap/TestDigest;-><init>()V\n'
	for i, bounds in [[-1, 0], [0, -1], [3, 2], [2147483647, 1]] {
		body += '
const/4 v1, 4
new-array v1, v1, [B
const v2, ${bounds[0]}
const v3, ${bounds[1]}
:start${i}
invoke-virtual {v0, v1, v2, v3}, Lorg/vinix/bootstrap/TestDigest;->engineUpdate([BII)V
:end${i}
goto :bad
:caught${i}
move-exception v4
.catch Ljava/lang/ArrayIndexOutOfBoundsException; {:start${i} .. :end${i}} :caught${i}
'
	}
	body += '
const/4 v1, 0
const/4 v2, 0
:nullstart
invoke-virtual {v0, v1, v2, v2}, Lorg/vinix/bootstrap/TestDigest;->engineUpdate([BII)V
:nullend
goto :bad
:nullcaught
move-exception v4
.catch Ljava/lang/NullPointerException; {:nullstart .. :nullend} :nullcaught
invoke-virtual {v0}, Lorg/vinix/bootstrap/TestDigest;->engineDigest()[B
move-result-object v1
const-string v2, "SHA-256"
const-string v3, "BC"
invoke-static {v2, v3}, Ljava/security/MessageDigest;->getInstance(Ljava/lang/String;Ljava/lang/String;)Ljava/security/MessageDigest;
move-result-object v2
invoke-virtual {v2}, Ljava/security/MessageDigest;->digest()[B
move-result-object v2
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->equal([B[B)V
invoke-virtual {v0}, Lorg/vinix/bootstrap/TestDigest;->finalize()V
invoke-virtual {v0}, Lorg/vinix/bootstrap/TestDigest;->finalize()V
:stalestart
invoke-virtual {v0}, Lorg/vinix/bootstrap/TestDigest;->engineReset()V
:staleend
goto :bad
:stalecaught
move-exception v4
.catch Ljava/lang/IllegalStateException; {:stalestart .. :staleend} :stalecaught
const/16 v5, 1000
:churn
new-instance v0, Lorg/vinix/bootstrap/TestDigest;
invoke-direct {v0}, Lorg/vinix/bootstrap/TestDigest;-><init>()V
invoke-virtual {v0}, Lorg/vinix/bootstrap/TestDigest;->finalize()V
add-int/lit8 v5, v5, -1
if-gtz v5, :churn
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Digest input/lifetime validation"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
	return source + method('public static check()V', body)
}
