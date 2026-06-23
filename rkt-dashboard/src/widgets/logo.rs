use gtk4::prelude::*;
use gtk4::{DrawingArea, EventControllerMotion, GestureClick};
use std::cell::RefCell;
use std::io::BufReader;
use std::rc::Rc;

fn hex_path(cr: &cairo::Context, cx: f64, cy: f64, r: f64) {
    cr.new_path();
    cr.move_to(cx + r, cy);
    for i in 1..=6 {
        let a = i as f64 * 2.0 * std::f64::consts::PI / 6.0;
        cr.line_to(cx + r * a.cos(), cy + r * a.sin());
    }
    cr.close_path();
}

pub fn build(
    width: i32,
    height: i32,
    on_trigger: Rc<dyn Fn()>,
    image_path: Option<&str>,
    hover_lines: Option<(&str, &str)>,
) -> DrawingArea {
    let da = DrawingArea::builder()
        .width_request(width)
        .height_request(height)
        .can_focus(false)
        .build();
    da.add_css_class("rkt-logo");

    // Load the PNG directly into a Cairo ARGB32 ImageSurface so premultiplied
    // alpha is preserved and no Pixbuf white-background compositing occurs.
    let image: Rc<RefCell<Option<cairo::ImageSurface>>> = Rc::new(RefCell::new(
        image_path.and_then(|p| {
            std::fs::File::open(p).ok().and_then(|f| {
                cairo::ImageSurface::create_from_png(&mut BufReader::new(f)).ok()
            })
        }),
    ));

    let phase = Rc::new(RefCell::new(0.0f64));
    let phase_clone = phase.clone();
    gtk4::glib::source::timeout_add_local(std::time::Duration::from_millis(25), move || {
        let mut v = phase_clone.borrow_mut();
        *v = (*v + 0.06) % 6.28318;
        gtk4::glib::ControlFlow::Continue
    });

    let hovered = Rc::new(RefCell::new(false));
    let hovered_draw = hovered.clone();

    let hover_line1 = hover_lines
        .map(|h| h.0.to_string())
        .unwrap_or_else(|| "CONTROL".to_string());
    let hover_line2 = hover_lines
        .map(|h| h.1.to_string())
        .unwrap_or_else(|| "CENTER".to_string());

    let phase2 = phase.clone();
    let image_draw = image.clone();
    da.set_draw_func(move |_, cr, w, h| {
        let cx = w as f64 / 2.0;
        let cy = h as f64 / 2.0;
        let r = cx.min(cy) * 0.72;
        let hover = *hovered_draw.borrow();

        if let Some(ref surf) = *image_draw.borrow() {
            // Clip drawing to the widget area so the logo never spills outside the panel.
            cr.rectangle(0.0, 0.0, w as f64, h as f64);
            cr.clip();

            // Draw the PNG fitted to the widget area so nothing is cropped.
            let img_w = surf.width() as f64;
            let img_h = surf.height() as f64;
            let scale = (w as f64 / img_w).min(h as f64 / img_h);
            let draw_w = img_w * scale;
            let draw_h = img_h * scale;
            let x = (w as f64 - draw_w) / 2.0;
            let y = (h as f64 - draw_h) / 2.0;

            cr.save().unwrap();
            cr.translate(x, y);
            cr.scale(scale, scale);
            cr.set_source_surface(surf, 0.0, 0.0).unwrap();
            cr.paint().unwrap();
            cr.restore().unwrap();

            if hover {
                // Dim the image and show CONTROL CENTER label.
                cr.set_source_rgba(0.0, 0.06, 0.12, 0.55);
                cr.paint().unwrap();

                cr.select_font_face(
                    "Adwaita Sans",
                    cairo::FontSlant::Normal,
                    cairo::FontWeight::Bold,
                );
                cr.set_font_size((cx.min(cy)) * 0.20);
                let line1 = hover_line1.as_str();
                let line2 = hover_line2.as_str();
                let ext1 = cr.text_extents(line1).unwrap();
                let ext2 = cr.text_extents(line2).unwrap();
                let y1 = cy - 4.0;
                let y2 = cy + ext1.height() + 6.0;

                cr.set_source_rgba(0.0, 0.94, 1.0, 0.25);
                cr.move_to(cx - ext1.width() / 2.0 - ext1.x_bearing(), y1 + 2.0);
                cr.show_text(line1).unwrap();
                cr.move_to(cx - ext2.width() / 2.0 - ext2.x_bearing(), y2 + 2.0);
                cr.show_text(line2).unwrap();

                cr.set_source_rgba(1.0, 1.0, 1.0, 0.95);
                cr.move_to(cx - ext1.width() / 2.0 - ext1.x_bearing(), y1);
                cr.show_text(line1).unwrap();
                cr.move_to(cx - ext2.width() / 2.0 - ext2.x_bearing(), y2);
                cr.show_text(line2).unwrap();
            }
        } else {
            // Fallback vector hex logo.
            hex_path(cr, cx, cy, r);
            cr.set_source_rgba(0.0, 0.12, 0.20, 0.45);
            cr.fill_preserve().unwrap();
            cr.set_line_width(if hover { 3.5 } else { 2.5 });
            cr.set_source_rgba(0.0, 0.94, 1.0, if hover { 1.0 } else { 0.80 });
            cr.stroke().unwrap();

            if hover {
                cr.select_font_face(
                    "Adwaita Sans",
                    cairo::FontSlant::Normal,
                    cairo::FontWeight::Bold,
                );
                cr.set_font_size(r * 0.18);
                let line1 = hover_line1.as_str();
                let line2 = hover_line2.as_str();
                let ext1 = cr.text_extents(line1).unwrap();
                let ext2 = cr.text_extents(line2).unwrap();
                let y1 = cy - 4.0;
                let y2 = cy + ext1.height() + 6.0;

                cr.set_source_rgba(0.0, 0.94, 1.0, 0.25);
                cr.move_to(cx - ext1.width() / 2.0 - ext1.x_bearing(), y1 + 2.0);
                cr.show_text(line1).unwrap();
                cr.move_to(cx - ext2.width() / 2.0 - ext2.x_bearing(), y2 + 2.0);
                cr.show_text(line2).unwrap();

                cr.set_source_rgba(1.0, 1.0, 1.0, 0.95);
                cr.move_to(cx - ext1.width() / 2.0 - ext1.x_bearing(), y1);
                cr.show_text(line1).unwrap();
                cr.move_to(cx - ext2.width() / 2.0 - ext2.x_bearing(), y2);
                cr.show_text(line2).unwrap();
            } else {
                let pulse = 0.5 + (*phase2.borrow()).sin() * 0.15;
                cr.arc(cx, cy, r * 0.78, 0.0, 2.0 * std::f64::consts::PI);
                cr.set_source_rgba(0.0, 0.94, 1.0, pulse * 0.22);
                cr.fill().unwrap();

                let text = "RKT";
                cr.select_font_face(
                    "Adwaita Sans",
                    cairo::FontSlant::Normal,
                    cairo::FontWeight::Bold,
                );
                cr.set_font_size(r * 0.48);
                let ext = cr.text_extents(text).unwrap();
                let tx = cx - ext.width() / 2.0 - ext.x_bearing();
                let ty = cy + ext.height() / 2.0 - ext.y_bearing();

                cr.set_source_rgba(0.0, 0.94, 1.0, 0.40);
                cr.set_font_size(r * 0.52);
                cr.move_to(tx, ty);
                cr.show_text(text).unwrap();

                cr.set_source_rgba(1.0, 1.0, 1.0, 1.0);
                cr.set_font_size(r * 0.48);
                cr.move_to(tx, ty);
                cr.show_text(text).unwrap();
            }
        }
    });

    let motion = EventControllerMotion::new();
    let enter_hovered = hovered.clone();
    let enter_da = da.clone();
    motion.connect_enter(move |_, _, _| {
        *enter_hovered.borrow_mut() = true;
        enter_da.queue_draw();
    });
    let leave_hovered = hovered.clone();
    let leave_da = da.clone();
    motion.connect_leave(move |_| {
        *leave_hovered.borrow_mut() = false;
        leave_da.queue_draw();
    });
    da.add_controller(motion);

    let click = GestureClick::new();
    click.connect_pressed(move |_: &GestureClick, _: i32, _: f64, _: f64| {
        on_trigger();
    });
    da.add_controller(click);

    da
}

