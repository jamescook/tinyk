/* tkphoto.c - Photo image C functions for tk-ng
 *
 * Fast pixel manipulation using Tk's photo image C API.
 * These functions bypass Tcl string parsing for better performance.
 */

#include "tcltkbridge.h"

/* ---------------------------------------------------------
 * Interp#photo_put_block(photo_path, pixel_data, width, height, opts={})
 *
 * Fast pixel writes to a photo image using Tk_PhotoPutBlock.
 * Much faster than Tcl's 'photo put' which requires parsing hex strings.
 *
 * Arguments:
 *   photo_path - Tcl path of the photo image (e.g., "i00001")
 *   pixel_data - Binary string of pixels (4 bytes per pixel)
 *   width      - Image width in pixels
 *   height     - Image height in pixels
 *   opts       - Optional hash:
 *                :x, :y    - destination offsets (default 0,0)
 *                :format   - :rgba (default) or :argb
 *
 * The pixel_data must be exactly width * height * 4 bytes.
 *
 * Format :argb expects pixels packed as 0xAARRGGBB integers (little-endian: B,G,R,A bytes).
 * This matches SDL2 and many graphics libraries.
 *
 * See: https://www.tcl-lang.org/man/tcl8.6/TkLib/FindPhoto.htm
 * --------------------------------------------------------- */

static VALUE
interp_photo_put_block(int argc, VALUE *argv, VALUE self)
{
    struct tcltk_interp *tip = get_interp(self);
    VALUE photo_path, pixel_data, width_val, height_val, opts;
    Tk_PhotoHandle photo;
    Tk_PhotoImageBlock block;
    int width, height, x_off, y_off;
    int is_argb = 0;
    long expected_size;

    rb_scan_args(argc, argv, "41", &photo_path, &pixel_data, &width_val, &height_val, &opts);

    StringValue(photo_path);
    StringValue(pixel_data);
    width = NUM2INT(width_val);
    height = NUM2INT(height_val);

    /* Validate dimensions */
    if (width <= 0 || height <= 0) {
        rb_raise(rb_eArgError, "width and height must be positive");
    }

    /* Validate data size */
    expected_size = (long)width * height * 4;
    if (RSTRING_LEN(pixel_data) != expected_size) {
        rb_raise(rb_eArgError, "pixel_data size mismatch: expected %ld bytes, got %ld",
                 expected_size, RSTRING_LEN(pixel_data));
    }

    /* Parse options */
    x_off = 0;
    y_off = 0;
    if (!NIL_P(opts) && TYPE(opts) == T_HASH) {
        VALUE val;
        val = rb_hash_aref(opts, ID2SYM(rb_intern("x")));
        if (!NIL_P(val)) x_off = NUM2INT(val);
        val = rb_hash_aref(opts, ID2SYM(rb_intern("y")));
        if (!NIL_P(val)) y_off = NUM2INT(val);
        val = rb_hash_aref(opts, ID2SYM(rb_intern("format")));
        if (!NIL_P(val) && TYPE(val) == T_SYMBOL) {
            if (rb_intern("argb") == SYM2ID(val)) {
                is_argb = 1;
            }
        }
    }

    /* Find the photo image by Tcl path */
    photo = Tk_FindPhoto(tip->interp, StringValueCStr(photo_path));
    if (!photo) {
        rb_raise(eTclError, "photo image not found: %s", StringValueCStr(photo_path));
    }

    /* Set up the pixel block structure */
    block.pixelPtr = (unsigned char *)RSTRING_PTR(pixel_data);
    block.width = width;
    block.height = height;
    block.pitch = width * 4;
    block.pixelSize = 4;

    if (is_argb) {
        /* ARGB: 0xAARRGGBB stored little-endian as bytes: [B, G, R, A] */
        block.offset[0] = 2;  /* Red at byte 2 */
        block.offset[1] = 1;  /* Green at byte 1 */
        block.offset[2] = 0;  /* Blue at byte 0 */
        block.offset[3] = 3;  /* Alpha at byte 3 */
    } else {
        /* RGBA: [R, G, B, A] */
        block.offset[0] = 0;
        block.offset[1] = 1;
        block.offset[2] = 2;
        block.offset[3] = 3;
    }

    /* Write pixels to the photo image */
    if (Tk_PhotoPutBlock(tip->interp, photo, &block, x_off, y_off,
                         width, height, TK_PHOTO_COMPOSITE_SET) != TCL_OK) {
        rb_raise(eTclError, "Tk_PhotoPutBlock failed: %s",
                 Tcl_GetStringResult(tip->interp));
    }

    return Qnil;
}

