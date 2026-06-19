use std::cell::RefCell;
use std::fs;
use std::net::Ipv4Addr;
use std::rc::Rc;

use gtk4::gdk::Display;
use gtk4::glib;
use gtk4::prelude::*;
use gtk4_layer_shell::{Edge, Layer, LayerShell};

const APP_ID: &str = "org.ratukidultech.RKTDashboard";
const CSS: &str = include_str!("style.css");

fn read_cpu_delta(prev: &mut (u64, u64)) -> String {
    let line = fs::read_to_string("/proc/stat")
        .ok()
        .and_then(|s| s.lines().next().map(|l| l.to_string()))
        .unwrap_or_default();
    let parts: Vec<&str> = line.split_whitespace().collect();
    if parts.len() < 5 {
        return String::from("CPU: N/A");
    }
    let user = parts[1].parse::<u64>().unwrap_or(0);
    let nice = parts[2].parse::<u64>().unwrap_or(0);
    let system = parts[3].parse::<u64>().unwrap_or(0);
    let idle = parts[4].parse::<u64>().unwrap_or(0);
    let busy = user + nice + system;
    let total = busy + idle;

    let (p_busy, p_total) = *prev;
    *prev = (busy, total);

    if p_total == 0 || total <= p_total {
        return String::from("CPU: ...%");
    }
    let delta_busy = busy - p_busy;
    let delta_total = total - p_total;
    let pct = (delta_busy as f64 / delta_total as f64) * 100.0;
    format!("CPU: {:.1}%", pct)
}

fn read_mem() -> String {
    let data = fs::read_to_string("/proc/meminfo").unwrap_or_default();
    let mut total = 0u64;
    let mut available = 0u64;
    for line in data.lines() {
        let mut it = line.split_whitespace();
        if let Some(key) = it.next() {
            if let Some(val) = it.next() {
                match key {
                    "MemTotal:" => total = val.parse::<u64>().unwrap_or(0),
                    "MemAvailable:" => available = val.parse::<u64>().unwrap_or(0),
                    _ => {}
                }
            }
        }
    }
    if total == 0 {
        return String::from("MEM: N/A");
    }
    let used = total - available;
    let pct = (used as f64 / total as f64) * 100.0;
    format!("MEM: {:.1}%", pct)
}

fn read_load() -> String {
    fs::read_to_string("/proc/loadavg")
        .ok()
        .and_then(|s| s.split_whitespace().next().map(|v| format!("Load: {}", v)))
        .unwrap_or_else(|| String::from("Load: N/A"))
}

fn read_net_rate(prev: &mut Vec<(String, u64, u64)>) -> String {
    let data = fs::read_to_string("/proc/net/dev").unwrap_or_default();
    let mut new = Vec::new();
    let mut total_up = 0f64;
    let mut total_down = 0f64;
    for line in data.lines().skip(2) {
        let cols: Vec<&str> = line.split_whitespace().collect();
        if cols.is_empty() {
            continue;
        }
        let iface = cols[0].trim_end_matches(':');
        if iface == "lo" || cols.len() < 10 {
            continue;
        }
        let recv = cols[1].parse::<u64>().unwrap_or(0);
        let send = cols[9].parse::<u64>().unwrap_or(0);
        new.push((iface.to_string(), recv, send));

        if let Some(old) = prev.iter().find(|p| p.0 == iface) {
            let dr = recv.saturating_sub(old.1) as f64;
            let ds = send.saturating_sub(old.2) as f64;
            total_down += dr;
            total_up += ds;
        }
    }
    *prev = new;
    format!(
        "↑ {:.1} KB/s\n↓ {:.1} KB/s",
        total_up / 1024.0,
        total_down / 1024.0
    )
}

fn decode_ipv4_port(raw: &str) -> Option<String> {
    let (ip_hex, port_hex) = raw.split_once(':')?;
    if ip_hex.len() != 8 {
        return None;
    }
    let ip_u32 = u32::from_str_radix(ip_hex, 16).ok()?;
    let ip = Ipv4Addr::from(ip_u32.to_le_bytes());
    let port = u16::from_str_radix(port_hex, 16).ok()?;
    Some(format!("{}:{}", ip, port))
}