pub fn build_catchy(width: i32, height: i32) -> DrawingArea {
    let da = DrawingArea::builder()
        .width_request(width)
        .height_request(height)
        .can_focus(false)
        .build();
    da.add_css_class("rkt-catchy");

    da.set_draw_func(move |_, cr, w, h| {
        let cx = w as f64 / 2.0;
        let cy = h as f64 / 2.0;
        let r = cx.min(cy) * 0.75;

        let sides = 6;
        cr.move_to(cx + r, cy);
        for i in 1..=sides {
            let a = i as f64 * 2.0 * std::f64::consts::PI / sides as f64;
            cr.line_to(cx + r * a.cos(), cy + r * a.sin());
        }
        cr.close_path();
        cr.set_source_rgba(0.63, 0.35, 1.0, 0.35);
        cr.set_line_width(1.5);
        cr.stroke().unwrap();

        cr.select_font_face(
            "Adwaita Sans",
            cairo::FontSlant::Normal,
            cairo::FontWeight::Bold,
        );
        let text = "CATCHY";
        cr.set_font_size(r * 0.32);
        let ext = cr.text_extents(text).unwrap();
        let tx = cx - ext.width() / 2.0 - ext.x_bearing();
        let ty = cy + ext.height() / 2.0 - ext.y_bearing();

        cr.set_source_rgba(0.63, 0.35, 1.0, 0.25);
        cr.move_to(tx, ty + 1.0);
        cr.show_text(text).unwrap();

        cr.set_source_rgba(1.0, 1.0, 1.0, 0.55);
        cr.move_to(tx, ty);
        cr.show_text(text).unwrap();
    });

    da
}
