pub mod config;
pub mod panel_data;
pub mod panels;
pub mod usb_guard;
pub mod widgets;

use gtk4::gdk::{Display, Monitor};
use gtk4::gio::prelude::ListModelExt;
use gtk4::prelude::*;
use gtk4_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};

fn main() {
    // Catch panics to /tmp/rkt-panic.txt so silent failures are visible.
    std::panic::set_hook(Box::new(|info| {
        let msg = format!("[rkt] PANIC: {}\n", info);
        let _ = std::fs::write("/tmp/rkt-panic.txt", msg.as_bytes());
        eprintln!("{}", msg);
    }));

    let app = gtk4::Application::builder()
        .application_id(&format!(
            "org.ratukidul.rkt-dashboard-{}",
            std::env::var("RKT_MONITOR").unwrap_or_else(|_| "all".to_string())
        ))
        .build();
    app.connect_activate(build_ui);
    app.run();
}

fn build_ui(app: &gtk4::Application) {
    eprintln!("[rkt] build_ui: gtk4_layer_shell supported={:?}", gtk4_layer_shell::is_supported());
    let cfg_path =
        std::env::var("RKT_DASHBOARD_CONFIG").unwrap_or_else(|_| "rkt-dashboard.json".to_string());
    let cfg = config::Config::load(&cfg_path);
    load_css();

    let values = Values::new();
    values.spawn_updater();

    let display = Display::default().expect("no display");
    eprintln!("[rkt] build_ui: display obtained");
    let supported = gtk4_layer_shell::is_supported();
    eprintln!("[rkt] build_ui: gtk4_layer_shell supported={:?}", supported);

    let monitors = display.monitors();
    eprintln!("[rkt] build_ui: {} monitors", monitors.n_items());

    // RKT_MONITOR=connector-name restricts this instance to one monitor.
    // Example: RKT_MONITOR=HDMI-A-1 runs panels only on HDMI-A-1.
    let target_connector = std::env::var("RKT_MONITOR").ok();

    for i in 0..monitors.n_items() {
        if let Some(mon) = monitors.item(i).and_downcast::<Monitor>() {
            let connector = mon
                .connector()
                .map(|s| format!("{}", s))
                .unwrap_or_else(|| format!("monitor-{}", i));
            if let Some(ref target) = target_connector {
                if target != &connector {
                    eprintln!("[rkt] build_ui: skipping monitor {} ({})", i, connector);
                    continue;
                }
            }
            eprintln!("[rkt] build_ui: monitor {}: {:?} name={}", i, mon.geometry(), connector);
            let h = mon.geometry().height();
            let mw = mon.geometry().width() as f64;
            let side_w = (mw * 0.08).round() as i32;

            let mut mon_cfg = cfg.clone();
            mon_cfg.left.width = side_w;
            mon_cfg.right.width = side_w;

            let left_win = gtk4::ApplicationWindow::builder()
                .application(app)
                .title("RKT Mission Control — Left")
                .decorated(false)
                .build();
            left_win.set_default_size(side_w, h);
            left_win.set_size_request(side_w, h);
            // Force a dark background so the panel is visible.
            left_win.add_css_class("rkt-panel");
            // Also set the window's CSS directly as a fallback.
            let _ = left_win.settings(); // ensure settings are loaded
            init_layer_shell(&left_win, true, Some(&mon));
            left_win.set_exclusive_zone(side_w);
            eprintln!("[rkt] build_ui: calling build_left");
            let left_panel = panels::build_left(&mon_cfg, &values, h);
            eprintln!("[rkt] build_ui: build_left returned");
            left_win.set_child(Some(&left_panel));
            eprintln!("[rkt] build_ui: left_win.set_child done");
            left_win.present();
            eprintln!("[rkt] build_ui: left_win.present() done");

            let right_win = gtk4::ApplicationWindow::builder()
                .application(app)
                .title("RKT Mission Control — Right")
                .decorated(false)
                .build();
            right_win.set_default_size(side_w, h);
            right_win.set_size_request(side_w, h);
            init_layer_shell(&right_win, false, Some(&mon));
            right_win.set_exclusive_zone(side_w);
            let right_panel = panels::build_right(&mon_cfg, h, &values);
            right_win.set_child(Some(&right_panel));
            eprintln!("[rkt] build_ui: calling present() on right_win");
            right_win.present();
            eprintln!("[rkt] build_ui: right_win present() done");
        } else {
            eprintln!("[rkt] build_ui: monitor {} downcast failed", i);
        }
    }
}

fn init_layer_shell(window: &gtk4::ApplicationWindow, left: bool, mon: Option<&Monitor>) {
    eprintln!("[rkt] init_layer_shell: starting, left={}", left);
    window.init_layer_shell();
    window.set_layer(Layer::Overlay);
    window.set_anchor(Edge::Top, true);
    window.set_anchor(Edge::Bottom, true);
    window.set_keyboard_mode(KeyboardMode::OnDemand);
    if left {
        window.set_anchor(Edge::Left, true);
        window.set_margin(Edge::Left, 0);
    } else {
        window.set_anchor(Edge::Right, true);
        window.set_margin(Edge::Right, 0);
    }
    // Restore set_monitor — needed for multi-monitor in niri.
    if let Some(m) = mon {
        // Debug: print the raw wl_output pointer
        eprintln!("[rkt] init_layer_shell: set_monitor called, monitor geometry={:?}", m.geometry());
        window.set_monitor(Some(m));
        eprintln!("[rkt] init_layer_shell: set_monitor done");
    }
    eprintln!("[rkt] init_layer_shell: done, left={}", left);
}

