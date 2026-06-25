use gtk4::prelude::*;
use gtk4::{Box, DrawingArea, EventControllerMotion, EventControllerScroll, Orientation};
use std::cell::RefCell;
use std::rc::Rc;
use std::time::Duration;

use crate::config::WidgetCfg;

pub fn build(
    widget: &WidgetCfg,
    value: Rc<RefCell<f64>>,
    width: i32,
    height: i32,
    label_below: bool,
) -> Box {
    build_internal(widget, value, width, height, None, label_below)
}

pub fn build_interactive(
    widget: &WidgetCfg,
    value: Rc<RefCell<f64>>,
    width: i32,
    height: i32,
    target: &str,
    label_below: bool,
) -> (Box, Rc<RefCell<f64>>, f64, String) {
    let target = target.to_string();
    let max = widget.max.unwrap_or(100.0);
    let bx = build_internal(
        widget,
        value.clone(),
        width,
        height,
        Some(target.clone()),
        label_below,
    );
    (bx, value, max, target)
}

fn build_internal(
    widget: &WidgetCfg,
    value: Rc<RefCell<f64>>,
    width: i32,
    height: i32,
    scroll_target: Option<String>,
    label_below: bool,
) -> Box {
    let bx = Box::builder()
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
        .build();
    da.add_css_class("rkt-dial-face");

    let max = widget.max.unwrap_or(100.0).max(1.0);
    let label_text = widget.label.clone().unwrap_or_default();
    let reversed = label_text.eq_ignore_ascii_case("BAT");
    let suffix = widget.suffix.clone().unwrap_or_else(|| {
        if max == 100.0 {
            "%".to_string()
        } else {
            "".to_string()
        }
    });

    bx.append(&da);

    if scroll_target.is_some() {
        bx.set_tooltip_text(Some("Scroll up/down to adjust"));
        da.set_tooltip_text(Some("Scroll up/down to adjust"));
    } else {
        da.set_tooltip_text(Some(&label_text));
    }

    let hovered = Rc::new(RefCell::new(false));
    let value_draw = value.clone();
    let hovered_draw = hovered.clone();
    let label_below_draw = label_below;

    da.set_draw_func(move |_da, cr, _alloc_w, _alloc_h| {
        let w = width as f64;
        let h = height as f64;
        let cx = w / 2.0;
        let cy = h / 2.0;
        let r = cx.min(cy) * if label_below_draw { 0.90 } else { 0.82 };
        let lw = (r * 0.05).max(2.0).min(4.0); // very thin ring
        let large_dial = r > 40.0;

        let raw = *value_draw.borrow();
        let val = raw.clamp(0.0, max);
        let pct = (val / max).clamp(0.0, 1.0);
        let sweep = pct * 270.0 * std::f64::consts::PI / 180.0;
        let start = 135.0 * std::f64::consts::PI / 180.0;
        let hover = *hovered_draw.borrow();

        let colour = colour_for_pct(pct, reversed);

        // Track and value indicator ring. Large dials show three concentric arcs
        // that all move with the same value; small dials keep a single arc.
        if large_dial {
            let arc_count = 3;
            let full_arc = 270.0_f64.to_radians();
            for i in 0..arc_count {
                let ir = r * (1.0 - i as f64 * 0.11).max(0.60);
                let arc_lw = if i == 0 {
                    (lw * 1.2).max(1.5)
                } else if i == 1 {
                    lw
                } else {
                    (lw * 0.55).max(1.0)
                };
                let ball_r = if i == 0 {
                    (lw * 2.2).max(r * 0.10)
                } else {
                    (lw * (1.2 - i as f64 * 0.16)).max(r * (0.06 - i as f64 * 0.005))
                };
                let theta = start + sweep;
                let ball_x = cx + ir * theta.cos();
                let ball_y = cy + ir * theta.sin();
                let track_alpha = if i == 0 { 0.14 } else { 0.08 };

                cr.arc(cx, cy, ir, start, start + full_arc);
                cr.set_source_rgba(1.0, 1.0, 1.0, track_alpha);
                cr.set_line_width(arc_lw);
                cr.set_line_cap(cairo::LineCap::Round);
                let _ = cr.stroke();

                let glow_r = ball_r * 1.75;
                let grad_glow =
                    cairo::RadialGradient::new(ball_x, ball_y, 0.0, ball_x, ball_y, glow_r);
                grad_glow.add_color_stop_rgba(0.0, colour.0, colour.1, colour.2, 0.90);
                grad_glow.add_color_stop_rgba(0.35, colour.0, colour.1, colour.2, 0.40);
                grad_glow.add_color_stop_rgba(1.0, colour.0, colour.1, colour.2, 0.0);
                cr.arc(ball_x, ball_y, glow_r, 0.0, 2.0 * std::f64::consts::PI);
                cr.set_source(&grad_glow).unwrap();
                let _ = cr.fill();

                if hover {
                    let grad =
                        cairo::RadialGradient::new(ball_x, ball_y, 0.0, ball_x, ball_y, ball_r);
                    grad.add_color_stop_rgb(
                        0.0,
                        lighten(colour.0),
                        lighten(colour.1),
                        lighten(colour.2),
                    );
                    grad.add_color_stop_rgb(0.6, colour.0, colour.1, colour.2);
                    grad.add_color_stop_rgb(
                        1.0,
                        darken(colour.0),
                        darken(colour.1),
                        darken(colour.2),
                    );
                    cr.arc(ball_x, ball_y, ball_r, 0.0, 2.0 * std::f64::consts::PI);
                    cr.set_source(&grad).unwrap();
                    let _ = cr.fill();
                }
            }
        } else {
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

            let theta = start + sweep;
            let ball_x = cx + r * theta.cos();
            let ball_y = cy + r * theta.sin();
            let ball_r = (lw * 2.2).max(r * 0.10);

            let glow_r = ball_r * 1.75;
            let grad_glow = cairo::RadialGradient::new(ball_x, ball_y, 0.0, ball_x, ball_y, glow_r);
            grad_glow.add_color_stop_rgba(0.0, colour.0, colour.1, colour.2, 0.90);
            grad_glow.add_color_stop_rgba(0.30, colour.0, colour.1, colour.2, 0.40);
            grad_glow.add_color_stop_rgba(1.0, colour.0, colour.1, colour.2, 0.0);
            cr.arc(ball_x, ball_y, glow_r, 0.0, 2.0 * std::f64::consts::PI);
            cr.set_source(&grad_glow).unwrap();
            let _ = cr.fill();

            if hover {
                let grad = cairo::RadialGradient::new(ball_x, ball_y, 0.0, ball_x, ball_y, ball_r);
                grad.add_color_stop_rgb(
                    0.0,
                    lighten(colour.0),
                    lighten(colour.1),
                    lighten(colour.2),
                );
                grad.add_color_stop_rgb(0.6, colour.0, colour.1, colour.2);
                grad.add_color_stop_rgb(1.0, darken(colour.0), darken(colour.1), darken(colour.2));
                cr.arc(ball_x, ball_y, ball_r, 0.0, 2.0 * std::f64::consts::PI);
                cr.set_source(&grad).unwrap();
                let _ = cr.fill();
            }
        }

        // Center value (white, slightly smaller)
        let value_text = if suffix == "%" {
            format!("{:.0}%", pct * 100.0)
        } else if suffix.is_empty() {
            format!("{:.1}", val)
        } else {
            format!("{:.0}{}", val, suffix)
        };
        let value_size = if label_below_draw {
            (r * 0.58).max(14.0).min(17.0)
        } else if large_dial {
            (r * 0.44) * 0.6
        } else {
            r * 0.44
        };
        draw_centered_text(
            cr,
            &value_text,
            cx,
            cy - r * 0.02,
            value_size.max(10.0),
            cairo::FontWeight::Bold,
            (0.94, 0.94, 0.94, 0.65),
        );

        // Label text inline in the bottom gap, scaled by dial size
        let label_size = if label_below_draw {
            (r * 0.62).max(14.0).min(18.0)
        } else if large_dial {
            (r * 0.22).max(12.0)
        } else {
            (r * 0.52).max(20.0)
        };
        let label_y = if label_below_draw {
            h - label_size / 2.0 - 2.0
        } else {
            cy + r * 0.72
        };
        draw_centered_text(
            cr,
            &label_text.to_lowercase(),
            cx,
            label_y,
            label_size,
            cairo::FontWeight::Bold,
            (0.94, 0.94, 0.94, 0.55),
        );
    });

    // Hover handling
    let motion = EventControllerMotion::new();
    let enter_hovered = hovered.clone();
    let enter_bx = bx.clone();
    let enter_da = da.clone();
    motion.connect_enter(move |_ctrl, _x, _y| {
        *enter_hovered.borrow_mut() = true;
        enter_bx.add_css_class("active");
        enter_da.queue_draw();
    });
    let leave_hovered = hovered.clone();
    let leave_bx = bx.clone();
    let leave_da = da.clone();
    motion.connect_leave(move |_ctrl| {
        *leave_hovered.borrow_mut() = false;
        leave_bx.remove_css_class("active");
        leave_da.queue_draw();
    });
    da.add_controller(motion);

    // Scroll interaction and click-and-drag for VOL / BRT.
    if let Some(target) = scroll_target {
        let scroll_target_str = target.clone();
        let scroll = EventControllerScroll::new(gtk4::EventControllerScrollFlags::VERTICAL);
        scroll.set_propagation_phase(gtk4::PropagationPhase::Capture);
        let last = Rc::new(RefCell::new(0i64));
        let da_ref = da.clone();
        let value_scroll = value.clone();
        let max_scroll = max;
        scroll.connect_scroll(move |_: &gtk4::EventControllerScroll, _dx: f64, dy: f64| {
            let now = gtk4::glib::monotonic_time();
            let mut l = last.borrow_mut();
            if now - *l < 120_000 {
                return gtk4::glib::Propagation::Stop;
            }
            *l = now;

            let current = *value_scroll.borrow();
            let step = max_scroll * 0.05;
            let new_val = if dy > 0.0 {
                (current + step).min(max_scroll)
            } else {
                (current - step).max(0.0)
            };
            {
                let mut v = value_scroll.borrow_mut();
                *v = new_val;
            }
            apply_volume_brightness(&scroll_target_str, new_val);

            da_ref.queue_draw();
            gtk4::glib::Propagation::Stop
        });
        bx.add_controller(scroll);

        let target_drag = target.clone();
        let value_drag = value.clone();
        let width_drag = width;
        let height_drag = height;
        let da_drag = da.clone();
        let dragging = Rc::new(RefCell::new(false));
        let drag_start = Rc::new(RefCell::new((0.0f64, 0.0f64)));
        let last_ipc = Rc::new(RefCell::new(0i64));

        let drag = gtk4::GestureDrag::new();
        drag.set_button(gtk4::gdk::BUTTON_PRIMARY);

        let dragging_begin = dragging.clone();
        let drag_start_begin = drag_start.clone();
        drag.connect_drag_begin(move |gesture, x, y| {
            let w = width_drag as f64;
            let h = height_drag as f64;
            let cx = w / 2.0;
            let cy = h / 2.0;
            let r = cx.min(cy) * 0.82;
            let dx = x - cx;
            let dy = y - cy;
            let dist = (dx * dx + dy * dy).sqrt();
            if dist >= r * 0.4 && dist <= r * 1.45 {
                *dragging_begin.borrow_mut() = true;
                *drag_start_begin.borrow_mut() = (x, y);
                gesture.set_state(gtk4::EventSequenceState::Claimed);
            }
        });

        let dragging_update = dragging.clone();
        let drag_start_update = drag_start.clone();
        let value_update = value_drag.clone();
        let da_update = da_drag.clone();
        let target_update = target_drag.clone();
        let last_ipc_update = last_ipc.clone();
        drag.connect_drag_update(move |_gesture, offset_x, offset_y| {
            if !*dragging_update.borrow() {
                return;
            }
            let (sx, sy) = *drag_start_update.borrow();
            let x = sx + offset_x;
            let y = sy + offset_y;
            let w = width_drag as f64;
            let h = height_drag as f64;
            let cx = w / 2.0;
            let cy = h / 2.0;

            let start = 135.0 * std::f64::consts::PI / 180.0;
            let sweep = 270.0 * std::f64::consts::PI / 180.0;
            let two_pi = 2.0 * std::f64::consts::PI;

            let mut cursor_angle = (y - cy).atan2(x - cx);
            if cursor_angle < 0.0 {
                cursor_angle += two_pi;
            }
            let mut rel = cursor_angle - start;
            if rel < 0.0 {
                rel += two_pi;
            }
            let pct = (rel / sweep).clamp(0.0, 1.0);
            let new_val = pct * max;

            {
                let mut v = value_update.borrow_mut();
                *v = new_val;
            }
            da_update.queue_draw();

            let now = gtk4::glib::monotonic_time();
            let mut l = last_ipc_update.borrow_mut();
            if now - *l > 80_000 {
                *l = now;
                apply_volume_brightness(&target_update, new_val);
            }
        });

        let dragging_end = dragging.clone();
        let value_end = value_drag.clone();
        let da_end = da_drag.clone();
        let target_end = target_drag.clone();
        drag.connect_drag_end(move |_gesture, _offset_x, _offset_y| {
            if !*dragging_end.borrow() {
                return;
            }
            *dragging_end.borrow_mut() = false;
            let val = *value_end.borrow();
            apply_volume_brightness(&target_end, val);
            da_end.queue_draw();
        });

        da.add_controller(drag);
    }

    // Redraw loop
    let da_ref = da.clone();
    gtk4::glib::source::timeout_add_local(Duration::from_millis(200), move || {
        da_ref.queue_draw();
        gtk4::glib::ControlFlow::Continue
    });

    bx
}

