// SPDX-License-Identifier: GPL-2.0-or-later
module keygenprobe

import os

pub fn install(root string) ! {
 os.write_file(root + '/smali/KeyGenProbe.smali', r'.class public Lorg/vinix/bootstrap/KeyGenProbe;
.super Ljava/lang/Object;
.method public static check()V
.locals 10
const/4 v6, 0
const/4 v7, 1
new-instance v0, Landroid/security/keystore/KeyGenParameterSpec$Builder;
const-string v5, "vinix-metadata-probe"
const/4 v8, 4
invoke-direct {v0, v5, v8}, Landroid/security/keystore/KeyGenParameterSpec$Builder;-><init>(Ljava/lang/String;I)V
invoke-virtual {v0}, Landroid/security/keystore/KeyGenParameterSpec$Builder;->build()Landroid/security/keystore/KeyGenParameterSpec;
move-result-object v4
invoke-virtual {v4}, Landroid/security/keystore/KeyGenParameterSpec;->isDigestsSpecified()Z
move-result v5
invoke-static {v5, v6}, Lorg/vinix/bootstrap/Main;->expect(II)V
:unspecified
invoke-virtual {v4}, Landroid/security/keystore/KeyGenParameterSpec;->getDigests()[Ljava/lang/String;
:unspecified_end
new-instance v5, Ljava/lang/AssertionError;
invoke-direct {v5}, Ljava/lang/AssertionError;-><init>()V
throw v5
.catch Ljava/lang/IllegalStateException; {:unspecified .. :unspecified_end} :unspecified_ok
:unspecified_ok
move-exception v5
invoke-virtual {v4}, Landroid/security/keystore/KeyGenParameterSpec;->getAlgorithmParameterSpec()Ljava/security/spec/AlgorithmParameterSpec;
move-result-object v5
if-nez v5, :fail
invoke-virtual {v4}, Landroid/security/keystore/KeyGenParameterSpec;->getAttestationChallenge()[B
move-result-object v5
if-nez v5, :fail
:null_spec
invoke-virtual {v0, v6}, Landroid/security/keystore/KeyGenParameterSpec$Builder;->setAlgorithmParameterSpec(Ljava/security/spec/AlgorithmParameterSpec;)Landroid/security/keystore/KeyGenParameterSpec$Builder;
:null_spec_end
goto/16 :fail
.catch Ljava/lang/NullPointerException; {:null_spec .. :null_spec_end} :null_ok
:null_ok
move-exception v5
new-instance v1, Ljava/security/spec/ECGenParameterSpec;
const-string v5, "secp256r1"
invoke-direct {v1, v5}, Ljava/security/spec/ECGenParameterSpec;-><init>(Ljava/lang/String;)V
invoke-virtual {v0, v1}, Landroid/security/keystore/KeyGenParameterSpec$Builder;->setAlgorithmParameterSpec(Ljava/security/spec/AlgorithmParameterSpec;)Landroid/security/keystore/KeyGenParameterSpec$Builder;
move-result-object v5
if-ne v5, v0, :fail
new-array v2, v7, [Ljava/lang/String;
const-string v5, "SHA-512"
aput-object v5, v2, v6
invoke-virtual {v0, v2}, Landroid/security/keystore/KeyGenParameterSpec$Builder;->setDigests([Ljava/lang/String;)Landroid/security/keystore/KeyGenParameterSpec$Builder;
new-array v3, v7, [B
const/16 v5, 42
aput-byte v5, v3, v6
invoke-virtual {v0, v3}, Landroid/security/keystore/KeyGenParameterSpec$Builder;->setAttestationChallenge([B)Landroid/security/keystore/KeyGenParameterSpec$Builder;
invoke-virtual {v0, v7}, Landroid/security/keystore/KeyGenParameterSpec$Builder;->setUniqueIdIncluded(Z)Landroid/security/keystore/KeyGenParameterSpec$Builder;
invoke-virtual {v0, v7}, Landroid/security/keystore/KeyGenParameterSpec$Builder;->setUserAuthenticationRequired(Z)Landroid/security/keystore/KeyGenParameterSpec$Builder;
const/16 v5, 256
invoke-virtual {v0, v5}, Landroid/security/keystore/KeyGenParameterSpec$Builder;->setKeySize(I)Landroid/security/keystore/KeyGenParameterSpec$Builder;
const-string v5, "GCM"
aput-object v5, v2, v6
invoke-virtual {v0, v2}, Landroid/security/keystore/KeyGenParameterSpec$Builder;->setBlockModes([Ljava/lang/String;)Landroid/security/keystore/KeyGenParameterSpec$Builder;
const-string v5, "NoPadding"
aput-object v5, v2, v6
invoke-virtual {v0, v2}, Landroid/security/keystore/KeyGenParameterSpec$Builder;->setEncryptionPaddings([Ljava/lang/String;)Landroid/security/keystore/KeyGenParameterSpec$Builder;
invoke-virtual {v0}, Landroid/security/keystore/KeyGenParameterSpec$Builder;->build()Landroid/security/keystore/KeyGenParameterSpec;
move-result-object v4
invoke-virtual {v0}, Landroid/security/keystore/KeyGenParameterSpec$Builder;->build()Landroid/security/keystore/KeyGenParameterSpec;
move-result-object v5
if-eq v5, v4, :fail
const-string v5, "changed"
aput-object v5, v2, v6
aput-byte v6, v3, v6
new-instance v5, Ljava/security/spec/ECGenParameterSpec;
const-string v8, "secp384r1"
invoke-direct {v5, v8}, Ljava/security/spec/ECGenParameterSpec;-><init>(Ljava/lang/String;)V
invoke-virtual {v0, v5}, Landroid/security/keystore/KeyGenParameterSpec$Builder;->setAlgorithmParameterSpec(Ljava/security/spec/AlgorithmParameterSpec;)Landroid/security/keystore/KeyGenParameterSpec$Builder;
invoke-virtual {v0, v6}, Landroid/security/keystore/KeyGenParameterSpec$Builder;->setDigests([Ljava/lang/String;)Landroid/security/keystore/KeyGenParameterSpec$Builder;
invoke-virtual {v0, v6}, Landroid/security/keystore/KeyGenParameterSpec$Builder;->setAttestationChallenge([B)Landroid/security/keystore/KeyGenParameterSpec$Builder;
invoke-virtual {v0, v6}, Landroid/security/keystore/KeyGenParameterSpec$Builder;->setUniqueIdIncluded(Z)Landroid/security/keystore/KeyGenParameterSpec$Builder;
const/16 v5, 512
invoke-virtual {v0, v5}, Landroid/security/keystore/KeyGenParameterSpec$Builder;->setKeySize(I)Landroid/security/keystore/KeyGenParameterSpec$Builder;
invoke-virtual {v4}, Landroid/security/keystore/KeyGenParameterSpec;->getAlgorithmParameterSpec()Ljava/security/spec/AlgorithmParameterSpec;
move-result-object v5
if-ne v5, v1, :fail
invoke-virtual {v4}, Landroid/security/keystore/KeyGenParameterSpec;->getKeySize()I
move-result v5
const/16 v8, 256
invoke-static {v5, v8}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v4}, Landroid/security/keystore/KeyGenParameterSpec;->isUniqueIdIncluded()Z
move-result v5
invoke-static {v5, v7}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v4}, Landroid/security/keystore/KeyGenParameterSpec;->isUserAuthenticationRequired()Z
move-result v5
invoke-static {v5, v7}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v4}, Landroid/security/keystore/KeyGenParameterSpec;->getPurposes()I
move-result v5
const/4 v8, 4
invoke-static {v5, v8}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v4}, Landroid/security/keystore/KeyGenParameterSpec;->getKeystoreAlias()Ljava/lang/String;
move-result-object v5
const-string v8, "vinix-metadata-probe"
invoke-virtual {v5, v8}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v5
invoke-static {v5, v7}, Lorg/vinix/bootstrap/Main;->expect(II)V
const/4 v9, 0
const-string v3, "getter-mutated"
:arrays
invoke-virtual {v4}, Landroid/security/keystore/KeyGenParameterSpec;->getDigests()[Ljava/lang/String;
move-result-object v5
aget-object v8, v5, v6
aput-object v3, v5, v6
const-string v5, "SHA-512"
invoke-virtual {v8, v5}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v5
invoke-static {v5, v7}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v4}, Landroid/security/keystore/KeyGenParameterSpec;->getAttestationChallenge()[B
move-result-object v5
aget-byte v8, v5, v6
aput-byte v6, v5, v6
const/16 v5, 42
invoke-static {v8, v5}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v4}, Landroid/security/keystore/KeyGenParameterSpec;->getBlockModes()[Ljava/lang/String;
move-result-object v5
aget-object v8, v5, v6
aput-object v3, v5, v6
const-string v5, "GCM"
invoke-virtual {v8, v5}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v5
invoke-static {v5, v7}, Lorg/vinix/bootstrap/Main;->expect(II)V
add-int/lit8 v9, v9, 1
invoke-virtual {v4}, Landroid/security/keystore/KeyGenParameterSpec;->getEncryptionPaddings()[Ljava/lang/String;
move-result-object v5
aget-object v8, v5, v6
aput-object v3, v5, v6
const-string v5, "NoPadding"
invoke-virtual {v8, v5}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v5
invoke-static {v5, v7}, Lorg/vinix/bootstrap/Main;->expect(II)V
const/4 v5, 2
if-lt v9, v5, :arrays
invoke-virtual {v0}, Landroid/security/keystore/KeyGenParameterSpec$Builder;->build()Landroid/security/keystore/KeyGenParameterSpec;
move-result-object v4
invoke-virtual {v4}, Landroid/security/keystore/KeyGenParameterSpec;->isDigestsSpecified()Z
move-result v5
invoke-static {v5, v6}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v4}, Landroid/security/keystore/KeyGenParameterSpec;->getAttestationChallenge()[B
move-result-object v5
if-nez v5, :fail
new-array v2, v6, [Ljava/lang/String;
invoke-virtual {v0, v2}, Landroid/security/keystore/KeyGenParameterSpec$Builder;->setDigests([Ljava/lang/String;)Landroid/security/keystore/KeyGenParameterSpec$Builder;
invoke-virtual {v0}, Landroid/security/keystore/KeyGenParameterSpec$Builder;->build()Landroid/security/keystore/KeyGenParameterSpec;
move-result-object v4
invoke-virtual {v4}, Landroid/security/keystore/KeyGenParameterSpec;->isDigestsSpecified()Z
move-result v5
invoke-static {v5, v7}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v4}, Landroid/security/keystore/KeyGenParameterSpec;->getDigests()[Ljava/lang/String;
move-result-object v5
array-length v5, v5
invoke-static {v5, v6}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-static {}, Lorg/vinix/bootstrap/KeyGenProbe;->authValidity()V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "KEYGEN-PARAMETERS-PASS metadata snapshots defensive-arrays null empty unspecified no-key-generation"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:fail
new-instance v5, Ljava/lang/AssertionError;
invoke-direct {v5}, Ljava/lang/AssertionError;-><init>()V
throw v5
.end method
')!
	path := root + '/smali/KeyGenProbe.smali'
	p := 'Landroid/security/keystore/KeyGenParameterSpec;'
	b := r'Landroid/security/keystore/KeyGenParameterSpec$Builder;'
	mut body := '\n.method private static authValidity()V\n.locals 8\nnew-instance v0, ' + b + '\nconst-string v1, "vinix-auth-validity-metadata"\nconst/4 v2, 1\ninvoke-direct {v0, v1, v2}, ' + b + '-><init>(Ljava/lang/String;I)V\ninvoke-virtual {v0}, ' + b + '->build()' + p + '\nmove-result-object v1\nconst/4 v6, -1\n'
	for value in [-1, 0, 60, 2147483647] {
		body += 'const v3, ${value}\ninvoke-virtual {v0, v3}, ${b}->setUserAuthenticationValidityDurationSeconds(I)${b}\nmove-result-object v4\nif-ne v4, v0, :auth_bad\ninvoke-virtual {v1}, ${p}->getUserAuthenticationValidityDurationSeconds()I\nmove-result v4\ninvoke-static {v4, v6}, Lorg/vinix/bootstrap/Main;->expect(II)V\ninvoke-virtual {v0}, ${b}->build()${p}\nmove-result-object v1\ninvoke-virtual {v1}, ${p}->getUserAuthenticationValidityDurationSeconds()I\nmove-result v4\ninvoke-static {v4, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V\ninvoke-virtual {v1}, ${p}->isUserAuthenticationRequired()Z\nmove-result v4\nif-nez v4, :auth_bad\nmove v6, v3\n'
	}
	for index, value in [-2, -2147483647 - 1] {
		body += 'const v3, ${value}\n:auth_invalid_${index}\ninvoke-virtual {v0, v3}, ${b}->setUserAuthenticationValidityDurationSeconds(I)${b}\n:auth_invalid_end_${index}\ngoto :auth_bad\n.catch Ljava/lang/IllegalArgumentException; {:auth_invalid_${index} .. :auth_invalid_end_${index}} :auth_caught_${index}\n:auth_caught_${index}\nmove-exception v4\ninvoke-virtual {v0}, ${b}->build()${p}\nmove-result-object v2\ninvoke-virtual {v2}, ${p}->getUserAuthenticationValidityDurationSeconds()I\nmove-result v4\ninvoke-static {v4, v6}, Lorg/vinix/bootstrap/Main;->expect(II)V\n'
	}
	body += 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "KEYGEN-AUTH-VALIDITY-PASS default per-operation zero positive max snapshots fluent invalid-preserves-state no-authentication-grant"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void\n:auth_bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "keygen authentication validity metadata"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0\n.end method\n'
	os.write_file(path, os.read_file(path)! + body)!
}
