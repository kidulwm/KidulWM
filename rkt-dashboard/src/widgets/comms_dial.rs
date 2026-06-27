use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;
use std::time::Duration;

use gtk4::prelude::*;
use gtk4::{Box as GtkBox, DrawingArea, EventControllerMotion, GestureClick, Orientation};

use crate::widgets::dial::draw_centered_text;
use crate::widgets::info_dial::draw_svg_icon;

#[derive(Clone, Default)]
pub struct CommsItem {
    pub label: String,
    pub value: String,
    pub source: String,
}

#[derive(Clone)]
pub struct CommsDialState {
    pub value: Rc<RefCell<f64>>, // overall normalised urgency (0..1)
    pub items: Rc<RefCell<Vec<CommsItem>>>, // top 3 display items (kept for compatibility)
    pub raw_counts: Rc<RefCell<HashMap<String, i64>>>,
    pub news_keys: Rc<RefCell<Vec<String>>>,
    pub source_pcts: Rc<RefCell<Vec<(String, f64)>>>, // per-source urgency
    pub snapshot: Rc<RefCell<HashMap<String, serde_json::Value>>>, // full panel data dump
}

impl CommsDialState {
    pub fn new() -> Self {
        Self {
            value: Rc::new(RefCell::new(0.0)),
            items: Rc::new(RefCell::new(Vec::new())),
            raw_counts: Rc::new(RefCell::new(HashMap::new())),
            news_keys: Rc::new(RefCell::new(Vec::new())),
            source_pcts: Rc::new(RefCell::new(Vec::new())),
            snapshot: Rc::new(RefCell::new(HashMap::new())),
        }
    }
}

