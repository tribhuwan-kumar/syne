mod metrics;
mod types;
mod utils;

use std::sync::Arc;
use tokio::sync::RwLock;
use tokio::time::interval;
use std::io::{self, Write};
use std::time::{Duration, Instant};
use sysinfo::{Components, Disks, Networks, System, Users};

use crate::metrics::{
    get_open_ports,
    fetch_ping_stats,
    get_disk_metrics,
    get_memory_metrics,
    get_battery_metrics,
    get_network_metrics,
    get_process_metrics,
    get_system_identity,
    get_hardware_metrics,
};

use crate::types::{
    SystemStats,
    NetworkExternalStats,
};

#[tokio::main]
async fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.contains(&"--version".to_string()) || args.contains(&"-V".to_string()) {
        println!("v{}", env!("CARGO_PKG_VERSION"));
        std::process::exit(0);
    }
    let mut sys = System::new_all();
    let mut disks = Disks::new_with_refreshed_list();
    let mut networks = Networks::new_with_refreshed_list();
    let mut components = Components::new_with_refreshed_list();
    let mut users = Users::new_with_refreshed_list();
    let battery_manager = starship_battery::Manager::new().ok();

    // Shared state for asynchronous network calls
    let external_stats = Arc::new(RwLock::new(NetworkExternalStats::default()));

    // Fetch public ip every 10 minutes
    let stats_ip_clone = Arc::clone(&external_stats);
    tokio::spawn(async move {
        let mut ticker = interval(Duration::from_secs(6000)); // 100 minutes
        loop {
            ticker.tick().await;
            if let Ok(res) = reqwest::get("https://ifconfig.me/all.json").await {
                if let Ok(json) = res.json::<serde_json::Value>().await {
                    if let Some(ip) = json["ip_addr"].as_str() {
                        let mut lock = stats_ip_clone.write().await;
                        lock.public_ip = ip.to_string();
                    }
                }
            }
        }
    });

    // Fetch latency & packet loss every 5 seconds on background thread
    let stats_ping_clone = Arc::clone(&external_stats);
    tokio::spawn(async move {
        let mut ticker = interval(Duration::from_secs(5));
        loop {
            ticker.tick().await;
            let (latency, loss) = fetch_ping_stats().await;
            let mut lock = stats_ping_clone.write().await;
            lock.latency_ms = latency;
            lock.packet_loss = loss;
        }
    });

    // Main 3-second streaming loop
    let mut ticker = interval(Duration::from_secs(3));
    let mut last_tick = Instant::now();
    let mut stdout = io::stdout();

    loop {
        ticker.tick().await;

        let now = Instant::now();
        let elapsed_secs = now.duration_since(last_tick).as_secs_f64();
        last_tick = now;

        sys.refresh_cpu_usage();

        // Read the latest background thread external network data safely
        let ext_network_data = external_stats.read().await.clone();

        let stats = SystemStats {
            identity: get_system_identity(&sys),
            hardware: get_hardware_metrics(&mut sys, &mut components),
            memory: get_memory_metrics(&mut sys),
            disks: get_disk_metrics(&mut disks),
            networks: get_network_metrics(&mut networks, elapsed_secs),
            external_network: ext_network_data,
            open_ports: get_open_ports(),
            processes: get_process_metrics(&mut sys, &mut users),
            batteries: get_battery_metrics(&battery_manager),
        };

        // Serialize directly to a `MessagePack` binary vector
        if let Ok(packed_bytes) = rmp_serde::to_vec_named(&stats) {
            let marker = b"SYNE";
            let payload_len = packed_bytes.len() as u32;
            // Create a 4-byte Big-Endian header
            // Indicating the size of the incoming payload
            let header = payload_len.to_be_bytes();
            if stdout.write_all(marker).is_err() ||
                stdout.write_all(&header).is_err() ||
                stdout.write_all(&packed_bytes).is_err() ||
                stdout.flush().is_err() {
                break;
            }
        }
    }
}
