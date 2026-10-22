// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Use AOSP's verifier, including digest verification and v3 proof of rotation.
// Reading certificates out of a signing block does not authenticate an APK.
fn framework_signature_dependency(smali string, work string, tools string, java string) !map[string]string {
	inputs := {
		'apksig-8.7.3.jar': [
			'c070ed1394629d74641aa0906f60b2ffa1ee77e6366a1f93437f59717b1aeb89',
			'https://dl.google.com/dl/android/maven2/com/android/tools/build/apksig/8.7.3/apksig-8.7.3.jar',
		]
		'r8-8.3.37.jar':    [r8_sha256, 'https://storage.googleapis.com/r8-releases/raw/8.3.37/r8.jar']
	}
	mut hashes := map[string]string{}
	for name, record in inputs {
		path := tools + '/' + name
		if !os.is_file(path) {
			checked(['curl', '--fail', '--location', '--silent', '--show-error', '--retry', '3',
				'--output', path + '.part', record[1]])!
			if framework_digest(path + '.part')! != record[0] {
				os.rm(path + '.part')!
				return error('APK verifier dependency checksum mismatch: ' + name)
			}
			os.mv(path + '.part', path)!
		}
		if framework_digest(path)! != record[0] {
			return error('APK verifier dependency checksum mismatch: ' + name)
		}
		hashes[name] = record[0]
	}
	dex := work + '/apksig-dex'
	os.mkdir_all(dex)!
	checked([java, '-cp', tools + '/r8-8.3.37.jar', 'com.android.tools.r8.D8', '--release', '--min-api',
		'26', '--output', dex, tools + '/apksig-8.7.3.jar'])!
	dex_callsites(os.read_bytes(dex + '/classes.dex')!)!
	checked([java, '-cp', tools + '/*', 'org.jf.baksmali.Main', 'disassemble', '--jobs', '2',
		dex + '/classes.dex', '-o', smali])!
	return hashes
}

fn signature_method(declaration string, body string) string {
	return '.method ' + declaration + '\n.locals 6\n' + body + '\n.end method\n'
}

fn framework_signature_notice(jar string, work string, tools string) ! {
	directory := os.abs_path(work + '/apk-verifier-notice')
	os.mkdir_all(directory + '/META-INF/licenses')!
	license := checked(['unzip', '-p', tools + '/apksig-8.7.3.jar', 'LICENSE'])!.stdout
	os.write_file(directory + '/META-INF/licenses/apksig-LICENSE',
		'AOSP APK Signature Scheme verification library 8.7.3\n' +
			'https://android.googlesource.com/platform/tools/apksig/\n' + license)!
	checked_in(['zip', '-q', os.abs_path(jar), 'META-INF/licenses/apksig-LICENSE'], directory)!
}

