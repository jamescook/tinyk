#include "teek_sdl2.h"

/* ---------------------------------------------------------
 * SDL2 AudioStream — push-based real-time PCM audio output
 *
 * Wraps SDL_OpenAudioDevice + SDL_QueueAudio for streaming
 * raw PCM data (emulators, synthesizers, procedural audio).
 * Independent of SDL2_mixer — uses a separate audio device.
 * --------------------------------------------------------- */

static VALUE cAudioStream;

static void
ensure_sdl_audio_init(void)
{
    if (!(SDL_WasInit(SDL_INIT_AUDIO) & SDL_INIT_AUDIO)) {
        if (SDL_InitSubSystem(SDL_INIT_AUDIO) < 0) {
            rb_raise(rb_eRuntimeError, "SDL_InitSubSystem(AUDIO) failed: %s",
                     SDL_GetError());
        }
    }
}

/* ---------------------------------------------------------
 * AudioStream (wraps SDL_AudioDeviceID)
 * --------------------------------------------------------- */

struct sdl2_audio_stream {
    SDL_AudioDeviceID device_id;
    int frequency;
    int channels;
    SDL_AudioFormat format;
    int bytes_per_sample;
    int destroyed;
};

static void
audio_stream_free(void *ptr)
{
    struct sdl2_audio_stream *a = ptr;
    if (!a->destroyed && a->device_id > 0) {
        SDL_CloseAudioDevice(a->device_id);
        a->device_id = 0;
        a->destroyed = 1;
    }
    xfree(a);
}

static size_t
audio_stream_memsize(const void *ptr)
{
    return sizeof(struct sdl2_audio_stream);
}