/* ---------------------------------------------------------
 * Interp#photo_put_zoomed_block(photo_path, pixel_data, width, height, opts={})
 *
 * Fast pixel writes with zoom/subsample using Tk_PhotoPutZoomedBlock.
 * Writes pixels and scales in a single operation - faster than put_block + copy.
 *
 * Arguments:
 *   photo_path - Tcl path of the photo image (e.g., "i00001")
 *   pixel_data - Binary string of pixels (4 bytes per pixel)
 *   width      - Source image width in pixels
 *   height     - Source image height in pixels
 *   opts       - Optional hash:
 *                :x, :y        - destination offsets (default 0,0)
 *                :zoom_x, :zoom_y       - zoom factors (default 1,1)
 *                :subsample_x, :subsample_y - subsample factors (default 1,1)
 *                :format       - :rgba (default) or :argb
 *
 * The pixel_data must be exactly width * height * 4 bytes.
 * Zoom replicates pixels (zoom=3 makes each pixel 3x3).
 * Subsample skips pixels (subsample=2 takes every other pixel).
 *
 * Format :argb expects pixels packed as 0xAARRGGBB integers (little-endian: B,G,R,A bytes).
 * This matches SDL2 and many graphics libraries.
 *
 * See: https://www.tcl-lang.org/man/tcl8.6/TkLib/FindPhoto.htm
 * --------------------------------------------------------- */

static VALUE
interp_photo_put_zoomed_block(int argc, VALUE *argv, VALUE self)
{
    struct tcltk_interp *tip = get_interp(self);
    VALUE photo_path, pixel_data, width_val, height_val, opts;
    Tk_PhotoHandle photo;
    Tk_PhotoImageBlock block;
    int width, height, x_off, y_off;
    int zoom_x, zoom_y, subsample_x, subsample_y;
    int dest_width, dest_height;
    int is_argb = 0;
    long expected_size;

    rb_scan_args(argc, argv, "41", &photo_path, &pixel_data, &width_val, &height_val, &opts);

    StringValue(photo_path);
    StringValue(pixel_data);
    width = NUM2INT(width_val);
    height = NUM2INT(height_val);

    /* Validate dimensions */
    if (width <= 0 || height <= 0) {
        rb_raise(rb_eArgError, "width and height must be positive");
    }

    /* Validate data size */
    expected_size = (long)width * height * 4;
    if (RSTRING_LEN(pixel_data) != expected_size) {
        rb_raise(rb_eArgError, "pixel_data size mismatch: expected %ld bytes, got %ld",
                 expected_size, RSTRING_LEN(pixel_data));
    }

    /* Parse options with defaults */
    x_off = 0;
    y_off = 0;
    zoom_x = 1;
    zoom_y = 1;
    subsample_x = 1;
    subsample_y = 1;

    if (!NIL_P(opts) && TYPE(opts) == T_HASH) {
        VALUE val;
        val = rb_hash_aref(opts, ID2SYM(rb_intern("x")));
        if (!NIL_P(val)) x_off = NUM2INT(val);
        val = rb_hash_aref(opts, ID2SYM(rb_intern("y")));
        if (!NIL_P(val)) y_off = NUM2INT(val);
        val = rb_hash_aref(opts, ID2SYM(rb_intern("zoom_x")));
        if (!NIL_P(val)) zoom_x = NUM2INT(val);
        val = rb_hash_aref(opts, ID2SYM(rb_intern("zoom_y")));
        if (!NIL_P(val)) zoom_y = NUM2INT(val);
        val = rb_hash_aref(opts, ID2SYM(rb_intern("subsample_x")));
        if (!NIL_P(val)) subsample_x = NUM2INT(val);
        val = rb_hash_aref(opts, ID2SYM(rb_intern("subsample_y")));
        if (!NIL_P(val)) subsample_y = NUM2INT(val);
        val = rb_hash_aref(opts, ID2SYM(rb_intern("format")));
        if (!NIL_P(val) && TYPE(val) == T_SYMBOL) {
            if (rb_intern("argb") == SYM2ID(val)) {
                is_argb = 1;
            }
        }
    }

    /* Validate zoom/subsample */
    if (zoom_x <= 0 || zoom_y <= 0) {
        rb_raise(rb_eArgError, "zoom factors must be positive");
    }
    if (subsample_x <= 0 || subsample_y <= 0) {
        rb_raise(rb_eArgError, "subsample factors must be positive");
    }

    /* Find the photo image by Tcl path */
    photo = Tk_FindPhoto(tip->interp, StringValueCStr(photo_path));
    if (!photo) {
        rb_raise(eTclError, "photo image not found: %s", StringValueCStr(photo_path));
    }

    /* Set up the pixel block structure */
    block.pixelPtr = (unsigned char *)RSTRING_PTR(pixel_data);
    block.width = width;
    block.height = height;
    block.pitch = width * 4;
    block.pixelSize = 4;

    if (is_argb) {
        /* ARGB: 0xAARRGGBB stored little-endian as bytes: [B, G, R, A] */
        block.offset[0] = 2;  /* Red at byte 2 */
        block.offset[1] = 1;  /* Green at byte 1 */
        block.offset[2] = 0;  /* Blue at byte 0 */
        block.offset[3] = 3;  /* Alpha at byte 3 */
    } else {
        /* RGBA: [R, G, B, A] */
        block.offset[0] = 0;
        block.offset[1] = 1;
        block.offset[2] = 2;
        block.offset[3] = 3;
    }

    /* Calculate destination dimensions */
    dest_width = (width / subsample_x) * zoom_x;
    dest_height = (height / subsample_y) * zoom_y;

    /* Write pixels with zoom/subsample */
    if (Tk_PhotoPutZoomedBlock(tip->interp, photo, &block, x_off, y_off,
                               dest_width, dest_height,
                               zoom_x, zoom_y, subsample_x, subsample_y,
                               TK_PHOTO_COMPOSITE_SET) != TCL_OK) {
        rb_raise(eTclError, "Tk_PhotoPutZoomedBlock failed: %s",
                 Tcl_GetStringResult(tip->interp));
    }

    return Qnil;
}

