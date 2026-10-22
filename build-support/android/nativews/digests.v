// SPDX-License-Identifier: GPL-2.0-or-later
// Streaming JCA SHA-2 over the private runtime's OpenSSL EVP implementation.
// Java stores registry IDs, never native pointers. The lock also protects an
// in-flight operation from a concurrent finalizer or a forged/stale handle.
@[translated]
module atlframework

type WsDigestNew = fn () voidptr
type WsDigestFree = fn (voidptr)
type WsDigestInit = fn (voidptr, voidptr, voidptr) i32
type WsDigestUpdate = fn (voidptr, voidptr, usize) i32
type WsDigestFinal = fn (voidptr, voidptr, &u32) i32
type WsDigestCopy = fn (voidptr, voidptr) i32

struct WsDigest {
mut:
	id    i64
	ctx   voidptr
	md    voidptr
	size  i32
	valid bool
	next  &WsDigest
}

__global ws_digest_provider voidptr
__global ws_digest_mutex C.pthread_mutex_t
__global ws_digest_head &WsDigest
__global ws_digest_next i64
__global ws_digest_new WsDigestNew
__global ws_digest_free WsDigestFree
__global ws_digest_init WsDigestInit
__global ws_digest_update WsDigestUpdate
__global ws_digest_final WsDigestFinal
__global ws_digest_copy WsDigestCopy
__global ws_digest_sha256 voidptr
__global ws_digest_sha384 voidptr
__global ws_digest_sha512 voidptr

fn ws_digest_failure(e voidptr) {
	throw(e, c'java/security/ProviderException', c'Native SHA-2 operation failed')
}

// Called with the registry locked. Invalid IDs cannot reach an EVP function.
fn ws_digest_find(e voidptr, id i64) &WsDigest {
	unsafe {
		mut item := ws_digest_head
		for item != nil {
			if id > 0 && item.id == id { return item }
			item = item.next
		}
		throw(e, c'java/lang/IllegalStateException', c'Invalid native digest handle')
		return nil
	}
}

fn ws_digest_allocate(e voidptr, md voidptr, size i32, source voidptr) i64 {
	unsafe {
		if ws_digest_next == i64(0x7fffffffffffffff) { ws_digest_failure(e); return 0 }
		mut item := &WsDigest(C.calloc(1, sizeof(WsDigest)))
		if item == nil { throw(e, c'java/lang/OutOfMemoryError', c'Native digest'); return 0 }
		item.ctx = ws_digest_new()
		if item.ctx == nil { C.free(item); throw(e, c'java/lang/OutOfMemoryError', c'EVP digest'); return 0 }
		status := if source == nil { ws_digest_init(item.ctx, md, nil) } else { ws_digest_copy(item.ctx, source) }
		if status != 1 { ws_digest_free(item.ctx); C.free(item); ws_digest_failure(e); return 0 }
		ws_digest_next++
		item.id = ws_digest_next
		item.md = md
		item.size = size
		item.valid = true
		item.next = ws_digest_head
		ws_digest_head = item
		return item.id
	}
}

fn ws_digest_create(e voidptr, class voidptr, algorithm i32) i64 {
	unsafe {
		C.pthread_mutex_lock(&ws_digest_mutex)
		defer { C.pthread_mutex_unlock(&ws_digest_mutex) }
		md := match algorithm { 256 { ws_digest_sha256 } 384 { ws_digest_sha384 } 512 { ws_digest_sha512 } else { nil } }
		if md == nil { throw(e, c'java/lang/IllegalArgumentException', c'Unknown native digest'); return 0 }
		return ws_digest_allocate(e, md, algorithm / 8, nil)
	}
}

fn ws_digest_bytes(e voidptr, class voidptr, id i64, bytes voidptr, offset i32, length i32) {
	unsafe {
		if bytes == nil { throw(e, c'java/lang/NullPointerException', c'Digest input'); return }
		count := ArrayLength(slot(e, 171))(e, bytes)
		if offset < 0 || length < 0 || i64(offset) + i64(length) > count {
			throw(e, c'java/lang/ArrayIndexOutOfBoundsException', c'Digest input range'); return
		}
		C.pthread_mutex_lock(&ws_digest_mutex)
		defer { C.pthread_mutex_unlock(&ws_digest_mutex) }
		item := ws_digest_find(e, id)
		if item == nil { return }
		if !item.valid { ws_digest_failure(e); return }
		// Bound memory use even for an APK-sized update; JNI copies this region.
		mut buffer := [65536]u8{}
		mut used := i32(0)
		for used < length {
			n := if length - used > 65536 { i32(65536) } else { length - used }
			WsByteRegion(slot(e, 200))(e, bytes, offset + used, n, &buffer[0])
			if pending(e) { item.valid = false; return }
			if ws_digest_update(item.ctx, &buffer[0], usize(n)) != 1 {
				item.valid = false; ws_digest_failure(e); return
			}
			used += n
		}
	}
}

fn ws_digest_finish(e voidptr, class voidptr, id i64) voidptr {
	unsafe {
		C.pthread_mutex_lock(&ws_digest_mutex)
		defer { C.pthread_mutex_unlock(&ws_digest_mutex) }
		item := ws_digest_find(e, id)
		if item == nil { return nil }
		if !item.valid { ws_digest_failure(e); return nil }
		result := WsNewByteArray(slot(e, 176))(e, item.size)
		if result == nil { return nil }
		mut bytes := [64]u8{}
		mut size := u32(0)
		item.valid = false
		if ws_digest_final(item.ctx, &bytes[0], &size) != 1 || size != u32(item.size)
			|| ws_digest_init(item.ctx, item.md, nil) != 1 { ws_digest_failure(e); return nil }
		item.valid = true
		WsByteRegion(slot(e, 208))(e, result, 0, item.size, &bytes[0])
		return result
	}
}

