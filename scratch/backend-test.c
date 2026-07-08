#include <wlr/backend.h>
#include <wlr/render/allocator.h>
#include <wlr/render/renderer.h>
#include <wlr/types/wlr_compositor.h>
#include <wlr/types/wlr_output_layout.h>
#include <wlr/types/wlr_scene.h>
#include <wlr/types/wlr_xdg_shell.h>
#include <wlr/types/wlr_seat.h>
#include <wayland-server-core.h>
#include <stdio.h>
#include <stdlib.h>

int main(void) {
    struct wl_display *dpy = wl_display_create();
    if (!dpy) { fprintf(stderr, "display create failed\n"); return 1; }
    struct wl_event_loop *loop = wl_display_get_event_loop(dpy);
    struct wlr_backend *backend = wlr_backend_autocreate(loop, NULL);
    if (!backend) { fprintf(stderr, "backend autocreate failed\n"); return 1; }
    struct wlr_renderer *r = wlr_renderer_autocreate(backend);
    if (!r) { fprintf(stderr, "renderer failed\n"); return 1; }
    wlr_renderer_init_wl_display(r, dpy);
    struct wlr_allocator *a = wlr_allocator_autocreate(backend, r);
    struct wlr_compositor *comp = wlr_compositor_create(dpy, 6, r);
    struct wlr_scene *scene = wlr_scene_create();
    struct wlr_output_layout *ol = wlr_output_layout_create(dpy);
    wlr_scene_attach_output_layout(scene, ol);
    struct wlr_xdg_shell *xdg = wlr_xdg_shell_create(dpy, 6);
    struct wlr_seat *seat = wlr_seat_create(dpy, "seat0");
    (void)a; (void)comp; (void)scene; (void)ol; (void)xdg; (void)seat;
    char name[11];
    if (wl_display_add_socket_auto(dpy, name) == NULL) { fprintf(stderr, "add socket failed\n"); return 1; }
    printf("socket %s\n", name);
    if (!wlr_backend_start(backend)) { fprintf(stderr, "backend start failed\n"); return 1; }
    printf("backend started\n");
    wl_display_run(dpy);
    wl_display_destroy_clients(dpy);
    wl_display_destroy(dpy);
    return 0;
}