/* ---------------------------------------------------------
 * Interp#photo_get_image(photo_path, opts={})
 *
 * Read pixel data from a photo image using Tk_PhotoGetImage.
 *
 * Arguments:
 *   photo_path - Tcl path of the photo image (e.g., "i00001")
 *   opts       - Optional hash:
 *                :x, :y        - source offsets (default 0,0)
 *                :width, :height - region size (default: full image)
 *                :unpack       - if true, return flat array of integers
 *                                instead of binary string (default: false)
 *
 * Returns a Hash with:
 *   :data   - Binary string of RGBA pixels (4 bytes per pixel), OR
 *   :pixels - Flat array of integers [r,g,b,a,r,g,b,a,...] if unpack: true
 *   :width  - Width of returned data
 *   :height - Height of returned data
 *
 * See: https://www.tcl-lang.org/man/tcl9.0/TkLib/FindPhoto.htm
 * --------------------------------------------------------- */

static VALUE
interp_photo_get_image(int argc, VALUE *argv, VALUE self)
{
    struct tcltk_interp *tip = get_interp(self);
    VALUE photo_path, opts, result;
    Tk_PhotoHandle photo;
    Tk_PhotoImageBlock block;
    int x_off, y_off, req_width, req_height;
    int img_width, img_height;
    int actual_width, actual_height;
    int do_unpack;
    unsigned char *src;
    int x, y;
    int r_off, g_off, b_off, a_off;

    rb_scan_args(argc, argv, "11", &photo_path, &opts);

    StringValue(photo_path);

    /* Find the photo image by Tcl path */
    photo = Tk_FindPhoto(tip->interp, StringValueCStr(photo_path));
    if (!photo) {
        rb_raise(eTclError, "photo image not found: %s", StringValueCStr(photo_path));
    }

    /* Get image info */
    if (!Tk_PhotoGetImage(photo, &block)) {
        rb_raise(eTclError, "failed to get photo image data");
    }

    img_width = block.width;
    img_height = block.height;

    /* Parse options */
    x_off = 0;
    y_off = 0;
    req_width = img_width;
    req_height = img_height;
    do_unpack = 0;

    if (!NIL_P(opts) && TYPE(opts) == T_HASH) {
        VALUE val;
        val = rb_hash_aref(opts, ID2SYM(rb_intern("x")));
        if (!NIL_P(val)) x_off = NUM2INT(val);
        val = rb_hash_aref(opts, ID2SYM(rb_intern("y")));
        if (!NIL_P(val)) y_off = NUM2INT(val);
        val = rb_hash_aref(opts, ID2SYM(rb_intern("width")));
        if (!NIL_P(val)) req_width = NUM2INT(val);
        val = rb_hash_aref(opts, ID2SYM(rb_intern("height")));
        if (!NIL_P(val)) req_height = NUM2INT(val);
        val = rb_hash_aref(opts, ID2SYM(rb_intern("unpack")));
        if (RTEST(val)) do_unpack = 1;
    }

    /* Validate and clamp region */
    if (x_off < 0) x_off = 0;
    if (y_off < 0) y_off = 0;
    if (x_off >= img_width || y_off >= img_height) {
        rb_raise(rb_eArgError, "offset outside image bounds");
    }

    actual_width = req_width;
    actual_height = req_height;
    if (x_off + actual_width > img_width) actual_width = img_width - x_off;
    if (y_off + actual_height > img_height) actual_height = img_height - y_off;

    if (actual_width <= 0 || actual_height <= 0) {
        rb_raise(rb_eArgError, "invalid region size");
    }

    /* Get channel offsets from the block */
    r_off = block.offset[0];
    g_off = block.offset[1];
    b_off = block.offset[2];
    a_off = block.offset[3];

    /* Build result hash */
    result = rb_hash_new();
    rb_hash_aset(result, ID2SYM(rb_intern("width")), INT2NUM(actual_width));
    rb_hash_aset(result, ID2SYM(rb_intern("height")), INT2NUM(actual_height));

    if (do_unpack) {
        /* Return flat array of integers: [r,g,b,a,r,g,b,a,...] */
        long num_values = (long)actual_width * actual_height * 4;
        VALUE pixels = rb_ary_new_capa(num_values);

        for (y = 0; y < actual_height; y++) {
            src = block.pixelPtr + (y_off + y) * block.pitch + x_off * block.pixelSize;
            for (x = 0; x < actual_width; x++) {
                rb_ary_push(pixels, INT2FIX(src[r_off]));
                rb_ary_push(pixels, INT2FIX(src[g_off]));
                rb_ary_push(pixels, INT2FIX(src[b_off]));
                rb_ary_push(pixels, INT2FIX((block.pixelSize >= 4) ? src[a_off] : 255));
                src += block.pixelSize;
            }
        }

        rb_hash_aset(result, ID2SYM(rb_intern("pixels")), pixels);
    } else {
        /* Return binary string */
        VALUE data_str = rb_str_new(NULL, (long)actual_width * actual_height * 4);
        unsigned char *dst = (unsigned char *)RSTRING_PTR(data_str);

        for (y = 0; y < actual_height; y++) {
            src = block.pixelPtr + (y_off + y) * block.pitch + x_off * block.pixelSize;
            for (x = 0; x < actual_width; x++) {
                *dst++ = src[r_off];
                *dst++ = src[g_off];
                *dst++ = src[b_off];
                *dst++ = (block.pixelSize >= 4) ? src[a_off] : 255;
                src += block.pixelSize;
            }
        }

        rb_hash_aset(result, ID2SYM(rb_intern("data")), data_str);
    }

    return result;
}