fn ws_digest_reset(e voidptr, class voidptr, id i64) {
	unsafe {
		C.pthread_mutex_lock(&ws_digest_mutex)
		defer { C.pthread_mutex_unlock(&ws_digest_mutex) }
		item := ws_digest_find(e, id)
		if item == nil { return }
		item.valid = ws_digest_init(item.ctx, item.md, nil) == 1
		if !item.valid { ws_digest_failure(e) }
	}
}

fn ws_digest_clone(e voidptr, class voidptr, id i64) i64 {
	unsafe {
		C.pthread_mutex_lock(&ws_digest_mutex)
		defer { C.pthread_mutex_unlock(&ws_digest_mutex) }
		item := ws_digest_find(e, id)
		if item == nil { return 0 }
		if !item.valid { ws_digest_failure(e); return 0 }
		return ws_digest_allocate(e, item.md, item.size, item.ctx)
	}
}

fn ws_digest_destroy(e voidptr, class voidptr, id i64) {
	unsafe {
		C.pthread_mutex_lock(&ws_digest_mutex)
		defer { C.pthread_mutex_unlock(&ws_digest_mutex) }
		mut previous := &WsDigest(nil)
		mut item := ws_digest_head
		for item != nil {
			if item.id == id {
				if previous == nil { ws_digest_head = item.next } else { previous.next = item.next }
				ws_digest_free(item.ctx)
				C.free(item)
				return
			}
			previous = item
			item = item.next
		}
	}
}

fn ws_install_digests(e voidptr, root &char) bool {
	unsafe {
		path := &char(C.alloca(8192))
		C.snprintf(path, 8192, c'%s/usr/lib/libcrypto.so.3', root)
		ws_digest_provider = C.dlopen(path, 2)
		if ws_digest_provider == nil { C.puts(C.dlerror()); return false }
		for symbol in [&char(c'EVP_MD_CTX_new'), &char(c'EVP_MD_CTX_free'), &char(c'EVP_DigestInit_ex'),
			&char(c'EVP_DigestUpdate'), &char(c'EVP_DigestFinal_ex'), &char(c'EVP_MD_CTX_copy_ex'),
			&char(c'EVP_sha256'), &char(c'EVP_sha384'), &char(c'EVP_sha512')]! {
			if C.dlsym(ws_digest_provider, symbol) == nil { C.puts(C.dlerror()); return false }
		}
		ws_digest_new = WsDigestNew(C.dlsym(ws_digest_provider, c'EVP_MD_CTX_new'))
		ws_digest_free = WsDigestFree(C.dlsym(ws_digest_provider, c'EVP_MD_CTX_free'))
		ws_digest_init = WsDigestInit(C.dlsym(ws_digest_provider, c'EVP_DigestInit_ex'))
		ws_digest_update = WsDigestUpdate(C.dlsym(ws_digest_provider, c'EVP_DigestUpdate'))
		ws_digest_final = WsDigestFinal(C.dlsym(ws_digest_provider, c'EVP_DigestFinal_ex'))
		ws_digest_copy = WsDigestCopy(C.dlsym(ws_digest_provider, c'EVP_MD_CTX_copy_ex'))
		ws_digest_sha256 = WsDigestNew(C.dlsym(ws_digest_provider, c'EVP_sha256'))()
		ws_digest_sha384 = WsDigestNew(C.dlsym(ws_digest_provider, c'EVP_sha384'))()
		ws_digest_sha512 = WsDigestNew(C.dlsym(ws_digest_provider, c'EVP_sha512'))()
		if ws_digest_sha256 == nil || ws_digest_sha384 == nil || ws_digest_sha512 == nil
			|| C.pthread_mutex_init(&ws_digest_mutex, nil) != 0 { return false }
		methods := [
			NativeMethod{c'create', c'(I)J', voidptr(ws_digest_create)},
			NativeMethod{c'update', c'(J[BII)V', voidptr(ws_digest_bytes)},
			NativeMethod{c'finish', c'(J)[B', voidptr(ws_digest_finish)},
			NativeMethod{c'reset', c'(J)V', voidptr(ws_digest_reset)},
			NativeMethod{c'copy', c'(J)J', voidptr(ws_digest_clone)},
			NativeMethod{c'destroy', c'(J)V', voidptr(ws_digest_destroy)},
		]!
		if register(e, c'android/atl/VinixNativeDigest', &methods[0], 6) != 0 { return false }
		provider := new_object(e, c'android/atl/VinixDigestProvider', c'()V', nil)
		if pending(e) || provider == nil { return false }
		args := [Value{l: provider}, Value{i: 1}]!
		security := cls(e, c'java/security/Security')
		if security == nil { return false }
		insert := Member(slot(e, 113))(e, security, c'insertProviderAt', c'(Ljava/security/Provider;I)I')
		if insert == nil { return false }
		position := IntCall(slot(e, 131))(e, security, insert, &args[0])
		if pending(e) || position != 1 { return false }
		C.puts(c'ANDROID-WS-DIGEST provider=VinixNative SHA-256 SHA-384 SHA-512')
		return true
	}
}
