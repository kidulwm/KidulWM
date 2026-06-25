use std::collections::HashMap;

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
    pub value: Rc<RefCell<f64>>, // overall max value (0..1)
    pub items: Rc<RefCell<Vec<CommsItem>>>,
    pub raw_counts: Rc<RefCell<HashMap<String, i64>>>,
    pub news_keys: Rc<RefCell<Vec<String>>>,
    pub source_pcts: Rc<RefCell<Vec<(String, f64)>>>, // per-source 0..1 for colour + arc/ball
}

impl CommsDialState {
    pub fn new() -> Self {
        Self {
            value: Rc::new(RefCell::new(0.0)),
            items: Rc::new(RefCell::new(Vec::new())),
            raw_counts: Rc::new(RefCell::new(HashMap::new())),
            news_keys: Rc::new(RefCell::new(Vec::new())),
            source_pcts: Rc::new(RefCell::new(Vec::new())),
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
    let hovered_line = Rc::new(RefCell::new(None));

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
        let leave_hovered_line = hovered_line.clone();
        motion.connect_leave(move |_| {
            *leave_hovered.borrow_mut() = false;
            *leave_hovered_line.borrow_mut() = None;
            leave_bx.remove_css_class("active");
            leave_da.queue_draw();
        });
    }
    {
        let move_hovered_line = hovered_line.clone();
        let move_da = da.clone();
        let move_items = state.items.clone();
        motion.connect_motion(move |_, _x, y| {
            let alloc = move_da.allocation();
            let w = alloc.width() as f64;
            let h = alloc.height() as f64;
            let cx = w / 2.0;
            let cy = h / 2.0;
            let r = cx.min(cy) * 0.82;
            let line_h = (r * 0.30).max(18.0);
            let items_len = std::cmp::max(move_items.borrow().len(), 1);
            let total_h = items_len as f64 * line_h;
            let start_y = cy - total_h / 2.0;
            let rel_y = y - start_y;
            let idx = (rel_y / line_h).floor() as isize;
            let new_idx = if idx >= 0 && idx < items_len as isize {
                Some(idx as usize)
            } else {
                None
            };
            let changed = *move_hovered_line.borrow() != new_idx;
            if changed {
                *move_hovered_line.borrow_mut() = new_idx;
                move_da.queue_draw();
            }
        });
    }
    da.add_controller(motion);

    let items_draw = state.items.clone();
    let source_pcts_draw = state.source_pcts.clone();
    let hovered_draw = hovered.clone();
    let hovered_line_draw = hovered_line.clone();

    da.set_draw_func(move |_, cr, w, h| {
        let w = w as f64;
        let h = h as f64;
        let cx = w / 2.0;
        let cy = h / 2.0;
        let r = cx.min(cy) * 0.82;
        let lw = (r * 0.05).max(2.0).min(4.0);
        let pi = std::f64::consts::PI;
        let sweep = 270.0 * pi / 180.0;
        let start = 135.0 * pi / 180.0;

        let source_pcts = source_pcts_draw.borrow();
        let items = items_draw.borrow();
        let hover = *hovered_draw.borrow();

        // Per-source lookup.
        let src_pct = |src: &str| -> f64 {
            source_pcts
                .iter()
                .find(|(k, _)| k == src)
                .map(|(_, p)| *p)
                .unwrap_or(0.0)
                .clamp(0.0, 1.0)
        };

        // Three concentric arcs: the top item sits on the outer ring, the rest inside.
        // The outer arc uses the full outer radius and gets the biggest glowball.
        for (i, item) in items.iter().take(3).enumerate() {
            let spct = src_pct(&item.source);
            let src_colour = colour_for_pct(spct, false);
            let ir = r * (1.0 - i as f64 * 0.14).max(0.60);
            let arc_lw = if i == 0 {
                (lw * 1.2).max(1.5)
            } else if i == 1 {
                lw
            } else {
                (lw * 0.55).max(1.0)
            };
            let ball_r = if i == 0 {
                (lw * 2.2).max(r * 0.11)
            } else {
                (lw * (1.3 - i as f64 * 0.18)).max(r * (0.07 - i as f64 * 0.005))
            };
            let theta = start + spct * sweep;
            let ball_x = cx + ir * theta.cos();
            let ball_y = cy + ir * theta.sin();
            let track_alpha = if i == 0 { 0.14 } else { 0.08 };

            // Track arc for this source.
            cr.arc(cx, cy, ir, start, start + sweep);
            cr.set_source_rgba(1.0, 1.0, 1.0, track_alpha);
            cr.set_line_width(arc_lw);
            cr.set_line_cap(cairo::LineCap::Round);
            let _ = cr.stroke();

            // Soft glow around the ball.
            let glow_r = ball_r * 1.75;
            let grad_glow = cairo::RadialGradient::new(ball_x, ball_y, 0.0, ball_x, ball_y, glow_r);
            grad_glow.add_color_stop_rgba(0.0, src_colour.0, src_colour.1, src_colour.2, 0.90);
            grad_glow.add_color_stop_rgba(0.35, src_colour.0, src_colour.1, src_colour.2, 0.40);
            grad_glow.add_color_stop_rgba(1.0, src_colour.0, src_colour.1, src_colour.2, 0.0);
            cr.arc(ball_x, ball_y, glow_r, 0.0, 2.0 * pi);
            cr.set_source(&grad_glow).unwrap();
            let _ = cr.fill();

            if hover {
                // Solid ball on dial hover.
                let grad = cairo::RadialGradient::new(ball_x, ball_y, 0.0, ball_x, ball_y, ball_r);
                grad.add_color_stop_rgb(
                    0.0,
                    lighten(src_colour.0),
                    lighten(src_colour.1),
                    lighten(src_colour.2),
                );
                grad.add_color_stop_rgb(0.6, src_colour.0, src_colour.1, src_colour.2);
                grad.add_color_stop_rgb(
                    1.0,
                    darken(src_colour.0),
                    darken(src_colour.1),
                    darken(src_colour.2),
                );
                cr.arc(ball_x, ball_y, ball_r, 0.0, 2.0 * pi);
                cr.set_source(&grad).unwrap();
                let _ = cr.fill();
            }
        }

        // Three media-name labels in the centre; no per-line glowballs.
        if !items.is_empty() {
            let count = items.len().min(3);
            let line_h = (r * 0.32).max(18.0);
            let total_h = count as f64 * line_h;
            let start_y = cy - total_h / 2.0 + line_h / 2.0;
            let text_size = (r * 0.22).max(11.0);

            cr.select_font_face(
                "Adwaita Sans",
                cairo::FontSlant::Normal,
                cairo::FontWeight::Bold,
            );
            cr.set_font_size(text_size);

            for (i, item) in items.iter().take(3).enumerate() {
                let y = start_y + i as f64 * line_h;
                let spct = src_pct(&item.source);
                let src_colour = colour_for_pct(spct, false);
                let full = if item.value.is_empty() {
                    item.label.clone()
                } else {
                    format!("{}: {}", item.label, item.value)
                };
                let extents = cr.text_extents(&full).expect("text_extents");
                let text_w = extents.width();
                let line_hovered = hover && *hovered_line_draw.borrow() == Some(i);

                if line_hovered {
                    // Subtle highlight pill behind the active line.
                    let pad_x = text_size * 1.4;
                    let pad_y = line_h * 0.12;
                    cr.set_source_rgba(src_colour.0, src_colour.1, src_colour.2, 0.10);
                    cr.rectangle(
                        cx - text_w / 2.0 - pad_x,
                        y - line_h / 2.0 + pad_y,
                        text_w + pad_x * 2.0,
                        line_h - pad_y * 2.0,
                    );
                    let _ = cr.fill();
                }

                // Label text only.
                let label_alpha = if line_hovered { 0.95 } else { 0.72 };
                draw_centered_text(
                    cr,
                    &full.to_lowercase(),
                    cx,
                    y,
                    text_size,
                    cairo::FontWeight::Bold,
                    (0.94, 0.94, 0.94, label_alpha),
                );
            }
        }
    });

    // Click handling: figure out which line was hit.
    {
        let click_items = state.items.clone();
        let click_da = da.clone();
        let gesture = GestureClick::new();
        gesture.connect_pressed(move |_: &GestureClick, _n: i32, _x: f64, y: f64| {
            let items = click_items.borrow();
            if items.is_empty() {
                return;
            }
            let alloc = click_da.allocation();
            let w = alloc.width() as f64;
            let h = alloc.height() as f64;
            let cx = w / 2.0;
            let cy = h / 2.0;
            let r = cx.min(cy) * 0.82;
            let line_h = (r * 0.30).max(18.0);
            let count = items.len().min(3);
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
