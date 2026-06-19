use std::cell::RefCell;
use std::fs;
use std::rc::Rc;

use gtk4::gdk::Display;
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
        let mut parts = line.split_whitespace();
        if let Some(iface_raw) = parts.next() {
            let iface = iface_raw.trim_end_matches(':');
            if iface == "lo" {
                continue;
            }
            let recv = parts.next().and_then(|s| s.parse::<u64>().ok()).unwrap_or(0);
            parts.nth(6);
            let send = parts.next().and_then(|s| s.parse::<u64>().ok()).unwrap_or(0);
            new.push((iface.to_string(), recv, send));

            if let Some(old) = prev.iter().find(|p| p.0 == iface) {
                let dr = recv.saturating_sub(old.1) as f64;
                let ds = send.saturating_sub(old.2) as f64;
                total_down += dr;
                total_up += ds;
            }
        }
    }
    *prev = new;
    format!("↑ {:.1} KB/s\n↓ {:.1} KB/s", total_up / 1024.0, total_down / 1024.0)
}

fn build_dashboard() -> gtk4::Box {
    let dashboard = gtk4::Box::new(gtk4::Orientation::Vertical, 8);
    dashboard.add_css_class("dashboard");
    dashboard.set_margin_top(12);
    dashboard.set_margin_bottom(12);
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

    logo_btn.connect_clicked(move |_| {
        popover.popup();
    });

    dashboard.append(&logo_btn);

    // Scrollable widget area
    let scroll = gtk4::ScrolledWindow::new();
    scroll.set_vexpand(true);
    scroll.set_policy(gtk4::PolicyType::Never, gtk4::PolicyType::Automatic);

    let widgets = gtk4::Box::new(gtk4::Orientation::Vertical, 12);
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
    let mem_lbl = gtk4::Label::new(Some("MEM: ...%"));
    let load_lbl = gtk4::Label::new(Some("Load: ..."));
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

    gtk4::glib::source::timeout_add_seconds_local(1, move || {
        cpu_lbl.set_text(&read_cpu_delta(&mut *cpu_state.borrow_mut()));
        mem_lbl.set_text(&read_mem());
        load_lbl.set_text(&read_load());
        net_lbl.set_text(&read_net_rate(&mut *net_state.borrow_mut()));
        gtk4::glib::ControlFlow::Continue
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

    // Layer-shell setup
    window.init_layer_shell();
    window.set_layer(Layer::Top);
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
