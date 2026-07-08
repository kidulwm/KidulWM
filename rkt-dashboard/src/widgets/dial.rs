use gtk4::prelude::*;
use gtk4::{Box, DrawingArea, EventControllerMotion, EventControllerScroll, Label, Orientation};
use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

use crate::config::WidgetCfg;

pub const DIAL_TEXT: (f64, f64, f64) = (148.0 / 255.0, 142.0 / 255.0, 123.0 / 255.0);

static IPC_OVERRIDES: OnceLock<Mutex<HashMap<String, Vec<String>>>> = OnceLock::new();

pub fn set_ipc_override(target: &str, cmd: Vec<String>) {
    let map = IPC_OVERRIDES.get_or_init(|| Mutex::new(HashMap::new()));
    if let Ok(mut m) = map.lock() {
        m.insert(target.to_string(), cmd);
    }
}

fn ipc_command_for(target: &str) -> Option<Vec<String>> {
    let map = IPC_OVERRIDES.get_or_init(|| Mutex::new(HashMap::new()));
    map.lock().ok()?.get(target).cloned()
}

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
    let is_mini = widget.dial_style.as_deref() == Some("mini");
    let hide_value_draw = widget.hide_value;
    let reversed = label_text.eq_ignore_ascii_case("BAT");
    let suffix = widget.suffix.clone().unwrap_or_else(|| {
        if max == 100.0 {
            "%".to_string()
        } else {
            "".to_string()
        }
    });

    bx.append(&da);

    let _label_below_widget = if label_below {
        let lbl = Label::new(Some(&label_text.to_lowercase()));
        lbl.add_css_class("rkt-dial-label-below");
        lbl.set_halign(gtk4::Align::Center);
        lbl.set_justify(gtk4::Justification::Center);
        bx.append(&lbl);
        Some(lbl)
    } else {
        None
    };

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
        let r = cx.min(cy) * if label_below_draw { 0.86 } else { 0.82 };
        let lw = (r * 0.05).max(2.0).min(4.0); // very thin ring
        let large_dial = r > 40.0;

        let raw = *value_draw.borrow();
        let val = raw.clamp(0.0, max);
        let pct = (val / max).clamp(0.0, 1.0);
        let sweep = pct * 270.0 * std::f64::consts::PI / 180.0;
        let start = 135.0 * std::f64::consts::PI / 180.0;
        let hover = *hovered_draw.borrow();

        let colour = colour_for_pct(pct, reversed);
        let mini = is_mini;
        let hide_value = hide_value_draw;

        let track_colour = (0.92, 0.86, 0.72);

        // Track and value indicator ring. Large dials and mini dials show six concentric arcs.
        if large_dial || mini {
            let arc_count = 6;
            let full_arc = 360.0_f64.to_radians();
            for i in 0..arc_count {
                let ir = r * (1.0 - i as f64 * 0.08).max(0.55);
                let arc_lw = if i == 0 {
                    (lw * 1.6).max(2.0)
                } else {
                    (lw * (1.3 - i as f64 * 0.18)).max(1.0)
                };

                // Single glowball on the arc just inside the outer ring (i == 1).
                if i == 1 {
                    let theta = if mini {
                        start + pct * full_arc
                    } else {
                        start + sweep
                    };
                    let ball_x = cx + ir * theta.cos();
                    let ball_y = cy + ir * theta.sin();
                    let ball_r = if mini {
                        (lw * 2.0).max(r * 0.11)
                    } else {
                        (lw * 2.5).max(r * 0.11)
                    };

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

                let gap_trim = 0.0;
                let track_alpha = if i == 0 {
                    // Outer arc: much more transparent.
                    0.08
                } else {
                    0.10 - i as f64 * 0.005
                };

                let (arc_start, arc_end) = if mini {
                    (0.0, full_arc)
                } else {
                    let max_sweep = 270.0_f64.to_radians();
                    let extra = (full_arc - max_sweep) / 2.0;
                    (
                        start - extra + gap_trim,
                        start + max_sweep + extra - gap_trim,
                    )
                };

                cr.arc(cx, cy, ir, arc_start, arc_end);
                cr.set_source_rgba(track_colour.0, track_colour.1, track_colour.2, track_alpha);
                cr.set_line_width(arc_lw);
                cr.set_line_cap(cairo::LineCap::Round);
                let _ = cr.stroke();
            }
        } else {
            // Small dial: two concentric arcs. Outer is thicker, inner is the old size.
            let radii = [r, r * 0.78];
            let lws = [(lw * 1.4).max(2.0), lw];
            for i in 0..2 {
                let ir = radii[i];
                let arc_lw = lws[i];
                let track_alpha = if i == 0 { 0.14 } else { 0.08 };

                cr.arc(
                    cx,
                    cy,
                    ir,
                    start,
                    start + 270.0 * std::f64::consts::PI / 180.0,
                );
                cr.set_source_rgba(1.0, 1.0, 1.0, track_alpha);
                cr.set_line_width(arc_lw);
                cr.set_line_cap(cairo::LineCap::Round);
                let _ = cr.stroke();

                let theta = start + sweep;
                let ball_x = cx + ir * theta.cos();
                let ball_y = cy + ir * theta.sin();
                let ball_r = if i == 0 {
                    (lw * 2.5).max(r * 0.11)
                } else {
                    (lw * 1.5).max(r * 0.07)
                };

                let glow_r = ball_r * 1.75;
                let grad_glow =
                    cairo::RadialGradient::new(ball_x, ball_y, 0.0, ball_x, ball_y, glow_r);
                grad_glow.add_color_stop_rgba(0.0, colour.0, colour.1, colour.2, 0.90);
                grad_glow.add_color_stop_rgba(0.30, colour.0, colour.1, colour.2, 0.40);
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
        }

        // Center value text, unless the dial is configured to hide it.
        let value_text = if suffix == "%" {
            format!("{:.0}%", pct * 100.0)
        } else if suffix.is_empty() {
            format!("{:.1}", val)
        } else {
            format!("{:.0}{}", val, suffix)
        };
        if !hide_value {
            let value_size = if label_below_draw {
                (r * 0.58).max(14.0).min(17.0)
            } else if large_dial || mini {
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
                (DIAL_TEXT.0, DIAL_TEXT.1, DIAL_TEXT.2, 0.65),
            );
        }

        // Label text. When label_below is enabled, it is drawn in a real Label widget
        // beneath the dial, not inside the arc square. For large/mini dials place the
        // label in the centre; for other small dials keep it low inside the dial.
        if !label_below_draw {
            let label_size = if large_dial || mini {
                if hide_value {
                    (r * 0.45).max(14.0)
                } else {
                    (r * 0.24).max(12.0)
                }
            } else {
                (r * 0.52).max(20.0)
            };
            let label_y = if large_dial || mini {
                if hide_value {
                    cy + r * 0.02
                } else {
                    cy + r * 0.24
                }
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
                (DIAL_TEXT.0, DIAL_TEXT.1, DIAL_TEXT.2, 0.70),
            );
        }
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

const FONT_FAMILY: &str = "FantasqueSansM Nerd Font";

pub fn draw_centered_text(
    cr: &cairo::Context,
    text: &str,
    cx: f64,
    cy: f64,
    size: f64,
    weight: cairo::FontWeight,
    rgba: (f64, f64, f64, f64),
) {
    cr.select_font_face(FONT_FAMILY, cairo::FontSlant::Normal, weight);
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
            if let Some(cmd) = ipc_command_for(target) {
                let _ = std::process::Command::new(&cmd[0]).args(&cmd[1..]).spawn();
            } else {
                let action = if val >= 50.0 { "increase" } else { "decrease" };
                let _ = std::process::Command::new("qs")
                    .args(["-c", "compositor-shell", "ipc", "call", target, action])
                    .spawn();
            }
        }
    }
}
