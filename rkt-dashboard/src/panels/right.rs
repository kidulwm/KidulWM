use gtk4::prelude::*;
use gtk4::{Box as GtkBox, Entry, Label, Orientation};
use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use crate::widgets::info_dial::{make_clickable_label, InfoDialState};

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

// Shared cache for rkt-panel-data so all monitors show identical data and we do
// not hammer the data script on every window.
static PANEL_DATA_CACHE: OnceLock<Mutex<Option<(Instant, serde_json::Value)>>> = OnceLock::new();

fn fetch_panel_data() -> Option<serde_json::Value> {
    const AGE: Duration = Duration::from_secs(4);
    let cache = PANEL_DATA_CACHE.get_or_init(|| Mutex::new(None));
    {
        if let Ok(guard) = cache.lock() {
            if let Some((when, data)) = guard.as_ref() {
                if when.elapsed() < AGE {
                    return Some(data.clone());
                }
            }
        }
    }

    let out = std::process::Command::new("rkt-panel-data")
        .output()
        .ok()
        .and_then(|o| serde_json::from_slice::<serde_json::Value>(&o.stdout).ok())?;

    if let Ok(mut guard) = cache.lock() {
        *guard = Some((Instant::now(), out.clone()));
    }
    Some(out)
}

pub fn right_dial_size(panel_width: i32) -> i32 {
    (panel_width - 60).max(96).min(220)
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
    let panel_w = cfg.right.width.max(180);
    let dial_size = right_dial_size(panel_w);
    let dial_height = dial_size.min((monitor_height / 4) - 20).max(120);

    let bx = GtkBox::builder()
        .orientation(Orientation::Vertical)
        .spacing(0)
        .margin_top(8)
        .margin_bottom(8)
        .margin_start(12)
        .margin_end(12)
        .build();
    bx.add_css_class("rkt-panel");

    // ── Top: clock dial (date drawn inside the dial, under the day) ──
    let top_box = GtkBox::builder()
        .orientation(Orientation::Vertical)
        .spacing(4)
        .halign(gtk4::Align::Center)
        .valign(gtk4::Align::Start)
        .build();

    let clock_state = InfoDialState::new();
    *clock_state.multi_arc.borrow_mut() = true;
    *clock_state.middle_ball_alpha.borrow_mut() = 0.12;
    let clock_click = || {
        let _ = std::process::Command::new("qs")
            .args(["-c", "noctalia-shell", "ipc", "call", "launcher", "toggle"])
            .spawn();
    };
    let clock_dial = crate::widgets::info_dial::build(
        &clock_state,
        dial_size,
        dial_height,
        Some(Box::new(clock_click)),
    );
    top_box.append(&clock_dial);

    bx.append(&top_box);

    // ── Comms dial (screen centre): email/telegram/discord/news in one ring ──
    bx.append(&v_spacer());
    let comms_state = crate::widgets::comms_dial::CommsDialState::new();
    let comms_dial = crate::widgets::comms_dial::build(&comms_state, dial_size, dial_height, {
        let click_state = comms_state.clone();
        Box::new(move |source: &str| {
            // Mark this source as seen before launching the viewer so the
            // dashboard count resets to zero on every screen.
            {
                let seen_arc = comms_seen();
                let mut seen = seen_arc.lock().unwrap();
                match source {
                    "news" => {
                        let keys = click_state.news_keys.borrow();
                        for k in keys.iter() {
                            seen.news.insert(k.clone(), true);
                        }
                    }
                    _ => {
                        if let Some(raw) = click_state.raw_counts.borrow().get(source) {
                            if *raw >= 0 {
                                seen.counts.insert(source.to_string(), *raw);
                            }
                        }
                    }
                }
                save_comms_seen(&seen);
            }

            let _ = std::process::Command::new("alacritty")
                .args([
                    "-e",
                    "fish",
                    "-c",
                    &format!("rkt-mediabob {}; read -P 'Press Enter to close'", source),
                ])
                .spawn();
        })
    });
    bx.append(&comms_dial);

    // ── USB + security between comms and weather dials ──
    bx.append(&v_spacer());

    // USB guard line with inline terminal-style PIN entry
    let usb_state = Rc::new(RefCell::new(UsbState::default()));
    let usb_box = GtkBox::builder()
        .orientation(Orientation::Vertical)
        .spacing(2)
        .halign(gtk4::Align::Center)
        .build();
    usb_box.add_css_class("rkt-right-widget");
    usb_box.add_css_class("hidden");

    let usb_label = Label::new(Some("usb: …"));
    usb_label.set_wrap(true);
    usb_label.set_max_width_chars(18);
    usb_label.set_justify(gtk4::Justification::Center);
    usb_label.add_css_class("rkt-right-label");
    usb_box.append(&usb_label);

    let usb_entry = Entry::new();
    const USB_PIN_PROMPT: &str = "passwd ~        ";
    usb_entry.set_placeholder_text(Some(USB_PIN_PROMPT));
    usb_entry.set_visibility(false);
    usb_entry.set_invisible_char(Some('\u{200B}'));
    usb_entry.set_halign(gtk4::Align::Center);
    usb_entry.set_max_width_chars(21);
    usb_entry.set_visible(false);
    usb_entry.add_css_class("rkt-usb-pin");
    usb_box.append(&usb_entry);

    // Click the usb label to reveal the PIN entry
    let usb_click_entry = usb_entry.clone();
    let usb_click_state = usb_state.clone();
    let usb_click_gesture = gtk4::GestureClick::new();
    usb_click_gesture.connect_pressed(move |_, _, _, _| {
        if usb_click_state.borrow().sysname.is_some() {
            usb_click_entry.set_text("");
            usb_click_entry.set_visible(true);
            usb_click_entry.grab_focus();
        }
    });
    usb_box.add_controller(usb_click_gesture);
    usb_box.set_cursor_from_name(None);

    // Enter PIN to authorise
    let auth_state = usb_state.clone();
    let auth_label = usb_label.clone();
    let auth_entry = usb_entry.clone();
    let pending_path_auth = usb_pending_file();
    usb_entry.connect_activate(move |entry| {
        let pin = entry.text().to_string().trim_end().to_string();
        let sysname = auth_state.borrow().sysname.clone().unwrap_or_default();
        if pin.is_empty() || sysname.is_empty() {
            return;
        }

        let mut pending = auth_state.borrow_mut();
        pending.attempts += 1;
        let attempt = pending.attempts;
        drop(pending);

        let result = (|| -> Result<String, String> {
            let mut child = std::process::Command::new("sudo")
                .args(["-n", "/usr/local/bin/brain-usb-authorize", &sysname])
                .stdin(std::process::Stdio::piped())
                .stdout(std::process::Stdio::piped())
                .stderr(std::process::Stdio::piped())
                .spawn()
                .map_err(|e| format!("spawn error: {}", e))?;
            if let Some(mut stdin) = child.stdin.take() {
                let _ = std::io::Write::write_all(&mut stdin, format!("{}\n", pin).as_bytes());
            }
            let out = child
                .wait_with_output()
                .map_err(|e| format!("wait error: {}", e))?;
            if out.status.success() {
                Ok("connected".to_string())
            } else {
                let err = String::from_utf8_lossy(&out.stderr);
                let stdout = String::from_utf8_lossy(&out.stdout);
                Err(if err.is_empty() {
                    stdout.to_string()
                } else {
                    err.to_string()
                })
            }
        })();

        match result {
            Ok(_) => {
                // success
                write_usb_state("connected", Some(&sysname));
                auth_state.borrow_mut().attempts = 0;
                auth_state.borrow_mut().sysname = None;
                auth_entry.set_text("");
                auth_entry.set_visible(false);
                auth_label.set_label("usb: connected");
            }
            Err(_) => {
                if attempt >= 3 {
                    // Too many attempts: block the device.
                    let auth_file = std::path::PathBuf::from(format!(
                        "/sys/bus/usb/devices/{}/authorized",
                        sysname
                    ));
                    let _ = std::process::Command::new("sudo")
                        .args(["-n", "tee", &auth_file.to_string_lossy()])
                        .stdin(std::process::Stdio::piped())
                        .stdout(std::process::Stdio::null())
                        .stderr(std::process::Stdio::null())
                        .spawn()
                        .and_then(|mut c| {
                            if let Some(mut stdin) = c.stdin.take() {
                                let _ = std::io::Write::write_all(&mut stdin, b"0\n");
                            }
                            c.wait()
                        });
                    let _ = std::fs::remove_file(&pending_path_auth);
                    write_usb_state("blocked", Some(&sysname));
                    auth_state.borrow_mut().attempts = 0;
                    auth_state.borrow_mut().sysname = None;
                    auth_entry.set_text("");
                    auth_entry.set_visible(false);
                    auth_label.set_label("usb: blocked");
                } else {
                    auth_label.set_label(&format!("usb: wrong ({})", attempt));
                    entry.set_text("");
                }
            }
        }
    });

    bx.append(&usb_box);

    // Security line
    let security_widget = make_clickable_label(
        "security: …",
        "rkt-right-widget",
        Box::new(|| {
            let _ = std::process::Command::new("alacritty")
                .args([
                    "-e",
                    "fish",
                    "-c",
                    "hermes -p security-bob chat -q 'Run a fresh security scan now and print a one-line summary.'; read -P 'Press Enter to close'",
                ])
                .spawn();
        }),
    );
    security_widget.set_halign(gtk4::Align::Center);
    bx.append(&security_widget);

    // ── Weather dial (bottom) ──
    let weather_state = InfoDialState::new();
    *weather_state.multi_arc.borrow_mut() = true;
    let weather_click = || {
        let _ = std::process::Command::new("xdg-open")
            .arg("https://wttr.in/Brisbane")
            .spawn();
    };
    let weather_dial = crate::widgets::info_dial::build(
        &weather_state,
        dial_size,
        dial_height,
        Some(Box::new(weather_click)),
    );
    weather_dial.set_valign(gtk4::Align::End);
    bx.append(&weather_dial);

    // ── Clock updater (every second) ──
    {
        let clock_state = clock_state.clone();
        gtk4::glib::source::timeout_add_local(Duration::from_secs(1), move || {
            let now = gtk4::glib::DateTime::now_local()
                .unwrap_or_else(|_| gtk4::glib::DateTime::now_utc().expect("time"));
            let hr = now.hour();
            let min = now.minute();
            let sec = now.second();
            *clock_state.center.borrow_mut() = now
                .format("%I%P")
                .unwrap_or_default()
                .trim_start_matches('0')
                .to_string();
            // Outer = seconds, middle = minutes (transparent), inner = hours.
            // Each hand moves through the full 360° like a normal analog clock.
            *clock_state.value.borrow_mut() = (sec as f64 / 60.0).clamp(0.0, 1.0);
            *clock_state.middle_value.borrow_mut() =
                ((min as f64 + sec as f64 / 60.0) / 60.0).clamp(0.0, 1.0);
            *clock_state.inner_value.borrow_mut() =
                (((hr % 12) as f64 + min as f64 / 60.0 + sec as f64 / 3600.0) / 12.0)
                    .clamp(0.0, 1.0);
            *clock_state.sub.borrow_mut() = now.format("%A").unwrap_or_default().to_lowercase();
            *clock_state.date.borrow_mut() = now.format("%d %B").unwrap_or_default().to_lowercase();
            gtk4::glib::ControlFlow::Continue
        });
    }

    // ── USB guard lifecycle updater (every 1s) ──
    {
        let usb_label = usb_label.clone();
        let usb_state = usb_state.clone();
        let usb_box = usb_box.clone();
        let usb_entry = usb_entry.clone();
        let pending_path = usb_pending_file();
        let state_path = usb_state_file();

        let update_usb = move || {
            let mut count = 0;
            let mut sysname = None;
            if pending_path.exists() {
                if let Ok(text) = std::fs::read_to_string(&pending_path) {
                    for line in text.lines() {
                        let line = line.trim();
                        if line.is_empty() {
                            continue;
                        }
                        if let Ok(obj) = serde_json::from_str::<serde_json::Value>(line) {
                            if sysname.is_none() {
                                sysname = obj
                                    .get("sysname")
                                    .and_then(|v| v.as_str())
                                    .map(String::from);
                            }
                            count += 1;
                        }
                    }
                }
            }

            if count > 0 {
                usb_label.set_label(&format!("usb: {} pending", count));
                usb_state.borrow_mut().sysname = sysname.clone();
                usb_box.set_cursor_from_name(Some("pointer"));
                usb_box.remove_css_class("hidden");
                return gtk4::glib::ControlFlow::Continue;
            }

            // No pending: see if we should still show "connected" or "clear".
            let mut lifecycle: (String, Option<String>) = ("idle".to_string(), None);
            if let Ok(text) = std::fs::read_to_string(&state_path) {
                if let Ok(obj) = serde_json::from_str::<serde_json::Value>(&text) {
                    if let Some(ts) = obj.get("at").and_then(|v| v.as_f64()) {
                        let now = SystemTime::now()
                            .duration_since(UNIX_EPOCH)
                            .unwrap_or_default()
                            .as_secs_f64();
                        let age = now - ts;
                        let status = obj
                            .get("status")
                            .and_then(|v| v.as_str())
                            .unwrap_or("connected")
                            .to_string();
                        if age < 3.0 {
                            lifecycle = (
                                status,
                                obj.get("sysname")
                                    .and_then(|v| v.as_str())
                                    .map(String::from),
                            );
                        } else if age < 6.0 && status != "blocked" {
                            lifecycle = ("clear".to_string(), None);
                        }
                    }
                }
            }

            match lifecycle.0.as_str() {
                "connected" => {
                    usb_label.set_label("usb: connected");
                    usb_box.set_cursor_from_name(None);
                    usb_box.remove_css_class("hidden");
                    usb_state.borrow_mut().sysname = None;
                }
                "clear" => {
                    usb_label.set_label("usb: clear");
                    usb_box.set_cursor_from_name(None);
                    usb_box.remove_css_class("hidden");
                    usb_state.borrow_mut().sysname = None;
                }
                "blocked" => {
                    usb_label.set_label("usb: blocked");
                    usb_box.set_cursor_from_name(None);
                    usb_box.remove_css_class("hidden");
                    usb_state.borrow_mut().sysname = None;
                }
                _ => {
                    usb_label.set_label("usb: …");
                    usb_state.borrow_mut().sysname = None;
                    usb_box.set_cursor_from_name(None);
                    usb_box.add_css_class("hidden");
                    if gtk4::prelude::WidgetExt::is_visible(&usb_entry) {
                        usb_entry.set_visible(false);
                        usb_entry.set_text("");
                    }
                }
            }

            gtk4::glib::ControlFlow::Continue
        };

        update_usb();
        gtk4::glib::source::timeout_add_local(Duration::from_secs(1), update_usb);
    }

    // ── Panel data updater (every 5s) ──
    {
        let weather_state = weather_state.clone();
        let comms_state = comms_state.clone();
        let security_widget = security_widget.clone();

        let refresh = move || -> Option<()> {
            let out = fetch_panel_data()?;

            if let Some(w) = out.get("weather") {
                let temp = w.get("current_temp_c")?.as_f64()?;
                let max = 45.0;
                let pct = (temp / max).clamp(0.0, 1.0);
                *weather_state.value.borrow_mut() = pct;
                *weather_state.center.borrow_mut() = format!("{:.0}°", temp);
                *weather_state.sub.borrow_mut() =
                    w.get("condition")?.as_str().unwrap_or("").to_string();
                *weather_state.colour_override.borrow_mut() = None;

                // Inner arc = expected low, middle arc = expected high.
                if let Some(forecast) = w.get("forecast")?.as_array() {
                    if let Some(today) = forecast.first() {
                        let high = today.get("max_c")?.as_f64().unwrap_or(temp);
                        let low = today.get("min_c")?.as_f64().unwrap_or(temp);
                        *weather_state.middle_value.borrow_mut() = (high / max).clamp(0.0, 1.0);
                        *weather_state.inner_value.borrow_mut() = (low / max).clamp(0.0, 1.0);
                    }
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

            *comms_state.raw_counts.borrow_mut() = raw_counts;
            *comms_state.source_pcts.borrow_mut() = source_pcts;
            *comms_state.items.borrow_mut() = items;
            let value = comms_state
                .source_pcts
                .borrow()
                .iter()
                .map(|(_, p)| *p)
                .fold(0.0, f64::max)
                .clamp(0.0, 1.0);
            *comms_state.value.borrow_mut() = value;

            if let Some(s) = out.get("security") {
                let text = s.get("text")?.as_str().unwrap_or("security: …");
                if let Some(lbl) = security_widget.first_child().and_downcast::<Label>() {
                    lbl.set_label(text);
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

#[derive(Default)]
struct UsbState {
    sysname: Option<String>,
    attempts: usize,
}

fn usb_state_file() -> std::path::PathBuf {
    std::path::PathBuf::from(std::env::var("HOME").unwrap_or_default())
        .join(".hermes")
        .join("brain")
        .join("state")
        .join("usb-guard-state.json")
}

fn usb_pending_file() -> std::path::PathBuf {
    std::path::PathBuf::from(std::env::var("HOME").unwrap_or_default())
        .join(".hermes")
        .join("brain")
        .join("state")
        .join("usb-guard-pending.jsonl")
}

fn write_usb_state(status: &str, sysname: Option<&str>) {
    let path = usb_state_file();
    if let Some(parent) = path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }
    let payload = serde_json::json!({
        "status": status,
        "sysname": sysname,
        "at": SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs_f64(),
    });
    let _ = std::fs::write(&path, payload.to_string());
}
