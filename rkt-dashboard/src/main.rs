pub mod config;
pub mod panels;
pub mod widgets;

use gtk4::gdk::{Display, Monitor};
use gtk4::gio::prelude::ListModelExt;
use gtk4::prelude::*;
use gtk4_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};

fn main() {
    let app = gtk4::Application::builder()
        .application_id("org.ratukidul.rkt-dashboard")
        .build();
    app.connect_activate(build_ui);
    app.run();
}

fn build_ui(app: &gtk4::Application) {
    let cfg = config::Config::load("/home/dad/dev/KidulWM/rkt-dashboard/rkt-dashboard.json");
    load_css();

    let values = Values::new();
    values.spawn_updater();

    let display = Display::default().expect("no display");
    let monitors = display.monitors();
    for i in 0..monitors.n_items() {
        if let Some(mon) = monitors.item(i).and_downcast::<Monitor>() {
            let h = mon.geometry().height();

            let left_win = gtk4::ApplicationWindow::builder()
                .application(app)
                .title("RKT Mission Control — Left")
                .default_width(cfg.left.width)
                .default_height(h)
                .decorated(false)
                .build();
            init_layer_shell(&left_win, true, Some(&mon));
            let left_panel = panels::build_left(&cfg, &values, h);
            left_win.set_child(Some(&left_panel));

            let right_win = gtk4::ApplicationWindow::builder()
                .application(app)
                .title("RKT Mission Control — Right")
                .default_width(cfg.right.width)
                .default_height(h)
                .decorated(false)
                .build();
            init_layer_shell(&right_win, false, Some(&mon));
            let right_panel = panels::build_right(&cfg, &values);
            right_win.set_child(Some(&right_panel));

            left_win.present();
            right_win.present();
        }
    }
}

fn init_layer_shell(window: &gtk4::ApplicationWindow, left: bool, mon: Option<&Monitor>) {
    window.init_layer_shell();
    window.set_layer(Layer::Bottom);
    window.set_monitor(mon);
    window.set_anchor(Edge::Top, true);
    window.set_anchor(Edge::Bottom, true);
    window.set_exclusive_zone(-1);
    window.set_keyboard_mode(KeyboardMode::OnDemand);
    if left {
        window.set_anchor(Edge::Left, true);
    } else {
        window.set_anchor(Edge::Right, true);
    }
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
