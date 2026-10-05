// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve the original userland image's smaller GLUT demo variant.
@[translated]
module legacytri

#include "gl_v.h"
fn C.glClearColor(f32, f32, f32, f32)
fn C.glClear(u32)
fn C.glBegin(u32)
fn C.glColor3f(f32, f32, f32)
fn C.glVertex2f(f32, f32)
fn C.glEnd()
fn C.glutSwapBuffers()
fn C.glutInit(&i32, &&char)
fn C.glutInitDisplayMode(u32)
fn C.glutInitWindowSize(i32, i32)
fn C.glutCreateWindow(&char) i32
fn C.glutDisplayFunc(fn ())
fn C.glutMainLoop()

fn draw() {
	C.glClearColor(0.08, 0.08, 0.10, 1.0)
	C.glClear(0x4000)
	C.glBegin(4)
	C.glColor3f(1.0, 0.2, 0.2)
	C.glVertex2f(-0.65, -0.45)
	C.glColor3f(0.2, 1.0, 0.2)
	C.glVertex2f(0.65, -0.45)
	C.glColor3f(0.2, 0.4, 1.0)
	C.glVertex2f(0.0, 0.65)
	C.glEnd()
	C.glutSwapBuffers()
}

@[export: 'main']
pub fn cli_main(argc i32, argv &&char) i32 {
	unsafe {
		C.glutInit(&argc, argv)
		C.glutInitDisplayMode(2)
		C.glutInitWindowSize(800, 600)
		C.glutCreateWindow(c'Vinix OpenGL Triangle')
		C.glutDisplayFunc(draw)
		C.glutMainLoop()
		return 0
	}
}
