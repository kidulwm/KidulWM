use gtk4::prelude::*;
use gtk4::{
    Box as GtkBox, DragSource, DrawingArea, DropTarget, EventControllerMotion,
    EventControllerScroll, EventControllerScrollFlags, Orientation, Overlay, ScrolledWindow,
};
use std::cell::RefCell;
use std::path::PathBuf;
use std::rc::{Rc, Weak};
use std::time::Duration;

use crate::config::{Config, WidgetCfg};
use crate::panel_data::fetch_panel_data;
use crate::panels::right::right_dial_size;
use crate::usb_guard::{build_usb_widget, spawn_usb_updater};
use crate::widgets;
use crate::widgets::info_dial::make_clickable_label;
use crate::Values;

fn create_transparent_icon(width: i32, height: i32) -> gtk4::gdk::Texture {
    let w = width.max(1);
    let h = height.max(1);
    let mut surface = cairo::ImageSurface::create(cairo::Format::ARgb32, w, h)
        .expect("transparent drag icon surface");
    let cr = cairo::Context::new(&surface).expect("transparent drag icon context");
    cr.set_source_rgba(0.0, 0.0, 0.0, 0.0);
    cr.paint().unwrap();
    drop(cr);
    surface.flush();
    let data = surface.data().unwrap().to_vec();
    let bytes = gtk4::glib::Bytes::from(&data);
    gtk4::gdk::MemoryTexture::new(
        w,
        h,
        gtk4::gdk::MemoryFormat::B8g8r8a8Premultiplied,
        &bytes,
        w as usize * 4,
    )
    .upcast::<gtk4::gdk::Texture>()
}

const DEFAULT_ORDER: &[&str] = &["gpu_temp", "cpu_temp", "mem_pct", "disk_pct"];

const ORDER_DIR: &str = ".config/rkt-dashboard";
const ORDER_FILE: &str = "dial-order.json";

#[derive(Clone)]
struct DialDef {
    id: &'static str,
    label: &'static str,
    max: f64,
    suffix: &'static str,
}

fn dial_defs() -> Vec<DialDef> {
    vec![
        DialDef {
            id: "cpu",
            label: "CPU",
            max: 100.0,
            suffix: "%",
        },
        DialDef {
            id: "mem_pct",
            label: "MEM",
            max: 100.0,
            suffix: "%",
        },
        DialDef {
            id: "load",
            label: "LD",
            max: 4.0,
            suffix: "",
        },
        DialDef {
            id: "cpu_temp",
            label: "CPU",
            max: 100.0,
            suffix: "°C",
        },
        DialDef {
            id: "gpu_temp",
            label: "GPU",
            max: 100.0,
            suffix: "°C",
        },
        DialDef {
            id: "cpu_freq",
            label: "FREQ",
            max: 5000.0,
            suffix: "MHz",
        },
        DialDef {
            id: "disk_pct",
            label: "DISK",
            max: 100.0,
            suffix: "%",
        },
        DialDef {
            id: "swap_pct",
            label: "SWAP",
            max: 100.0,
            suffix: "%",
        },
        DialDef {
            id: "fan_rpm",
            label: "FAN",
            max: 5000.0,
            suffix: "RPM",
        },
        DialDef {
            id: "power_w",
            label: "PWR",
            max: 200.0,
            suffix: "W",
        },
    ]
}

fn order_path() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    let mut p = PathBuf::from(home);
    p.push(ORDER_DIR);
    p.push(ORDER_FILE);
    p
}

fn load_order() -> Vec<String> {
    let defs: Vec<&str> = dial_defs().iter().map(|d| d.id).collect();
    let mut order = std::fs::read_to_string(order_path())
        .ok()
        .and_then(|data| serde_json::from_str::<Vec<String>>(&data).ok())
        .unwrap_or_default();
    for id in DEFAULT_ORDER {
        if !order.iter().any(|s| s == *id) && defs.contains(id) {
            order.push(id.to_string());
        }
    }
    order.retain(|s| defs.contains(&s.as_str()));
    if order.is_empty() {
        DEFAULT_ORDER.iter().map(|s| s.to_string()).collect()
    } else {
        order
    }
}

fn save_order(order: &[String]) {
    let path = order_path();
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let _ = std::fs::write(
        path,
        serde_json::to_string_pretty(order).unwrap_or_default(),
    );
}

