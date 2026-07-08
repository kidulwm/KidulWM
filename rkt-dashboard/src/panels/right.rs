use gtk4::gdk_pixbuf::Pixbuf;
use gtk4::prelude::*;
use gtk4::{Box as GtkBox, DrawingArea, GestureClick, Label, Orientation};
use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use crate::widgets::info_dial::InfoDialState;

const COMMS_SCALE: f64 = 17.0;

#[derive(Default, serde::Serialize, serde::Deserialize, Clone)]
struct CommsSeen {
    #[serde(default)]
    counts: HashMap<String, i64>,
    #[serde(default)]
    news: HashMap<String, bool>,
}

fn comms_seen_path() -> std::path::PathBuf {
    std::path::PathBuf::from(std::env::var("HOME").unwrap_or_default())
        .join(".cache")
        .join("rkt-dashboard")
        .join("comms-seen.json")
}

fn load_comms_seen() -> CommsSeen {
    let path = comms_seen_path();
    if let Ok(text) = std::fs::read_to_string(&path) {
        if let Ok(state) = serde_json::from_str::<CommsSeen>(&text) {
            return state;
        }
    }
    CommsSeen::default()
}

fn save_comms_seen(state: &CommsSeen) {
    let path = comms_seen_path();
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let _ = std::fs::write(
        &path,
        serde_json::to_string_pretty(state).unwrap_or_default(),
    );
}

// Shared across all monitors so a click on one screen resets counts on the other.
static COMMS_SEEN: OnceLock<Arc<Mutex<CommsSeen>>> = OnceLock::new();

fn comms_seen() -> Arc<Mutex<CommsSeen>> {
    COMMS_SEEN
        .get_or_init(|| Arc::new(Mutex::new(load_comms_seen())))
        .clone()
}

pub fn right_dial_size(panel_width: i32) -> i32 {
    panel_width.max(96).min(320)
}

fn weather_icon_and_colour(condition: &str) -> (String, (f64, f64, f64)) {
    let c = condition.to_lowercase();
    // Soft company palette.
    let blue = (0.42, 0.58, 0.88);
    let turquoise = (0.38, 0.78, 0.76);
    let purple = (0.55, 0.38, 0.75);

    if c.contains("thunder") || c.contains("storm") {
        ("rkt-icon-weather-thunderstorm".to_string(), purple)
    } else if c.contains("snow") || c.contains("sleet") || c.contains("hail") {
        ("rkt-icon-weather-snow".to_string(), turquoise)
    } else if c.contains("rain") || c.contains("drizzle") || c.contains("shower") {
        ("rkt-icon-weather-rain".to_string(), blue)
    } else if c.contains("cloud") || c.contains("overcast") {
        ("rkt-icon-weather-cloudy".to_string(), blue)
    } else if c.contains("partly") || c.contains("mostly") {
        ("rkt-icon-weather-partly-cloudy".to_string(), turquoise)
    } else if c.contains("fog") || c.contains("mist") || c.contains("haze") {
        ("rkt-icon-weather-fog".to_string(), purple)
    } else {
        // Clear/sunny/default.
        ("rkt-icon-weather-sunny".to_string(), turquoise)
    }
}

fn v_spacer() -> Label {
    let s = Label::new(None);
    s.set_vexpand(true);
    s.set_valign(gtk4::Align::Fill);
    s
}

