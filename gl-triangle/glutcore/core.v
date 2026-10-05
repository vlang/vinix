// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module gluttri

#include "gl_v.h"

fn C.glClearColor(f32, f32, f32, f32)
fn C.glClear(u32)
fn C.glBegin(u32)
fn C.glColor3f(f32, f32, f32)
fn C.glVertex2f(f32, f32)
fn C.glEnd()
fn C.glFinish()
fn C.glViewport(i32, i32, i32, i32)
fn C.glGetString(u32) &u8
fn C.glutSwapBuffers()
fn C.glutInit(&i32, &&char)
fn C.glutInitDisplayMode(u32)
fn C.glutInitWindowSize(i32, i32)
fn C.glutCreateWindow(&char) i32
fn C.glutDisplayFunc(fn ())
fn C.glutReshapeFunc(fn (i32, i32))
fn C.glutMainLoop()
fn C.puts(&char) i32
fn C.printf(&char, ...i32) i32
fn C.fflush(voidptr) i32
fn C.vkg_stdout() voidptr

__global reported_frame i32

fn display() {
	C.glClearColor(0.035, 0.045, 0.075, 1.0)
	C.glClear(0x4000)
	C.glBegin(4)
	C.glColor3f(1.0, 0.18, 0.16)
	C.glVertex2f(-0.72, -0.58)
	C.glColor3f(0.16, 1.0, 0.30)
	C.glVertex2f(0.72, -0.58)
	C.glColor3f(0.18, 0.42, 1.0)
	C.glVertex2f(0.0, 0.72)
	C.glEnd()
	C.glutSwapBuffers()
	C.glFinish()
	unsafe {
		if reported_frame == 0 {
			C.puts(c'gl-triangle: rendered frame successfully')
			C.fflush(C.vkg_stdout())
			reported_frame = 1
		}
	}
}

fn reshape(width i32, height i32) { C.glViewport(0, 0, width, height) }

@[export: 'main']
pub fn cli_main(argc i32, argv &&char) i32 {
	unsafe {
		C.glutInit(&argc, argv)
		C.glutInitDisplayMode(2)
		C.glutInitWindowSize(800, 600)
		C.glutCreateWindow(c'Vinix OpenGL Triangle')
		vendor := &u8(C.glGetString(0x1f00))
		renderer := &u8(C.glGetString(0x1f01))
		version := &u8(C.glGetString(0x1f02))
		C.printf(c'gl-triangle: GL_VENDOR=%s\n', if usize(vendor) != 0 {
			&char(vendor)
		} else {
			c'unknown'
		})
		C.printf(c'gl-triangle: GL_RENDERER=%s\n', if usize(renderer) != 0 {
			&char(renderer)
		} else {
			c'unknown'
		})
		C.printf(c'gl-triangle: GL_VERSION=%s\n', if usize(version) != 0 {
			&char(version)
		} else {
			c'unknown'
		})
		C.fflush(C.vkg_stdout())
		C.glutDisplayFunc(display)
		C.glutReshapeFunc(reshape)
		C.glutMainLoop()
		return 0
	}
}
