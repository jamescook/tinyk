#include "teek_sdl2.h"

/* ---------------------------------------------------------
 * Pixel format conversion helpers
 *
 * Fast C-level conversion from various pixel formats to
 * ARGB8888 (our native SDL2 texture format). Designed for
 * emulators and games that output pixels in different formats.
 * --------------------------------------------------------- */

/*
 * Teek::SDL2::Pixels.pack_uint32(array, width, height) -> String
 *
 * Packs an Array of uint32 integers into an ARGB8888 byte string
 * suitable for Texture#update. Each integer is treated as a
 * native-endian 32-bit pixel value.
 *
 * This is the fast path for optcarrot and similar emulators that
 * output pre-palette-mapped uint32 pixel arrays.
 */
static VALUE
pixels_pack_uint32(VALUE self, VALUE ary, VALUE vw, VALUE vh)
{
    int w = NUM2INT(vw);
    int h = NUM2INT(vh);
    long expected = (long)w * h;
    long len;
    VALUE result;
    uint32_t *dst;
    long i;

    Check_Type(ary, T_ARRAY);
    len = RARRAY_LEN(ary);

    if (len < expected) {
        rb_raise(rb_eArgError,
                 "array too short: need %ld pixels, got %ld", expected, len);
    }

    result = rb_str_new(NULL, expected * 4);
    dst = (uint32_t *)RSTRING_PTR(result);

    for (i = 0; i < expected; i++) {
        dst[i] = (uint32_t)NUM2UINT(rb_ary_entry(ary, i));
    }

    return result;
}

/*
 * Teek::SDL2::Pixels.convert(source, width, height, from_format) -> String
 *
 * Converts a pixel byte string from one format to ARGB8888.
 *
 * Supported from_format values:
 *   :argb8888 - passthrough (no conversion)
 *   :rgba8888 - RGBA -> ARGB byte shuffle
 *   :bgra8888 - BGRA -> ARGB byte shuffle
 *   :abgr8888 - ABGR -> ARGB byte shuffle
 *   :rgb888   - 3-byte RGB -> 4-byte ARGB (adds 0xFF alpha)
 */
static VALUE
pixels_convert(VALUE self, VALUE source, VALUE vw, VALUE vh, VALUE format)
{
    int w = NUM2INT(vw);
    int h = NUM2INT(vh);
    long npixels = (long)w * h;
    const uint8_t *src;
    uint8_t *dst;
    VALUE result;
    ID fmt;
    long i;

    Check_Type(source, T_STRING);
    fmt = SYM2ID(format);
    src = (const uint8_t *)RSTRING_PTR(source);

    /* :argb8888 — passthrough */
    if (fmt == rb_intern("argb8888")) {
        if (RSTRING_LEN(source) < npixels * 4) {
            rb_raise(rb_eArgError, "source too short for %ldx%d ARGB8888", (long)w, h);
        }
        return rb_str_dup(source);
    }

    /* :rgba8888 — RGBA -> ARGB */
    if (fmt == rb_intern("rgba8888")) {
        if (RSTRING_LEN(source) < npixels * 4) {
            rb_raise(rb_eArgError, "source too short for %ldx%d RGBA8888", (long)w, h);
        }
        result = rb_str_new(NULL, npixels * 4);
        dst = (uint8_t *)RSTRING_PTR(result);
        for (i = 0; i < npixels; i++) {
            long off = i * 4;
            dst[off + 0] = src[off + 3]; /* A */
            dst[off + 1] = src[off + 0]; /* R */
            dst[off + 2] = src[off + 1]; /* G */
            dst[off + 3] = src[off + 2]; /* B */
        }
        return result;
    }

    /* :bgra8888 — BGRA -> ARGB */
    if (fmt == rb_intern("bgra8888")) {
        if (RSTRING_LEN(source) < npixels * 4) {
            rb_raise(rb_eArgError, "source too short for %ldx%d BGRA8888", (long)w, h);
        }
        result = rb_str_new(NULL, npixels * 4);
        dst = (uint8_t *)RSTRING_PTR(result);
        for (i = 0; i < npixels; i++) {
            long off = i * 4;
            dst[off + 0] = src[off + 3]; /* A */
            dst[off + 1] = src[off + 2]; /* R */
            dst[off + 2] = src[off + 1]; /* G */
            dst[off + 3] = src[off + 0]; /* B */
        }
        return result;
    }

    /* :abgr8888 — ABGR -> ARGB */
    if (fmt == rb_intern("abgr8888")) {
        if (RSTRING_LEN(source) < npixels * 4) {
            rb_raise(rb_eArgError, "source too short for %ldx%d ABGR8888", (long)w, h);
        }
        result = rb_str_new(NULL, npixels * 4);
        dst = (uint8_t *)RSTRING_PTR(result);
        for (i = 0; i < npixels; i++) {
            long off = i * 4;
            dst[off + 0] = src[off + 0]; /* A */
            dst[off + 1] = src[off + 3]; /* R */
            dst[off + 2] = src[off + 2]; /* G */
            dst[off + 3] = src[off + 1]; /* B */
        }
        return result;
    }

    /* :rgb888 — 3-byte RGB -> 4-byte ARGB */
    if (fmt == rb_intern("rgb888")) {
        if (RSTRING_LEN(source) < npixels * 3) {
            rb_raise(rb_eArgError, "source too short for %ldx%d RGB888", (long)w, h);
        }
        result = rb_str_new(NULL, npixels * 4);
        dst = (uint8_t *)RSTRING_PTR(result);
        for (i = 0; i < npixels; i++) {
            long src_off = i * 3;
            long dst_off = i * 4;
            dst[dst_off + 0] = 0xFF;           /* A */
            dst[dst_off + 1] = src[src_off + 0]; /* R */
            dst[dst_off + 2] = src[src_off + 1]; /* G */
            dst[dst_off + 3] = src[src_off + 2]; /* B */
        }
        return result;
    }

    rb_raise(rb_eArgError, "unknown pixel format: %"PRIsVALUE, format);
    return Qnil; /* unreachable */
}

void
Init_sdl2pixels(VALUE mTeekSDL2)
{
    VALUE cPixels = rb_define_module_under(mTeekSDL2, "Pixels");

    rb_define_module_function(cPixels, "pack_uint32", pixels_pack_uint32, 3);
    rb_define_module_function(cPixels, "convert", pixels_convert, 4);
}
