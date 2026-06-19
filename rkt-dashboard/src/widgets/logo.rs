use gtk4::prelude::*;
use gtk4::{DrawingArea, EventControllerMotion, GestureClick};
use std::cell::RefCell;
use std::rc::Rc;

pub fn build(width: i32, height: i32, on_trigger: Rc<dyn Fn()>) -> DrawingArea {
    let da = DrawingArea::builder()
        .width_request(width)
        .height_request(height)
        .can_focus(false)
        .build();

    let phase = Rc::new(RefCell::new(0.0f64));
    let phase_clone = phase.clone();
    gtk4::glib::source::timeout_add_local(std::time::Duration::from_millis(25), move || {
        let mut v = phase_clone.borrow_mut();
        *v = (*v + 0.06) % 6.28318;
        gtk4::glib::ControlFlow::Continue
    });

    let phase2 = phase.clone();
    da.set_draw_func(move |_, cr, w, h| {
        let cx = w as f64 / 2.0;
        let cy = h as f64 / 2.0;
        let r = cx.min(cy) * 0.72;

        // Glass hex
        let sides = 6;
        cr.move_to(cx + r, cy);
        for i in 1..=sides {
            let a = i as f64 * 2.0 * std::f64::consts::PI / sides as f64;
            cr.line_to(cx + r * a.cos(), cy + r * a.sin());
        }
        cr.close_path();
        cr.set_source_rgba(0.0, 0.12, 0.20, 0.40);
        cr.fill_preserve().unwrap();
        cr.set_line_width(2.5);
        cr.set_source_rgba(0.0, 0.94, 1.0, 0.80);
        cr.stroke().unwrap();

        // Animated inner glow
        let pulse = 0.5 + (*phase2.borrow()).sin() * 0.15;
        cr.arc(cx, cy, r * 0.78, 0.0, 2.0 * std::f64::consts::PI);
        cr.set_source_rgba(0.0, 0.94, 1.0, pulse * 0.22);
        cr.fill().unwrap();

        // RKT text
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

        // Glow layer
        cr.set_source_rgba(0.0, 0.94, 1.0, 0.40);
        cr.set_font_size(r * 0.52);
        cr.move_to(tx, ty);
        cr.show_text(text).unwrap();

        // Solid layer
        cr.set_source_rgba(1.0, 1.0, 1.0, 1.0);
        cr.set_font_size(r * 0.48);
        cr.move_to(tx, ty);
        cr.show_text(text).unwrap();
    });

    let trigger = Rc::new(RefCell::new(0i64));

    let motion = EventControllerMotion::new();
    {
        let on_trigger = on_trigger.clone();
        let trigger2 = trigger.clone();
        motion.connect_enter(move |_: &gtk4::EventControllerMotion, _: f64, _: f64| {
            let now = gtk4::glib::monotonic_time();
            let mut t = trigger2.borrow_mut();
            if now - *t > 1_500_000 {
                *t = now;
                on_trigger();
            }
        });
    }
    da.add_controller(motion);

    let click = GestureClick::new();
    {
        let on_trigger = on_trigger.clone();
        click.connect_pressed(move |_: &GestureClick, _: i32, _: f64, _: f64| {
            on_trigger();
        });
    }
    da.add_controller(click);

    da
}