fn framework_package_signatures(smali string) ! {
	info := 'Landroid/content/pm/SigningInfo;'
	pkg := 'Landroid/content/pm/PackageParser$Package;'
	helper := 'Landroid/atl/VinixApkSignatures;'
	mut signing := '.class public final ' + info + '\n.super Ljava/lang/Object;\n' +
		'.field public vinixCurrent:[Landroid/content/pm/Signature;\n.field public vinixHistory:[Landroid/content/pm/Signature;\n' +
		signature_method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void')
	for name, field in {
		'getApkContentsSigners':        'vinixCurrent'
		'getSigningCertificateHistory': 'vinixHistory'
	} {
		prefix := if name == 'getSigningCertificateHistory' {
			'invoke-virtual {p0}, ' + info + '->hasMultipleSigners()Z\nmove-result v0\nif-eqz v0, :single\nconst/4 v0, 0\nreturn-object v0\n:single\n'
		} else {
			''
		}
		signing += signature_method('public ' + name + '()[Landroid/content/pm/Signature;', prefix +
			'iget-object v0, p0, ' + info + '->' + field + ':[Landroid/content/pm/Signature;\nif-eqz v0, :done\n' +
			'invoke-virtual {v0}, [Landroid/content/pm/Signature;->clone()Ljava/lang/Object;\nmove-result-object v0\ncheck-cast v0, [Landroid/content/pm/Signature;\n:done\nreturn-object v0')
	}
	for name, field in {
		'hasMultipleSigners':         'vinixCurrent'
		'hasPastSigningCertificates': 'vinixHistory'
	} {
		signing += signature_method('public ' + name + '()Z', 'const/4 v1, 0\niget-object v0, p0, ' + info + '->' + field +
			':[Landroid/content/pm/Signature;\nif-eqz v0, :done\narray-length v0, v0\nconst/4 v2, 1\nif-le v0, v2, :done\nconst/4 v1, 1\n:done\nreturn v1')
	}
	os.write_file(smali + '/android/content/pm/SigningInfo.smali', signing)!
	package_path := smali + '/android/content/pm/PackageParser$Package.smali'
	os.write_file(package_path, os.read_file(package_path)! + '\n.field public vinixSigningInfo:' + info + '\n')!
	verifier := '.class public final ' + helper + '\n.super Ljava/lang/Object;\n' +
		signature_method('private static certificates(Ljava/util/List;)[Landroid/content/pm/Signature;', '
invoke-interface {p0}, Ljava/util/List;->size()I
move-result v0
new-array v1, v0, [Landroid/content/pm/Signature;
const/4 v2, 0
:loop
if-ge v2, v0, :done
invoke-interface {p0, v2}, Ljava/util/List;->get(I)Ljava/lang/Object;
move-result-object v3
check-cast v3, Ljava/security/cert/X509Certificate;
invoke-virtual {v3}, Ljava/security/cert/X509Certificate;->getEncoded()[B
move-result-object v3
new-instance v4, Landroid/content/pm/Signature;
invoke-direct {v4, v3}, Landroid/content/pm/Signature;-><init>([B)V
aput-object v4, v1, v2
add-int/lit8 v2, v2, 1
goto :loop
:done
return-object v1') +
		signature_method('public static verify(Ljava/lang/String;)' + info, '
new-instance v0, Ljava/io/File;
invoke-direct {v0, p0}, Ljava/io/File;-><init>(Ljava/lang/String;)V
new-instance v1, Lcom/android/apksig/ApkVerifier$Builder;
invoke-direct {v1, v0}, Lcom/android/apksig/ApkVerifier$Builder;-><init>(Ljava/io/File;)V
# Vinix supports APK signing schemes through Android 15. ATL defaults its
# Java compatibility SDK to 9; that historical UI profile must not require
# JAR signatures on APKs authenticated by a supported signing block.
const/16 v0, 35
invoke-virtual {v1, v0}, Lcom/android/apksig/ApkVerifier$Builder;->setMinCheckedPlatformVersion(I)Lcom/android/apksig/ApkVerifier$Builder;
invoke-virtual {v1, v0}, Lcom/android/apksig/ApkVerifier$Builder;->setMaxCheckedPlatformVersion(I)Lcom/android/apksig/ApkVerifier$Builder;
invoke-virtual {v1}, Lcom/android/apksig/ApkVerifier$Builder;->build()Lcom/android/apksig/ApkVerifier;
move-result-object v0
invoke-virtual {v0}, Lcom/android/apksig/ApkVerifier;->verify()Lcom/android/apksig/ApkVerifier$Result;
move-result-object v0
invoke-virtual {v0}, Lcom/android/apksig/ApkVerifier$Result;->isVerified()Z
move-result v1
if-nez v1, :verified
invoke-virtual {v0}, Lcom/android/apksig/ApkVerifier$Result;->getAllErrors()Ljava/util/List;
move-result-object v0
invoke-static {v0}, Ljava/lang/String;->valueOf(Ljava/lang/Object;)Ljava/lang/String;
move-result-object v0
new-instance v1, Ljava/lang/SecurityException;
invoke-direct {v1, v0}, Ljava/lang/SecurityException;-><init>(Ljava/lang/String;)V
throw v1
:verified
invoke-virtual {v0}, Lcom/android/apksig/ApkVerifier$Result;->getSignerCertificates()Ljava/util/List;
move-result-object v1
invoke-static {v1}, Landroid/atl/VinixApkSignatures;->certificates(Ljava/util/List;)[Landroid/content/pm/Signature;
move-result-object v1
new-instance v2, Landroid/content/pm/SigningInfo;
invoke-direct {v2}, Landroid/content/pm/SigningInfo;-><init>()V
iput-object v1, v2, Landroid/content/pm/SigningInfo;->vinixCurrent:[Landroid/content/pm/Signature;
array-length v3, v1
const/4 v4, 1
if-ne v3, v4, :done
iput-object v1, v2, Landroid/content/pm/SigningInfo;->vinixHistory:[Landroid/content/pm/Signature;
invoke-virtual {v0}, Lcom/android/apksig/ApkVerifier$Result;->getSigningCertificateLineage()Lcom/android/apksig/SigningCertificateLineage;
move-result-object v0
if-eqz v0, :done
invoke-virtual {v0}, Lcom/android/apksig/SigningCertificateLineage;->getCertificatesInLineage()Ljava/util/List;
move-result-object v0
invoke-static {v0}, Landroid/atl/VinixApkSignatures;->certificates(Ljava/util/List;)[Landroid/content/pm/Signature;
move-result-object v0
iput-object v0, v2, Landroid/content/pm/SigningInfo;->vinixHistory:[Landroid/content/pm/Signature;
:done
return-object v2')
	os.write_file(smali + '/android/atl/VinixApkSignatures.smali', verifier)!
	parser_path := smali + '/android/content/pm/PackageParser.smali'
	mut parser := os.read_file(parser_path)!
	parser = framework_replace_method(parser, 'collectCertificates(' + pkg + 'I)Z', signature_method('public collectCertificates(' + pkg + 'I)Z', '
const/4 v0, 0
iput-object v0, p1, Landroid/content/pm/PackageParser$Package;->mSignatures:[Landroid/content/pm/Signature;
iput-object v0, p1, Landroid/content/pm/PackageParser$Package;->vinixSigningInfo:Landroid/content/pm/SigningInfo;
:try
iget-object v0, p0, Landroid/content/pm/PackageParser;->mArchiveSourcePath:Ljava/lang/String;
invoke-static {v0}, Landroid/atl/VinixApkSignatures;->verify(Ljava/lang/String;)Landroid/content/pm/SigningInfo;
move-result-object v0
iput-object v0, p1, Landroid/content/pm/PackageParser$Package;->vinixSigningInfo:Landroid/content/pm/SigningInfo;
invoke-virtual {v0}, Landroid/content/pm/SigningInfo;->getApkContentsSigners()[Landroid/content/pm/Signature;
move-result-object v1
invoke-virtual {v0}, Landroid/content/pm/SigningInfo;->hasPastSigningCertificates()Z
move-result v2
if-eqz v2, :legacy
invoke-virtual {v0}, Landroid/content/pm/SigningInfo;->getSigningCertificateHistory()[Landroid/content/pm/Signature;
move-result-object v1
const/4 v2, 0
aget-object v1, v1, v2
const/4 v2, 1
new-array v2, v2, [Landroid/content/pm/Signature;
const/4 v3, 0
aput-object v1, v2, v3
move-object v1, v2
:legacy
iput-object v1, p1, Landroid/content/pm/PackageParser$Package;->mSignatures:[Landroid/content/pm/Signature;
:end
const/4 v0, 1
return v0
:bad
move-exception v0
const-string v1, "VinixApkSignatures"
const-string v2, "APK signature verification failed"
invoke-static {v1, v2, v0}, Landroid/util/Log;->e(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)I
const/4 v0, 0
return v0
.catch Ljava/lang/Exception; {:try .. :end} :bad'))!
	// Preserve the old PackageInfo generation, filling signingInfo only for
	// GET_SIGNING_CERTIFICATES. Legacy GET_SIGNATURES gets the oldest signer.
	args := '(' + pkg + '[IIJJLjava/util/HashSet;Landroid/content/pm/PackageUserState;I)Landroid/content/pm/PackageInfo;'
	declaration := '.method public static generatePackageInfo' + args
	if parser.count(declaration) != 1 {
		return error('unexpected PackageParser.generatePackageInfo')
	}
	parser = parser.replace(declaration, '.method public static vinixOriginalGeneratePackageInfo' + args)
	parser += '.method public static generatePackageInfo' + args + '\n.locals 2\n' +
		'invoke-static/range {p0 .. p9}, Landroid/content/pm/PackageParser;->vinixOriginalGeneratePackageInfo' + args + '\nmove-result-object v0\n' +
		'if-eqz v0, :done\nconst/4 v1, 0\niput-object v1, v0, Landroid/content/pm/PackageInfo;->signingInfo:' + info + '\n' +
		'const v1, 0x8000000\nand-int v1, p2, v1\nif-eqz v1, :done\niget-object v1, p0, ' + pkg + '->vinixSigningInfo:' + info + '\n' +
		'iput-object v1, v0, Landroid/content/pm/PackageInfo;->signingInfo:' + info + '\n:done\nreturn-object v0\n.end method\n'
	os.write_file(parser_path, parser)!
	framework_verified_loaders(smali)!
}

fn framework_verified_loaders(smali string) ! {
	loaded_path := smali + '/android/atl/ATLLoadedApp.smali'
	mut loaded := os.read_file(loaded_path)!
	factory := loaded.index('.method public static loadFromPath(') or { return error('missing APK loader') }
	start := factory + (loaded[factory..].index('    sget-object v2, Landroid/atl/ATLLoadedApp;->play_services:Ljava/util/HashSet;') or { return error('missing signature substitution') })
	end := start + (loaded[start..].index('    :cond_58') or { return error('missing signature substitution exit') })
	loaded = loaded[..start] + '    move-result v2\n    if-nez v2, :cond_58\n    new-instance v2, Ljava/io/IOException;\n    const-string v4, "APK signature verification failed"\n    invoke-direct {v2, v4}, Ljava/io/IOException;-><init>(Ljava/lang/String;)V\n    throw v2\n\n' + loaded[end..]
	os.write_file(loaded_path, loaded)!
	manager_path := smali + '/android/atl/ATLLoadedAppManager.smali'
	mut manager := os.read_file(manager_path)!
	collect := '    invoke-virtual {v1, v0, v3}, Landroid/content/pm/PackageParser;->collectCertificates(Landroid/content/pm/PackageParser$Package;I)Z'
	if manager.count(collect) != 1 { return error('unexpected companion signature collection') }
	manager = manager.replace(collect, collect + '\n    move-result v1\n    if-nez v1, :vinix_signature_valid\n    const/4 v0, 0\n    goto :cond_88\n    :vinix_signature_valid\n')
	os.write_file(manager_path, manager)!
	context_path := smali + '/android/app/ContextImpl.smali'
	mut context := os.read_file(context_path)!
	method := context.index('.method public createPackageContext(') or { return error('missing package context') }
	tail := context[method..]
	start_context := method + (tail.index('    :cond_5e\n') or { return error('missing package context absence branch') })
	end_context := method + (tail.index('.end method') or { return error('unterminated package context') })
	context = context[..start_context] + '    :cond_5e\n    new-instance v0, Landroid/content/pm/PackageManager$NameNotFoundException;\n    invoke-direct {v0, p1}, Landroid/content/pm/PackageManager$NameNotFoundException;-><init>(Ljava/lang/String;)V\n    throw v0\n' + context[end_context..]
	os.write_file(context_path, context)!
}