fn read_tcp_connections() -> Vec<(String, String, String)> {
    let mut out = Vec::new();
    for path in ["/proc/net/tcp", "/proc/net/tcp6"] {
        let data = fs::read_to_string(path).unwrap_or_default();
        for (idx, line) in data.lines().enumerate() {
            if idx == 0 {
                // header
                continue;
            }
            let cols: Vec<&str> = line.split_whitespace().collect();
            if cols.len() < 4 {
                continue;
            }
            let st = u8::from_str_radix(cols[3], 16).unwrap_or(0);
            if st != 0x01 {
                // only ESTABLISHED
                continue;
            }
            let local = decode_ipv4_port(cols[1]).unwrap_or_else(|| cols[1].to_string());
            let remote = decode_ipv4_port(cols[2]).unwrap_or_else(|| cols[2].to_string());
            let uid = cols[7].parse::<u32>().unwrap_or(0);
            out.push((format!("uid:{}", uid), local, remote));
        }
    }
    out
}

fn build_dashboard() -> gtk4::Box {
    let dashboard = gtk4::Box::new(gtk4::Orientation::Vertical, 8);
    dashboard.add_css_class("dashboard");
    dashboard.set_margin_top(16);
    dashboard.set_margin_bottom(16);
    dashboard.set_margin_start(12);
    dashboard.set_margin_end(12);

    // Logo / control center button
    let logo_btn = gtk4::Button::with_label("RKT");
    logo_btn.add_css_class("logo-button");
    logo_btn.set_hexpand(false);

    // Control center popover
    let menu_box = gtk4::Box::new(gtk4::Orientation::Vertical, 4);
    menu_box.add_css_class("control-center");
    for label in &["Terminal", "Files", "Browser", "Settings", "Power Off"] {
        let btn = gtk4::Button::with_label(label);
        btn.add_css_class("flat");
        menu_box.append(&btn);
    }
    let popover = gtk4::Popover::new();
    popover.set_child(Some(&menu_box));
    popover.set_parent(&logo_btn);
    popover.set_position(gtk4::PositionType::Right);

    // Click: toggle Noctalia launcher and popover stays open / opens on hover too.
    let pc = popover.clone(); // actuallypopover need not be held
    logo_btn.connect_clicked(move |_| {
        let _ = std::process::Command::new("qs")
            .args(["-c", "noctalia-shell", "ipc", "call", "launcher", "toggle"])
            .spawn();
        pc.popup();
    });

    /* Hover: show Noctalia launcher (disabled for now; click toggles).
    let last_toggle: Rc<RefCell<std::time::Instant>> =
        Rc::new(RefCell::new(std::time::Instant::now()));
    let hover = gtk4::EventControllerMotion::new();
    hover.connect_enter(move |_, _, _| {
        let mut last = last_toggle.borrow_mut();
        if last.elapsed().as_secs() >= 2 {
            *last = std::time::Instant::now();
            let _ = std::process::Command::new("qs")
                .args(["-c", "noctalia-shell", "ipc", "call", "launcher", "toggle"])
                .spawn();
        }
    });
    logo_btn.add_controller(hover);
    */

    dashboard.append(&logo_btn);

    // Scrollable widget area
    let scroll = gtk4::ScrolledWindow::new();
    scroll.set_vexpand(true);
    scroll.set_policy(gtk4::PolicyType::Never, gtk4::PolicyType::Automatic);

    let widgets = gtk4::Box::new(gtk4::Orientation::Vertical, 14);
    widgets.add_css_class("widgets");

    // System vitals
    let vitals = gtk4::Frame::new(Some("System Vitals"));
    vitals.add_css_class("widget-frame");
    let vbox = gtk4::Box::new(gtk4::Orientation::Vertical, 4);
    vbox.set_margin_top(8);
    vbox.set_margin_bottom(8);
    vbox.set_margin_start(8);
    vbox.set_margin_end(8);
    let cpu_lbl = gtk4::Label::new(Some("CPU: ...%"));
    cpu_lbl.add_css_class("top-text");
    let mem_lbl = gtk4::Label::new(Some("MEM: ...%"));
    mem_lbl.add_css_class("mid-text");
    let load_lbl = gtk4::Label::new(Some("Load: ..."));
    load_lbl.add_css_class("bottom-text");
    vbox.append(&cpu_lbl);
    vbox.append(&mem_lbl);
    vbox.append(&load_lbl);
    vitals.set_child(Some(&vbox));
    widgets.append(&vitals);

    // Network visual
    let net = gtk4::Frame::new(Some("Network"));
    net.add_css_class("widget-frame");
    let nbox = gtk4::Box::new(gtk4::Orientation::Vertical, 4);
    nbox.set_margin_top(8);
    nbox.set_margin_bottom(8);
    nbox.set_margin_start(8);
    nbox.set_margin_end(8);
    let net_lbl = gtk4::Label::new(Some("↑ ... KB/s\n↓ ... KB/s"));
    net_lbl.set_single_line_mode(false);
    nbox.append(&net_lbl);

    // Live connections list
    let conn_box = gtk4::Box::new(gtk4::Orientation::Vertical, 2);
    conn_box.set_margin_top(4);
    let conn_list = gtk4::Box::new(gtk4::Orientation::Vertical, 2);
    conn_box.append(&conn_list);
    nbox.append(&conn_box);
    net.set_child(Some(&nbox));
    widgets.append(&net);

    // News river
    let news = gtk4::Frame::new(Some("News River"));
    news.add_css_class("widget-frame");
    let news_box = gtk4::Box::new(gtk4::Orientation::Vertical, 4);
    news_box.set_margin_top(8);
    news_box.set_margin_bottom(8);
    news_box.set_margin_start(8);
    news_box.set_margin_end(8);
    news_box.append(&gtk4::Label::new(Some("No updates yet.")));
    news.set_child(Some(&news_box));
    widgets.append(&news);

    scroll.set_child(Some(&widgets));
    dashboard.append(&scroll);

    // Update loop
    let cpu_state: Rc<RefCell<(u64, u64)>> = Rc::new(RefCell::new((0, 0)));
    let net_state: Rc<RefCell<Vec<(String, u64, u64)>>> = Rc::new(RefCell::new(Vec::new()));

    glib::source::timeout_add_seconds_local(1, move || {
        cpu_lbl.set_text(&read_cpu_delta(&mut *cpu_state.borrow_mut()));
        mem_lbl.set_text(&read_mem());
        load_lbl.set_text(&read_load());
        net_lbl.set_text(&read_net_rate(&mut *net_state.borrow_mut()));

        // refresh connections list (keep last 5)
        let conns = read_tcp_connections();
        while conn_list.first_child().is_some() {
            conn_list.remove(&conn_list.first_child().unwrap());
        }
        for (user, local, remote) in conns.iter().take(5) {
            let row = gtk4::Label::new(Some(&format!("{} → {}", local, remote)));
            row.add_css_class("connection-row");
            row.set_xalign(0.0);
            conn_list.append(&row);
            let sub = gtk4::Label::new(Some(&format!("  {}", user)));
            sub.add_css_class("connection-row");
            sub.set_xalign(0.0);
            conn_list.append(&sub);
        }

        glib::ControlFlow::Continue
    });

    dashboard
}

fn activate(app: &gtk4::Application) {
    let window = gtk4::ApplicationWindow::new(app);
    window.set_title(Some("RKT Dashboard"));
    window.set_default_size(260, -1);

    // Style
    let provider = gtk4::CssProvider::new();
    provider.load_from_data(CSS);
    if let Some(display) = Display::default() {
        gtk4::style_context_add_provider_for_display(
            &display,
            &provider,
            gtk4::STYLE_PROVIDER_PRIORITY_APPLICATION,
        );
    }

    window.set_child(Some(&build_dashboard()));

    // Layer-shell setup: sit above windows, anchored to left gap.
    window.init_layer_shell();
    window.set_layer(Layer::Overlay);
    window.auto_exclusive_zone_enable();
    window.set_anchor(Edge::Left, true);
    window.set_anchor(Edge::Top, true);
    window.set_anchor(Edge::Bottom, true);

    window.present();
}

fn main() {
    let app = gtk4::Application::new(Some(APP_ID), Default::default());
    app.connect_activate(|app| activate(app));
    app.run();
}
