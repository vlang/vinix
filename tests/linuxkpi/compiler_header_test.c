/* SPDX-License-Identifier: GPL-2.0-only */
/* Linux Kbuild preincludes compiler_types.h before this unchanged DRM header.
 * Keep it first: it has no includes and immediately uses __must_check. */
#include <drm/drm_atomic_uapi.h>

_Static_assert(__same_type(&drm_atomic_set_mode_for_crtc,
    (int (*)(struct drm_crtc_state *, const struct drm_display_mode *))0),
    "original checked CRTC mode declaration");
_Static_assert(__same_type(&drm_atomic_set_mode_prop_for_crtc,
    (int (*)(struct drm_crtc_state *, struct drm_property_blob *))0),
    "original checked CRTC mode-property declaration");
_Static_assert(__same_type(&drm_atomic_set_crtc_for_plane,
    (int (*)(struct drm_plane_state *, struct drm_crtc *))0),
    "original checked plane CRTC declaration");
_Static_assert(__same_type(&drm_atomic_set_crtc_for_connector,
    (int (*)(struct drm_connector_state *, struct drm_crtc *))0),
    "original checked connector CRTC declaration");
_Static_assert(__same_type(&drm_atomic_set_fb_for_plane,
    (void (*)(struct drm_plane_state *, struct drm_framebuffer *))0),
    "original framebuffer declaration");

int main(void)
{
    return 0;
}
