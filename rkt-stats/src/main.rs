use serde::Serialize;
use std::collections::HashMap;
use std::fs;
use std::io;
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

const CPU_FILE: &str = "/tmp/.rkt-stats-cpu-prev";
const NET_FILE: &str = "/tmp/.rkt-stats-net-prev";

#[derive(Serialize)]
struct Stats {
    cpu: f64,
    mem_used: f64,
    mem_total: f64,
    load: [f64; 3],
    net_up: f64,
    net_down: f64,
    connections: Vec<Connection>,
    battery: f64,
    volume: f64,
    brightness: f64,
    clock_pct: f64,
    cpu_temp: f64,
    gpu_temp: f64,
    cpu_freq: f64,
    disk_pct: f64,
    swap_pct: f64,
    fan_rpm: f64,
    power_w: f64,
}

#[derive(Serialize)]
struct Connection {
    local: String,
    remote: String,
    state: String,
    owner: String,
}

fn read_cpu() -> (u64, u64, u64) {
    let line = fs::read_to_string("/proc/stat")
        .unwrap_or_default()
        .lines()
        .next()
        .unwrap_or("")
        .to_string();
    let parts: Vec<u64> = line
        .split_whitespace()
        .skip(1)
        .filter_map(|s| s.parse().ok())
        .collect();
    if parts.len() < 4 {
        return (0, 0, 0);
    }
    let total: u64 = parts.iter().sum();
    let idle = parts[3];
    (total, total, idle)
}

fn cpu_usage() -> f64 {
    let (total, _, idle) = read_cpu();
    let prev = fs::read_to_string(CPU_FILE).ok().and_then(|s| {
        let mut it = s.split(',');
        Some((
            it.next()?.parse::<u64>().ok()?,
            it.next()?.parse::<u64>().ok()?,
        ))
    });
    let usage = if let Some((p_total, p_idle)) = prev {
        let dt = total.saturating_sub(p_total);
        let di = idle.saturating_sub(p_idle);
        if dt == 0 {
            0.0
        } else {
            ((dt - di) as f64 / dt as f64) * 100.0
        }
    } else {
        0.0
    };
    let _ = fs::write(CPU_FILE, format!("{},{}\n", total, idle));
    usage
}

fn read_mem() -> (f64, f64) {
    let data = fs::read_to_string("/proc/meminfo").unwrap_or_default();
    let mut total = 0.0;
    let mut available = 0.0;
    for line in data.lines() {
        if let Some(val) = line.strip_prefix("MemTotal:") {
            total = val
                .trim()
                .split_whitespace()
                .next()
                .unwrap_or("0")
                .parse::<f64>()
                .unwrap_or(0.0)
                / 1_048_576.0;
        } else if let Some(val) = line.strip_prefix("MemAvailable:") {
            available = val
                .trim()
                .split_whitespace()
                .next()
                .unwrap_or("0")
                .parse::<f64>()
                .unwrap_or(0.0)
                / 1_048_576.0;
        }
    }
    (total - available, total)
}

fn read_load() -> [f64; 3] {
    let line = fs::read_to_string("/proc/loadavg").unwrap_or_default();
    let mut out = [0.0; 3];
    for (i, s) in line.split_whitespace().take(3).enumerate() {
        out[i] = s.parse::<f64>().unwrap_or(0.0);
    }
    out
}

fn parse_addr(s: &str) -> Option<(String, u16)> {
    let (ip_hex, port_hex) = s.split_once(':')?;
    let ip_u32 = u32::from_str_radix(ip_hex, 16).ok()?;
    let ip = std::net::Ipv4Addr::from(ip_u32.to_le_bytes());
    let port = u16::from_str_radix(port_hex, 16).ok()?;
    Some((ip.to_string(), port))
}

fn state_name(code: u32) -> &'static str {
    match code {
        0x01 => "ESTABLISHED",
        0x02 => "SYN_SENT",
        0x03 => "SYN_RECV",
        0x04 => "FIN_WAIT1",
        0x05 => "FIN_WAIT2",
        0x06 => "TIME_WAIT",
        0x07 => "CLOSE",
        0x08 => "CLOSE_WAIT",
        0x09 => "LAST_ACK",
        0x0A => "LISTEN",
        0x0B => "CLOSING",
        _ => "UNKNOWN",
    }
}

