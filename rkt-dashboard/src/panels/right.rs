use gtk4::prelude::*;
use gtk4::{Box, Orientation};
use std::cell::RefCell;
use std::rc::Rc;

use crate::config::{Config, WidgetCfg};
use crate::widgets;
use crate::Values;

pub fn build_right(cfg: &Config, values: &Values) -> Box {
    let bx = Box::builder()
        .orientation(Orientation::Vertical)
        .spacing(14)
        .margin_top(24)
        .margin_bottom(24)
        .margin_start(12)
        .margin_end(18)
        .build();
    bx.add_css_class("rkt-panel");

    for w in &cfg.right.widgets {
        if let Some(child) = build_widget(w, cfg.right.width, values) {
            bx.append(&child);
        }
    }

    bx
}

fn build_widget(w: &WidgetCfg, _width: i32, values: &Values) -> Option<gtk4::Widget> {
    match w.ty.as_str() {
        "clock" => Some(widgets::clock::build(180, 180).upcast()),
        "dial" => {
            let v = value_for(w.source.as_deref()?, values)?;
            Some(widgets::dial::build(w, v, 180, 180).upcast())
        }
        _ => None,
    }
}

fn value_for(source: &str, values: &Values) -> Option<Rc<RefCell<f64>>> {
    match source {
        "cpu" => Some(values.cpu.clone()),
        "mem_pct" => Some(values.mem_pct.clone()),
        _ => None,
    }
}
