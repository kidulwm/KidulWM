use gtk4::prelude::*;
use gtk4::{Box as GtkBox, DrawingArea, EventControllerMotion, GestureClick, Label, Orientation};
use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;
use std::time::Duration;

use crate::widgets::dial::{colour_for_pct, draw_centered_text};
use librsvg_rebind::prelude::*;

// Soft company-colour palette for clock/weather glowballs and icons.
const SOFT_BLUE: (f64, f64, f64) = (0.42, 0.58, 0.88);
const SOFT_TURQUOISE: (f64, f64, f64) = (0.38, 0.78, 0.76);
const SOFT_PURPLE: (f64, f64, f64) = (0.55, 0.38, 0.75);

#[derive(Clone)]
pub struct InfoDialState {
    pub value: Rc<RefCell<f64>>, // outer hand / single value, 0.0 .. 1.0
    pub middle_value: Rc<RefCell<f64>>, // middle hand, 0.0 .. 1.0
    pub inner_value: Rc<RefCell<f64>>, // inner hand, 0.0 .. 1.0
    pub middle_ball_alpha: Rc<RefCell<f64>>, // 0.0 = transparent middle glowball
    pub multi_arc: Rc<RefCell<bool>>, // true for clock/weather 3-arc mode
    pub hands_full_circle: Rc<RefCell<bool>>, // true for analog 360° clock hands
    pub weather_layout: Rc<RefCell<bool>>, // weather-specific arc sizing
    pub center: Rc<RefCell<String>>,
    pub sub: Rc<RefCell<String>>,
    pub date: Rc<RefCell<String>>,
    pub icon: Rc<RefCell<String>>,
    pub detail: Rc<RefCell<String>>, // extra small line under center (e.g. weather low/high)
    pub icon_colour: Rc<RefCell<(f64, f64, f64)>>,
    pub colour_override: Rc<RefCell<Option<(f64, f64, f64)>>>,
}

impl InfoDialState {
    pub fn new() -> Self {
        Self {
            value: Rc::new(RefCell::new(0.0)),
            middle_value: Rc::new(RefCell::new(0.0)),
            inner_value: Rc::new(RefCell::new(0.0)),
            middle_ball_alpha: Rc::new(RefCell::new(1.0)),
            multi_arc: Rc::new(RefCell::new(false)),
            hands_full_circle: Rc::new(RefCell::new(false)),
            weather_layout: Rc::new(RefCell::new(false)),
            center: Rc::new(RefCell::new(String::new())),
            sub: Rc::new(RefCell::new(String::new())),
            date: Rc::new(RefCell::new(String::new())),
            icon: Rc::new(RefCell::new(String::new())),
            detail: Rc::new(RefCell::new(String::new())),
            icon_colour: Rc::new(RefCell::new((0.94, 0.94, 0.94))),
            colour_override: Rc::new(RefCell::new(None)),
        }
    }
}

