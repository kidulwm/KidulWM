use gtk4::prelude::*;
use gtk4::{Box as GtkBox, Entry, Label, Orientation};
use std::cell::RefCell;
use std::rc::Rc;
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Default)]
pub struct UsbState {
    pub sysname: Option<String>,
    pub attempts: usize,
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

pub fn build_usb_widget() -> (GtkBox, Label, Entry, Rc<RefCell<UsbState>>) {
    let usb_state = Rc::new(RefCell::new(UsbState::default()));
    let usb_box = GtkBox::builder()
        .orientation(Orientation::Vertical)
        .spacing(2)
        .halign(gtk4::Align::Center)
        .build();
    usb_box.add_css_class("rkt-right-widget");
    usb_box.add_css_class("hidden");
    usb_box.set_visible(false);

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

    (usb_box, usb_label, usb_entry, usb_state)
}

pub fn spawn_usb_updater(
    usb_label: Label,
    usb_state: Rc<RefCell<UsbState>>,
    usb_box: GtkBox,
    usb_entry: Entry,
) {
    let pending_path = usb_pending_file();
    let state_path = usb_state_file();

    gtk4::glib::source::timeout_add_local(std::time::Duration::from_secs(1), move || {
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
            usb_box.set_visible(true);
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
                usb_box.set_visible(true);
                usb_state.borrow_mut().sysname = None;
            }
            "clear" => {
                usb_label.set_label("usb: clear");
                usb_box.set_cursor_from_name(None);
                usb_box.remove_css_class("hidden");
                usb_box.set_visible(true);
                usb_state.borrow_mut().sysname = None;
            }
            "blocked" => {
                usb_label.set_label("usb: blocked");
                usb_box.set_cursor_from_name(None);
                usb_box.remove_css_class("hidden");
                usb_box.set_visible(true);
                usb_state.borrow_mut().sysname = None;
            }
            _ => {
                usb_label.set_label("usb: …");
                usb_state.borrow_mut().sysname = None;
                usb_box.set_cursor_from_name(None);
                usb_box.add_css_class("hidden");
                usb_box.set_visible(false);
                if gtk4::prelude::WidgetExt::is_visible(&usb_entry) {
                    usb_entry.set_visible(false);
                    usb_entry.set_text("");
                }
            }
        }

        gtk4::glib::ControlFlow::Continue
    });
}
