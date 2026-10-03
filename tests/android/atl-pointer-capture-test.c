/* Run with GDK_BACKEND=x11 under a real X server (e.g. Xvfb), linked to
 * PointerCapture.c from the patched production source. */
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <gtk/gtk.h>
#include <gdk/x11/gdkx.h>
#include <X11/Xlib.h>
#include <X11/extensions/XTest.h>
#include "PointerCapture.h"

static GtkWidget *window, *target;
static int changes, events, clicks;
static int actions[128], states[128], action_buttons[128];
static double sum_x, sum_y, wheel_y;
static gboolean reenter;
static void changed(GtkWidget *root, gboolean captured, gpointer data);
static void event(GtkWidget *focused, int action, int buttons, int button,
                  double dx, double dy, double raw_x, double raw_y,
                  double sx, double sy, guint32 time, gpointer data)
{
	(void)raw_x; (void)raw_y; (void)sx; (void)time; (void)data;
	assert(focused == target || gtk_widget_is_ancestor(focused, target));
	assert(atl_pointer_capture_has(target));
	assert(events < 128);
	actions[events] = action; states[events] = buttons; action_buttons[events++] = button;
	if (action == 2) { sum_x += dx; sum_y += dy; }
	if (action == 8) wheel_y += sy;
	if (reenter && action == 0) {
		reenter = FALSE;
		atl_pointer_capture_release(target);
		assert(atl_pointer_capture_request(target, event, changed, NULL, NULL));
	}
}
static void changed(GtkWidget *root, gboolean captured, gpointer data)
{
	(void)data;
	assert(root == window);
	assert(atl_pointer_capture_has(root) == captured);
	changes++;
}
static void clicked(GtkButton *button, gpointer data) { (void)button; (void)data; clicks++; }
static void pump(void)
{
	for (int i = 0; i < 100; i++) {
		while (g_main_context_iteration(NULL, FALSE));
		g_usleep(1000);
	}
}
int main(void)
{
	gtk_init();
	window = gtk_window_new();
	gtk_window_set_default_size(GTK_WINDOW(window), 400, 300);
	GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
	GtkWidget *requester = gtk_button_new_with_label("requester");
	target = gtk_button_new_with_label("focused target");
	gtk_box_append(GTK_BOX(box), requester); gtk_box_append(GTK_BOX(box), target);
	gtk_window_set_child(GTK_WINDOW(window), box);
	g_signal_connect(target, "clicked", G_CALLBACK(clicked), NULL);
	GtkWidget *unattached = g_object_ref_sink(gtk_button_new());
	assert(!atl_pointer_capture_request(unattached, event, changed, NULL, NULL));
	g_object_unref(unattached);
	gtk_window_present(GTK_WINDOW(window)); pump();
	Display *display = XOpenDisplay(NULL); assert(display);
	Window xid = gdk_x11_surface_get_xid(gtk_native_get_surface(GTK_NATIVE(window)));
	XSetInputFocus(display, xid, RevertToParent, CurrentTime); XSync(display, False); pump();
	assert(gtk_window_is_active(GTK_WINDOW(window)));
	gtk_widget_grab_focus(target); pump();
	/* Request on A, but dispatch to B. Removing A must not end window capture. */
	XTestFakeMotionEvent(display, DefaultScreen(display), 80, 80, CurrentTime);
	XTestFakeButtonEvent(display, 1, True, CurrentTime); XSync(display, False); pump();
	assert(!atl_pointer_capture_request(requester, event, changed, NULL, NULL));
	assert(!atl_pointer_capture_has(target));
	XTestFakeButtonEvent(display, 1, False, CurrentTime); XSync(display, False); pump();
	assert(atl_pointer_capture_request(requester, event, changed, NULL, NULL));
	assert(atl_pointer_capture_has(target)); assert(changes == 1);
	gtk_box_remove(GTK_BOX(box), requester);
	assert(atl_pointer_capture_has(target));
	XTestFakeRelativeMotionEvent(display, 12, -7, CurrentTime);
	XTestFakeRelativeMotionEvent(display, 5, 3, CurrentTime);
	XSync(display, False); pump();
	assert(events >= 2 && states[0] == 0);
	assert(fabs(sum_x - 17) < 0.01 && fabs(sum_y + 4) < 0.01);
	/* Raw relative deltas remain truthful beyond the screen edge. */
	XTestFakeRelativeMotionEvent(display, 10000, 0, CurrentTime);
	XSync(display, False); pump(); assert(fabs(sum_x - 10017) < 0.01);
	XTestFakeButtonEvent(display, 1, True, CurrentTime);
	XTestFakeButtonEvent(display, 3, True, CurrentTime);
	XTestFakeButtonEvent(display, 1, False, CurrentTime);
	XTestFakeButtonEvent(display, 3, False, CurrentTime);
	XTestFakeButtonEvent(display, 4, True, CurrentTime);
	XTestFakeButtonEvent(display, 4, False, CurrentTime);
	XSync(display, False); pump();
	assert(wheel_y == 1 && clicks == 0);
	int n = events;
	assert(actions[n-10] == 0 && states[n-10] == 1);
	assert(actions[n-9] == 11 && action_buttons[n-9] == 1 && states[n-9] == 1);
	assert(actions[n-8] == 2 && states[n-8] == 3);
	assert(actions[n-7] == 11 && action_buttons[n-7] == 2 && states[n-7] == 3);
	assert(actions[n-6] == 12 && action_buttons[n-6] == 1 && states[n-6] == 2);
	assert(actions[n-5] == 2 && states[n-5] == 2);
	assert(actions[n-4] == 12 && action_buttons[n-4] == 2 && states[n-4] == 0);
	assert(actions[n-3] == 1 && states[n-3] == 0);
	assert(actions[n-2] == 2 && actions[n-1] == 8);
	atl_pointer_capture_release(target); assert(!atl_pointer_capture_has(window));
	Window root, child; int rx, ry, wx, wy; unsigned int mask;
	XQueryPointer(display, DefaultRootWindow(display), &root, &child, &rx, &ry, &wx, &wy, &mask);
	assert(rx == 80 && ry == 80);
	/* Releasing/reacquiring during DOWN must not leak the old BUTTON_PRESS. */
	assert(atl_pointer_capture_request(target, event, changed, NULL, NULL));
	n = events; reenter = TRUE;
	XTestFakeButtonEvent(display, 1, True, CurrentTime); XSync(display, False); pump();
	assert(events == n + 1 && actions[n] == 0 && atl_pointer_capture_has(target));
	XTestFakeButtonEvent(display, 1, False, CurrentTime); XSync(display, False); pump();
	assert(actions[events-2] == 12 && actions[events-1] == 1);
	/* Losing window focus releases and restores normal GTK input. */
	XSetInputFocus(display, DefaultRootWindow(display), RevertToParent, CurrentTime);
	XSync(display, False); pump(); assert(!atl_pointer_capture_has(target));
	XSetInputFocus(display, xid, RevertToParent, CurrentTime); XSync(display, False); pump();
	assert(gtk_window_is_active(GTK_WINDOW(window)));
	/* A fresh real click must work, with no delayed old gesture/click. */
	graphene_point_t point;
	assert(gtk_widget_compute_point(target, window, &GRAPHENE_POINT_INIT(10, 10), &point));
	Window child_window; int origin_x, origin_y;
	XTranslateCoordinates(display, xid, DefaultRootWindow(display), 0, 0, &origin_x, &origin_y, &child_window);
	XTestFakeMotionEvent(display, DefaultScreen(display), origin_x + point.x, origin_y + point.y, CurrentTime);
	XTestFakeButtonEvent(display, 1, True, CurrentTime);
	XTestFakeButtonEvent(display, 1, False, CurrentTime); XSync(display, False); pump();
	assert(clicks == 1);
	gtk_window_destroy(GTK_WINDOW(window)); pump(); XCloseDisplay(display);
	printf("ATL-POINTER-CAPTURE-PASS events=%d changes=%d relative=10017,-4\n", events, changes);
	return 0;
}
