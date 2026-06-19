use gtk4::prelude::*;
use gtk4::DrawingArea;
use std::time::Duration;

use gtk4::glib;

pub fn build(width: i32, height: i32) -> DrawingArea {
    let da = DrawingArea::builder()
        .width_request(width)
        .height_request(height)
        .can_focus(false)
        .build();

    da.set_draw_func(move |_, cr, w, h| {
        let cx = w as f64 / 2.0;
        let cy = h as f64 / 2.0;
        let r = cx.min(cy) * 0.75;

        // Outer ring
        cr.arc(cx, cy, r, 0.0, 2.0 * std::f64::consts::PI);
        cr.set_source_rgba(0.0, 0.94, 1.0, 0.30);
        cr.set_line_width(2.0);
        cr.stroke().unwrap();

        // Hour indices
        for i in 0..12 {
            let a = i as f64 * 30.0 * std::f64::consts::PI / 180.0;
            cr.move_to(cx + r * 0.85 * a.cos(), cy + r * 0.85 * a.sin());
            cr.line_to(cx + r * 0.96 * a.cos(), cy + r * 0.96 * a.sin());
        }
        cr.set_source_rgba(1.0, 1.0, 1.0, 0.8);
        cr.set_line_width(2.5);
        cr.stroke().unwrap();

        // Time
        let now = glib::DateTime::now_local()
            .unwrap_or_else(|_| glib::DateTime::now_utc().expect("time"));
        let sec = now.second() as f64 + now.microsecond() as f64 / 1_000_000.0;
        let min = now.minute() as f64 + sec / 60.0;
        let hr = (now.hour() % 12) as f64 + min / 60.0;

        let sec_a = (sec * 6.0 - 90.0) * std::f64::consts::PI / 180.0;
        let min_a = (min * 6.0 - 90.0) * std::f64::consts::PI / 180.0;
        let hr_a = (hr * 30.0 - 90.0) * std::f64::consts::PI / 180.0;

        // Hour hand - white
        draw_hand(cr, cx, cy, hr_a, r * 0.50, 4.5, 1.0, 1.0, 1.0, 1.0);
        // Minute hand - electric blue
        draw_hand(cr, cx, cy, min_a, r * 0.72, 3.0, 0.0, 0.94, 1.0, 1.0);
        // Second hand - teal
        draw_hand(cr, cx, cy, sec_a, r * 0.83, 1.5, 0.0, 1.0, 0.78, 1.0);

        // Center cap
        cr.arc(cx, cy, 5.0, 0.0, 2.0 * std::f64::consts::PI);
        cr.set_source_rgba(0.0, 0.94, 1.0, 1.0);
        cr.fill().unwrap();
    });

    let da_ref = da.clone();
    gtk4::glib::source::timeout_add_local(Duration::from_millis(1000), move || {
        da_ref.queue_draw();
        gtk4::glib::ControlFlow::Continue
    });

    da
}

fn draw_hand(
    cr: &cairo::Context,
    cx: f64,
    cy: f64,
    angle: f64,
    length: f64,
    width: f64,
    r: f64,
    g: f64,
    b: f64,
    a: f64,
) {
    cr.set_source_rgba(r, g, b, a);
    cr.set_line_width(width);
    cr.set_line_cap(cairo::LineCap::Round);
    cr.move_to(cx, cy);
    cr.line_to(cx + length * angle.cos(), cy + length * angle.sin());
    cr.stroke().unwrap();
}