fn load_css() {
    let css = include_str!("style.css");
    let provider = gtk4::CssProvider::new();
    provider.load_from_data(css);
    gtk4::style_context_add_provider_for_display(
        &Display::default().expect("no display"),
        &provider,
        gtk4::STYLE_PROVIDER_PRIORITY_APPLICATION,
    );
}
#[derive(Clone)]
pub struct Values {
    cpu: RcBar,
    mem_used: RcBar,
    mem_total: RcBar,
    load_0: RcBar,
    net_up: RcBar,
    net_down: RcBar,
    mem_pct: RcBar,
    battery: RcBar,
    volume: RcBar,
    brightness: RcBar,
    clock_pct: RcBar,
    cpu_temp: RcBar,
    gpu_temp: RcBar,
    cpu_freq: RcBar,
    disk_pct: RcBar,
    swap_pct: RcBar,
    fan_rpm: RcBar,
    power_w: RcBar,
}

type RcBar = std::rc::Rc<std::cell::RefCell<f64>>;

impl Values {
    fn new() -> Self {
        Self {
            cpu: default(),
            mem_used: default(),
            mem_total: default(),
            load_0: default(),
            net_up: default(),
            net_down: default(),
            mem_pct: default(),
            battery: default(),
            volume: default(),
            brightness: default(),
            clock_pct: default(),
            cpu_temp: default(),
            gpu_temp: default(),
            cpu_freq: default(),
            disk_pct: default(),
            swap_pct: default(),
            fan_rpm: default(),
            power_w: default(),
        }
    }
    fn spawn_updater(&self) {
        let vals = self.clone();
        gtk4::glib::source::timeout_add_seconds_local(1, move || {
            let out = std::process::Command::new("rkt-stats")
                .output()
                .ok()
                .and_then(|o| serde_json::from_slice::<serde_json::Value>(&o.stdout).ok());
            if let Some(data) = out {
                *vals.cpu.borrow_mut() = data.get("cpu").and_then(|v| v.as_f64()).unwrap_or(0.0);
                *vals.mem_used.borrow_mut() =
                    data.get("mem_used").and_then(|v| v.as_f64()).unwrap_or(0.0);
                *vals.mem_total.borrow_mut() = data
                    .get("mem_total")
                    .and_then(|v| v.as_f64())
                    .unwrap_or(0.0);
                if let (Some(m), Some(t)) = (
                    data.get("mem_used").and_then(|v| v.as_f64()),
                    data.get("mem_total").and_then(|v| v.as_f64()),
                ) {
                    *vals.mem_pct.borrow_mut() = if t > 0.0 { (m / t) * 100.0 } else { 0.0 };
                }
                if let Some(load) = data.get("load").and_then(|v| v.as_array()) {
                    *vals.load_0.borrow_mut() = load.get(0).and_then(|v| v.as_f64()).unwrap_or(0.0);
                }
                *vals.net_up.borrow_mut() =
                    data.get("net_up").and_then(|v| v.as_f64()).unwrap_or(0.0);
                *vals.net_down.borrow_mut() =
                    data.get("net_down").and_then(|v| v.as_f64()).unwrap_or(0.0);
                *vals.battery.borrow_mut() =
                    data.get("battery").and_then(|v| v.as_f64()).unwrap_or(-1.0);
                *vals.volume.borrow_mut() =
                    data.get("volume").and_then(|v| v.as_f64()).unwrap_or(-1.0);
                *vals.brightness.borrow_mut() = data
                    .get("brightness")
                    .and_then(|v| v.as_f64())
                    .unwrap_or(-1.0);
                *vals.clock_pct.borrow_mut() = data
                    .get("clock_pct")
                    .and_then(|v| v.as_f64())
                    .unwrap_or(0.0);
                *vals.cpu_temp.borrow_mut() = data
                    .get("cpu_temp")
                    .and_then(|v| v.as_f64())
                    .unwrap_or(-1.0);
                *vals.gpu_temp.borrow_mut() = data
                    .get("gpu_temp")
                    .and_then(|v| v.as_f64())
                    .unwrap_or(-1.0);
                *vals.cpu_freq.borrow_mut() = data
                    .get("cpu_freq")
                    .and_then(|v| v.as_f64())
                    .unwrap_or(-1.0);
                *vals.disk_pct.borrow_mut() = data
                    .get("disk_pct")
                    .and_then(|v| v.as_f64())
                    .unwrap_or(-1.0);
                *vals.swap_pct.borrow_mut() =
                    data.get("swap_pct").and_then(|v| v.as_f64()).unwrap_or(0.0);
                *vals.fan_rpm.borrow_mut() =
                    data.get("fan_rpm").and_then(|v| v.as_f64()).unwrap_or(-1.0);
                *vals.power_w.borrow_mut() =
                    data.get("power_w").and_then(|v| v.as_f64()).unwrap_or(-1.0);
            }
            gtk4::glib::ControlFlow::Continue
        });
    }
}

fn default() -> RcBar {
    std::rc::Rc::new(std::cell::RefCell::new(0.0))
}
