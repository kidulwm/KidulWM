use gtk4::prelude::*;
use gtk4::{Box as GtkBox, Entry, Label, Orientation};
use std::cell::RefCell;
use std::rc::Rc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use crate::widgets::info_dial::{make_clickable_label, InfoDialState};

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

    // ── Email/Telegram/Discord/News cluster centred in gap between clock and backup ──
    bx.append(&v_spacer());
    let email_state = Rc::new(RefCell::new(EmailState::default()));
    let rss_state = Rc::new(RefCell::new(RssState::default()));
    let comms_box = GtkBox::builder()
        .orientation(Orientation::Vertical)
        .spacing(2)
        .halign(gtk4::Align::Center)
        .valign(gtk4::Align::Center)
        .build();

    let media_click = |source: &'static str| {
        move || {
            let _ = std::process::Command::new("alacritty")
                .args([
                    "-e",
                    "fish",
                    "-c",
                    &format!("rkt-mediabob {}; read -P 'Press Enter to close'", source),
                ])
                .spawn();
        }
    };

    let email_widget = make_clickable_label(
        "email: …",
        "rkt-right-widget",
        Box::new(media_click("email")),
    );
    email_widget.set_halign(gtk4::Align::Center);
    comms_box.append(&email_widget);

    let telegram_widget = make_clickable_label(
        "telegram: …",
        "rkt-right-widget",
        Box::new(media_click("telegram")),
    );
    telegram_widget.set_halign(gtk4::Align::Center);
    comms_box.append(&telegram_widget);

    let discord_widget = make_clickable_label(
        "discord: …",
        "rkt-right-widget",
        Box::new(media_click("discord")),
    );
    discord_widget.set_halign(gtk4::Align::Center);
    comms_box.append(&discord_widget);

    let rss_widget =
        make_clickable_label("news: …", "rkt-right-widget", Box::new(media_click("news")));
    rss_widget.set_halign(gtk4::Align::Center);
    rss_widget.set_valign(gtk4::Align::Center);
    comms_box.append(&rss_widget);

    bx.append(&comms_box);

    // ── Backup dial (screen centre) ──
    bx.append(&v_spacer());
    let backup_state = InfoDialState::new();
    let backup_click = || {
        let script = std::path::PathBuf::from(std::env::var("HOME").unwrap_or_default())
            .join(".hermes")
            .join("skills")
            .join("system-administration")
            .join("workstation-backup-recovery")
            .join("scripts")
            .join("hermes-system-backup.sh");
        let _ = std::process::Command::new("alacritty")
            .args([
                "-e",
                "fish",
                "-c",
                &format!(
                    "echo 'Starting backup…'; {} || read -P 'Press Enter'",
                    script.display()
                ),
            ])
            .spawn();
    };
    let backup_dial = crate::widgets::info_dial::build(
        &backup_state,
        dial_size,
        dial_height,
        Some(Box::new(backup_click)),
    );
    bx.append(&backup_dial);

    // ── USB + security between backup and weather dials ──
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
            let _hr = now.hour();
            let min = now.minute();
            *clock_state.center.borrow_mut() = now
                .format("%I%P")
                .unwrap_or_default()
                .trim_start_matches('0')
                .to_string();
            *clock_state.value.borrow_mut() = (min as f64 / 60.0).clamp(0.0, 1.0);
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

    // ── Panel data updater (every 30s) ──
    {
        let weather_state = weather_state.clone();
        let backup_state = backup_state.clone();
        let email_state = email_state.clone();
        let rss_state = rss_state.clone();
        let email_widget = email_widget.clone();
        let telegram_widget = telegram_widget.clone();
        let discord_widget = discord_widget.clone();
        let rss_widget = rss_widget.clone();
        let security_widget = security_widget.clone();

        let refresh = move || -> Option<()> {
            let out = std::process::Command::new("rkt-panel-data")
                .output()
                .ok()
                .and_then(|o| serde_json::from_slice::<serde_json::Value>(&o.stdout).ok())?;

            if let Some(w) = out.get("weather") {
                let temp = w.get("current_temp_c")?.as_f64()?;
                let max = 45.0;
                let pct = (temp / max).clamp(0.0, 1.0);
                *weather_state.value.borrow_mut() = pct;
                *weather_state.center.borrow_mut() = format!("{:.0}°", temp);
                *weather_state.sub.borrow_mut() =
                    w.get("condition")?.as_str().unwrap_or("").to_string();
                *weather_state.colour_override.borrow_mut() = None;
            }

            if let Some(e) = out.get("email") {
                let unread = e.get("unread")?.as_i64().unwrap_or(-1);
                email_state.borrow_mut().unread = Some(unread);
                let text = if unread < 0 {
                    "email: ?".to_string()
                } else {
                    format!("email: {}", unread)
                };
                if let Some(lbl) = email_widget.first_child().and_downcast::<Label>() {
                    lbl.set_label(&text);
                }
            }

            if let Some(s) = out.get("social") {
                let tg = s.get("telegram")?.get("unread")?.as_i64().unwrap_or(-1);
                let tg_text = if tg < 0 {
                    "telegram: ?".to_string()
                } else {
                    format!("telegram: {}", tg)
                };
                if let Some(lbl) = telegram_widget.first_child().and_downcast::<Label>() {
                    lbl.set_label(&tg_text);
                }
                let dc = s.get("discord")?.get("unread")?.as_i64().unwrap_or(-1);
                let dc_text = if dc < 0 {
                    "discord: ?".to_string()
                } else {
                    format!("discord: {}", dc)
                };
                if let Some(lbl) = discord_widget.first_child().and_downcast::<Label>() {
                    lbl.set_label(&dc_text);
                }
            }

            if let Some(r) = out.get("rss") {
                let count = r.get("items")?.as_array()?.len() as i64;
                if let Some(lbl) = rss_widget.first_child().and_downcast::<Label>() {
                    lbl.set_label(&format!("news: {}", count));
                }
                let items: Vec<(String, String)> = r
                    .get("items")?
                    .as_array()?
                    .iter()
                    .filter_map(|it| {
                        let title = it.get("title")?.as_str()?.to_string();
                        let link = it.get("link")?.as_str()?.to_string();
                        Some((title, link))
                    })
                    .take(30)
                    .collect();
                if !items.is_empty() {
                    rss_state.borrow_mut().items = items;
                }
            }

            if let Some(b) = out.get("backup") {
                let days = b.get("days_since")?.as_i64().unwrap_or(-1);
                *backup_state.center.borrow_mut() = if days < 0 {
                    "?".to_string()
                } else {
                    days.to_string()
                };
                *backup_state.sub.borrow_mut() = if days == 1 {
                    "day".to_string()
                } else {
                    "days".to_string()
                };
                if days < 0 {
                    *backup_state.value.borrow_mut() = 0.0;
                    *backup_state.colour_override.borrow_mut() = Some((0.4, 0.4, 0.4));
                } else {
                    let max_days = 14.0;
                    *backup_state.value.borrow_mut() = (days as f64 / max_days).clamp(0.0, 1.0);
                    *backup_state.colour_override.borrow_mut() = None;
                }
                let status = b.get("status")?.as_str().unwrap_or("unknown");
                email_state.borrow_mut().last_backup_status = Some(status.to_string());
            }

            if let Some(s) = out.get("security") {
                let text = s.get("text")?.as_str().unwrap_or("security: …");
                if let Some(lbl) = security_widget.first_child().and_downcast::<Label>() {
                    lbl.set_label(text);
                }
            }

            Some(())
        };

        refresh();

        gtk4::glib::source::timeout_add_local(Duration::from_secs(30), move || {
            refresh();
            gtk4::glib::ControlFlow::Continue
        });
    }

    bx
}

#[derive(Default)]
struct EmailState {
    unread: Option<i64>,
    last_backup_status: Option<String>,
}

#[derive(Default)]
struct RssState {
    items: Vec<(String, String)>,
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
