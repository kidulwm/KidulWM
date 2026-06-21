use gtk4::prelude::*;
use gtk4::{Box, Orientation};
use std::cell::RefCell;
use std::rc::Rc;

use crate::config::WidgetCfg;
use crate::widgets;
use crate::Values;

pub fn build_right(_cfg: &crate::config::Config, values: &Values) -> Box {
    let bx = Box::builder()
        .orientation(Orientation::Vertical)
        .spacing(10)
        .margin_top(24)
        .margin_bottom(24)
        .margin_start(12)
        .margin_end(12)
        .build();
    bx.add_css_class("rkt-panel");

    let clock = widgets::clock::build(270, 270);
    clock.set_halign(gtk4::Align::Center);
    clock.set_valign(gtk4::Align::Center);
    bx.append(&clock);

    // NET bar gauge — moved to right panel for more width/visibility.
    if let Some(val) = value_for("net_down", values) {
        let net_cfg = WidgetCfg {
            id: "net-bar".to_string(),
            ty: "bar_gauge".to_string(),
            label: Some("NET".to_string()),
            source: Some("net_down".to_string()),
            max: Some(5000.0),
            suffix: None,
            extra: Default::default(),
        };
        let gauge = widgets::bar_gauge::build(&net_cfg, val, 280, 120);
        gauge.set_halign(gtk4::Align::Center);
        bx.append(&gauge);
    }

    bx
}

fn value_for(source: &str, values: &Values) -> Option<Rc<RefCell<f64>>> {
    match source {
        "cpu" => Some(values.cpu.clone()),
        "mem_pct" => Some(values.mem_pct.clone()),
        "load" => Some(values.load_0.clone()),
        "battery" => Some(values.battery.clone()),
        "volume" => Some(values.volume.clone()),
        "brightness" => Some(values.brightness.clone()),
        "clock_pct" => Some(values.clock_pct.clone()),
        "net_down" => Some(values.net_down.clone()),
        "net_up" => Some(values.net_up.clone()),
        _ => None,
    }
}