pub fn build_right(
    cfg: &crate::config::Config,
    monitor_height: i32,
    _values: &crate::Values,
) -> GtkBox {
    let _panel_w = cfg.right.width.max(180);

    // Clock/weather dials should match the left panel's large dials in size.
    let dial_size_base = right_dial_size(cfg.left.width)
        .min((monitor_height / 4) - 20)
        .max(120);
    let dial_size = (dial_size_base as f64 * 0.85) as i32;
    let dial_height = dial_size;

    // ── Top: weather dial + date/time + Bob logo ──
    let bx = GtkBox::builder()
        .orientation(Orientation::Vertical)
        .spacing(0)
        .margin_top(8)
        .margin_bottom(8)
        .margin_start(12)
        .margin_end(12)
        .build();
    bx.add_css_class("rkt-panel");

    // ── Top: weather dial + date/time + Bob logo ──
    let top_box = GtkBox::builder()
        .orientation(Orientation::Vertical)
        .spacing(4)
        .halign(gtk4::Align::Center)
        .valign(gtk4::Align::Start)
        .build();

    let weather_state = InfoDialState::new();
    *weather_state.multi_arc.borrow_mut() = true;
    *weather_state.weather_layout.borrow_mut() = true;
    let weather_click = {
        let loc = cfg
            .right
            .weather_location
            .clone()
            .unwrap_or_else(|| "wttr.in".to_string());
        move || {
            let url = if loc.starts_with("http://") || loc.starts_with("https://") {
                loc.clone()
            } else {
                format!("https://wttr.in/{}", urlencoding::encode(&loc))
            };
            let _ = std::process::Command::new("xdg-open").arg(&url).spawn();
        }
    };
    let weather_dial = crate::widgets::info_dial::build(
        &weather_state,
        dial_size,
        dial_height,
        Some(Box::new(weather_click)),
    );
    top_box.append(&weather_dial);

    // Date + time under the weather dial. Time is bigger and sits directly under the date.
    let date_label = Label::new(Some("…"));
    date_label.add_css_class("rkt-right-date");
    date_label.set_halign(gtk4::Align::Center);
    top_box.append(&date_label);

    let time_label = Label::new(Some("…"));
    time_label.add_css_class("rkt-right-time");
    time_label.set_halign(gtk4::Align::Center);
    time_label.set_margin_top(2);
    top_box.append(&time_label);

    // ── Bob logo under the date/time ──
    let comms_state = crate::widgets::comms_dial::CommsDialState::new();
    let logo_widget = build_bob_logo_widget(dial_size, &comms_state, cfg);
    top_box.append(&logo_widget);

    bx.append(&top_box);

    // ── Comms dial replaced by Bob logo above; module kept for easy revert ──
    // bx.append(&v_spacer());
    // USB guard widget moved to left panel.

    // Clock dial removed. Keep a 1-second update for the date/time label under the weather dial.
    {
        let date_label = date_label.clone();
        let time_label = time_label.clone();
        gtk4::glib::source::timeout_add_local(Duration::from_secs(1), move || {
            let now = gtk4::glib::DateTime::now_local()
                .unwrap_or_else(|_| gtk4::glib::DateTime::now_utc().expect("time"));
            let day = now.format("%A").unwrap_or_default().to_lowercase();
            let day = match day.as_str() {
                "monday" => "mon",
                "tuesday" => "tues",
                "wednesday" => "wednes",
                "thursday" => "thurs",
                "friday" => "fri",
                "saturday" => "satur",
                "sunday" => "sun",
                _ => &day,
            };
            let date = now.format("%d %B").unwrap_or_default().to_lowercase();
            date_label.set_text(&format!("{} {}", day, date));

            let mut hour = now.hour();
            if hour == 0 {
                hour = 12;
            } else if hour > 12 {
                hour -= 12;
            }
            let minute = now.minute();
            let ampm = now.format("%P").unwrap_or_default().to_lowercase();
            time_label.set_text(&format!("{}:{} {}", hour, format!("{:02}", minute), ampm));
            gtk4::glib::ControlFlow::Continue
        });
    }

    // USB guard widget moved to left panel.

    // ── Panel data updater (every 5s) ──
    {
        let weather_state = weather_state.clone();
        let comms_state = comms_state.clone();

        let refresh = move || -> Option<()> {
            let out = crate::panel_data::fetch_panel_data()?;

            if let Some(w) = out.get("weather") {
                let temp = w.get("current_temp_c")?.as_f64()?;
                *weather_state.center.borrow_mut() = format!("{:.0}°", temp);
                *weather_state.sub.borrow_mut() = String::new();

                let (icon, icon_colour) =
                    weather_icon_and_colour(w.get("condition")?.as_str().unwrap_or(""));
                *weather_state.icon.borrow_mut() = icon;
                *weather_state.icon_colour.borrow_mut() = icon_colour;
                *weather_state.colour_override.borrow_mut() = None;

                // Fixed calibrated positions for low/high arc markers so the dial stays
                // readable even on days with almost no temperature range.
                // Low sits between the left horizontal and the arc's left end; high sits
                // between the right horizontal and the arc's right end.
                // start = 135°, full = 270°. Left target = 168.75°, right target = 371.25°.
                let low_pct =
                    (168.75_f64.to_radians() - 135.0_f64.to_radians()) / (270.0_f64.to_radians());
                let high_pct =
                    (371.25_f64.to_radians() - 135.0_f64.to_radians()) / (270.0_f64.to_radians());

                if let Some(forecast) = w.get("forecast")?.as_array() {
                    if let Some(today) = forecast.first() {
                        let high = today.get("max_c")?.as_f64().unwrap_or(temp.max(36.0));
                        let low = today.get("min_c")?.as_f64().unwrap_or(temp);

                        // Calibrate the live temperature between the fixed low/high markers.
                        let temp_norm = if high > low {
                            ((temp - low) / (high - low)).clamp(0.0, 1.0)
                        } else {
                            0.5
                        };
                        let temp_pct = low_pct + (high_pct - low_pct) * temp_norm;

                        *weather_state.value.borrow_mut() = temp_pct.clamp(0.0, 1.0);
                        *weather_state.middle_value.borrow_mut() = low_pct.clamp(0.0, 1.0);
                        *weather_state.inner_value.borrow_mut() = high_pct.clamp(0.0, 1.0);
                        *weather_state.detail.borrow_mut() =
                            format!("{:.0}           {:.0}", low, high);
                    }
                } else {
                    *weather_state.value.borrow_mut() = (temp / 36.0).clamp(0.0, 1.0);
                    *weather_state.middle_value.borrow_mut() = low_pct.clamp(0.0, 1.0);
                    *weather_state.inner_value.borrow_mut() = high_pct.clamp(0.0, 1.0);
                    *weather_state.detail.borrow_mut() = String::new();
                }
            }

            // Build three comms lines sorted by highest unchecked count first, using
            // per-source "seen" offsets so clicking a source resets its displayed count.
            let mut entries: Vec<(String, String, f64)> = Vec::new(); // (source, label, delta)
            let mut raw_counts: HashMap<String, i64> = HashMap::new();
            let mut seen_dirty = false;

            {
                let seen_arc = comms_seen();
                let mut seen = seen_arc.lock().unwrap();

                if let Some(e) = out.get("email") {
                    let raw = e.get("unread")?.as_i64().unwrap_or(-1);
                    raw_counts.insert("email".to_string(), raw);
                    let last_seen = seen.counts.get("email").copied().unwrap_or(0);
                    if raw >= 0 && raw < last_seen {
                        seen.counts.insert("email".to_string(), raw);
                        seen_dirty = true;
                    }
                    let delta = if raw < 0 { 0 } else { (raw - last_seen).max(0) };
                    entries.push(("email".to_string(), "mail".to_string(), delta as f64));
                }

                if let Some(s) = out.get("social") {
                    let tg_raw = s.get("telegram")?.get("unread")?.as_i64().unwrap_or(-1);
                    raw_counts.insert("telegram".to_string(), tg_raw);
                    let tg_seen = seen.counts.get("telegram").copied().unwrap_or(0);
                    if tg_raw >= 0 && tg_raw < tg_seen {
                        seen.counts.insert("telegram".to_string(), tg_raw);
                        seen_dirty = true;
                    }
                    let tg_delta = if tg_raw < 0 {
                        0
                    } else {
                        (tg_raw - tg_seen).max(0)
                    };
                    entries.push(("telegram".to_string(), "gram".to_string(), tg_delta as f64));

                    let dc_raw = s.get("discord")?.get("unread")?.as_i64().unwrap_or(-1);
                    raw_counts.insert("discord".to_string(), dc_raw);
                    let dc_seen = seen.counts.get("discord").copied().unwrap_or(0);
                    if dc_raw >= 0 && dc_raw < dc_seen {
                        seen.counts.insert("discord".to_string(), dc_raw);
                        seen_dirty = true;
                    }
                    let dc_delta = if dc_raw < 0 {
                        0
                    } else {
                        (dc_raw - dc_seen).max(0)
                    };
                    entries.push(("discord".to_string(), "cord".to_string(), dc_delta as f64));
                }

                if let Some(r) = out.get("rss") {
                    let raw_items = r.get("items")?.as_array()?;
                    let mut keys = Vec::new();
                    let mut unseen = 0i64;
                    for it in raw_items.iter().take(30) {
                        let key = it
                            .get("link")
                            .and_then(|v| v.as_str())
                            .or_else(|| it.get("title").and_then(|v| v.as_str()))
                            .unwrap_or("")
                            .to_string();
                        keys.push(key.clone());
                        if !seen.news.contains_key(&key) {
                            unseen += 1;
                        }
                    }
                    *comms_state.news_keys.borrow_mut() = keys;
                    entries.push(("news".to_string(), "news".to_string(), unseen as f64));
                    // Prune old news keys so the map does not grow forever.
                    let current_keys: std::collections::HashSet<_> =
                        comms_state.news_keys.borrow().iter().cloned().collect();
                    let before = seen.news.len();
                    seen.news.retain(|k, _| current_keys.contains(k));
                    if seen.news.len() != before {
                        seen_dirty = true;
                    }
                }

                if seen_dirty {
                    save_comms_seen(&seen);
                }
            }

            // Sort highest unchecked count first, keep top three.
            entries.sort_by(|a, b| b.2.partial_cmp(&a.2).unwrap_or(std::cmp::Ordering::Equal));
            entries.truncate(3);

            let mut items = Vec::new();
            let mut source_pcts = Vec::new();
            for (source, label, delta) in entries {
                source_pcts.push((source.clone(), delta / COMMS_SCALE));
                items.push(crate::widgets::comms_dial::CommsItem {
                    label,
                    value: String::new(),
                    source,
                });
            }

            // Keep a full snapshot so the report can show real messages, not just counts.
            let snapshot = if let Some(obj) = out.as_object() {
                let mut snap = HashMap::new();
                for key in ["email", "social", "rss"] {
                    if let Some(v) = obj.get(key) {
                        snap.insert(key.to_string(), v.clone());
                    }
                }
                snap
            } else {
                HashMap::new()
            };

            *comms_state.raw_counts.borrow_mut() = raw_counts;
            *comms_state.source_pcts.borrow_mut() = source_pcts;
            *comms_state.items.borrow_mut() = items;
            *comms_state.snapshot.borrow_mut() = snapshot;
            let value = comms_state
                .source_pcts
                .borrow()
                .iter()
                .map(|(_, p)| *p)
                .fold(0.0, f64::max)
                .clamp(0.0, 1.0);
            *comms_state.value.borrow_mut() = value;

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

/// Render the Bob PNG logo to a Cairo ARGB32 surface so transparency is respected.
fn load_png_to_surface(path: std::path::PathBuf, size: i32) -> Option<cairo::ImageSurface> {
    let pixbuf = Pixbuf::from_file_at_scale(&path, size, size, true).ok()?;
    let surface = cairo::ImageSurface::create(cairo::Format::ARgb32, size, size).ok()?;
    let cr = cairo::Context::new(&surface).ok()?;
    cr.set_source_rgba(0.0, 0.0, 0.0, 0.0);
    cr.set_operator(cairo::Operator::Source);
    let _ = cr.paint();
    cr.set_operator(cairo::Operator::Over);
    cr.set_source_pixbuf(&pixbuf, 0.0, 0.0);
    let _ = cr.paint();
    Some(surface)
}

/// A clickable logo widget. Clicking opens the configured media/report command.
fn build_bob_logo_widget(
    dial_size: i32,
    state: &crate::widgets::comms_dial::CommsDialState,
    cfg: &crate::config::Config,
) -> DrawingArea {
    let da = DrawingArea::builder()
        .width_request(dial_size)
        .height_request(dial_size)
        .halign(gtk4::Align::Center)
        .valign(gtk4::Align::Center)
        .can_focus(false)
        .can_target(true)
        .build();

    let logo_path = {
        let file = std::path::PathBuf::from("assets/bob-logo.png");
        if file.exists() {
            file
        } else if let Ok(exe) = std::env::current_exe() {
            exe.ancestors()
                .find_map(|d| {
                    let p = d.join("assets/bob-logo.png");
                    p.exists().then_some(p)
                })
                .unwrap_or(file)
        } else {
            file
        }
    };

    let surface: Rc<RefCell<Option<cairo::ImageSurface>>> = Rc::new(RefCell::new(None));
    {
        let s = surface.clone();
        let p = logo_path.clone();
        da.set_draw_func(move |_, cr, w, h| {
            let avail = w.min(h) as i32;
            if avail <= 0 {
                return;
            }
            // Render the logo at 60% of the dial slot and keep it centered.
            let size = (avail as f64 * 0.60).round() as i32;
            let mut inner = s.borrow_mut();
            if inner.as_ref().map(|x| x.width() != size).unwrap_or(true) {
                *inner = load_png_to_surface(p.clone(), size);
            }
            if let Some(ref img) = *inner {
                let iw = img.width() as f64;
                let ih = img.height() as f64;
                let x = (w as f64 - iw) / 2.0;
                let y = (h as f64 - ih) / 2.0;
                cr.set_source_surface(img, x, y).unwrap();
                cr.set_operator(cairo::Operator::Over);
                let _ = cr.paint();
            }
        });
    }

    let term_cmd = cfg.right.terminal_command.clone().unwrap_or_else(|| {
        vec![
            "alacritty".to_string(),
            "-e".to_string(),
            "sh".to_string(),
            "-c".to_string(),
        ]
    });
    let media_cmd = cfg
        .right
        .media_command
        .clone()
        .unwrap_or_else(|| vec!["rkt-media-report".to_string(), "--snapshot".to_string()]);
    let shell_cmd = cfg
        .right
        .shell_command
        .clone()
        .unwrap_or_else(|| "sh -c".to_string());

    let gesture = GestureClick::new();
    let click_state = state.clone();
    gesture.connect_pressed(move |_g, _n, _x, _y| {
        // Mark every source as seen before opening the full report.
        {
            let seen_arc = comms_seen();
            let mut seen = seen_arc.lock().unwrap();
            let raw = click_state.raw_counts.borrow();
            for (source, count) in raw.iter() {
                if *count >= 0 {
                    seen.counts.insert(source.clone(), *count);
                }
            }
            for k in click_state.news_keys.borrow().iter() {
                seen.news.insert(k.clone(), true);
            }
            save_comms_seen(&seen);
        }

        // Dump the current panel snapshot to a temp file for the report script.
        let snapshot = click_state.snapshot.borrow();
        let snapshot_path = std::env::temp_dir().join(format!(
            "rkt-dashboard-snapshot-{}.json",
            std::process::id()
        ));
        let _ = std::fs::write(
            &snapshot_path,
            serde_json::to_string(&*snapshot).unwrap_or_default(),
        );

        if let Some(prog) = term_cmd.first() {
            let mut c = std::process::Command::new(prog);
            c.args(&term_cmd[1..]);
            let body = format!(
                "{} {}; read -P 'Press Enter to close'",
                shlex::join(media_cmd.iter().map(|s| s.as_str())),
                shlex::quote(&snapshot_path.to_string_lossy())
            );
            c.arg(&format!("{} {}", shell_cmd, body));
            let _ = c.spawn();
        }
    });
    da.add_controller(gesture);
    da.set_cursor_from_name(Some("pointer"));

    da
}
