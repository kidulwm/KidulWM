use gtk4::prelude::*;
use gtk4::{Box, Orientation};
use std::cell::RefCell;
use std::rc::Rc;

use crate::config::{Config, WidgetCfg};
use crate::widgets;
use crate::Values;

pub fn build_left(cfg: &Config, values: &Values) -> Box {
    let bx = Box::builder()
        .orientation(Orientation::Vertical)
        .spacing(12)
        .margin_top(24)
        .margin_bottom(24)
        .margin_start(18)
        .margin_end(12)
        .build();
    bx.add_css_class("rkt-panel");

    for w in &cfg.left.widgets {
        if let Some(child) = build_widget(w, cfg.left.width, values) {
            bx.append(&child);
        }
    }

    bx
}

fn build_widget(w: &WidgetCfg, _width: i32, values: &Values) -> Option<gtk4::Widget> {
    match w.ty.as_str() {
        "logo" => {
            let trigger: Rc<dyn Fn()> = Rc::new(|| {
                let _ = std::process::Command::new("qs")
                    .args(["-c", "noctalia-shell", "ipc", "call", "launcher", "toggle"])
                    .spawn();
            });
            Some(widgets::logo::build(160, 160, trigger).upcast())
        }
        "text_block" => {
            let v = value_for(w.source.as_deref()?, values)?;
            Some(widgets::text_block::build(w, v, 180, 60).upcast())
        }
        "bar_gauge" => {
            let v = value_for(w.source.as_deref()?, values)?;
            Some(widgets::bar_gauge::build(w, v, 180, 90).upcast())
        }
        _ => None,
    }
}

fn value_for(source: &str, values: &Values) -> Option<Rc<RefCell<f64>>> {
    match source {
        "cpu" => Some(values.cpu.clone()),
        "mem_used" => Some(values.mem_used.clone()),
        "mem_total" => Some(values.mem_total.clone()),
        "load_1" => Some(values.load_0.clone()),
        "net_up" => Some(values.net_up.clone()),
        "net_down" => Some(values.net_down.clone()),
        "mem_pct" => Some(values.mem_pct.clone()),
        _ => None,
    }
}
