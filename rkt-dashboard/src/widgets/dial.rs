use gtk4::prelude::*;
use gtk4::DrawingArea;
use std::cell::RefCell;
use std::rc::Rc;

use crate::config::WidgetCfg;

pub fn build(widget: &WidgetCfg, value: Rc<RefCell<f64>>, width: i32, height: i32) -> DrawingArea {
    let da = DrawingArea::builder()
        .width_request(width)
        .height_request(height)
        .can_focus(false)
        .build();

    let max = widget.max.unwrap_or(100.0).max(1.0);
    let label = widget.label.clone().unwrap_or_default();

    da.set_draw_func(move |_, cr, w, h| {
        let cx = w as f64 / 2.0;
        let cy = h as f64 / 2.0;
        let r = cx.min(cy) * 0.65;

        let val = value.borrow().clamp(0.0, max);
        let pct = val / max;
        let sweep = pct * 270.0 * std::f64::consts::PI / 180.0;
        let start = 135.0 * std::f64::consts::PI / 180.0;

        // Track
        cr.arc(
            cx,
            cy,
            r,
            start,
            start + 270.0 * std::f64::consts::PI / 180.0,
        );
        cr.set_source_rgba(1.0, 1.0, 1.0, 0.1);
        cr.set_line_width(8.0);
        cr.set_line_cap(cairo::LineCap::Round);
        cr.stroke().unwrap();

        // Fill
        let grad = cairo::LinearGradient::new(0.0, cy - r, 0.0, cy + r);
        grad.add_color_stop_rgb(0.0, 0.64, 0.35, 1.0);
        grad.add_color_stop_rgb(0.5, 0.0, 0.94, 1.0);
        grad.add_color_stop_rgb(1.0, 0.0, 1.0, 0.78);
        cr.arc(cx, cy, r, start, start + sweep);
        cr.set_source(&grad).unwrap();
        cr.set_line_width(8.0);
        cr.stroke().unwrap();

        // Label
        cr.select_font_face(
            "Adwaita Sans",
            cairo::FontSlant::Normal,
            cairo::FontWeight::Bold,
        );
        cr.set_font_size(14.0);
        let ext = cr.text_extents(&label).unwrap();
        cr.set_source_rgba(1.0, 1.0, 1.0, 0.9);
        cr.move_to(cx - ext.width() / 2.0, cy + 4.0);
        cr.show_text(&label).unwrap();

        // Value
        cr.set_font_size(12.0);
        let t = format!("{:.0}", val);
        let ext2 = cr.text_extents(&t).unwrap();
        cr.set_source_rgba(0.0, 0.94, 1.0, 1.0);
        cr.move_to(cx - ext2.width() / 2.0, cy - 10.0);
        cr.show_text(&t).unwrap();
    });

    let da_clone = da.clone();
    gtk4::glib::source::timeout_add_local(std::time::Duration::from_millis(200), move || {
        da_clone.queue_draw();
        gtk4::glib::ControlFlow::Continue
    });

    da
}