pub fn build_left(cfg: &Config, values: &Values, monitor_height: i32) -> GtkBox {
    let cfg = std::sync::Arc::new(cfg.clone());
    #[derive(Clone, Copy, PartialEq, Eq)]
    enum Highlight {
        None,
        Hover,
        Dragging,
        DropBefore,
        DropAfter,
    }

    let drag_snapshot: Rc<RefCell<Option<Vec<String>>>> = Rc::new(RefCell::new(None));

    let (_base_large, base_small, base_catchy, spacing, small_spacing) = if monitor_height < 1300 {
        (120, 55, 55, 6, 6)
    } else if monitor_height < 1800 {
        (140, 65, 65, 8, 6)
    } else {
        (160, 75, 80, 10, 8)
    };

    let avail_width = cfg.left.width - 24;

    let max_small_by_width = (avail_width - small_spacing) / 2;
    let small_size = ((base_small as f64 * 1.35) as i32)
        .min(max_small_by_width)
        .max(base_small);
    let catchy_h = (small_size.min(base_catchy + 15) as f64 * 1.7) as i32;

    let small_widget_h = |s: i32| s + 28;

    // CachyOS logo lives at the top; small dials live at the bottom.
    let top_logo_h = (catchy_h as f64 * 0.81) as i32;

    let large_size = ((right_dial_size(cfg.left.width)
        .min((monitor_height / 4) - 20)
        .max(120)) as f64
        * 0.75) as i32;

    let rkt_width = avail_width;

    let top_h = top_logo_h + spacing;
    let tight_spacing = 2;
    let bottom_h = small_widget_h(small_size) + tight_spacing + spacing;

    let bx = GtkBox::builder()
        .orientation(Orientation::Vertical)
        .spacing(spacing)
        .margin_top(24)
        .margin_bottom(0)
        .margin_start(12)
        .margin_end(12)
        .build();
    bx.add_css_class("rkt-panel");

    // Top fixed section: logo + optional widgets. Kept transparent.
    let top_box = GtkBox::builder()
        .orientation(Orientation::Vertical)
        .spacing(spacing)
        .build();
    top_box.set_height_request(top_h);

    let control_trigger: Rc<dyn Fn()> = {
        let cfg = std::sync::Arc::clone(&cfg);
        Rc::new(move || {
            if let Some(cmd) = cfg.left.control_center_command.as_deref() {
                if let Some(prog) = cmd.first() {
                    let _ = std::process::Command::new(prog).args(&cmd[1..]).spawn();
                }
            }
        })
    };
    let logo = cfg
        .left
        .logo_path
        .as_deref()
        .unwrap_or("assets/control-center-logo.png");
    let catchy_logo = widgets::logo::build(
        rkt_width,
        top_logo_h,
        control_trigger,
        Some(logo),
        Some(("CONTROL", "CENTER")),
    );
    catchy_logo.set_halign(gtk4::Align::Center);
    top_box.append(&catchy_logo);

    let left_width = cfg.left.width;
    for w in &cfg.left.widgets {
        if let Some(child) = build_widget(w, left_width, values) {
            top_box.append(&child);
        }
    }
    // Spacer positions the logo so its vertical centre matches the right clock.
    let right_clock_h = (right_dial_size(cfg.left.width)
        .min((monitor_height / 4) - 20)
        .max(120) as f64
        * 0.85) as i32;
    let right_clock_center_y = 8 + right_clock_h / 2; // right panel margin_top is 8
    let logo_spacer_h = (right_clock_center_y - 24 - spacing - top_logo_h / 2).max(0);

    let logo_spacer = GtkBox::builder()
        .orientation(Orientation::Vertical)
        .height_request(logo_spacer_h)
        .build();
    bx.append(&logo_spacer);
    // Security line sits just under the top logo.
    let sec_font_px = 17;
    let sec_css = format!(
        ".rkt-security-label {{ color: #948e7b; font-size: {}px; }} \
         .rkt-security-label.warning {{ color: rgba(255,95,70,0.95); }}",
        sec_font_px
    );
    let sec_provider = gtk4::CssProvider::new();
    sec_provider.load_from_data(&sec_css);
    if let Some(display) = gtk4::gdk::Display::default() {
        gtk4::style_context_add_provider_for_display(
            &display,
            &sec_provider,
            gtk4::STYLE_PROVIDER_PRIORITY_USER,
        );
    }

    let security_widget = {
        let cfg = std::sync::Arc::clone(&cfg);
        make_clickable_label(
            "security: …",
            "rkt-right-widget",
            Box::new(move || {
                if let Some(cmd) = cfg.left.terminal_command.as_deref() {
                    if let Some(prog) = cmd.first() {
                        let profile = cfg.left.security_profile.as_deref().unwrap_or("default");
                        let mut c = std::process::Command::new(prog);
                        c.args(&cmd[1..]);
                        let _shell = cfg.left.shell_command.as_deref().unwrap_or("sh -c");
                        c.arg(format!(
                            "hermes -p {} chat -q 'Run a fresh security scan now and print a one-line summary.'; read -P 'Press Enter to close'",
                            profile
                        ));
                        let _ = c.spawn();
                    }
                }
            }),
        )
    };
    security_widget.set_halign(gtk4::Align::Center);

    let sec_label = {
        let sec_label = security_widget
            .first_child()
            .and_downcast::<gtk4::Label>()
            .expect("security line label");
        sec_label.add_css_class("rkt-security-label");
        sec_label.set_text("security: …");
        sec_label.clone()
    };

    bx.append(&top_box);
    bx.append(&security_widget);

    // ── USB guard, just under the security line ──
    let (usb_box, usb_label, usb_entry, usb_state) = build_usb_widget();
    bx.append(&usb_box);
    spawn_usb_updater(usb_label, usb_state, usb_box, usb_entry);

    // Equal expanders above/below the dial block keep it centred between the logo/security-usb block and the bottom dials.
    let top_spacer = GtkBox::builder()
        .orientation(Orientation::Vertical)
        .vexpand(true)
        .build();
    let bottom_spacer = GtkBox::builder()
        .orientation(Orientation::Vertical)
        .vexpand(true)
        .build();

    // Middle: large-dial pager. Viewport is exactly four slots tall.
    // The .rkt-dial CSS adds 8px top + 8px bottom padding, so each slot is
    // the dial height plus that padding plus the box spacing between dials.
    let dial_padding_v = 16;
    let slot_h = large_size + dial_padding_v + spacing;
    let visible_h = 4 * (large_size + dial_padding_v) + 3 * spacing;
    let scroll = ScrolledWindow::builder()
        .hscrollbar_policy(gtk4::PolicyType::Never)
        .vscrollbar_policy(gtk4::PolicyType::External)
        .focusable(false)
        .can_focus(false)
        .hexpand(true)
        .vexpand(false)
        .valign(gtk4::Align::Fill)
        .height_request(visible_h)
        .build();
    scroll.set_kinetic_scrolling(false);
    scroll.add_css_class("rkt-large-dials-scroll");

    let vadj = scroll.vadjustment();
    vadj.set_step_increment(slot_h as f64);
    vadj.set_page_increment(slot_h as f64);

    let dial_box = GtkBox::builder()
        .orientation(Orientation::Vertical)
        .spacing(spacing)
        .valign(gtk4::Align::Start)
        .build();
    dial_box.add_css_class("rkt-large-dials-box");

    // Capture wheel/trackpad scroll on the dial box. Accumulate wheel units and
    // move exactly one slot per unit, so wheels step cleanly while trackpads can
    // still build up to a slot smoothly.
    let dial_scroll = EventControllerScroll::new(EventControllerScrollFlags::VERTICAL);
    dial_scroll.set_propagation_phase(gtk4::PropagationPhase::Capture);
    let vadj_scroll = vadj.clone();
    let slot_scroll = slot_h as f64;
    let accum_scroll: Rc<RefCell<f64>> = Rc::new(RefCell::new(0.0));
    dial_scroll.connect_scroll(move |_ctrl, _dx, dy| {
        let mut a = accum_scroll.borrow_mut();
        *a += dy;
        if a.abs() >= 1.0 {
            let adj = &vadj_scroll;
            let steps = a.trunc();
            *a -= steps;
            let direction = steps.signum();
            let new_val = (adj.value() + direction * slot_scroll)
                .max(adj.lower())
                .min((adj.upper() - adj.page_size()).max(adj.lower()));
            adj.set_value(new_val);
        }
        gtk4::glib::Propagation::Stop
    });
    dial_box.add_controller(dial_scroll);

    let order: Rc<RefCell<Vec<String>>> = Rc::new(RefCell::new(load_order()));
    let defs = dial_defs();

    // True while a dial is being dragged; suppresses hover previews on other dials.
    let is_dragging: Rc<RefCell<bool>> = Rc::new(RefCell::new(false));

    // Rebuild closure: repopulates dial_box with current order and re-attaches DnD.
    let rebuild: Rc<RefCell<Box<dyn Fn()>>> = Rc::new(RefCell::new(Box::new(|| {})));
    {
        let rebuild_weak: Weak<RefCell<Box<dyn Fn()>>> = Rc::downgrade(&rebuild);
        let dial_box_ref = dial_box.clone();
        let order_ref = order.clone();
        let values_ref = values.clone();
        let defs_ref = defs.clone();
        let scroll_ref = scroll.clone();
        let snapshot_ref = drag_snapshot.clone();
        let dragging_ref = is_dragging.clone();

        *rebuild.borrow_mut() = Box::new(move || {
            while let Some(child) = dial_box_ref.first_child() {
                dial_box_ref.remove(&child);
            }

            let current = order_ref.borrow().clone();
            for (idx, id) in current.iter().enumerate() {
                let drag_idx = idx;
                let def = match defs_ref.iter().find(|d| d.id == *id) {
                    Some(d) => d,
                    None => continue,
                };
                let Some(val) = value_for(id, &values_ref) else {
                    continue;
                };
                if *val.borrow() < 0.0 {
                    continue; // sensor unavailable
                }

                let cfg = WidgetCfg {
                    id: format!("{}-dial", def.id),
                    ty: "dial".to_string(),
                    label: Some(def.label.to_string()),
                    source: Some(def.id.to_string()),
                    max: Some(def.max),
                    suffix: Some(def.suffix.to_string()),
                    hide_value: false,
                    dial_style: None,
                    extra: Default::default(),
                };
                let dial = widgets::dial::build(&cfg, val, large_size, large_size, false);
                dial.set_halign(gtk4::Align::Center);

                // Shared highlight state for this dial's overlay border.
                let highlight: Rc<RefCell<Highlight>> = Rc::new(RefCell::new(Highlight::None));

                let border_da = DrawingArea::builder()
                    .can_target(false)
                    .hexpand(false)
                    .vexpand(false)
                    .halign(gtk4::Align::Fill)
                    .valign(gtk4::Align::Fill)
                    .build();
                let hl_draw = highlight.clone();
                border_da.set_draw_func(move |_, cr, w, h| match *hl_draw.borrow() {
                    Highlight::Hover => {
                        let c = 12.0_f64.min(w as f64 * 0.18).min(h as f64 * 0.18);
                        cr.move_to(c, 0.0);
                        cr.line_to((w as f64) - c, 0.0);
                        cr.line_to(w as f64, c);
                        cr.line_to(w as f64, (h as f64) - c);
                        cr.line_to((w as f64) - c, h as f64);
                        cr.line_to(c, h as f64);
                        cr.line_to(0.0, (h as f64) - c);
                        cr.line_to(0.0, c);
                        cr.close_path();
                        cr.set_source_rgba(0.0, 0.94, 1.0, 0.75);
                        cr.set_line_width(2.0);
                        let _ = cr.stroke();
                    }
                    // Dragging, DropBefore and DropAfter are kept in the enum but rendered
                    // transparent so the drag still works without visual clutter.
                    _ => {}
                });

                let overlay = Overlay::builder().valign(gtk4::Align::Center).build();
                overlay.set_child(Some(&dial));
                overlay.set_widget_name(&def.id);
                overlay.add_overlay(&border_da);

                // Drag source.
                let drag_source = DragSource::new();
                drag_source.set_actions(gtk4::gdk::DragAction::MOVE);
                let dial_drag_source = dial.clone();
                let snapshot_begin = snapshot_ref.clone();
                let order_begin = order_ref.clone();
                let hl_drag_begin = highlight.clone();
                let bd_drag_begin = border_da.clone();
                let dragging_begin = dragging_ref.clone();
                drag_source.connect_drag_begin(move |source, _drag| {
                    *dragging_begin.borrow_mut() = true;
                    *snapshot_begin.borrow_mut() = Some(order_begin.borrow().clone());
                    *hl_drag_begin.borrow_mut() = Highlight::Dragging;
                    bd_drag_begin.queue_draw();
                    dial_drag_source.add_css_class("dragging");
                    dial_drag_source.set_cursor_from_name(Some("grabbing"));
                    // Invisible drag surface: same size as the dial to cover GTK's default green icon.
                    let icon = create_transparent_icon(
                        dial_drag_source.width(),
                        dial_drag_source.height(),
                    );
                    source.set_icon(
                        Some(&icon),
                        (large_size / 2) as i32,
                        (large_size / 2) as i32,
                    );
                });
                drag_source.connect_prepare(move |_, _, _| {
                    let value = gtk4::glib::Value::from(drag_idx as i32);
                    Some(gtk4::gdk::ContentProvider::for_value(&value))
                });
                let snapshot_end = snapshot_ref.clone();
                let order_end = order_ref.clone();
                let rebuild_end = rebuild_weak.clone();
                let dial_drag_end = dial.clone();
                let hl_drag_end = highlight.clone();
                let bd_drag_end = border_da.clone();
                let dragging_end = dragging_ref.clone();
                drag_source.connect_drag_end(move |_, _, _| {
                    *dragging_end.borrow_mut() = false;
                    *hl_drag_end.borrow_mut() = Highlight::None;
                    bd_drag_end.queue_draw();
                    dial_drag_end.remove_css_class("dragging");
                    dial_drag_end.set_cursor_from_name(Some("grab"));
                    if let Some(snap) = snapshot_end.borrow_mut().take() {
                        *order_end.borrow_mut() = snap;
                        if let Some(r) = rebuild_end.upgrade() {
                            (*r.borrow())();
                        }
                    }
                });
                dial.set_cursor_from_name(Some("grab"));
                dial.add_controller(drag_source);

                // Drop target: top half inserts before, bottom half inserts after.
                let drop_target = DropTarget::new(i32::static_type(), gtk4::gdk::DragAction::MOVE);
                let drop_idx = idx;
                let order_drop = order_ref.clone();
                let rebuild_drop = rebuild_weak.clone();
                let snapshot_drop = snapshot_ref.clone();
                drop_target.connect_drop(move |target, value, _x, y| {
                    *snapshot_drop.borrow_mut() = None;
                    let dragged_idx = value.get::<i32>().unwrap_or(-1) as usize;
                    if dragged_idx == usize::MAX || dragged_idx == drop_idx {
                        return false;
                    }
                    let alloc = target.widget().unwrap().allocation();
                    let before = y < alloc.height() as f64 / 2.0;
                    {
                        let mut o = order_drop.borrow_mut();
                        if dragged_idx < o.len() {
                            let item = o.remove(dragged_idx);
                            let mut insert_at = if before { drop_idx } else { drop_idx + 1 };
                            if dragged_idx < insert_at {
                                insert_at -= 1;
                            }
                            let insert_at = insert_at.min(o.len());
                            o.insert(insert_at, item);
                            save_order(&o);
                        }
                    }
                    if let Some(r) = rebuild_drop.upgrade() {
                        (*r.borrow())();
                    }
                    true
                });

                // Hover highlight.
                let motion = EventControllerMotion::new();
                let hl_motion_enter = highlight.clone();
                let bd_motion_enter = border_da.clone();
                let dragging_hover = dragging_ref.clone();
                motion.connect_enter(move |_, _, _| {
                    if !*dragging_hover.borrow() && *hl_motion_enter.borrow() == Highlight::None {
                        *hl_motion_enter.borrow_mut() = Highlight::Hover;
                        bd_motion_enter.queue_draw();
                    }
                });
                let hl_motion_leave = highlight.clone();
                let bd_motion_leave = border_da.clone();
                motion.connect_leave(move |_| {
                    if *hl_motion_leave.borrow() == Highlight::Hover {
                        *hl_motion_leave.borrow_mut() = Highlight::None;
                        bd_motion_leave.queue_draw();
                    }
                });
                dial.add_controller(motion);

                // Auto-scroll when dragging near the viewport edges, and update insertion preview.
                let scroll_drag = scroll_ref.clone();
                let vadj_drag = vadj.clone();
                let slot_scroll_drag = slot_h as f64;
                let hl_motion_drop = highlight.clone();
                let bd_motion_drop = border_da.clone();
                let auto_scroll_id: Rc<RefCell<Option<gtk4::glib::SourceId>>> =
                    Rc::new(RefCell::new(None));
                drop_target.connect_motion(move |target, _x, y| {
                    // Don't show a drop preview on the dial that is currently being dragged.
                    if *hl_motion_drop.borrow() == Highlight::Dragging {
                        return gtk4::gdk::DragAction::MOVE;
                    }
                    let alloc = target.widget().unwrap().allocation();
                    let widget = target.widget().unwrap();
                    let before = y < alloc.height() as f64 / 2.0;
                    let new_hl = if before {
                        Highlight::DropBefore
                    } else {
                        Highlight::DropAfter
                    };
                    if *hl_motion_drop.borrow() != new_hl {
                        *hl_motion_drop.borrow_mut() = new_hl;
                        bd_motion_drop.queue_draw();
                    }

                    let scroll = &scroll_drag;
                    if let Some(pt) =
                        widget.compute_point(scroll, &gtk4::graphene::Point::new(0.0, 0.0))
                    {
                        let scroll_h = scroll.allocation().height() as f64;
                        let edge = 44.0;
                        let dial_h = alloc.height() as f64;
                        let y = pt.y() as f64;
                        let near_top = y < edge;
                        let near_bottom = y + dial_h > scroll_h - edge;

                        if near_top || near_bottom {
                            if auto_scroll_id.borrow().is_none() {
                                let vadj_auto = vadj_drag.clone();
                                let id_auto = auto_scroll_id.clone();
                                let top = near_top;
                                let step = slot_scroll_drag * 0.06;
                                *auto_scroll_id.borrow_mut() =
                                    Some(gtk4::glib::source::timeout_add_local(
                                        std::time::Duration::from_millis(16),
                                        move || {
                                            let adj = &vadj_auto;
                                            let max =
                                                (adj.upper() - adj.page_size()).max(adj.lower());
                                            if top {
                                                adj.set_value(
                                                    (adj.value() - step).max(adj.lower()),
                                                );
                                            } else {
                                                adj.set_value((adj.value() + step).min(max));
                                            }
                                            if id_auto.borrow().is_some() {
                                                gtk4::glib::ControlFlow::Continue
                                            } else {
                                                gtk4::glib::ControlFlow::Break
                                            }
                                        },
                                    ));
                            }
                        } else if let Some(id) = auto_scroll_id.borrow_mut().take() {
                            id.remove();
                        }
                    }
                    gtk4::gdk::DragAction::MOVE
                });
                let hl_drop_leave = highlight.clone();
                let bd_drop_leave = border_da.clone();
                drop_target.connect_leave(move |_| {
                    *hl_drop_leave.borrow_mut() = Highlight::None;
                    bd_drop_leave.queue_draw();
                });

                dial.add_controller(drop_target);

                dial_box_ref.append(&overlay);
            }
        });
    }
    (*rebuild.borrow())();

    // Keep the rebuild closure alive so DropTarget callbacks can trigger rebuilds.
    let rebuild_keep = rebuild.clone();
    bx.connect_destroy(move |_| {
        let _ = &rebuild_keep;
    });

    scroll.set_child(Some(&dial_box));

    bx.append(&top_spacer);
    bx.append(&scroll);
    bx.append(&bottom_spacer);

    // Bottom fixed section: small interactive dials + Catchy.
    let bottom_box = GtkBox::builder()
        .orientation(Orientation::Vertical)
        .spacing(small_spacing)
        .build();
    bottom_box.set_height_request(bottom_h);

    let small_grid = GtkBox::builder()
        .orientation(Orientation::Horizontal)
        .spacing(tight_spacing)
        .halign(gtk4::Align::Center)
        .valign(gtk4::Align::End)
        .build();

    let left_col = GtkBox::builder()
        .orientation(Orientation::Vertical)
        .spacing(tight_spacing)
        .build();
    let right_col = GtkBox::builder()
        .orientation(Orientation::Vertical)
        .spacing(tight_spacing)
        .valign(gtk4::Align::End)
        .build();

    let sys = [
        (
            "BRI",
            "brightness",
            100.0,
            "",
            Some("brightness"),
            true,
            Some("mini"),
        ),
        // BAT is hidden until the settings tray is built (laptop is currently
        // always plugged in, so it is not needed in the main panel).
        // (
        //     "BAT",
        //     ...
        // ),
        (
            "VOL",
            "volume",
            100.0,
            "",
            Some("volume"),
            true,
            Some("mini"),
        ),
    ];
    for (label, source, max, suffix, target, hide_value, dial_style) in sys.iter() {
        if let Some(val) = value_for(source, values) {
            let cfg = WidgetCfg {
                id: format!("{}-dial", source),
                ty: "dial".to_string(),
                label: Some(label.to_string()),
                source: Some(source.to_string()),
                max: Some(*max),
                suffix: Some(suffix.to_string()),
                hide_value: *hide_value,
                dial_style: dial_style.map(|s| s.to_string()),
                extra: Default::default(),
            };
            let dial = if let Some(t) = target {
                let (dial, _v, _m, _t) =
                    widgets::dial::build_interactive(&cfg, val, small_size, small_size, t, false);
                dial.set_halign(gtk4::Align::Center);
                dial
            } else {
                let dial = widgets::dial::build(&cfg, val, small_size, small_size, false);
                dial.set_halign(gtk4::Align::Center);
                dial
            };
            match *label {
                "BRI" => left_col.append(&dial),
                "VOL" => right_col.append(&dial),
                _ => left_col.append(&dial),
            }
        }
    }
    small_grid.append(&left_col);
    small_grid.append(&right_col);

    bottom_box.append(&small_grid);

    bx.append(&bottom_box);

    // Security status updater (every 5s).
    {
        let sec_label = sec_label.clone();
        let refresh = move || -> Option<()> {
            let out = fetch_panel_data()?;
            if let Some(s) = out.get("security") {
                let blocked = s.get("blocked_ips").and_then(|v| v.as_i64()).unwrap_or(0);
                let failed = s
                    .get("failed_ssh_15m")
                    .and_then(|v| v.as_i64())
                    .unwrap_or(0);
                let bad = s
                    .get("high_risk_downloads")
                    .and_then(|v| v.as_i64())
                    .unwrap_or(0);
                let warning = blocked > 0 || failed > 0 || bad > 0;
                sec_label.set_text(if warning {
                    "security:warning"
                } else {
                    "security:ok"
                });
                if warning {
                    sec_label.add_css_class("warning");
                } else {
                    sec_label.remove_css_class("warning");
                }
            }
            Some(())
        };
        refresh();
        gtk4::glib::source::timeout_add_local(Duration::from_secs(5), move || {
            refresh();
            gtk4::glib::ControlFlow::Continue
        });
    }

    bx
}