pub fn draw_centered_text(
    cr: &cairo::Context,
    text: &str,
    cx: f64,
    cy: f64,
    size: f64,
    weight: cairo::FontWeight,
    rgba: (f64, f64, f64, f64),
) {
    cr.select_font_face("Adwaita Sans", cairo::FontSlant::Normal, weight);
    cr.set_font_size(size);
    let extents = cr.text_extents(text).expect("text_extents");
    cr.set_source_rgba(rgba.0, rgba.1, rgba.2, rgba.3);
    cr.move_to(
        cx - (extents.width() / 2.0 + extents.x_bearing()),
        cy - (extents.height() / 2.0 + extents.y_bearing()),
    );
    cr.show_text(text).expect("show_text");
}

pub fn colour_for_pct(pct: f64, reversed: bool) -> (f64, f64, f64) {
    let p = if reversed { 1.0 - pct } else { pct };
    // Stops: 0% teal, 9% blue, 45% purple, 90% burnt orange, 95% bright red
    let stops = [
        (0.00, (0.00, 1.00, 0.78)), // teal
        (0.09, (0.00, 0.94, 1.00)), // blue
        (0.45, (0.64, 0.35, 1.00)), // purple
        (0.90, (0.80, 0.33, 0.00)), // burnt orange
        (0.95, (1.00, 0.10, 0.10)), // bright red
        (1.00, (1.00, 0.10, 0.10)), // clamp red at top
    ];
    for window in stops.windows(2) {
        let (a, ca) = window[0];
        let (b, cb) = window[1];
        if p >= a && p <= b {
            let t = if b == a { 0.0 } else { (p - a) / (b - a) };
            return lerp_colour(ca, cb, t);
        }
    }
    stops[stops.len() - 1].1
}

fn lerp_colour(a: (f64, f64, f64), b: (f64, f64, f64), t: f64) -> (f64, f64, f64) {
    let tt = t.clamp(0.0, 1.0);
    (
        a.0 + (b.0 - a.0) * tt,
        a.1 + (b.1 - a.1) * tt,
        a.2 + (b.2 - a.2) * tt,
    )
}

fn lighten(c: f64) -> f64 {
    (c + 0.25).min(1.0)
}

fn darken(c: f64) -> f64 {
    (c - 0.25).max(0.0)
}

pub fn apply_volume_brightness(target: &str, val: f64) {
    let v = val.clamp(0.0, 100.0) as i32;
    match target {
        "volume" => {
            let _ = std::process::Command::new("pactl")
                .args(["set-sink-volume", "@DEFAULT_SINK@", &format!("{}%", v)])
                .spawn();
        }
        "brightness" => {
            let _ = std::process::Command::new("brightnessctl")
                .args(["set", &format!("{}%", v)])
                .spawn();
        }
        _ => {
            let action = if val >= 50.0 { "increase" } else { "decrease" };
            let _ = std::process::Command::new("qs")
                .args(["-c", "noctalia-shell", "ipc", "call", target, action])
                .spawn();
        }
    }
}