fn read_connections() -> Vec<Connection> {
    let mut out = Vec::new();
    for path in ["/proc/net/tcp", "/proc/net/tcp6"] {
        let data = fs::read_to_string(path).unwrap_or_default();
        for line in data.lines().skip(1) {
            let cols: Vec<&str> = line.split_whitespace().collect();
            if cols.len() < 10 {
                continue;
            }
            let st = u32::from_str_radix(cols[3], 16).unwrap_or(0);
            if st != 0x01 {
                continue;
            }
            let Some((local_ip, local_port)) = parse_addr(cols[1]) else {
                continue;
            };
            let Some((remote_ip, remote_port)) = parse_addr(cols[2]) else {
                continue;
            };
            let Ok(uid) = cols[7].parse::<u32>() else {
                continue;
            };
            out.push(Connection {
                local: format!("{}:{}", local_ip, local_port),
                remote: format!("{}:{}", remote_ip, remote_port),
                state: state_name(st).to_string(),
                owner: format!("uid:{}", uid),
            });
        }
    }
    out.into_iter().take(6).collect()
}

fn read_net() -> HashMap<String, (u64, u64)> {
    let mut map = HashMap::new();
    let data = fs::read_to_string("/proc/net/dev").unwrap_or_default();
    for line in data.lines().skip(2) {
        let mut parts = line.split_whitespace();
        let Some(iface) = parts.next() else { continue };
        let iface = iface.trim_end_matches(':');
        if iface == "lo" {
            continue;
        }
        let Some(recv) = parts.next().and_then(|s| s.parse::<u64>().ok()) else {
            continue;
        };
        parts.nth(6);
        let Some(send) = parts.next().and_then(|s| s.parse::<u64>().ok()) else {
            continue;
        };
        map.insert(iface.to_string(), (recv, send));
    }
    map
}

fn net_rates() -> (f64, f64) {
    let cur = read_net();
    let prev = fs::read_to_string(NET_FILE).ok().map(|s| {
        let mut map = HashMap::new();
        for line in s.lines() {
            let mut it = line.split(',');
            if let (Some(iface), Some(r), Some(s)) = (it.next(), it.next(), it.next()) {
                if let (Ok(r), Ok(s)) = (r.parse::<u64>(), s.parse::<u64>()) {
                    map.insert(iface.to_string(), (r, s));
                }
            }
        }
        map
    });
    let mut up = 0.0;
    let mut down = 0.0;
    if let Some(p) = prev {
        for (iface, (cr, cs)) in &cur {
            if let Some((pr, ps)) = p.get(iface) {
                down += (*cr as f64 - *pr as f64).max(0.0);
                up += (*cs as f64 - *ps as f64).max(0.0);
            }
        }
    }
    let out: Vec<String> = cur
        .iter()
        .map(|(k, (r, s))| format!("{},{},{}", k, r, s))
        .collect();
    let _ = fs::write(NET_FILE, out.join("\n"));
    (up, down)
}

fn read_battery() -> f64 {
    let Ok(entries) = fs::read_dir("/sys/class/power_supply") else {
        return -1.0;
    };
    for entry in entries.flatten() {
        if let Some(name) = entry.file_name().to_str() {
            if name.starts_with("BAT") {
                let path = entry.path().join("capacity");
                if let Ok(s) = fs::read_to_string(&path) {
                    return s.trim().parse::<f64>().unwrap_or(-1.0);
                }
            }
        }
    }
    -1.0
}

fn read_brightness() -> f64 {
    let Ok(entries) = fs::read_dir("/sys/class/backlight") else {
        return -1.0;
    };
    for entry in entries.flatten() {
        let b = entry.path().join("brightness");
        let m = entry.path().join("max_brightness");
        if let (Ok(bv), Ok(mv)) = (fs::read_to_string(&b), fs::read_to_string(&m)) {
            let bval = bv.trim().parse::<f64>().unwrap_or(0.0);
            let mval = mv.trim().parse::<f64>().unwrap_or(1.0);
            if mval > 0.0 {
                return (bval / mval) * 100.0;
            }
        }
    }
    -1.0
}