fn build_widget(w: &WidgetCfg, _width: i32, values: &Values) -> Option<gtk4::Widget> {
    match w.ty.as_str() {
        "logo" => {
            let trigger: Rc<dyn Fn()> = Rc::new(|| {
                // Logo click command is intentionally not hard-coded; configure it via
                // left_panel.control_center_command in rkt-dashboard.json.
            });
            Some(widgets::logo::build(160, 160, trigger, None, None).upcast())
        }
        "text_block" => {
            let v = value_for(w.source.as_deref()?, values)?;
            Some(widgets::text_block::build(w, v, 180, 60).upcast())
        }
        "bar_gauge" => {
            let v = value_for(w.source.as_deref()?, values)?;
            Some(widgets::bar_gauge::build(w, v, 180, 90).upcast())
        }
        _ => None,
    }
}

fn value_for(source: &str, values: &Values) -> Option<Rc<RefCell<f64>>> {
    match source {
        "cpu" => Some(values.cpu.clone()),
        "mem_used" => Some(values.mem_used.clone()),
        "mem_total" => Some(values.mem_total.clone()),
        "load_1" => Some(values.load_0.clone()),
        "load" => Some(values.load_0.clone()),
        "net_up" => Some(values.net_up.clone()),
        "net_down" => Some(values.net_down.clone()),
        "mem_pct" => Some(values.mem_pct.clone()),
        "battery" => Some(values.battery.clone()),
        "volume" => Some(values.volume.clone()),
        "brightness" => Some(values.brightness.clone()),
        "cpu_temp" => Some(values.cpu_temp.clone()),
        "gpu_temp" => Some(values.gpu_temp.clone()),
        "cpu_freq" => Some(values.cpu_freq.clone()),
        "disk_pct" => Some(values.disk_pct.clone()),
        "swap_pct" => Some(values.swap_pct.clone()),
        "fan_rpm" => Some(values.fan_rpm.clone()),
        "power_w" => Some(values.power_w.clone()),
        _ => None,
    }
}