pub fn build(
    state: &CommsDialState,
    width: i32,
    height: i32,
    on_click: Box<dyn Fn() + 'static>,
) -> GtkBox {
    let bx = GtkBox::builder()
        .orientation(Orientation::Vertical)
        .spacing(0)
        .halign(gtk4::Align::Center)
        .valign(gtk4::Align::Center)
        .build();
    bx.add_css_class("rkt-dial");

    let da = DrawingArea::builder()
        .width_request(width)
        .height_request(height)
        .halign(gtk4::Align::Center)
        .valign(gtk4::Align::Center)
        .can_focus(false)
        .can_target(true)
        .build();
    da.add_css_class("rkt-dial-face");

    bx.append(&da);

    let hovered = Rc::new(RefCell::new(false));

    let motion = EventControllerMotion::new();
    {
        let enter_hovered = hovered.clone();
        let enter_bx = bx.clone();
        let enter_da = da.clone();
        motion.connect_enter(move |_, _, _| {
            *enter_hovered.borrow_mut() = true;
            enter_bx.add_css_class("active");
            enter_da.queue_draw();
        });
    }
    {
        let leave_hovered = hovered.clone();
        let leave_bx = bx.clone();
        let leave_da = da.clone();
        motion.connect_leave(move |_| {
            *leave_hovered.borrow_mut() = false;
            leave_bx.remove_css_class("active");
            leave_da.queue_draw();
        });
    }
    da.add_controller(motion);

    let value_draw = state.value.clone();
    let source_pcts_draw = state.source_pcts.clone();
    let hovered_draw = hovered.clone();

    da.set_draw_func(move |_, cr, w, h| {
        let w = w as f64;
        let h = h as f64;
        let cx = w / 2.0;
        let cy = h / 2.0;
        let r = cx.min(cy) * 0.82;
        let lw = (r * 0.05).max(2.0).min(4.0);
        let pi = std::f64::consts::PI;
        let hover = *hovered_draw.borrow();

        // Urgency colour based on the current value.
        let value = (*value_draw.borrow()).clamp(0.0, 1.0);
        let ball_colour = if value > 0.8 {
            (0.85, 0.22, 0.22) // urgent red
        } else if value > 0.5 {
            (0.85, 0.45, 0.18) // warning orange
        } else if value > 0.0 {
            (0.2, 0.6, 0.75) // bob blue
        } else {
            (0.55, 0.55, 0.6) // quiet grey
        };

        // Six full 360° reference arcs; the single glowball sits on i = 1.
        let arc_count = 6;
        let ball_ir = r * (1.0 - 1.0_f64 * 0.08).max(0.55);
        for i in 0..arc_count {
            let ir = r * (1.0 - i as f64 * 0.08).max(0.55);
            let arc_lw = if i == 0 {
                (lw * 1.6).max(2.0)
            } else {
                (lw * (1.3 - i as f64 * 0.18)).max(1.0)
            };
            let track_alpha = if i == 0 {
                0.14
            } else {
                (0.08 - i as f64 * 0.005).max(0.02)
            };

            cr.arc(cx, cy, ir, 0.0, 2.0 * pi);
            cr.set_source_rgba(1.0, 1.0, 1.0, track_alpha);
            cr.set_line_width(arc_lw);
            cr.set_line_cap(cairo::LineCap::Round);
            let _ = cr.stroke();
        }

        // Single glowball on the second ring, rotating with total urgency.
        let ball_r = (lw * 2.5).max(r * 0.11);
        let theta = value * 2.0 * pi - pi / 2.0; // 12 o'clock = quiet, clockwise = more
        let ball_x = cx + ball_ir * theta.cos();
        let ball_y = cy + ball_ir * theta.sin();
        let glow_r = ball_r * 1.75;
        let grad_glow = cairo::RadialGradient::new(ball_x, ball_y, 0.0, ball_x, ball_y, glow_r);
        grad_glow.add_color_stop_rgba(0.0, ball_colour.0, ball_colour.1, ball_colour.2, 0.90);
        grad_glow.add_color_stop_rgba(0.35, ball_colour.0, ball_colour.1, ball_colour.2, 0.40);
        grad_glow.add_color_stop_rgba(1.0, ball_colour.0, ball_colour.1, ball_colour.2, 0.0);
        cr.arc(ball_x, ball_y, glow_r, 0.0, 2.0 * pi);
        cr.set_source(&grad_glow).unwrap();
        let _ = cr.fill();

        // Soft halo behind the centre Bob logo when hovered.
        if hover {
            let halo_r = r * 0.55;
            let halo = cairo::RadialGradient::new(cx, cy, r * 0.15, cx, cy, halo_r);
            halo.add_color_stop_rgba(0.0, ball_colour.0, ball_colour.1, ball_colour.2, 0.30);
            halo.add_color_stop_rgba(0.6, ball_colour.0, ball_colour.1, ball_colour.2, 0.08);
            halo.add_color_stop_rgba(1.0, ball_colour.0, ball_colour.1, ball_colour.2, 0.0);
            cr.arc(cx, cy, halo_r, 0.0, 2.0 * pi);
            cr.set_source(&halo).unwrap();
            let _ = cr.fill();
        }

        // Centre Bob logo.
        let icon_size = (r * 0.90).max(64.0);
        draw_svg_icon(
            cr,
            "rkt-icon-media-bob",
            icon_size,
            (0.85, 0.85, 0.85),
            cx,
            cy,
        );

        // Optional tiny unread count under the icon.
        if value > 0.0 {
            // source_pcts gives us raw counts; total them for a small badge.
            let total: i64 = source_pcts_draw
                .borrow()
                .iter()
                .map(|(_, p)| (p * 100.0).round() as i64)
                .sum();
            if total > 0 {
                draw_centered_text(
                    cr,
                    &format!("{}", total.min(99)),
                    cx,
                    cy + r * 0.08,
                    (r * 0.14).max(11.0),
                    cairo::FontWeight::Bold,
                    (0.35, 0.35, 0.4, 0.55),
                );
            }
        }
    });

    let gesture = GestureClick::new();
    gesture.connect_pressed(move |_: &GestureClick, _: i32, _: f64, _: f64| {
        on_click();
    });
    da.add_controller(gesture);
    da.set_cursor_from_name(Some("pointer"));

    let da_ref = da.clone();
    gtk4::glib::source::timeout_add_local(Duration::from_millis(500), move || {
        da_ref.queue_draw();
        gtk4::glib::ControlFlow::Continue
    });

    bx
}
