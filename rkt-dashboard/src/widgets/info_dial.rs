use gtk4::prelude::*;
use gtk4::{Box as GtkBox, DrawingArea, EventControllerMotion, GestureClick, Label, Orientation};
use std::cell::RefCell;
use std::rc::Rc;
use std::time::Duration;

use crate::widgets::dial::{colour_for_pct, draw_centered_text};

#[derive(Clone)]
pub struct InfoDialState {
    pub value: Rc<RefCell<f64>>, // 0.0 .. 1.0
    pub center: Rc<RefCell<String>>,
    pub sub: Rc<RefCell<String>>,
    pub date: Rc<RefCell<String>>,
    pub colour_override: Rc<RefCell<Option<(f64, f64, f64)>>>,
}

impl InfoDialState {
    pub fn new() -> Self {
        Self {
            value: Rc::new(RefCell::new(0.0)),
            center: Rc::new(RefCell::new(String::new())),
            sub: Rc::new(RefCell::new(String::new())),
            date: Rc::new(RefCell::new(String::new())),
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
    let center_draw = state.center.clone();
    let sub_draw = state.sub.clone();
    let date_draw = state.date.clone();
    let colour_override_draw = state.colour_override.clone();
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

        let colour = *colour_override_draw.borrow();
        let colour = colour.unwrap_or_else(|| colour_for_pct(pct, false));

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

        // Center text: scale proportionally with the dial. The previous
        // logical-pixel "large dial" threshold made physically smaller laptop
        // dials use *bigger* proportional fonts than the 4K screen.
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

        // Sub-label
        let sub_text = sub_draw.borrow().clone();
        if !sub_text.is_empty() {
            let label_size = (r * 0.22).max(12.0);
            draw_centered_text(
                cr,
                &sub_text.to_lowercase(),
                cx,
                cy + r * 0.72,
                label_size,
                cairo::FontWeight::Bold,
                (0.94, 0.94, 0.94, 0.55),
            );
        }

        // Date label under the day
        let date_text = date_draw.borrow().clone();
        if !date_text.is_empty() {
            let label_size = (r * 0.17).max(10.0);
            draw_centered_text(
                cr,
                &date_text.to_lowercase(),
                cx,
                cy + r * 0.96,
                label_size,
                cairo::FontWeight::Bold,
                (0.94, 0.94, 0.94, 0.45),
            );
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