pub fn build(
    state: &InfoDialState,
    width: i32,
    height: i32,
    on_click: Option<std::boxed::Box<dyn Fn() + 'static>>,
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

    // Bottom label sits outside the dial arcs so long text is not crowded inside them.
    let r_for_text = (width.min(height) as f64 / 2.0) * 0.76;
    let label_font_px = (r_for_text * 0.22).max(12.0).round() as i32;
    let info_css = format!(
        ".rkt-info-label-below {{ color: rgba(240, 240, 240, 0.55); font-size: {}px; font-weight: 700; }}",
        label_font_px
    );
    let info_provider = gtk4::CssProvider::new();
    info_provider.load_from_data(&info_css);
    if let Some(display) = gtk4::gdk::Display::default() {
        gtk4::style_context_add_provider_for_display(
            &display,
            &info_provider,
            gtk4::STYLE_PROVIDER_PRIORITY_USER,
        );
    }

    let bottom_label = Label::new(None);
    bottom_label.add_css_class("rkt-info-label-below");
    bottom_label.set_halign(gtk4::Align::Center);
    bottom_label.set_justify(gtk4::Justification::Center);
    bottom_label.set_visible(false);
    bx.append(&bottom_label);

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
    let middle_value_draw = state.middle_value.clone();
    let inner_value_draw = state.inner_value.clone();
    let middle_alpha_draw = state.middle_ball_alpha.clone();
    let multi_arc_draw = state.multi_arc.clone();
    let hands_full_circle_draw = state.hands_full_circle.clone();
    let weather_layout_draw = state.weather_layout.clone();
    let center_draw = state.center.clone();
    let icon_draw = state.icon.clone();
    let detail_draw = state.detail.clone();
    let icon_colour_draw = state.icon_colour.clone();
    let colour_override_draw = state.colour_override.clone();
    let hovered_draw = hovered.clone();

    da.set_draw_func(move |_, cr, w, h| {
        let w = w as f64;
        let h = h as f64;
        let cx = w / 2.0;
        let cy = h / 2.0;
        let multi_arc = *multi_arc_draw.borrow();
        let r = cx.min(cy) * if multi_arc { 0.76 } else { 0.82 };
        let lw = (r * 0.05).max(2.0).min(4.0);

        let hover = *hovered_draw.borrow();

        let pct = (*value_draw.borrow()).clamp(0.0, 1.0);
        let sweep = pct * 270.0 * std::f64::consts::PI / 180.0;
        let start = 135.0 * std::f64::consts::PI / 180.0;

        let colour = *colour_override_draw.borrow();
        let colour = colour.unwrap_or_else(|| colour_for_pct(pct, false));

        if *multi_arc_draw.borrow() {
            // Three-arc mode (clock / weather). Arcs stay as a 270° grey backdrop.
            // The clock uses full 360° hands; weather/others stay clamped to the
            // arc unless a value is negative or extreme.
            let full = 270.0_f64.to_radians();
            let twelve = -std::f64::consts::PI / 2.0; // 12 o'clock in Cairo coords
            let full_circle = *hands_full_circle_draw.borrow();
            let weather_layout = *weather_layout_draw.borrow();

            let hands = if weather_layout {
                // Outer = current (largest), middle = low, inner = high.
                [
                    (
                        *value_draw.borrow(),
                        SOFT_TURQUOISE,
                        *middle_alpha_draw.borrow(),
                        true,
                    ),
                    (*middle_value_draw.borrow(), SOFT_BLUE, 1.0, false),
                    (*inner_value_draw.borrow(), SOFT_PURPLE, 1.0, false),
                ]
            } else if full_circle {
                // Clock hands use company colours: blue (minute), turquoise (seconds), purple (hour).
                [
                    (*value_draw.borrow(), SOFT_BLUE, 1.0, true),
                    (
                        *middle_value_draw.borrow(),
                        SOFT_TURQUOISE,
                        *middle_alpha_draw.borrow(),
                        false,
                    ),
                    (*inner_value_draw.borrow(), SOFT_PURPLE, 1.0, true),
                ]
            } else {
                [
                    (pct, colour, 1.0, true),
                    (
                        *middle_value_draw.borrow(),
                        colour,
                        *middle_alpha_draw.borrow(),
                        false,
                    ),
                    (
                        *inner_value_draw.borrow(),
                        colour_for_pct((*inner_value_draw.borrow()).clamp(0.0, 1.0), false),
                        1.0,
                        true,
                    ),
                ]
            };

            let mut text_push: f64 = 0.0;

            for (i, (hand_pct, hand_colour, ball_alpha, strong_ball)) in hands.iter().enumerate() {
                let ir = r * (1.0 - i as f64 * 0.14).max(0.60);
                let arc_lw = if i == 0 {
                    (lw * 1.2).max(1.5)
                } else if i == 1 {
                    lw
                } else {
                    (lw * 0.55).max(1.0)
                };
                // Large ball on the outer arc, medium on the middle, small on the inner.
                // Clock dial makes the minute (outer) and hour (inner) hands the same
                // large size; weather dial makes the middle/current temp largest.
                let ball_r = if weather_layout {
                    (lw * 2.5).max(r * 0.11)
                } else if full_circle {
                    (lw * 2.5).max(r * 0.11)
                } else if i == 0 {
                    (lw * 2.5).max(r * 0.11)
                } else if i == 1 {
                    (lw * 1.5).max(r * 0.07)
                } else {
                    (lw * 0.9).max(r * 0.045)
                };

                let track_alpha = if i == 0 { 0.14 } else { 0.08 };

                // Grey reference arc.
                cr.arc(cx, cy, ir, start, start + full);
                cr.set_source_rgba(1.0, 1.0, 1.0, track_alpha);
                cr.set_line_width(arc_lw);
                cr.set_line_cap(cairo::LineCap::Round);
                let _ = cr.stroke();

                // Hand position. Clock hands sweep the full dial; temperature hands
                // stick to the 270° arc unless they go negative or above the max.
                let theta = if full_circle {
                    twelve + hand_pct * 2.0 * std::f64::consts::PI
                } else {
                    start + hand_pct * full
                };
                let ball_x = cx + ir * theta.cos();
                let ball_y = cy + ir * theta.sin();

                // Push the day/date text away from any glowing ball in the lower half.
                if *ball_alpha > 0.05 && full_circle {
                    let dx = ball_x - cx;
                    let dy = ball_y - cy;
                    if dy > r * 0.10 && dx > r * -0.10 {
                        text_push = text_push.max((dy - r * 0.10).min(r * 0.18));
                    }
                }

                if *ball_alpha > 0.05 && !(weather_layout && i == 2) {
                    let glow_r = ball_r * 1.75;
                    let grad_glow =
                        cairo::RadialGradient::new(ball_x, ball_y, 0.0, ball_x, ball_y, glow_r);
                    grad_glow.add_color_stop_rgba(
                        0.0,
                        hand_colour.0,
                        hand_colour.1,
                        hand_colour.2,
                        0.90 * ball_alpha,
                    );
                    grad_glow.add_color_stop_rgba(
                        0.35,
                        hand_colour.0,
                        hand_colour.1,
                        hand_colour.2,
                        0.40 * ball_alpha,
                    );
                    grad_glow.add_color_stop_rgba(
                        1.0,
                        hand_colour.0,
                        hand_colour.1,
                        hand_colour.2,
                        0.0,
                    );
                    cr.arc(ball_x, ball_y, glow_r, 0.0, 2.0 * std::f64::consts::PI);
                    cr.set_source(&grad_glow).unwrap();
                    let _ = cr.fill();
                }

                // Draw the daily high marker on the same middle arc as the low marker.
                if weather_layout && i == 1 {
                    let high_pct = (*inner_value_draw.borrow()).clamp(0.0, 1.0);
                    let high_theta = if full_circle {
                        twelve + high_pct * 2.0 * std::f64::consts::PI
                    } else {
                        start + high_pct * full
                    };
                    let hx = cx + ir * high_theta.cos();
                    let hy = cy + ir * high_theta.sin();
                    let glow_r = ball_r * 1.75;
                    let grad_glow = cairo::RadialGradient::new(hx, hy, 0.0, hx, hy, glow_r);
                    grad_glow.add_color_stop_rgba(
                        0.0,
                        SOFT_PURPLE.0,
                        SOFT_PURPLE.1,
                        SOFT_PURPLE.2,
                        0.90,
                    );
                    grad_glow.add_color_stop_rgba(
                        0.35,
                        SOFT_PURPLE.0,
                        SOFT_PURPLE.1,
                        SOFT_PURPLE.2,
                        0.40,
                    );
                    grad_glow.add_color_stop_rgba(
                        1.0,
                        SOFT_PURPLE.0,
                        SOFT_PURPLE.1,
                        SOFT_PURPLE.2,
                        0.0,
                    );
                    cr.arc(hx, hy, glow_r, 0.0, 2.0 * std::f64::consts::PI);
                    cr.set_source(&grad_glow).unwrap();
                    let _ = cr.fill();
                }

                // Clock/weather hands are glow-only; don't draw solid coloured bodies.
                if !full_circle && !weather_layout && (hover || *strong_ball) {
                    let alpha = if hover { 1.0 } else { *ball_alpha };
                    if alpha > 0.05 {
                        let grad =
                            cairo::RadialGradient::new(ball_x, ball_y, 0.0, ball_x, ball_y, ball_r);
                        grad.add_color_stop_rgb(
                            0.0,
                            lighten(hand_colour.0),
                            lighten(hand_colour.1),
                            lighten(hand_colour.2),
                        );
                        grad.add_color_stop_rgb(0.6, hand_colour.0, hand_colour.1, hand_colour.2);
                        grad.add_color_stop_rgb(
                            1.0,
                            darken(hand_colour.0),
                            darken(hand_colour.1),
                            darken(hand_colour.2),
                        );
                        cr.arc(ball_x, ball_y, ball_r, 0.0, 2.0 * std::f64::consts::PI);
                        cr.set_source(&grad).unwrap();
                        let _ = cr.fill();
                    }
                }
            }

            // Center text.
            let center_text = center_draw.borrow().clone();
            let detail_text = detail_draw.borrow().clone();
            if !center_text.is_empty() {
                let value_size = (r * 0.44) * 0.6;
                let cy_offset = if detail_text.is_empty() {
                    -r * 0.02
                } else {
                    -r * 0.12
                };
                draw_centered_text(
                    cr,
                    &center_text,
                    cx,
                    cy + cy_offset,
                    value_size.max(10.0),
                    cairo::FontWeight::Bold,
                    (0.94, 0.94, 0.94, 0.65),
                );
            }

            if !detail_text.is_empty() {
                let value_size = (r * 0.44) * 0.6;
                let detail_size = value_size * 0.68;
                draw_centered_text(
                    cr,
                    &detail_text,
                    cx,
                    cy + r * 0.16,
                    detail_size.max(10.0),
                    cairo::FontWeight::Normal,
                    (0.88, 0.88, 0.88, 0.48),
                );
            }

            // Weather icon sits in the bottom arc gap; allowed to slightly overlap arcs.
            let icon_key = icon_draw.borrow().clone();
            if !icon_key.is_empty() {
                let (ir, ig, ib) = *icon_colour_draw.borrow();
                let icon_size = (r * 1.16).max(72.0);
                draw_svg_icon(cr, &icon_key, icon_size, (ir, ig, ib), cx, cy + r * 0.84);
            }
        } else {
            // Single-arc fallback.
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

            let center_text = center_draw.borrow().clone();
            if !center_text.is_empty() {
                let value_size = (r * 0.44) * 0.6;
                draw_centered_text(
                    cr,
                    &center_text,
                    cx,
                    cy - r * 0.02,
                    value_size.max(10.0),
                    cairo::FontWeight::Bold,
                    (0.94, 0.94, 0.94, 0.65),
                );
            }
        }
    });

    if let Some(cb) = on_click {
        let click = GestureClick::new();
        click.connect_pressed(move |_: &GestureClick, _: i32, _: f64, _: f64| {
            cb();
        });
        da.add_controller(click);
        da.set_cursor_from_name(Some("pointer"));
    }

    let da_ref = da.clone();
    gtk4::glib::source::timeout_add_local(Duration::from_millis(250), move || {
        da_ref.queue_draw();
        gtk4::glib::ControlFlow::Continue
    });

    // Remove inline sub/date drawing; sync them to the external label instead.
    let sub_label = state.sub.clone();
    let date_label = state.date.clone();
    gtk4::glib::source::timeout_add_local(Duration::from_millis(250), move || {
        let sub = sub_label.borrow().clone();
        let date = date_label.borrow().clone();
        let text = if sub.is_empty() && date.is_empty() {
            String::new()
        } else {
            format!("{} {}", sub, date).trim().to_string()
        };
        if text.is_empty() {
            bottom_label.set_visible(false);
        } else {
            bottom_label.set_text(&text);
            bottom_label.set_visible(true);
        }
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

thread_local! {
    static SVG_CACHE: RefCell<HashMap<String, Rc<cairo::ImageSurface>>> =
        RefCell::new(HashMap::new());
}

fn icon_path_for(key: &str) -> Option<std::path::PathBuf> {
    let file = format!("{}.svg", key);
    let mut candidates: Vec<std::path::PathBuf> = Vec::new();

    // 1) cwd/assets/icons (useful when running from the project root).
    candidates.push(std::path::PathBuf::from("assets/icons").join(&file));

    // 2) Walk up from the binary location.
    if let Ok(exe) = std::env::current_exe() {
        for dir in exe.ancestors() {
            candidates.push(dir.join("assets/icons").join(&file));
        }
    }

    // 3) System install location.
    candidates.push(std::path::PathBuf::from("/usr/share/rkt-dashboard/assets/icons").join(&file));

    candidates.into_iter().find(|p| p.exists())
}

fn render_svg_to_surface(path: &str, size: i32) -> Option<Rc<cairo::ImageSurface>> {
    let handle = librsvg_rebind::Handle::from_file(path).ok()?;
    let surface = cairo::ImageSurface::create(cairo::Format::ARgb32, size, size).ok()?;
    let ctx = cairo::Context::new(&surface).ok()?;
    ctx.set_source_rgba(0.0, 0.0, 0.0, 0.0);
    ctx.set_operator(cairo::Operator::Source);
    let _ = ctx.paint();
    ctx.set_operator(cairo::Operator::Over);
    let viewport = librsvg_rebind::Rectangle::new(0.0, 0.0, size as f64, size as f64);
    handle.render_document(&ctx, &viewport).ok()?;
    Some(Rc::new(surface))
}

fn get_or_render_surface(path: &str, size: i32) -> Option<Rc<cairo::ImageSurface>> {
    let cache_key = format!("{}@{}", path, size);
    SVG_CACHE.with(|cache| {
        let cache_ref = cache.borrow();
        if let Some(surface) = cache_ref.get(&cache_key) {
            return Some(surface.clone());
        }
        drop(cache_ref);
        let surface = render_svg_to_surface(path, size)?;
        cache.borrow_mut().insert(cache_key, surface.clone());
        Some(surface)
    })
}

fn draw_svg_icon(
    cr: &cairo::Context,
    key: &str,
    size: f64,
    colour: (f64, f64, f64),
    cx: f64,
    cy: f64,
) {
    let size = size.round() as i32;
    if size <= 0 {
        return;
    }
    let Some(path) = icon_path_for(key) else {
        return;
    };
    let path_str = path.to_string_lossy().to_string();

    let (_w, _h, x, y) = if let Some(surface) = get_or_render_surface(&path_str, size) {
        let w = surface.width() as f64;
        let h = surface.height() as f64;
        (w, h, cx - w / 2.0, cy - h / 2.0)
    } else {
        return;
    };

    // Weather icons are split: translucent company-colour fill, grey outline.
    if key.starts_with("rkt-icon-weather-")
        && !key.ends_with("-fill.svg")
        && !key.ends_with("-stroke.svg")
    {
        let fill_key = format!("{}-fill", key);
        let stroke_key = format!("{}-stroke", key);
        if let Some(fill_path) = icon_path_for(&fill_key) {
            if let Some(fill_surface) = get_or_render_surface(&fill_path.to_string_lossy(), size) {
                cr.set_source_rgb(colour.0, colour.1, colour.2);
                let _ = cr.mask_surface(&*fill_surface, x, y);
            }
        }
        if let Some(stroke_path) = icon_path_for(&stroke_key) {
            if let Some(stroke_surface) =
                get_or_render_surface(&stroke_path.to_string_lossy(), size)
            {
                // Arc-track grey: white at ~18% alpha.
                cr.set_source_rgba(1.0, 1.0, 1.0, 0.18);
                let _ = cr.mask_surface(&*stroke_surface, x, y);
            }
        }
        return;
    }

    // Fallback / non-weather: draw the whole icon in one colour.
    let Some(surface) = get_or_render_surface(&path_str, size) else {
        return;
    };
    cr.set_source_rgb(colour.0, colour.1, colour.2);
    let _ = cr.mask_surface(&*surface, x, y);
}

pub fn make_clickable_label(
    text: &str,
    css_class: &str,
    on_click: std::boxed::Box<dyn Fn() + 'static>,
) -> GtkBox {
    let bx = GtkBox::builder()
        .orientation(Orientation::Vertical)
        .spacing(4)
        .build();
    bx.add_css_class(css_class);

    let label = Label::new(Some(text));
    label.set_wrap(true);
    label.set_max_width_chars(18);
    label.set_justify(gtk4::Justification::Center);
    label.add_css_class("rkt-right-label");
    bx.append(&label);

    let motion = EventControllerMotion::new();
    let bx_enter = bx.clone();
    motion.connect_enter(move |_, _, _| {
        bx_enter.add_css_class("active");
    });
    let bx_leave = bx.clone();
    motion.connect_leave(move |_| {
        bx_leave.remove_css_class("active");
    });
    bx.add_controller(motion);

    let click = GestureClick::new();
    click.connect_pressed(move |_: &GestureClick, _: i32, _: f64, _: f64| {
        on_click();
    });
    bx.add_controller(click);
    bx.set_cursor_from_name(Some("pointer"));

    bx
}
