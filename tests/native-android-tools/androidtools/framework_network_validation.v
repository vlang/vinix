// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// A configured default route is not proof of Internet access. Keep one
// asynchronous HTTPS probe per process, and expose validation only while its
// successful result is fresh and the selected kernel link is unchanged.
pub fn framework_network_validation(smali string) ! {
	path := smali + '/android/net/ConnectivityManager.smali'
	mut text := os.read_file(path)!
	if text.contains('VinixNetworkValidation') || text.contains('vinixRawNetworkState') {
		return error('network validation already installed')
	}
	window_animations_method(text, 'public vinixNetworkState()I',
		'.registers 9\ninvoke-virtual {p0}, Landroid/net/ConnectivityManager;->nativeGetNetworkState()I\nmove-result v0\nreturn v0')!
	// Every public snapshot and callback must use the same measured state.
	text = text.replace('->nativeGetNetworkState()I', '->vinixNetworkState()I')
	text = framework_replace_method(text, 'vinixNetworkState()I', r'
.method public vinixNetworkState()I
.locals 1
invoke-virtual {p0}, Landroid/net/ConnectivityManager;->nativeGetNetworkState()I
move-result v0
invoke-static {p0, v0}, Landroid/atl/VinixNetworkValidation;->state(Landroid/net/ConnectivityManager;I)I
move-result v0
return v0
.end method')!
	text += r'
.method public vinixRawNetworkState()I
.locals 1
invoke-virtual {p0}, Landroid/net/ConnectivityManager;->nativeGetNetworkState()I
move-result v0
return v0
.end method
'
	// Bit 4 is private to the Java bridge; the native low byte uses only 1/2.
	cap_start := text.index('.method public static vinixCapabilities(I)') or {
		return error('network capabilities bridge missing')
	}
	cap_end := cap_start + (text[cap_start..].index('.end method') or {
		return error('unterminated capabilities bridge')
	})
	cap := text[cap_start..cap_end]
	needle := 'invoke-direct {v0}, Landroid/net/NetworkCapabilities;-><init>()V'
	if cap.count(needle) != 1 { return error('unique capabilities construction required') }
	updated := cap.replace(needle, needle + r'
and-int/lit8 v1, p0, 0x4
if-eqz v1, :vinix_not_validated
const/16 v1, 0x10
invoke-virtual {v0, v1}, Landroid/net/NetworkCapabilities;->addCapability(I)Landroid/net/NetworkCapabilities;
:vinix_not_validated
')
	text = text[..cap_start] + updated + text[cap_end..]
	os.write_file(path, text)!
	os.write_file(smali + '/android/atl/VinixNetworkValidation.smali', network_validation_smali())!
}

fn network_validation_smali() string {
	return r'.class public final Landroid/atl/VinixNetworkValidation;
.super Ljava/lang/Object;
.implements Ljava/lang/Runnable;
.field private static selected:I
.field private static generation:I
.field private static freshUntil:J
.field private static nextProbe:J
.field private static running:Z
.field private final manager:Landroid/net/ConnectivityManager;
.field private final link:I
.field private final epoch:I

.method private constructor <init>(Landroid/net/ConnectivityManager;II)V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
iput-object p1, p0, Landroid/atl/VinixNetworkValidation;->manager:Landroid/net/ConnectivityManager;
iput p2, p0, Landroid/atl/VinixNetworkValidation;->link:I
iput p3, p0, Landroid/atl/VinixNetworkValidation;->epoch:I
return-void
.end method

.method public static declared-synchronized state(Landroid/net/ConnectivityManager;I)I
.locals 8
invoke-static {}, Ljava/lang/System;->nanoTime()J
move-result-wide v0
sget v2, Landroid/atl/VinixNetworkValidation;->selected:I
if-eq v2, p1, :same
sput p1, Landroid/atl/VinixNetworkValidation;->selected:I
sget v2, Landroid/atl/VinixNetworkValidation;->generation:I
add-int/lit8 v2, v2, 1
sput v2, Landroid/atl/VinixNetworkValidation;->generation:I
const-wide/16 v2, 0
sput-wide v2, Landroid/atl/VinixNetworkValidation;->freshUntil:J
sput-wide v2, Landroid/atl/VinixNetworkValidation;->nextProbe:J
:same
and-int/lit8 v2, p1, 3
const/4 v3, 3
if-ne v2, v3, :done
sget-boolean v2, Landroid/atl/VinixNetworkValidation;->running:Z
if-nez v2, :fresh
sget-wide v2, Landroid/atl/VinixNetworkValidation;->nextProbe:J
const-wide/16 v4, 0
cmp-long v4, v2, v4
if-eqz v4, :schedule
cmp-long v2, v0, v2
if-ltz v2, :fresh
:schedule
const/4 v2, 1
sput-boolean v2, Landroid/atl/VinixNetworkValidation;->running:Z
const-wide v2, 30000000000L
add-long/2addr v2, v0
sput-wide v2, Landroid/atl/VinixNetworkValidation;->nextProbe:J
:start
new-instance v2, Landroid/atl/VinixNetworkValidation;
sget v3, Landroid/atl/VinixNetworkValidation;->generation:I
invoke-direct {v2, p0, p1, v3}, Landroid/atl/VinixNetworkValidation;-><init>(Landroid/net/ConnectivityManager;II)V
new-instance v3, Ljava/lang/Thread;
const-string v4, "VinixNetworkValidation"
invoke-direct {v3, v2, v4}, Ljava/lang/Thread;-><init>(Ljava/lang/Runnable;Ljava/lang/String;)V
const/4 v2, 1
invoke-virtual {v3, v2}, Ljava/lang/Thread;->setDaemon(Z)V
invoke-virtual {v3}, Ljava/lang/Thread;->start()V
:started
goto :fresh
.catch Ljava/lang/Throwable; {:start .. :started} :failed
:failed
move-exception v2
const/4 v2, 0
sput-boolean v2, Landroid/atl/VinixNetworkValidation;->running:Z
:fresh
sget-wide v2, Landroid/atl/VinixNetworkValidation;->freshUntil:J
const-wide/16 v4, 0
cmp-long v4, v2, v4
if-eqz v4, :done
sub-long/2addr v2, v0
const-wide/16 v4, 0
cmp-long v2, v2, v4
if-lez v2, :done
or-int/lit8 p1, p1, 4
:done
return p1
.end method

.method private static declared-synchronized complete(IIZ)V
.locals 5
const/4 v0, 0
sput-boolean v0, Landroid/atl/VinixNetworkValidation;->running:Z
sget v0, Landroid/atl/VinixNetworkValidation;->generation:I
if-ne p1, v0, :done
sget v0, Landroid/atl/VinixNetworkValidation;->selected:I
if-ne p0, v0, :done
const-wide/16 v0, 0
if-eqz p2, :store
invoke-static {}, Ljava/lang/System;->nanoTime()J
move-result-wide v0
const-wide v2, 60000000000L
add-long/2addr v0, v2
:store
sput-wide v0, Landroid/atl/VinixNetworkValidation;->freshUntil:J
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "VINIX-NETWORK-VALIDATION HTTPS-204"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0, p2}, Ljava/io/PrintStream;->println(Z)V
:done
return-void
.end method

.method public run()V
.locals 9
const/4 v0, 0
const/4 v1, 0
invoke-static {}, Ljava/lang/System;->nanoTime()J
move-result-wide v5
:try_start
iget-object v2, p0, Landroid/atl/VinixNetworkValidation;->manager:Landroid/net/ConnectivityManager;
invoke-virtual {v2}, Landroid/net/ConnectivityManager;->vinixRawNetworkState()I
move-result v2
iget v3, p0, Landroid/atl/VinixNetworkValidation;->link:I
if-ne v2, v3, :try_end
new-instance v2, Ljava/net/URL;
const-string v3, "https://www.google.com/generate_204"
invoke-direct {v2, v3}, Ljava/net/URL;-><init>(Ljava/lang/String;)V
invoke-virtual {v2}, Ljava/net/URL;->openConnection()Ljava/net/URLConnection;
move-result-object v2
check-cast v2, Ljavax/net/ssl/HttpsURLConnection;
move-object v0, v2
const/16 v2, 3000
invoke-virtual {v0, v2}, Ljava/net/URLConnection;->setConnectTimeout(I)V
invoke-virtual {v0, v2}, Ljava/net/URLConnection;->setReadTimeout(I)V
const/4 v2, 0
invoke-virtual {v0, v2}, Ljava/net/HttpURLConnection;->setInstanceFollowRedirects(Z)V
invoke-virtual {v0, v2}, Ljava/net/URLConnection;->setUseCaches(Z)V
invoke-virtual {v0}, Ljava/net/HttpURLConnection;->getResponseCode()I
move-result v2
const/16 v3, 204
if-ne v2, v3, :try_end
iget-object v2, p0, Landroid/atl/VinixNetworkValidation;->manager:Landroid/net/ConnectivityManager;
invoke-virtual {v2}, Landroid/net/ConnectivityManager;->vinixRawNetworkState()I
move-result v2
iget v3, p0, Landroid/atl/VinixNetworkValidation;->link:I
if-ne v2, v3, :try_end
invoke-static {}, Ljava/lang/System;->nanoTime()J
move-result-wide v7
sub-long/2addr v7, v5
const-wide v3, 10000000000L
cmp-long v2, v7, v3
if-gtz v2, :try_end
const/4 v1, 1
:try_end
goto :cleanup
.catch Ljava/lang/Exception; {:try_start .. :try_end} :error
:error
move-exception v2
:cleanup
if-eqz v0, :complete
:disconnect
invoke-virtual {v0}, Ljava/net/HttpURLConnection;->disconnect()V
:disconnected
goto :complete
.catch Ljava/lang/Exception; {:disconnect .. :disconnected} :disconnect_error
:disconnect_error
move-exception v2
const/4 v1, 0
:complete
iget v2, p0, Landroid/atl/VinixNetworkValidation;->link:I
iget v3, p0, Landroid/atl/VinixNetworkValidation;->epoch:I
invoke-static {v2, v3, v1}, Landroid/atl/VinixNetworkValidation;->complete(IIZ)V
return-void
.end method
'
}
