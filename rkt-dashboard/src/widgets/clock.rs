use gtk4::prelude::*;
use gtk4::{Box, DrawingArea, EventControllerMotion, GestureClick, Label, Orientation};
use std::cell::RefCell;
use std::rc::Rc;
use std::time::Duration;

use gtk4::glib;

const RING_R: f64 = 0.0;
const RING_G: f64 = 0.94;
const RING_B: f64 = 1.0;

pub fn build(width: i32, height: i32) -> Box {
    let bx = Box::builder()
        .orientation(Orientation::Vertical)
        .spacing(6)
        .halign(gtk4::Align::Center)
        .valign(gtk4::Align::Center)
        .build();
    bx.add_css_class("rkt-clock-wrap");

    let da = DrawingArea::builder()
        .width_request(width)
        .height_request(height)
        .halign(gtk4::Align::Center)
        .valign(gtk4::Align::Center)
        .can_focus(false)
        .build();
    da.add_css_class("rkt-clock");

    let date_label = Label::new(None);
    date_label.add_css_class("rkt-clock-date");
    date_label.set_halign(gtk4::Align::Center);
    date_label.set_valign(gtk4::Align::Center);

    bx.append(&date_label);
    bx.append(&da);

    // Update date text now and every minute.
    fn update_date(label: &Label) {
        let now = glib::DateTime::now_local()
            .unwrap_or_else(|_| glib::DateTime::now_utc().expect("time"));
        label.set_label(&now.format("%a %d %b").unwrap_or_default().to_lowercase());
    }
    update_date(&date_label);
    let date_label_ref = date_label.clone();
    glib::source::timeout_add_local(Duration::from_secs(30), move || {
        update_date(&date_label_ref);
        glib::ControlFlow::Continue
    });

    let clock_hovered = Rc::new(RefCell::new(false));
    let clock_hovered_draw = clock_hovered.clone();

    da.set_draw_func(move |_, cr, w, h| {
        let cx = w as f64 / 2.0;
        let cy = h as f64 / 2.0;
        let r = cx.min(cy) * 0.78;
        let hover = *clock_hovered_draw.borrow();

        // Outer ring
        cr.arc(cx, cy, r, 0.0, 2.0 * std::f64::consts::PI);
        cr.set_source_rgba(RING_R, RING_G, RING_B, if hover { 0.75 } else { 0.55 });
        cr.set_line_width(2.0);
        let _ = cr.stroke();

        // Hour indices
        for i in 0..12 {
            let a = i as f64 * 30.0 * std::f64::consts::PI / 180.0;
            cr.move_to(cx + r * 0.85 * a.cos(), cy + r * 0.85 * a.sin());
            cr.line_to(cx + r * 0.96 * a.cos(), cy + r * 0.96 * a.sin());
        }
        cr.set_source_rgba(1.0, 1.0, 1.0, 0.8);
        cr.set_line_width(2.5);
        let _ = cr.stroke();

        // Time
        let now = glib::DateTime::now_local()
            .unwrap_or_else(|_| glib::DateTime::now_utc().expect("time"));
        let min = now.minute() as f64;
        let hr = (now.hour() % 12) as f64 + min / 60.0;

        let min_a = (min * 6.0 - 90.0) * std::f64::consts::PI / 180.0;
        let hr_a = (hr * 30.0 - 90.0) * std::f64::consts::PI / 180.0;

        // Hour + minute hands match the ring colour
        draw_hand(cr, cx, cy, hr_a, r * 0.52, 6.0, RING_R, RING_G, RING_B, 1.0);
        draw_hand(
            cr,
            cx,
            cy,
            min_a,
            r * 0.74,
            4.0,
            RING_R,
            RING_G,
            RING_B,
            1.0,
        );

        // Center cap
        cr.arc(cx, cy, 6.0, 0.0, 2.0 * std::f64::consts::PI);
        cr.set_source_rgba(RING_R, RING_G, RING_B, 1.0);
        let _ = cr.fill();

        if hover {
            cr.arc(cx, cy, r + 8.0, 0.0, 2.0 * std::f64::consts::PI);
            cr.set_source_rgba(RING_G, RING_B, RING_R, 0.12);
            cr.set_line_width(14.0);
            let _ = cr.stroke();
        }
    });

    let trigger = Rc::new(RefCell::new(0i64));

    let calendar_toggle = {
        let trigger = trigger.clone();
        move || {
            let now = glib::monotonic_time();
            let mut t = trigger.borrow_mut();
            if now - *t > 1_200_000 {
                *t = now;
                let _ = std::process::Command::new("qs")
                    .args(["-c", "noctalia-shell", "ipc", "call", "calendar", "toggle"])
                    .spawn();
            }
        }
    };

    let launcher_toggle = move || {
        let _ = std::process::Command::new("qs")
            .args(["-c", "noctalia-shell", "ipc", "call", "launcher", "toggle"])
            .spawn();
    };

    // Hover over the date opens the calendar and highlights the date.
    let date_hovered = Rc::new(RefCell::new(false));
    let date_motion = EventControllerMotion::new();
    let date_hovered_enter = date_hovered.clone();
    let date_da_enter = da.clone();
    let date_bx_enter = bx.clone();
    let on_date_enter = calendar_toggle.clone();
    date_motion.connect_enter(move |_, _, _| {
        *date_hovered_enter.borrow_mut() = true;
        date_bx_enter.add_css_class("active");
        date_da_enter.queue_draw();
        on_date_enter();
    });
    let date_hovered_leave = date_hovered.clone();
    let date_da_leave = da.clone();
    let date_bx_leave = bx.clone();
    date_motion.connect_leave(move |_| {
        *date_hovered_leave.borrow_mut() = false;
        date_bx_leave.remove_css_class("active");
        date_da_leave.queue_draw();
    });
    date_label.add_controller(date_motion);

    // Hover over the clock only affects the clock glow.
    let clock_motion = EventControllerMotion::new();
    let clock_hovered_enter = clock_hovered.clone();
    let clock_da_enter = da.clone();
    clock_motion.connect_enter(move |_, _, _| {
        *clock_hovered_enter.borrow_mut() = true;
        clock_da_enter.queue_draw();
    });
    let clock_hovered_leave = clock_hovered.clone();
    let clock_da_leave = da.clone();
    clock_motion.connect_leave(move |_| {
        *clock_hovered_leave.borrow_mut() = false;
        clock_da_leave.queue_draw();
    });
    da.add_controller(clock_motion);

    // Click the clock face to open the launcher.
    let click_clock = GestureClick::new();
    click_clock.connect_pressed(move |_: &GestureClick, _: i32, _: f64, _: f64| {
        launcher_toggle();
    });
    da.add_controller(click_clock);

    // Click the date to open the calendar.
    let click_date = GestureClick::new();
    click_date.connect_pressed(move |_: &GestureClick, _: i32, _: f64, _: f64| {
        calendar_toggle();
    });
    date_label.add_controller(click_date);

    let da_ref = da.clone();
    glib::source::timeout_add_local(Duration::from_millis(1000), move || {
        da_ref.queue_draw();
        glib::ControlFlow::Continue
    });

    bx
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
    let _ = cr.stroke();
}
