// SPDX-License-Identifier: GPL-2.0-or-later
// NDK SurfaceTexture handles retain and delegate to the Java producer. A
// texture is never invented when the framework has no SurfaceTexture class.
@[translated]
module atlframework

type WsTextureGetVM = fn (voidptr, &voidptr) i32
type WsTextureGetEnv = fn (voidptr, &voidptr, i32) i32
type WsTextureAttach = fn (voidptr, &voidptr, voidptr) i32
type WsTextureDetach = fn (voidptr) i32
type WsTextureLong = fn (voidptr, voidptr, voidptr, &Value) i64
type WsTextureNewFloats = fn (voidptr, i32) voidptr
type WsTextureReadFloats = fn (voidptr, voidptr, i32, i32, &f32)
type WsTextureClear = fn (voidptr)
type WsTextureIsInstance = fn (voidptr, voidptr, voidptr) u8

struct WsSurfaceTexture {
	vm voidptr
	object voidptr
	attach voidptr
	detach voidptr
	update voidptr
	matrix voidptr
	timestamp voidptr
}

fn ws_texture_env(texture &WsSurfaceTexture, attached &bool) voidptr {
	unsafe {
		*attached = false
		if texture == nil { return nil }
		mut e := voidptr(nil)
		status := WsTextureGetEnv(slot(texture.vm, 6))(texture.vm, &e, 0x10006)
		if status == -2 {
			if WsTextureAttach(slot(texture.vm, 4))(texture.vm, &e, nil) != 0 { return nil }
			*attached = true
		} else if status != 0 { return nil }
		return e
	}
}

fn ws_texture_done(texture &WsSurfaceTexture, attached bool) {
	if attached { unsafe { WsTextureDetach(slot(texture.vm, 5))(texture.vm) } }
}

@[export: 'ASurfaceTexture_fromSurfaceTexture']
pub fn ws_texture_from_java(e voidptr, object voidptr) &WsSurfaceTexture {
	unsafe {
		if e == nil || object == nil || pending(e) { return nil }
		class := cls(e, c'android/graphics/SurfaceTexture')
		if class == nil {
			if pending(e) { WsTextureClear(slot(e, 17))(e) }
			return nil
		}
		defer { Drop(slot(e, 23))(e, class) }
		if WsTextureIsInstance(slot(e, 32))(e, object, class) == 0 { return nil }
		mut vm := voidptr(nil)
		if WsTextureGetVM(slot(e, 219))(e, &vm) != 0 { return nil }
		get := Member(slot(e, 33))
		attach := get(e, class, c'attachToGLContext', c'(I)V')
		detach := if pending(e) { nil } else { get(e, class, c'detachFromGLContext', c'()V') }
		update := if pending(e) { nil } else { get(e, class, c'updateTexImage', c'()V') }
		matrix := if pending(e) { nil } else { get(e, class, c'getTransformMatrix', c'([F)V') }
		timestamp := if pending(e) { nil } else { get(e, class, c'getTimestamp', c'()J') }
		if pending(e) { WsTextureClear(slot(e, 17))(e); return nil }
		retained := WsRef(slot(e, 21))(e, object)
		if retained == nil { return nil }
		texture := &WsSurfaceTexture(C.malloc(sizeof(WsSurfaceTexture)))
		if texture == nil { Drop(slot(e, 22))(e, retained); return nil }
		*texture = WsSurfaceTexture{vm, retained, attach, detach, update, matrix, timestamp}
		return texture
	}
}

@[export: 'ASurfaceTexture_release']
pub fn ws_texture_release(texture &WsSurfaceTexture) {
	unsafe {
		if texture == nil { return }
		mut attached := false
		e := ws_texture_env(texture, &attached)
		if e == nil { return }
		Drop(slot(e, 22))(e, texture.object)
		ws_texture_done(texture, attached)
		C.free(texture)
	}
}

fn ws_texture_call(texture &WsSurfaceTexture, method voidptr, args &Value) i32 {
	unsafe {
		mut attached := false
		e := ws_texture_env(texture, &attached)
		if e == nil { return -22 }
		defer { ws_texture_done(texture, attached) }
		if pending(e) { return -22 }
		VoidCall(slot(e, 63))(e, texture.object, method, args)
		if pending(e) { WsTextureClear(slot(e, 17))(e); return -22 }
		return 0
	}
}

@[export: 'ASurfaceTexture_attachToGLContext']
pub fn ws_texture_attach(texture &WsSurfaceTexture, name u32) i32 {
	if texture == unsafe { nil } { return -22 }
	mut arg := Value{ i: i32(name) }
	return ws_texture_call(texture, texture.attach, &arg)
}

@[export: 'ASurfaceTexture_detachFromGLContext']
pub fn ws_texture_detach(texture &WsSurfaceTexture) i32 {
	if texture == unsafe { nil } { return -22 }
	return ws_texture_call(texture, texture.detach, unsafe { nil })
}

@[export: 'ASurfaceTexture_updateTexImage']
pub fn ws_texture_update(texture &WsSurfaceTexture) i32 {
	if texture == unsafe { nil } { return -22 }
	return ws_texture_call(texture, texture.update, unsafe { nil })
}

@[export: 'ASurfaceTexture_getTimestamp']
pub fn ws_texture_timestamp(texture &WsSurfaceTexture) i64 {
	unsafe {
		mut attached := false
		e := ws_texture_env(texture, &attached)
		if e == nil { return 0 }
		defer { ws_texture_done(texture, attached) }
		if pending(e) { return 0 }
		result := WsTextureLong(slot(e, 54))(e, texture.object, texture.timestamp, nil)
		if pending(e) { WsTextureClear(slot(e, 17))(e); return 0 }
		return result
	}
}

@[export: 'ASurfaceTexture_getTransformMatrix']
pub fn ws_texture_matrix(texture &WsSurfaceTexture, matrix &f32) {
	unsafe {
		if matrix == nil { return }
		mut attached := false
		e := ws_texture_env(texture, &attached)
		if e == nil { return }
		defer { ws_texture_done(texture, attached) }
		if pending(e) { return }
		array := WsTextureNewFloats(slot(e, 181))(e, 16)
		if array == nil { if pending(e) { WsTextureClear(slot(e, 17))(e) }; return }
		defer { Drop(slot(e, 23))(e, array) }
		mut arg := Value{ l: array }
		VoidCall(slot(e, 63))(e, texture.object, texture.matrix, &arg)
		if !pending(e) { WsTextureReadFloats(slot(e, 205))(e, array, 0, 16, matrix) }
		if pending(e) { WsTextureClear(slot(e, 17))(e) }
	}
}