fn read_volume() -> f64 {
    let output = Command::new("pactl").args(["list", "sinks"]).output();
    if let Ok(out) = output {
        if out.status.success() {
            let text = String::from_utf8_lossy(&out.stdout);
            for line in text.lines() {
                let line = line.trim();
                if line.starts_with("Volume:") {
                    if let Some(pct) = line
                        .split_whitespace()
                        .find(|s| s.ends_with('%'))
                        .and_then(|s| s.trim_end_matches('%').parse::<f64>().ok())
                    {
                        return pct;
                    }
                }
            }
        }
    }
    -1.0
}

fn read_clock_pct() -> f64 {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as f64;
    let secs_in_day = now % 86_400.0;
    (secs_in_day / 86_400.0) * 100.0
}

fn read_cpu_temp() -> f64 {
    // Try hwmon coretemp first.
    if let Ok(entries) = fs::read_dir("/sys/class/hwmon") {
        for entry in entries.flatten() {
            let name_path = entry.path().join("name");
            if let Ok(name) = fs::read_to_string(&name_path) {
                let name = name.trim();
                if name == "coretemp" || name == "k10temp" || name == "zenpower" {
                    for i in 1..=8 {
                        let p = entry.path().join(format!("temp{}_input", i));
                        if let Ok(s) = fs::read_to_string(&p) {
                            if let Ok(v) = s.trim().parse::<f64>() {
                                return v / 1000.0;
                            }
                        }
                    }
                }
            }
        }
    }
    // Fallback: thermal zones.
    if let Ok(entries) = fs::read_dir("/sys/class/thermal") {
        let mut max = -1.0;
        for entry in entries.flatten() {
            let p = entry.path().join("temp");
            if let Ok(s) = fs::read_to_string(&p) {
                if let Ok(v) = s.trim().parse::<f64>() {
                    let c = v / 1000.0;
                    if c > max {
                        max = c;
                    }
                }
            }
        }
        if max > 0.0 {
            return max;
        }
    }
    -1.0
}

fn read_gpu_temp() -> f64 {
    if Command::new("which")
        .arg("nvidia-smi")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
    {
        if let Ok(out) = Command::new("nvidia-smi")
            .args([
                "--query-gpu=temperature.gpu",
                "--format=csv,noheader,nounits",
            ])
            .output()
        {
            if out.status.success() {
                if let Ok(s) = String::from_utf8(out.stdout) {
                    if let Ok(v) = s.trim().parse::<f64>() {
                        return v;
                    }
                }
            }
        }
    }
    // Try amdgpu sysfs.
    if let Ok(entries) = fs::read_dir("/sys/class/hwmon") {
        for entry in entries.flatten() {
            let name_path = entry.path().join("name");
            if let Ok(name) = fs::read_to_string(&name_path) {
                if name.trim().starts_with("amdgpu") {
                    let p = entry.path().join("temp1_input");
                    if let Ok(s) = fs::read_to_string(&p) {
                        if let Ok(v) = s.trim().parse::<f64>() {
                            return v / 1000.0;
                        }
                    }
                }
            }
        }
    }
    -1.0
}

fn read_cpu_freq() -> f64 {
    let mut total = 0.0;
    let mut count = 0;
    if let Ok(entries) = fs::read_dir("/sys/devices/system/cpu") {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().to_string();
            if name.starts_with("cpu") && name[3..].parse::<u32>().is_ok() {
                let p = entry.path().join("cpufreq/scaling_cur_freq");
                if let Ok(s) = fs::read_to_string(&p) {
                    if let Ok(v) = s.trim().parse::<f64>() {
                        total += v / 1000.0; // kHz -> MHz
                        count += 1;
                    }
                }
            }
        }
    }
    if count > 0 {
        return total / count as f64;
    }
    // Fallback to cpuinfo.
    let data = fs::read_to_string("/proc/cpuinfo").unwrap_or_default();
    let mut sum = 0.0;
    let mut n = 0;
    for line in data.lines() {
        if let Some(val) = line.strip_prefix("cpu MHz\t\t:") {
            if let Ok(v) = val.trim().parse::<f64>() {
                sum += v;
                n += 1;
            }
        }
    }
    if n > 0 {
        sum / n as f64
    } else {
        -1.0
    }
}

