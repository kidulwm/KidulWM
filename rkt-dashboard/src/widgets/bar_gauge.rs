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
    let orientation: String = widget
        .extra
        .get("orientation")
        .and_then(|v| v.as_str())
        .unwrap_or("vertical")
        .to_string();

    da.set_draw_func(move |_, cr, w, h| {
        let val = value.borrow().clamp(0.0, max);
        let pct = val / max;

        // Background track
        cr.set_source_rgba(1.0, 1.0, 1.0, 0.08);
        cr.rounded_rectangle(6.0, 6.0, w as f64 - 12.0, h as f64 - 12.0, 6.0);
        cr.fill().unwrap();

        let grad = cairo::LinearGradient::new(0.0, 0.0, 0.0, h as f64);
        grad.add_color_stop_rgba(0.0, 0.64, 0.35, 1.0, 0.9);
        grad.add_color_stop_rgba(0.5, 0.0, 0.94, 1.0, 0.9);
        grad.add_color_stop_rgba(1.0, 0.0, 1.0, 0.78, 0.9);
        cr.set_source(&grad).unwrap();

        if orientation == "horizontal" {
            let fill_w = (w as f64 - 12.0) * pct;
            cr.rounded_rectangle(6.0, 6.0, fill_w, h as f64 - 12.0, 6.0);
        } else {
            let fill_h = (h as f64 - 12.0) * pct;
            let y = h as f64 - 6.0 - fill_h;
            cr.rounded_rectangle(6.0, y, w as f64 - 12.0, fill_h, 6.0);
        }
        cr.fill().unwrap();

        // Label
        cr.select_font_face(
            "Adwaita Sans",
            cairo::FontSlant::Normal,
            cairo::FontWeight::Bold,
        );
        cr.set_font_size(13.0);
        cr.set_source_rgba(1.0, 1.0, 1.0, 0.95);
        cr.move_to(12.0, 22.0);
        cr.show_text(&label).unwrap();

        // Value
        cr.set_font_size(11.0);
        let t = format!("{:.0}", val);
        let ext2 = cr.text_extents(&t).unwrap();
        cr.move_to(w as f64 - ext2.width() - 10.0, 22.0);
        cr.show_text(&t).unwrap();
    });

    let da_clone = da.clone();
    gtk4::glib::source::timeout_add_local(std::time::Duration::from_millis(200), move || {
        da_clone.queue_draw();
        gtk4::glib::ControlFlow::Continue
    });

    da
}

trait RoundedRect {
    fn rounded_rectangle(&self, x: f64, y: f64, w: f64, h: f64, r: f64);
}

impl RoundedRect for cairo::Context {
    fn rounded_rectangle(&self, x: f64, y: f64, w: f64, h: f64, r: f64) {
        self.move_to(x + r, y);
        self.line_to(x + w - r, y);
        self.arc(x + w - r, y + r, r, -std::f64::consts::PI / 2.0, 0.0);
        self.line_to(x + w, y + h - r);
        self.arc(x + w - r, y + h - r, r, 0.0, std::f64::consts::PI / 2.0);
        self.line_to(x + r, y + h);
        self.arc(
            x + r,
            y + h - r,
            r,
            std::f64::consts::PI / 2.0,
            std::f64::consts::PI,
        );
        self.line_to(x, y + r);
        self.arc(
            x + r,
            y + r,
            r,
            std::f64::consts::PI,
            -std::f64::consts::PI / 2.0,
        );
        self.close_path();
    }
}
