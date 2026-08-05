// Tiny C shim for kmedia: everything that touches variadic C APIs or SPA pod
// builder macros lives here so the Zig side stays pure extern-struct calls.

#include <pipewire/pipewire.h>
#include <spa/param/audio/format-utils.h>
#include <spa/pod/builder.h>
#include <spa/utils/result.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>

// Build an s16le audio format pod in the caller's buffer.
const struct spa_pod *kmedia_build_audio_format(uint8_t *buf, size_t size,
                                                uint32_t rate, uint32_t channels) {
    struct spa_pod_builder b = SPA_POD_BUILDER_INIT(buf, size);
    struct spa_audio_info_raw info = SPA_AUDIO_INFO_RAW_INIT(
        .format = SPA_AUDIO_FORMAT_S16_LE,
        .rate = rate,
        .channels = channels);
    info.position[0] = SPA_AUDIO_CHANNEL_FL;
    info.position[1] = SPA_AUDIO_CHANNEL_FR;
    return spa_format_audio_raw_build(&b, SPA_PARAM_EnumFormat, &info);
}

// Create the capture stream and connect it. Returns the connected stream,
// or NULL on failure (with an error string in err_buf).
struct pw_stream *kmedia_stream_connect(struct pw_loop *loop,
                                        const struct pw_stream_events *events,
                                        char *err_buf, size_t err_buf_len) {
    struct pw_properties *props = pw_properties_new(
        PW_KEY_MEDIA_TYPE, "Audio",
        PW_KEY_MEDIA_CATEGORY, "Capture",
        PW_KEY_MEDIA_ROLE, "Music",
        PW_KEY_STREAM_CAPTURE_SINK, "true",
        NULL);

    struct pw_stream *s = pw_stream_new_simple(loop, "kidulwm-kmedia", props,
                                               events, NULL);
    if (!s) {
        snprintf(err_buf, err_buf_len, "pw_stream_new_simple failed");
        return NULL;
    }

    uint8_t pod_buf[256];
    const struct spa_pod *params[1];
    params[0] = kmedia_build_audio_format(pod_buf, sizeof(pod_buf), 44100, 2);

    int rc = pw_stream_connect(s, PW_DIRECTION_INPUT, PW_ID_ANY,
        PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS, params, 1);
    if (rc < 0) {
        snprintf(err_buf, err_buf_len, "pw_stream_connect rc=%d (%s)", rc, spa_strerror(rc));
        pw_stream_destroy(s);
        return NULL;
    }
    return s;
}