static const rb_data_type_t audio_stream_type = {
    .wrap_struct_name = "TeekSDL2::AudioStream",
    .function = {
        .dmark = NULL,
        .dfree = audio_stream_free,
        .dsize = audio_stream_memsize,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE
audio_stream_alloc(VALUE klass)
{
    struct sdl2_audio_stream *a;
    VALUE obj = TypedData_Make_Struct(klass, struct sdl2_audio_stream,
                                     &audio_stream_type, a);
    a->device_id = 0;
    a->frequency = 0;
    a->channels = 0;
    a->format = 0;
    a->bytes_per_sample = 0;
    a->destroyed = 0;
    return obj;
}

static struct sdl2_audio_stream *
get_audio_stream(VALUE self)
{
    struct sdl2_audio_stream *a;
    TypedData_Get_Struct(self, struct sdl2_audio_stream, &audio_stream_type, a);
    if (a->destroyed || a->device_id == 0) {
        rb_raise(rb_eRuntimeError, "audio stream has been destroyed");
    }
    return a;
}

/* Helper: map Ruby symbol to SDL_AudioFormat + bytes_per_sample */
static int
resolve_format(VALUE sym, SDL_AudioFormat *out_fmt, int *out_bps)
{
    ID id;
    if (NIL_P(sym) || sym == Qundef) {
        *out_fmt = AUDIO_S16SYS;
        *out_bps = 2;
        return 1;
    }
    if (!SYMBOL_P(sym)) return 0;

    id = SYM2ID(sym);
    if (id == rb_intern("s16")) {
        *out_fmt = AUDIO_S16SYS;
        *out_bps = 2;
    } else if (id == rb_intern("f32")) {
        *out_fmt = AUDIO_F32SYS;
        *out_bps = 4;
    } else if (id == rb_intern("u8")) {
        *out_fmt = AUDIO_U8;
        *out_bps = 1;
    } else {
        return 0;
    }
    return 1;
}

/*
 * AudioStream.new(frequency: 44100, format: :s16, channels: 2)
 *
 * Opens a push-based audio output device. Starts paused —
 * call #resume after queuing initial data.
 */
static VALUE
audio_stream_initialize(int argc, VALUE *argv, VALUE self)
{
    struct sdl2_audio_stream *a;
    TypedData_Get_Struct(self, struct sdl2_audio_stream, &audio_stream_type, a);

    ensure_sdl_audio_init();

    /* Defaults */
    int frequency = 44100;
    int channels = 2;
    SDL_AudioFormat format = AUDIO_S16SYS;
    int bps = 2;

    /* Parse keyword arguments */
    VALUE kwargs;
    rb_scan_args(argc, argv, ":", &kwargs);

    if (!NIL_P(kwargs)) {
        ID keys[3];
        VALUE vals[3];
        keys[0] = rb_intern("frequency");
        keys[1] = rb_intern("format");
        keys[2] = rb_intern("channels");

        rb_get_kwargs(kwargs, keys, 0, 3, vals);

        if (vals[0] != Qundef) {
            frequency = NUM2INT(vals[0]);
            if (frequency <= 0) {
                rb_raise(rb_eArgError, "frequency must be positive");
            }
        }

        if (vals[1] != Qundef) {
            if (!resolve_format(vals[1], &format, &bps)) {
                rb_raise(rb_eArgError,
                         "format must be :s16, :f32, or :u8");
            }
        }

        if (vals[2] != Qundef) {
            channels = NUM2INT(vals[2]);
            if (channels < 1 || channels > 2) {
                rb_raise(rb_eArgError, "channels must be 1 or 2");
            }
        }
    }

    /* Open audio device */
    SDL_AudioSpec desired;
    SDL_memset(&desired, 0, sizeof(desired));
    desired.freq = frequency;
    desired.format = format;
    desired.channels = (Uint8)channels;
    desired.samples = 2048;

    SDL_AudioDeviceID dev = SDL_OpenAudioDevice(
        NULL, 0, &desired, NULL, 0);
    if (dev == 0) {
        rb_raise(rb_eRuntimeError, "SDL_OpenAudioDevice failed: %s",
                 SDL_GetError());
    }

    a->device_id = dev;
    a->frequency = frequency;
    a->channels = channels;
    a->format = format;
    a->bytes_per_sample = bps;

    return self;
}

/*
 * stream.queue(data) -> nil
 *
 * Push raw PCM data to the audio device.
 * +data+ must be a binary String matching the stream's format and channels.
 */
static VALUE
audio_stream_queue(VALUE self, VALUE data)
{
    struct sdl2_audio_stream *a = get_audio_stream(self);

    StringValue(data);
    if (RSTRING_LEN(data) == 0) return Qnil;

    if (SDL_QueueAudio(a->device_id, RSTRING_PTR(data),
                       (Uint32)RSTRING_LEN(data)) < 0) {
        rb_raise(rb_eRuntimeError, "SDL_QueueAudio failed: %s",
                 SDL_GetError());
    }
    return Qnil;
}

/*
 * stream.queued_bytes -> Integer
 *
 * Bytes of audio data currently queued for playback.
 */
static VALUE
audio_stream_queued_bytes(VALUE self)
{
    struct sdl2_audio_stream *a = get_audio_stream(self);
    Uint32 bytes = SDL_GetQueuedAudioSize(a->device_id);
    return UINT2NUM(bytes);
}

/*
 * stream.queued_samples -> Integer
 *
 * Number of audio samples (frames) currently queued.
 * One sample = one value per channel.
 */
static VALUE
audio_stream_queued_samples(VALUE self)
{
    struct sdl2_audio_stream *a = get_audio_stream(self);
    Uint32 bytes = SDL_GetQueuedAudioSize(a->device_id);
    int frame_size = a->bytes_per_sample * a->channels;
    return UINT2NUM(bytes / (Uint32)frame_size);
}

/*
 * stream.resume -> nil
 *
 * Start or unpause audio playback.
 */
static VALUE
audio_stream_resume(VALUE self)
{
    struct sdl2_audio_stream *a = get_audio_stream(self);
    SDL_PauseAudioDevice(a->device_id, 0);
    return Qnil;
}

/*
 * stream.pause -> nil
 *
 * Pause audio playback. Queued data is preserved.
 */
static VALUE
audio_stream_pause(VALUE self)
{
    struct sdl2_audio_stream *a = get_audio_stream(self);
    SDL_PauseAudioDevice(a->device_id, 1);
    return Qnil;
}

/*
 * stream.playing? -> Boolean
 *
 * Whether the audio device is currently playing (not paused).
 */
static VALUE
audio_stream_playing_p(VALUE self)
{
    struct sdl2_audio_stream *a = get_audio_stream(self);
    SDL_AudioStatus status = SDL_GetAudioDeviceStatus(a->device_id);
    return status == SDL_AUDIO_PLAYING ? Qtrue : Qfalse;
}

/*
 * stream.clear -> nil
 *
 * Flush all queued audio data.
 */
static VALUE
audio_stream_clear(VALUE self)
{
    struct sdl2_audio_stream *a = get_audio_stream(self);
    SDL_ClearQueuedAudio(a->device_id);
    return Qnil;
}

/*
 * stream.frequency -> Integer
 *
 * Sample rate in Hz.
 */
static VALUE
audio_stream_frequency(VALUE self)
{
    struct sdl2_audio_stream *a = get_audio_stream(self);
    return INT2NUM(a->frequency);
}

/*
 * stream.channels -> Integer
 *
 * Number of audio channels (1 = mono, 2 = stereo).
 */
static VALUE
audio_stream_channels(VALUE self)
{
    struct sdl2_audio_stream *a = get_audio_stream(self);
    return INT2NUM(a->channels);
}

/*
 * stream.format -> Symbol
 *
 * Audio sample format (:s16, :f32, or :u8).
 */
static VALUE
audio_stream_format(VALUE self)
{
    struct sdl2_audio_stream *a = get_audio_stream(self);
    if (a->format == AUDIO_S16SYS) return ID2SYM(rb_intern("s16"));
    if (a->format == AUDIO_F32SYS) return ID2SYM(rb_intern("f32"));
    if (a->format == AUDIO_U8)     return ID2SYM(rb_intern("u8"));
    return ID2SYM(rb_intern("unknown"));
}

/*
 * stream.destroy -> nil
 *
 * Close the audio device. Further method calls will raise.
 */
static VALUE
audio_stream_destroy(VALUE self)
{
    struct sdl2_audio_stream *a;
    TypedData_Get_Struct(self, struct sdl2_audio_stream, &audio_stream_type, a);
    if (!a->destroyed && a->device_id > 0) {
        SDL_CloseAudioDevice(a->device_id);
        a->device_id = 0;
        a->destroyed = 1;
    }
    return Qnil;
}

/*
 * stream.destroyed? -> Boolean
 *
 * Whether the audio stream has been destroyed.
 */
static VALUE
audio_stream_destroyed_p(VALUE self)
{
    struct sdl2_audio_stream *a;
    TypedData_Get_Struct(self, struct sdl2_audio_stream, &audio_stream_type, a);
    return a->destroyed ? Qtrue : Qfalse;
}

/* --------------------------------------------------------- */

void
Init_sdl2audio(VALUE mTeekSDL2)
{
    cAudioStream = rb_define_class_under(mTeekSDL2, "AudioStream", rb_cObject);
    rb_define_alloc_func(cAudioStream, audio_stream_alloc);

    rb_define_method(cAudioStream, "initialize", audio_stream_initialize, -1);
    rb_define_method(cAudioStream, "queue", audio_stream_queue, 1);
    rb_define_method(cAudioStream, "queued_bytes", audio_stream_queued_bytes, 0);
    rb_define_method(cAudioStream, "queued_samples", audio_stream_queued_samples, 0);
    rb_define_method(cAudioStream, "resume", audio_stream_resume, 0);
    rb_define_method(cAudioStream, "pause", audio_stream_pause, 0);
    rb_define_method(cAudioStream, "playing?", audio_stream_playing_p, 0);
    rb_define_method(cAudioStream, "clear", audio_stream_clear, 0);
    rb_define_method(cAudioStream, "frequency", audio_stream_frequency, 0);
    rb_define_method(cAudioStream, "channels", audio_stream_channels, 0);
    rb_define_method(cAudioStream, "format", audio_stream_format, 0);
    rb_define_method(cAudioStream, "destroy", audio_stream_destroy, 0);
    rb_define_method(cAudioStream, "destroyed?", audio_stream_destroyed_p, 0);
}
