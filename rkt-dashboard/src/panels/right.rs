use gtk4::prelude::*;
use gtk4::{Box as GtkBox, Label, Orientation};
use std::cell::RefCell;
use std::rc::Rc;
use std::time::Duration;

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

    // ── Top: clock dial + date ──
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

    let date_label = Label::new(None);
    date_label.add_css_class("rkt-clock-date");
    date_label.set_halign(gtk4::Align::Center);
    top_box.append(&date_label);

    bx.append(&top_box);

    // ── Email/Telegram/Discord cluster centred in gap between clock and backup ──
    bx.append(&v_spacer());
    let email_state = Rc::new(RefCell::new(EmailState::default()));
    let comms_box = GtkBox::builder()
        .orientation(Orientation::Vertical)
        .spacing(2)
        .halign(gtk4::Align::Center)
        .valign(gtk4::Align::Center)
        .build();

    let email_click = || {
        let _ = std::process::Command::new("alacritty")
            .args([
                "-e",
                "fish",
                "-c",
                "rkt-email-view; read -P 'Press Enter to close'",
            ])
            .spawn();
    };
    let email_widget = make_clickable_label("email: …", "rkt-right-widget", Box::new(email_click));
    email_widget.set_halign(gtk4::Align::Center);
    comms_box.append(&email_widget);

    let telegram_widget = make_clickable_label(
        "telegram: …",
        "rkt-right-widget",
        Box::new(|| {
            let _ = std::process::Command::new("telegram").spawn();
        }),
    );
    telegram_widget.set_halign(gtk4::Align::Center);
    comms_box.append(&telegram_widget);

    let discord_widget = make_clickable_label(
        "discord: …",
        "rkt-right-widget",
        Box::new(|| {
            let _ = std::process::Command::new("xdg-open")
                .arg("https://discord.com/channels/@me")
                .spawn();
        }),
    );
    discord_widget.set_halign(gtk4::Align::Center);
    comms_box.append(&discord_widget);

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

    // ── Security scan feed (between backup and news) ──
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

    // ── News line centred in gap between backup and weather ──
    bx.append(&v_spacer());
    let rss_state = Rc::new(RefCell::new(RssState::default()));
    let rss_click = {
        let st = rss_state.clone();
        move || {
            if let Some(link) = st.borrow().current_link() {
                let _ = std::process::Command::new("xdg-open").arg(link).spawn();
            }
        }
    };
    let rss_widget = make_clickable_label("news: …", "rkt-right-widget", Box::new(rss_click));
    rss_widget.set_halign(gtk4::Align::Center);
    rss_widget.set_valign(gtk4::Align::Center);
    bx.append(&rss_widget);

    // ── Weather dial (bottom) ──
    bx.append(&v_spacer());
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
        let date_label = date_label.clone();
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
            date_label.set_label(&now.format("%d %B").unwrap_or_default().to_lowercase());
            gtk4::glib::ControlFlow::Continue
        });
    }

    // ── RSS rotator (every 12s) ──
    {
        let rss_state = rss_state.clone();
        let rss_widget = rss_widget.clone();
        gtk4::glib::source::timeout_add_local(Duration::from_secs(12), move || {
            let (text, _link) = rss_state.borrow_mut().next_item();
            if let Some(lbl) = rss_widget.first_child().and_downcast::<Label>() {
                lbl.set_label(&text);
            }
            gtk4::glib::ControlFlow::Continue
        });
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
                } else if unread == 0 {
                    "email: clear".to_string()
                } else if unread == 1 {
                    "email: 1 new".to_string()
                } else {
                    format!("email: {} new", unread)
                };
                if let Some(lbl) = email_widget.first_child().and_downcast::<Label>() {
                    lbl.set_label(&text);
                }
            }

            if let Some(e) = out.get("social") {
                let tg = e
                    .get("telegram")?
                    .get("label")?
                    .as_str()
                    .unwrap_or("telegram: -");
                if let Some(lbl) = telegram_widget.first_child().and_downcast::<Label>() {
                    lbl.set_label(tg);
                }
                let dc = e
                    .get("discord")?
                    .get("label")?
                    .as_str()
                    .unwrap_or("discord: -");
                if let Some(lbl) = discord_widget.first_child().and_downcast::<Label>() {
                    lbl.set_label(dc);
                }
            }

            if let Some(b) = out.get("backup") {
                let days = b.get("days_since")?.as_i64().unwrap_or(-1);
                let status = b.get("status")?.as_str().unwrap_or("unknown");
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
                email_state.borrow_mut().last_backup_status = Some(status.to_string());
            }

            if let Some(r) = out.get("rss") {
                if let Some(items) = r.get("items").and_then(|v| v.as_array()) {
                    let headlines: Vec<(String, String)> = items
                        .iter()
                        .filter_map(|it| {
                            let title = it.get("title")?.as_str()?.to_string();
                            let link = it.get("link")?.as_str()?.to_string();
                            Some((title, link))
                        })
                        .take(30)
                        .collect();
                    if !headlines.is_empty() {
                        let mut st = rss_state.borrow_mut();
                        st.items = headlines;
                        let (text, _link) = st.next_item();
                        if let Some(lbl) = rss_widget.first_child().and_downcast::<Label>() {
                            lbl.set_label(&text);
                        }
                    }
                }
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
    idx: usize,
}

impl RssState {
    fn next_item(&mut self) -> (String, String) {
        if self.items.is_empty() {
            return ("news: no updates".to_string(), String::new());
        }
        let item = self.items[self.idx].clone();
        let preview = if item.0.len() > 50 {
            format!("{}…", &item.0[..50])
        } else {
            item.0.clone()
        };
        self.idx = (self.idx + 1) % self.items.len();
        (format!("news: {}", preview), item.1)
    }

    fn current_link(&self) -> Option<String> {
        if self.items.is_empty() {
            None
        } else {
            let idx = (self.idx + self.items.len() - 1) % self.items.len();
            Some(self.items[idx].1.clone())
        }
    }
}