/* ---------------------------------------------------------
 * Interp#photo_get_size(photo_path)
 *
 * Get dimensions of a photo image using Tk_PhotoGetSize.
 * Faster than querying via Tcl commands.
 *
 * Arguments:
 *   photo_path - Tcl path of the photo image (e.g., "i00001")
 *
 * Returns [width, height] array.
 *
 * See: https://www.tcl-lang.org/man/tcl9.0/TkLib/FindPhoto.htm
 * --------------------------------------------------------- */

static VALUE
interp_photo_get_size(VALUE self, VALUE photo_path)
{
    struct tcltk_interp *tip = get_interp(self);
    Tk_PhotoHandle photo;
    int width, height;

    StringValue(photo_path);

    photo = Tk_FindPhoto(tip->interp, StringValueCStr(photo_path));
    if (!photo) {
        rb_raise(eTclError, "photo image not found: %s", StringValueCStr(photo_path));
    }

    Tk_PhotoGetSize(photo, &width, &height);

    return rb_ary_new_from_args(2, INT2NUM(width), INT2NUM(height));
}

/* ---------------------------------------------------------
 * Interp#photo_blank(photo_path)
 *
 * Clear a photo image to transparent using Tk_PhotoBlank.
 * Faster than setting all pixels manually.
 *
 * Arguments:
 *   photo_path - Tcl path of the photo image (e.g., "i00001")
 *
 * Returns nil.
 *
 * See: https://www.tcl-lang.org/man/tcl9.0/TkLib/FindPhoto.htm
 * --------------------------------------------------------- */

static VALUE
interp_photo_blank(VALUE self, VALUE photo_path)
{
    struct tcltk_interp *tip = get_interp(self);
    Tk_PhotoHandle photo;

    StringValue(photo_path);

    photo = Tk_FindPhoto(tip->interp, StringValueCStr(photo_path));
    if (!photo) {
        rb_raise(eTclError, "photo image not found: %s", StringValueCStr(photo_path));
    }

    Tk_PhotoBlank(photo);

    return Qnil;
}

/* ---------------------------------------------------------
 * Init_tkphoto - Register photo image methods on TclTkIp class
 *
 * Called from Init_tcltklib in tcltkbridge.c
 * --------------------------------------------------------- */

void
Init_tkphoto(VALUE cTclTkIp)
{
    rb_define_method(cTclTkIp, "photo_put_block", interp_photo_put_block, -1);
    rb_define_method(cTclTkIp, "photo_put_zoomed_block", interp_photo_put_zoomed_block, -1);
    rb_define_method(cTclTkIp, "photo_get_image", interp_photo_get_image, -1);
    rb_define_method(cTclTkIp, "photo_get_size", interp_photo_get_size, 1);
    rb_define_method(cTclTkIp, "photo_blank", interp_photo_blank, 1);
}
