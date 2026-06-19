use serde::Serialize;
use std::collections::HashMap;
use std::fs;
use std::io;

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
        Some((it.next()?.parse::<u64>().ok()?, it.next()?.parse::<u64>().ok()?))
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
            total = val.trim().split_whitespace().next().unwrap_or("0").parse::<f64>().unwrap_or(0.0) / 1_048_576.0;
        } else if let Some(val) = line.strip_prefix("MemAvailable:") {
            available = val.trim().split_whitespace().next().unwrap_or("0").parse::<f64>().unwrap_or(0.0) / 1_048_576.0;
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
            let Some((local_ip, local_port)) = parse_addr(cols[1]) else { continue };
            let Some((remote_ip, remote_port)) = parse_addr(cols[2]) else { continue };
            let Ok(uid) = cols[7].parse::<u32>() else { continue };
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
        let Some(recv) = parts.next().and_then(|s| s.parse::<u64>().ok()) else { continue };
        // skip 7 columns to send
        parts.nth(6);
        let Some(send) = parts.next().and_then(|s| s.parse::<u64>().ok()) else { continue };
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
    let out: Vec<String> = cur.iter().map(|(k, (r, s))| format!("{},{},{}", k, r, s)).collect();
    let _ = fs::write(NET_FILE, out.join("\n"));
    (up, down)
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
    };
    println!("{}", serde_json::to_string(&stats).unwrap());
    io::Write::flush(&mut io::stdout()).unwrap();
}