fn read_disk_pct() -> f64 {
    // Use df for root partition used percentage.
    if let Ok(out) = Command::new("df").args(["-P", "/"]).output() {
        let text = String::from_utf8_lossy(&out.stdout);
        if let Some(line) = text.lines().nth(1) {
            let cols: Vec<&str> = line.split_whitespace().collect();
            if cols.len() >= 5 {
                if let Ok(pct) = cols[4].trim_end_matches('%').parse::<f64>() {
                    return pct;
                }
            }
        }
    }
    -1.0
}

fn read_swap_pct() -> f64 {
    let data = fs::read_to_string("/proc/meminfo").unwrap_or_default();
    let mut total = 0.0;
    let mut free = 0.0;
    for line in data.lines() {
        if let Some(val) = line.strip_prefix("SwapTotal:") {
            total = val
                .trim()
                .split_whitespace()
                .next()
                .unwrap_or("0")
                .parse::<f64>()
                .unwrap_or(0.0);
        } else if let Some(val) = line.strip_prefix("SwapFree:") {
            free = val
                .trim()
                .split_whitespace()
                .next()
                .unwrap_or("0")
                .parse::<f64>()
                .unwrap_or(0.0);
        }
    }
    if total > 0.0 {
        ((total - free) / total) * 100.0
    } else {
        0.0
    }
}

fn read_fan_rpm() -> f64 {
    let mut max = -1.0;
    if let Ok(entries) = fs::read_dir("/sys/class/hwmon") {
        for entry in entries.flatten() {
            for i in 1..=4 {
                let p = entry.path().join(format!("fan{}_input", i));
                if let Ok(s) = fs::read_to_string(&p) {
                    if let Ok(v) = s.trim().parse::<f64>() {
                        if v > max {
                            max = v;
                        }
                    }
                }
            }
        }
    }
    max
}

fn read_power_w() -> f64 {
    // Try battery power_now (µW -> W).
    if let Ok(entries) = fs::read_dir("/sys/class/power_supply") {
        for entry in entries.flatten() {
            let p = entry.path().join("power_now");
            if let Ok(s) = fs::read_to_string(&p) {
                if let Ok(v) = s.trim().parse::<f64>() {
                    return v / 1_000_000.0;
                }
            }
        }
    }
    // Fallback to nvidia-smi power.draw.
    if Command::new("which")
        .arg("nvidia-smi")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
    {
        if let Ok(out) = Command::new("nvidia-smi")
            .args(["--query-gpu=power.draw", "--format=csv,noheader,nounits"])
            .output()
        {
            if out.status.success() {
                if let Ok(s) = String::from_utf8(out.stdout) {
                    if let Ok(v) = s.trim().parse::<f64>() {
                        return v;
                    }
                }
            }
        }
    }
    -1.0
}

fn main() {
    let stats = Stats {
        cpu: cpu_usage(),
        mem_used: read_mem().0,
        mem_total: read_mem().1,
        load: read_load(),
        net_up: net_rates().0 / 1024.0,
        net_down: net_rates().1 / 1024.0,
        connections: read_connections(),
        battery: read_battery(),
        volume: read_volume(),
        brightness: read_brightness(),
        clock_pct: read_clock_pct(),
        cpu_temp: read_cpu_temp(),
        gpu_temp: read_gpu_temp(),
        cpu_freq: read_cpu_freq(),
        disk_pct: read_disk_pct(),
        swap_pct: read_swap_pct(),
        fan_rpm: read_fan_rpm(),
        power_w: read_power_w(),
    };
    println!("{}", serde_json::to_string(&stats).unwrap());
    io::Write::flush(&mut io::stdout()).unwrap();
}
