/* tkfont.c - Font measurement C functions for tk-ng
 *
 * Fast font and text measurement using Tk's font C API.
 * These functions bypass Tcl string parsing for better performance.
 */

#include "tcltkbridge.h"

/* ---------------------------------------------------------
 * Interp#text_width(font_name, text)
 *
 * Measure pixel width of text string using Tk_TextWidth.
 * Faster than querying via Tcl font measure command.
 *
 * Arguments:
 *   font_name - Font description string (e.g., "Helvetica 12", "TkDefaultFont")
 *   text      - Text string to measure
 *
 * Returns integer pixel width.
 *
 * See: https://www.tcl-lang.org/man/tcl9.0/TkLib/MeasureChar.html
 * --------------------------------------------------------- */

static VALUE
interp_text_width(VALUE self, VALUE font_name, VALUE text)
{
    struct tcltk_interp *tip = get_interp(self);
    Tk_Window mainWin;
    Tk_Font tkfont;
    const char *font_str;
    const char *text_str;
    int width;

    StringValue(font_name);
    StringValue(text);

    font_str = StringValueCStr(font_name);
    text_str = StringValueCStr(text);

    /* Get the main window for font allocation */
    mainWin = Tk_MainWindow(tip->interp);
    if (!mainWin) {
        rb_raise(eTclError, "Tk not initialized (no main window)");
    }

    /* Get the font */
    tkfont = Tk_GetFont(tip->interp, mainWin, font_str);
    if (!tkfont) {
        rb_raise(eTclError, "font not found: %s - %s",
                 font_str, Tcl_GetStringResult(tip->interp));
    }

    /* Measure the text width */
    width = Tk_TextWidth(tkfont, text_str, (int)strlen(text_str));

    /* Release the font */
    Tk_FreeFont(tkfont);

    return INT2NUM(width);
}

/* ---------------------------------------------------------
 * Interp#font_metrics(font_name)
 *
 * Get font metrics using Tk_GetFontMetrics.
 * Faster than querying via Tcl font metrics command.
 *
 * Arguments:
 *   font_name - Font description string (e.g., "Helvetica 12", "TkDefaultFont")
 *
 * Returns Hash with:
 *   :ascent   - Pixels from baseline to top of highest character
 *   :descent  - Pixels from baseline to bottom of lowest character
 *   :linespace - Total line height (ascent + descent)
 *
 * See: https://www.tcl-lang.org/man/tcl9.0/TkLib/FontId.html
 * --------------------------------------------------------- */

static VALUE
interp_font_metrics(VALUE self, VALUE font_name)
{
    struct tcltk_interp *tip = get_interp(self);
    Tk_Window mainWin;
    Tk_Font tkfont;
    Tk_FontMetrics fm;
    const char *font_str;
    VALUE result;

    StringValue(font_name);
    font_str = StringValueCStr(font_name);

    /* Get the main window for font allocation */
    mainWin = Tk_MainWindow(tip->interp);
    if (!mainWin) {
        rb_raise(eTclError, "Tk not initialized (no main window)");
    }

    /* Get the font */
    tkfont = Tk_GetFont(tip->interp, mainWin, font_str);
    if (!tkfont) {
        rb_raise(eTclError, "font not found: %s - %s",
                 font_str, Tcl_GetStringResult(tip->interp));
    }

    /* Get font metrics */
    Tk_GetFontMetrics(tkfont, &fm);

    /* Build result hash */
    result = rb_hash_new();
    rb_hash_aset(result, ID2SYM(rb_intern("ascent")), INT2NUM(fm.ascent));
    rb_hash_aset(result, ID2SYM(rb_intern("descent")), INT2NUM(fm.descent));
    rb_hash_aset(result, ID2SYM(rb_intern("linespace")), INT2NUM(fm.linespace));

    /* Release the font */
    Tk_FreeFont(tkfont);

    return result;
}

/* ---------------------------------------------------------
 * Interp#measure_chars(font_name, text, max_pixels, opts={})
 *
 * Measure how many characters/bytes of text fit within a pixel width limit.
 * Useful for text truncation, ellipsis, and line wrapping.
 *
 * Arguments:
 *   font_name  - Font description string (e.g., "Helvetica 12")
 *   text       - Text string to measure
 *   max_pixels - Maximum pixel width allowed (-1 for unlimited)
 *   opts       - Optional hash:
 *                :partial_ok  - Allow partial character at boundary (default: false)
 *                :whole_words - Break only at word boundaries (default: false)
 *                :at_least_one - Always return at least one character (default: false)
 *
 * Returns Hash with:
 *   :bytes  - Number of bytes that fit within max_pixels
 *   :width  - Actual pixel width of those bytes
 *
 * See: https://www.tcl-lang.org/man/tcl9.0/TkLib/MeasureChar.html
 * --------------------------------------------------------- */

static VALUE
interp_measure_chars(int argc, VALUE *argv, VALUE self)
{
    struct tcltk_interp *tip = get_interp(self);
    VALUE font_name, text, max_pixels_val, opts;
    Tk_Window mainWin;
    Tk_Font tkfont;
    const char *font_str;
    const char *text_str;
    int max_pixels;
    int flags;
    int length;
    int num_bytes;
    VALUE result;

    rb_scan_args(argc, argv, "31", &font_name, &text, &max_pixels_val, &opts);

    StringValue(font_name);
    StringValue(text);

    font_str = StringValueCStr(font_name);
    text_str = StringValueCStr(text);
    max_pixels = NUM2INT(max_pixels_val);

    /* Parse flags from options */
    flags = 0;
    if (!NIL_P(opts) && TYPE(opts) == T_HASH) {
        VALUE val;
        val = rb_hash_aref(opts, ID2SYM(rb_intern("partial_ok")));
        if (RTEST(val)) flags |= TK_PARTIAL_OK;
        val = rb_hash_aref(opts, ID2SYM(rb_intern("whole_words")));
        if (RTEST(val)) flags |= TK_WHOLE_WORDS;
        val = rb_hash_aref(opts, ID2SYM(rb_intern("at_least_one")));
        if (RTEST(val)) flags |= TK_AT_LEAST_ONE;
    }

    /* Get the main window for font allocation */
    mainWin = Tk_MainWindow(tip->interp);
    if (!mainWin) {
        rb_raise(eTclError, "Tk not initialized (no main window)");
    }

    /* Get the font */
    tkfont = Tk_GetFont(tip->interp, mainWin, font_str);
    if (!tkfont) {
        rb_raise(eTclError, "font not found: %s - %s",
                 font_str, Tcl_GetStringResult(tip->interp));
    }

    /* Measure characters */
    num_bytes = Tk_MeasureChars(tkfont, text_str, (int)strlen(text_str),
                                 max_pixels, flags, &length);

    /* Release the font */
    Tk_FreeFont(tkfont);

    /* Build result hash */
    result = rb_hash_new();
    rb_hash_aset(result, ID2SYM(rb_intern("bytes")), INT2NUM(num_bytes));
    rb_hash_aset(result, ID2SYM(rb_intern("width")), INT2NUM(length));

    return result;
}

/* ---------------------------------------------------------
 * Init_tkfont - Register font methods on TclTkIp class
 *
 * Called from Init_tcltklib in tcltkbridge.c
 * --------------------------------------------------------- */

void
Init_tkfont(VALUE cTclTkIp)
{
    rb_define_method(cTclTkIp, "text_width", interp_text_width, 2);
    rb_define_method(cTclTkIp, "font_metrics", interp_font_metrics, 1);
    rb_define_method(cTclTkIp, "measure_chars", interp_measure_chars, -1);
}
