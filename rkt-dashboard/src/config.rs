use serde::Deserialize;
use std::collections::HashMap;

#[derive(Debug, Deserialize, Clone)]
pub struct Theme {
    pub electric_blue: String,
    pub purple: String,
    pub teal: String,
    pub white: String,
    pub glass: String,
    pub glow: String,
}

#[derive(Debug, Deserialize, Clone)]
pub struct PanelCfg {
    pub width: i32,
    pub widgets: Vec<WidgetCfg>,
}

#[derive(Debug, Deserialize, Clone)]
pub struct WidgetCfg {
    pub id: String,
    #[serde(rename = "type")]
    pub ty: String,
    #[serde(default)]
    pub label: Option<String>,
    #[serde(default)]
    pub source: Option<String>,
    #[serde(default)]
    pub max: Option<f64>,
    #[serde(default)]
    pub suffix: Option<String>,
    #[serde(flatten)]
    pub extra: HashMap<String, serde_json::Value>,
}

#[derive(Debug, Deserialize, Clone)]
pub struct Config {
    pub theme: Theme,
    #[serde(rename = "left_panel")]
    pub left: PanelCfg,
    #[serde(rename = "right_panel")]
    pub right: PanelCfg,
}

impl Config {
    pub fn load(path: &str) -> Self {
        let data = std::fs::read_to_string(path)
            .unwrap_or_else(|_| include_str!("../rkt-dashboard.json").to_string());
        serde_json::from_str(&data).expect("invalid config")
    }
}
