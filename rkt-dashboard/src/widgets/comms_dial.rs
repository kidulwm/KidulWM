use gtk4::prelude::*;
use gtk4::{Box as GtkBox, DrawingArea, EventControllerMotion, GestureClick, Orientation};
use std::cell::RefCell;
use std::rc::Rc;
use std::time::Duration;

use crate::widgets::dial::{colour_for_pct, draw_centered_text};

#[derive(Clone, Default)]
pub struct CommsItem {
    pub label: String,
    pub value: String,
    pub source: String,
}

#[derive(Clone)]
pub struct CommsDialState {
    pub value: Rc<RefCell<f64>>, // 0.0 .. 1.0, drives ring/glowball colour
    pub items: Rc<RefCell<Vec<CommsItem>>>,
}

impl CommsDialState {
    pub fn new() -> Self {
        Self {
            value: Rc::new(RefCell::new(0.0)),
            items: Rc::new(RefCell::new(Vec::new())),
        }
    }
}

pub fn build(
    state: &CommsDialState,
    width: i32,
    height: i32,
    on_click: Box<dyn Fn(&str) + 'static>,
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
    let items_draw = state.items.clone();
    let hovered_draw = hovered.clone();

    da.set_draw_func(move |_, cr, w, h| {
        let w = w as f64;
        let h = h as f64;
        let cx = w / 2.0;
        let cy = h / 2.0;
        let r = cx.min(cy) * 0.82;
        let lw = (r * 0.05).max(2.0).min(4.0);

        let pct = (*value_draw.borrow()).clamp(0.0, 1.0);
        let sweep = pct * 270.0 * std::f64::consts::PI / 180.0;
        let start = 135.0 * std::f64::consts::PI / 180.0;

        let colour = colour_for_pct(pct, false);

        // Track arc (thin ring)
        cr.arc(
            cx,
            cy,
            r,
            start,
            start + 270.0 * std::f64::consts::PI / 180.0,
        );
        cr.set_source_rgba(1.0, 1.0, 1.0, 0.14);
        cr.set_line_width(lw);
        cr.set_line_cap(cairo::LineCap::Round);
        let _ = cr.stroke();

        // Position of the coloured ball on the ring
        let theta = start + sweep;
        let ball_x = cx + r * theta.cos();
        let ball_y = cy + r * theta.sin();
        let ball_r = (lw * 2.2).max(r * 0.10);

        let hover = *hovered_draw.borrow();

        // Permanent soft glow at the ball position
        let glow_r = ball_r * 1.75;
        let grad_glow = cairo::RadialGradient::new(ball_x, ball_y, 0.0, ball_x, ball_y, glow_r);
        grad_glow.add_color_stop_rgba(0.0, colour.0, colour.1, colour.2, 0.90);
        grad_glow.add_color_stop_rgba(0.30, colour.0, colour.1, colour.2, 0.40);
        grad_glow.add_color_stop_rgba(1.0, colour.0, colour.1, colour.2, 0.0);
        cr.arc(ball_x, ball_y, glow_r, 0.0, 2.0 * std::f64::consts::PI);
        cr.set_source(&grad_glow).unwrap();
        let _ = cr.fill();

        if hover {
            // The solid ball appears on hover
            let grad = cairo::RadialGradient::new(ball_x, ball_y, 0.0, ball_x, ball_y, ball_r);
            grad.add_color_stop_rgb(0.0, lighten(colour.0), lighten(colour.1), lighten(colour.2));
            grad.add_color_stop_rgb(0.6, colour.0, colour.1, colour.2);
            grad.add_color_stop_rgb(1.0, darken(colour.0), darken(colour.1), darken(colour.2));
            cr.arc(ball_x, ball_y, ball_r, 0.0, 2.0 * std::f64::consts::PI);
            cr.set_source(&grad).unwrap();
            let _ = cr.fill();
        }

        // Comms lines in the centre, each with a matching glowball
        let items = items_draw.borrow();
        if !items.is_empty() {
            let count = items.len();
            let line_h = (r * 0.30).max(18.0);
            let total_h = count as f64 * line_h;
            let start_y = cy - total_h / 2.0 + line_h / 2.0;
            let text_size = (r * 0.20).max(11.0);

            cr.select_font_face("Adwaita Sans", cairo::FontSlant::Normal, cairo::FontWeight::Bold);
            cr.set_font_size(text_size);

            for (i, item) in items.iter().enumerate() {
                let y = start_y + i as f64 * line_h;
                let full = format!("{}: {}", item.label, item.value);
                let extents = cr.text_extents(&full).expect("text_extents");
                let text_w = extents.width();
                let ball_r = (line_h * 0.18).max(3.5);
                let gap = ball_r * 1.4;
                let ball_cx = cx - text_w / 2.0 - gap;

                // Small glowball for this line, same colour as the ring ball
                let g_r = ball_r * 2.2;
                let grad = cairo::RadialGradient::new(ball_cx, y, 0.0, ball_cx, y, g_r);
                grad.add_color_stop_rgba(0.0, colour.0, colour.1, colour.2, 0.95);
                grad.add_color_stop_rgba(0.4, colour.0, colour.1, colour.2, 0.45);
                grad.add_color_stop_rgba(1.0, colour.0, colour.1, colour.2, 0.0);
                cr.arc(ball_cx, y, g_r, 0.0, 2.0 * std::f64::consts::PI);
                cr.set_source(&grad).unwrap();
                let _ = cr.fill();

                cr.arc(ball_cx, y, ball_r, 0.0, 2.0 * std::f64::consts::PI);
                cr.set_source_rgb(colour.0, colour.1, colour.2);
                let _ = cr.fill();

                // Label text
                draw_centered_text(
                    cr,
                    &full.to_lowercase(),
                    cx,
                    y,
                    text_size,
                    cairo::FontWeight::Bold,
                    (0.94, 0.94, 0.94, 0.72),
                );

                // Hover highlight bar behind active line
                if hover {
                    let my_top = y - line_h / 2.0;
                    let my_bottom = y + line_h / 2.0;
                    // Use cursor position if available; otherwise skip.
                    // We approximate by drawing nothing unless we know the line.
                    let _ = (my_top, my_bottom);
                }
            }
        }
    });

    // Click handling: figure out which line was hit
    {
        let click_items = state.items.clone();
        let click_value = state.value.clone();
        let click_da = da.clone();
        let gesture = GestureClick::new();
        gesture.connect_pressed(move |_: &GestureClick, _n: i32, x: f64, y: f64| {
            let items = click_items.borrow();
            if items.is_empty() {
                return;
            }
            // We need the same geometry used in the draw function. Approximate
            // using the current allocation. The drawing area size matches the
            // requested width/height but query the allocation to be safe.
            let alloc = click_da.allocation();
            let w = alloc.width() as f64;
            let h = alloc.height() as f64;
            let cx = w / 2.0;
            let cy = h / 2.0;
            let r = cx.min(cy) * 0.82;
            let line_h = (r * 0.30).max(18.0);
            let count = items.len();
            let total_h = count as f64 * line_h;
            let start_y = cy - total_h / 2.0;

            let rel_y = y - start_y;
            let idx = (rel_y / line_h).floor() as isize;
            if idx >= 0 && idx < items.len() as isize {
                let source = items[idx as usize].source.clone();
                if !source.is_empty() {
                    on_click(&source);
                }
            }
            let _ = click_value.clone(); // keep captured state alive
        });
        da.add_controller(gesture);
        da.set_cursor_from_name(Some("pointer"));
    }

    let da_ref = da.clone();
    gtk4::glib::source::timeout_add_local(Duration::from_millis(500), move || {
        da_ref.queue_draw();
        gtk4::glib::ControlFlow::Continue
    });

    bx
}

fn lighten(c: f64) -> f64 {
    (c + 0.25).min(1.0)
}

fn darken(c: f64) -> f64 {
    (c - 0.25).max(0.0)
}
