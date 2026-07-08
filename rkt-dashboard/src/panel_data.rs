use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

// Shared cache for rkt-panel-data so all panels show identical data and we do
// not hammer the data script on every window.
static PANEL_DATA_CACHE: OnceLock<Mutex<Option<(Instant, serde_json::Value)>>> = OnceLock::new();

pub fn fetch_panel_data() -> Option<serde_json::Value> {
    const AGE: Duration = Duration::from_secs(4);
    let cache = PANEL_DATA_CACHE.get_or_init(|| Mutex::new(None));
    {
        if let Ok(guard) = cache.lock() {
            if let Some((when, data)) = guard.as_ref() {
                if when.elapsed() < AGE {
                    return Some(data.clone());
                }
            }
        }
    }

    let out = std::process::Command::new("rkt-panel-data")
        .output()
        .ok()
        .and_then(|o| serde_json::from_slice::<serde_json::Value>(&o.stdout).ok())?;

    if let Ok(mut guard) = cache.lock() {
        *guard = Some((Instant::now(), out.clone()));
    }
    Some(out)
}
