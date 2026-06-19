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

    let label = widget.label.clone().unwrap_or_default();
    let max = widget.max.unwrap_or(100.0).max(1.0);
    let suffix = widget.suffix.clone().unwrap_or_default();
    let source = widget.source.clone().unwrap_or_default();

    da.set_draw_func(move |_, cr, _w, _h| {
        let val = value.borrow().clamp(0.0, max);
        let x = 12.0;
        let y = 20.0;

        cr.select_font_face(
            "Adwaita Sans",
            cairo::FontSlant::Normal,
            cairo::FontWeight::Bold,
        );
        cr.set_font_size(13.0);
        cr.set_source_rgba(0.0, 0.94, 1.0, 0.65);
        let ext = cr.text_extents(&label).unwrap();
        cr.move_to(x, y);
        cr.show_text(&label).unwrap();

        // Big value
        cr.set_font_size(34.0);
        let t = match source.as_str() {
            "mem_used" => format!("{:.1}", val),
            "load_1" => format!("{:.2}", val),
            _ => format!("{:.0}", val),
        };
        cr.set_source_rgba(1.0, 1.0, 1.0, 1.0);
        let ext2 = cr.text_extents(&t).unwrap();
        cr.move_to(x + ext.width() + 12.0, y + 10.0);
        cr.show_text(&t).unwrap();

        // Suffix
        if !suffix.is_empty() {
            cr.set_font_size(12.0);
            cr.set_source_rgba(0.0, 0.94, 1.0, 0.7);
            let _ext3 = cr.text_extents(&suffix).unwrap();
            cr.move_to(x + ext.width() + 16.0 + ext2.width(), y + 10.0);
            cr.show_text(&suffix).unwrap();
        }
    });

    let da_clone = da.clone();
    gtk4::glib::source::timeout_add_local(std::time::Duration::from_millis(200), move || {
        da_clone.queue_draw();
        gtk4::glib::ControlFlow::Continue
    });

    da
}
