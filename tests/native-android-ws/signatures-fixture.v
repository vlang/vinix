// SPDX-License-Identifier: GPL-2.0-or-later
// Build after bootstrap-fixture.v. Verifies real APK digests in guest ART,
// including negative cases; the primary APK uses the normal verified loader.
module main

import os

fn checked(args []string) {
	r := os.exec(args)
	if r.exit_code != 0 { panic(r.output) }
}

fn main() {
	if os.args.len != 6 { panic('OUTPUT FIXTURE_DIR SMALI_TOOLS JAVA APKSIGNER') }
	out, fixture, tools := os.abs_path(os.args[1]), os.abs_path(os.args[2]), os.abs_path(os.args[3])
	java, signer := os.args[4], os.abs_path(os.args[5])
	os.mkdir_all(out + '/smali/org/vinix/bootstrap')!
	os.mkdir_all(out + '/assets/signatures')!
	unsigned := out + '/assets/signatures/unsigned.apk'
	os.cp(fixture + '/unsigned.apk', unsigned)!
	// Stored entry: change its contents while preserving the ZIP structure.
	payload := 'VINIX-SIGNATURE-DIGEST-CHECK-7fc91d6a'
	os.write_file(out + '/signature-payload.txt', payload)!
	checked(['zip', '-q', '-0', '-j', unsigned, out + '/signature-payload.txt'])
	for scheme in ['v1', 'v2', 'v3'] {
		checked([java, '-jar', signer, 'sign', '--ks', fixture + '/fixture.p12', '--ks-key-alias',
			'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--min-sdk-version',
			'28', '--v1-signing-enabled', (scheme == 'v1').str(), '--v2-signing-enabled',
			(scheme == 'v2').str(), '--v3-signing-enabled', (scheme == 'v3').str(),
			'--v4-signing-enabled', 'false', '--out', out + '/assets/signatures/' + scheme + '.apk',
			unsigned])
		checked([java, '-jar', signer, 'verify', '--min-sdk-version', '35', '--max-sdk-version',
			'35', out + '/assets/signatures/' + scheme + '.apk'])
	}
	keytool := os.dir(java) + '/keytool'
	checked([keytool, '-exportcert', '-keystore', fixture + '/fixture.p12', '-alias', 'fixture',
		'-storepass', 'android', '-file', out + '/original.der'])
	original := os.read_bytes(out + '/original.der')!.hex()
	if !os.is_file(out + '/rotated.p12') {
		checked([keytool, '-genkeypair', '-keystore', out + '/rotated.p12', '-alias', 'rotated',
			'-storepass', 'android', '-keypass', 'android', '-dname', 'CN=Vinix rotated fixture',
			'-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650'])
	}
	old_key := ['--ks', fixture + '/fixture.p12', '--ks-key-alias', 'fixture', '--ks-pass',
		'pass:android', '--key-pass', 'pass:android']
	new_key := ['--ks', out + '/rotated.p12', '--ks-key-alias', 'rotated', '--ks-pass', 'pass:android',
		'--key-pass', 'pass:android']
	mut rotate := [java, '-jar', signer, 'rotate', '--out', out + '/lineage', '--old-signer']
	rotate << old_key
	rotate << '--new-signer'
	rotate << new_key
	checked(rotate)
	mut rotated := [java, '-jar', signer, 'sign', '--min-sdk-version', '28',
		'--rotation-min-sdk-version', '33', '--v1-signing-enabled', 'false', '--v2-signing-enabled',
		'false', '--v3-signing-enabled', 'true', '--v4-signing-enabled', 'false', '--lineage',
		out + '/lineage', '--out', out + '/assets/signatures/rotated.apk']
	rotated << old_key
	rotated << '--next-signer'
	rotated << new_key
	rotated << unsigned
	checked(rotated)
	checked([java, '-jar', signer, 'verify', '--min-sdk-version', '35', '--max-sdk-version', '35',
		out + '/assets/signatures/rotated.apk'])
	mut tampered := os.read_bytes(out + '/assets/signatures/v3.apk')!
	at := tampered.bytestr().index(payload) or { panic('missing stored tamper target') }
	tampered[at] ^= 1
	os.write_file_array(out + '/assets/signatures/tampered.apk', tampered)!
	failed := os.exec([java, '-jar', signer, 'verify', out + '/assets/signatures/tampered.apk'])
	assert failed.exit_code != 0
	source := '.class public Lorg/vinix/bootstrap/Main;\n.super Landroid/app/Activity;\n' +
		'.method public constructor <init>()V\n.locals 0\ninvoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void\n.end method\n' +
		'.method public onCreate(Landroid/os/Bundle;)V\n.locals 6\n' + '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
const-string v0, "v1"
const/4 v1, 1
invoke-direct {p0, v0, v1}, Lorg/vinix/bootstrap/Main;->verify(Ljava/lang/String;Z)V
const-string v0, "v2"
invoke-direct {p0, v0, v1}, Lorg/vinix/bootstrap/Main;->verify(Ljava/lang/String;Z)V
const-string v0, "v3"
invoke-direct {p0, v0, v1}, Lorg/vinix/bootstrap/Main;->verify(Ljava/lang/String;Z)V
const-string v0, "rotated"
invoke-direct {p0, v0, v1}, Lorg/vinix/bootstrap/Main;->verify(Ljava/lang/String;Z)V
const-string v0, "unsigned"
const/4 v1, 0
invoke-direct {p0, v0, v1}, Lorg/vinix/bootstrap/Main;->verify(Ljava/lang/String;Z)V
const-string v0, "tampered"
invoke-direct {p0, v0, v1}, Lorg/vinix/bootstrap/Main;->verify(Ljava/lang/String;Z)V
invoke-virtual {p0}, Landroid/app/Activity;->getPackageManager()Landroid/content/pm/PackageManager;
move-result-object v0
invoke-virtual {p0}, Landroid/app/Activity;->getPackageName()Ljava/lang/String;
move-result-object v1
const v2, 0x8000040
invoke-virtual {v0, v1, v2}, Landroid/content/pm/PackageManager;->getPackageInfo(Ljava/lang/String;I)Landroid/content/pm/PackageInfo;
move-result-object v0
iget-object v1, v0, Landroid/content/pm/PackageInfo;->signatures:[Landroid/content/pm/Signature;
array-length v1, v1
const/4 v2, 1
if-ne v1, v2, :bad
iget-object v1, v0, Landroid/content/pm/PackageInfo;->signatures:[Landroid/content/pm/Signature;
const/4 v3, 0
aget-object v1, v1, v3
invoke-virtual {v1}, Landroid/content/pm/Signature;->toCharsString()Ljava/lang/String;
move-result-object v1
const-string v3, "' + original + '"
invoke-virtual {v1, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :bad
iget-object v0, v0, Landroid/content/pm/PackageInfo;->signingInfo:Landroid/content/pm/SigningInfo;
invoke-virtual {v0}, Landroid/content/pm/SigningInfo;->getApkContentsSigners()[Landroid/content/pm/Signature;
move-result-object v1
array-length v1, v1
if-ne v1, v2, :bad
invoke-virtual {v0}, Landroid/content/pm/SigningInfo;->hasMultipleSigners()Z
move-result v1
if-nez v1, :bad
invoke-virtual {v0}, Landroid/content/pm/SigningInfo;->hasPastSigningCertificates()Z
move-result v1
if-nez v1, :bad
invoke-virtual {v0}, Landroid/content/pm/SigningInfo;->getApkContentsSigners()[Landroid/content/pm/Signature;
move-result-object v1
const/4 v2, 0
const/4 v3, 0
aput-object v3, v1, v2
invoke-virtual {v0}, Landroid/content/pm/SigningInfo;->getApkContentsSigners()[Landroid/content/pm/Signature;
move-result-object v1
aget-object v1, v1, v2
if-eqz v1, :bad
:missing
const-string v0, "org.vinix.package.does.not.exist"
const/4 v1, 3
invoke-virtual {p0, v0, v1}, Landroid/app/Activity;->createPackageContext(Ljava/lang/String;I)Landroid/content/Context;
:missing_end
goto :bad
:missing_ok
move-exception v0
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "SIGNATURE-FIXTURE-PASS v1 v2 v3 rotation unsigned-rejected tampered-rejected signing-info actual-certificate missing-context"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "APK signature checks passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "APK verification or PackageManager signing information"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
.catch Landroid/content/pm/PackageManager$NameNotFoundException; {:missing .. :missing_end} :missing_ok
.end method
.method private verify(Ljava/lang/String;Z)V
.locals 8
new-instance v0, Ljava/lang/StringBuilder;
invoke-direct {v0}, Ljava/lang/StringBuilder;-><init>()V
const-string v1, "signatures/"
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v0, p1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
const-string v1, ".apk"
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
move-result-object v0
invoke-virtual {p0}, Landroid/app/Activity;->getAssets()Landroid/content/res/AssetManager;
move-result-object v1
invoke-virtual {v1, v0}, Landroid/content/res/AssetManager;->open(Ljava/lang/String;)Ljava/io/InputStream;
move-result-object v0
const-string v1, "signature"
const-string v2, ".apk"
invoke-virtual {p0}, Landroid/app/Activity;->getCacheDir()Ljava/io/File;
move-result-object v3
invoke-static {v1, v2, v3}, Ljava/io/File;->createTempFile(Ljava/lang/String;Ljava/lang/String;Ljava/io/File;)Ljava/io/File;
move-result-object v1
new-instance v2, Ljava/io/FileOutputStream;
invoke-direct {v2, v1}, Ljava/io/FileOutputStream;-><init>(Ljava/io/File;)V
const/16 v3, 8192
new-array v3, v3, [B
const/4 v5, 0
:copy
invoke-virtual {v0, v3}, Ljava/io/InputStream;->read([B)I
move-result v4
if-lez v4, :copied
invoke-virtual {v2, v3, v5, v4}, Ljava/io/FileOutputStream;->write([BII)V
goto :copy
:copied
invoke-virtual {v2}, Ljava/io/FileOutputStream;->close()V
invoke-virtual {v0}, Ljava/io/InputStream;->close()V
:try
invoke-virtual {v1}, Ljava/io/File;->getPath()Ljava/lang/String;
move-result-object v0
invoke-static {v0}, Landroid/atl/VinixApkSignatures;->verify(Ljava/lang/String;)Landroid/content/pm/SigningInfo;
move-result-object v0
:end
if-eqz p2, :bad
move-object v6, v0
invoke-virtual {v0}, Landroid/content/pm/SigningInfo;->getApkContentsSigners()[Landroid/content/pm/Signature;
move-result-object v0
array-length v0, v0
const/4 v2, 1
if-ne v0, v2, :bad
const-string v0, "rotated"
invoke-virtual {v0, p1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v7
invoke-virtual {v6}, Landroid/content/pm/SigningInfo;->hasPastSigningCertificates()Z
move-result v0
if-ne v0, v7, :bad
if-eqz v7, :done
invoke-virtual {v6}, Landroid/content/pm/SigningInfo;->getSigningCertificateHistory()[Landroid/content/pm/Signature;
move-result-object v0
array-length v2, v0
const/4 v3, 2
if-ne v2, v3, :bad
const/4 v2, 0
aget-object v0, v0, v2
invoke-virtual {v0}, Landroid/content/pm/Signature;->toCharsString()Ljava/lang/String;
move-result-object v0
const-string v2, "' + original + '"
invoke-virtual {v0, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
goto :done
:rejected
move-exception v0
invoke-virtual {v0}, Ljava/lang/Throwable;->printStackTrace()V
if-nez p2, :bad
:done
invoke-virtual {v1}, Ljava/io/File;->delete()Z
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
invoke-virtual {v0, p1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
.catch Ljava/lang/SecurityException; {:try .. :end} :rejected
.end method
'
	os.write_file(out + '/smali/org/vinix/bootstrap/Main.smali', source)!
	for name in ['App', 'High', 'Low'] {
		os.cp(fixture + '/smali/org/vinix/bootstrap/' + name + '.smali', out + '/smali/org/vinix/bootstrap/' + name + '.smali')!
	}
	checked([java, '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', out + '/smali', '-o',
		out + '/classes.dex'])
	os.cp(fixture + '/unsigned.apk', out + '/unsigned.apk')!
	checked(['zip', '-q', '-j', out + '/unsigned.apk', out + '/classes.dex'])
	// zip's directory argument is relative to cwd; use a process working directory.
	mut zip := os.new_process('zip')
	zip.set_work_folder(out)
	zip.set_args(['-q', '-r', out + '/unsigned.apk', 'assets'])
	zip.set_redirect_stdio()
	zip.run()
	zip.wait()
	if zip.code != 0 { panic(zip.stdout_slurp() + zip.stderr_slurp()) }
	checked([java, '-jar', signer, 'sign', '--ks', fixture + '/fixture.p12', '--ks-key-alias',
		'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out',
		out + '/probe.apk', out + '/unsigned.apk'])
	println('SIGNATURE-FIXTURE-APK ' + out + '/probe.apk')
}
