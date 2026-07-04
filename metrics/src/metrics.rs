use chrono::Local;
use std::process::Stdio;
use if_addrs::get_if_addrs;
use tokio::process::Command;
use std::collections::HashMap;
use sysinfo::{
    Users,
    Disks,
    System,
    Networks,
    Components,
    CpuRefreshKind,
    ProcessesToUpdate,
    ProcessRefreshKind,
};

use crate::utils::format_size;
use crate::types::{
    DiskMetrics,
    MemoryMetrics,
    ProcessMetrics,
    BatteryMetrics,
    SystemIdentity,
    OpenPortMetrics,
    HardwareMetrics,
    TemperatureMetrics,
    NetworkInterfaceMetrics,
};

use starship_battery::Manager;
use starship_battery::units::{
    power::watt,
    ratio::percent,
    electric_potential::volt,
};

use netstat2::{
    get_sockets_info,
    AddressFamilyFlags,
    ProtocolFlags,
    ProtocolSocketInfo
};

/// Retrieves cross-platform memory metrics
pub fn get_memory_metrics(sys: &mut System) -> MemoryMetrics {
    sys.refresh_memory();

    let total = sys.total_memory();
    let used = sys.used_memory();
    let free = sys.free_memory();
    let available = sys.available_memory();
    
    // Cached/Standby memory calculation
    let cached = total.saturating_sub(used).saturating_sub(free);

    MemoryMetrics {
        total: format_size(total),
        used: format_size(used),
        available: format_size(available),
        cached: format_size(cached),
        free: format_size(free),
    }
}

/// Polls mounted disks and calculates usage cross-platform
pub fn get_disk_metrics(disks: &mut Disks) -> Vec<DiskMetrics> {
    disks.refresh(true);
    
    disks.iter().map(|disk| {
        let total = disk.total_space();
        let available = disk.available_space();
        let used = total.saturating_sub(available);
        
        let use_percent = if total > 0 {
            (used as f64 / total as f64 * 100.0).round() as u64
        } else {
            0
        };

        DiskMetrics {
            mount_point: disk.mount_point().to_string_lossy().into_owned(),
            size: format_size(total),
            used: format_size(used),
            use_percent: format!("{}%", use_percent),
        }
    }).collect()
}

/// Fetches IPs and calculates network speeds based on elapsed time
pub fn get_network_metrics(networks: &mut Networks, elapsed_secs: f64) -> Vec<NetworkInterfaceMetrics> {
    networks.refresh(true);

    let default_iface_name = default_net::get_default_interface()
        .map(|iface| iface.name)
        .unwrap_or_default();

    // Map IP addresses to interface names
    let mut ip_map: HashMap<String, Vec<String>> = HashMap::new();
    if let Ok(interfaces) = get_if_addrs() {
        for iface in interfaces {
            ip_map
                .entry(iface.name.clone())
                .or_default()
                .push(iface.addr.ip().to_string());
        }
    }

    networks
        .iter()
        .map(|(name, data)| {
            let recv_speed = (data.received() as f64 / elapsed_secs).round() as u64;
            let trans_speed = (data.transmitted() as f64 / elapsed_secs).round() as u64;

            let is_active = recv_speed > 0 || trans_speed > 0;
            let is_default = name == &default_iface_name;

            NetworkInterfaceMetrics {
                name: name.to_string(),
                ip_addresses: ip_map.get(name).cloned().unwrap_or_default(),
                mac_address: data.mac_address().to_string(),
                download_speed: format!("{}/s", format_size(recv_speed)),
                upload_speed: format!("{}/s", format_size(trans_speed)),
                total_downloaded: format_size(data.total_received()),
                total_uploaded: format_size(data.total_transmitted()),
                is_active,
                is_default,
            }
        })
        .collect()
}

/// Replicates the output of `hostnamectl` and uptime natively
pub fn get_system_identity(_sys: &System) -> SystemIdentity {
    let now = Local::now();
    let os = std::env::consts::OS;
    let load = System::load_average();
    let time = now.format("%I:%M %p, %e %b %Y").to_string().replace("  ", " ");
    let user_name = std::env::var("USER")
        .or_else(|_| std::env::var("USERNAME"))
        .unwrap_or_else(|_| "Unknown".to_string());

    SystemIdentity {
        os: os.to_uppercase(),
        os_name: System::long_os_version().unwrap_or_else(|| "<Unknown OS>".to_string()),
        date_time: time,
        username: user_name,
        kernel_name: System::kernel_long_version(),
        architecture: System::cpu_arch(),
        hostname: System::host_name().unwrap_or_else(|| "<Untitled>".to_string()),
        uptime_secs: System::uptime(),
        load_average: [
            (load.one * 100.0).round() / 100.0,
            (load.five * 100.0).round() / 100.0,
            (load.fifteen * 100.0).round() / 100.0,
        ],
    }
}

/// Gathers CPU & GPU info
pub fn get_hardware_metrics(sys: &mut System, components: &mut Components) -> HardwareMetrics {
    sys.refresh_cpu_specifics(CpuRefreshKind::everything());
    components.refresh(true);

    let cpus = sys.cpus();
    let cpu_model = cpus.first().map(|c| c.brand()).unwrap_or("Unknown CPU").to_string();
    let global_cpu_usage = format!("{:.1}%", sys.global_cpu_usage());

    let mut sensors = Vec::new();
    let mut total_cpu_temp = 0.0;
    let mut cpu_temp_count = 0.0;

    #[cfg(feature = "gpu")]
    let mut total_gpu_temp = 0.0;
    #[cfg(feature = "gpu")]
    let mut gpu_temp_count = 0.0;

    for comp in components.iter() {
        if let Some(temp) = comp.temperature() {
            let label = comp.label().to_lowercase();
            sensors.push(TemperatureMetrics {
                label: comp.label().to_string(),
                temperature_c: temp,
            });

            if label.contains("cpu") || label.contains("core") {
                total_cpu_temp += temp;
                cpu_temp_count += 1.0;
            } 
            
            #[cfg(feature = "gpu")]
            if label.contains("gpu") || label.contains("amdgpu") || label.contains("edge") {
                total_gpu_temp += temp;
                gpu_temp_count += 1.0;
            }
        }
    }

    // Attempt to fetch dedicated GPU data via gfxinfo
    #[cfg(feature = "gpu")]
    let (final_gpu_model, final_gpu_usage, final_avg_gpu_temp) = {
        let mut gfx_gpu_model = String::new();
        let mut gfx_gpu_usage = String::new();
        let mut gfx_gpu_temp: Option<f32> = None;

        if let Ok(gpu) = gfxinfo::active_gpu() {
            gfx_gpu_model = gpu.model().to_string();
            
            {
                let info = gpu.info();
                gfx_gpu_usage = format!("{}%", info.load_pct());
                let temp_mcel = info.temperature();
                if temp_mcel > 0 {
                    gfx_gpu_temp = Some(temp_mcel as f32 / 1000.0);
                }
            }
        }

        // Fallback logic inside the feature block
        let (model, usage) = if !gfx_gpu_model.is_empty() {
            (gfx_gpu_model, gfx_gpu_usage)
        } else if gpu_temp_count > 0.0 {
            ("Detected GPU".to_string(), "N/A".to_string())
        } else {
            ("".to_string(), "".to_string())
        };

        let avg_temp = if gpu_temp_count > 0.0 {
            total_gpu_temp / gpu_temp_count
        } else {
            gfx_gpu_temp.unwrap_or(0.0)
        };

        (model, usage, avg_temp)
    };

    HardwareMetrics {
        cpu_model,
        global_cpu_usage,
        avg_cpu_temp: if cpu_temp_count > 0.0 { total_cpu_temp / cpu_temp_count } else { 0.0 },
        #[cfg(feature = "gpu")]
        gpu_model: final_gpu_model,
        #[cfg(feature = "gpu")]
        global_gpu_usage: final_gpu_usage,
        #[cfg(feature = "gpu")]
        avg_gpu_temp: final_avg_gpu_temp,
        sensors,
    }
}

/// Natively reads open TCP/UDP sockets cross-platform
pub fn get_open_ports() -> Vec<OpenPortMetrics> {
    let af_flags = AddressFamilyFlags::IPV4 | AddressFamilyFlags::IPV6;
    let proto_flags = ProtocolFlags::TCP | ProtocolFlags::UDP;
    
    let mut open_ports = Vec::new();

    if let Ok(sockets) = get_sockets_info(af_flags, proto_flags) {
        for socket in sockets {
            let (protocol, state, local, peer) = match socket.protocol_socket_info {
                ProtocolSocketInfo::Tcp(tcp) => {
                    (
                        "tcp",
                        format!("{:?}", tcp.state).to_uppercase(),
                        format!("{}:{}", tcp.local_addr, tcp.local_port),
                        format!("{}:{}", tcp.remote_addr, tcp.remote_port),
                    )
                },
                ProtocolSocketInfo::Udp(udp) => {
                    (
                        "udp",
                        "UNCONN".to_string(),
                        format!("{}:{}", udp.local_addr, udp.local_port),
                        "*:*".to_string(),
                    )
                },
            };

            open_ports.push(OpenPortMetrics {
                protocol: protocol.to_string(),
                state,
                local_address: local,
                peer_address: peer,
            });
        }
    }
    
    open_ports
}

/// Asynchronously shells out to execute ping to avoid root requirements for raw sockets
pub async fn fetch_ping_stats() -> (String, String) {
    // Cross-platform Ping arguments
    #[cfg(unix)]
    let cmd = Command::new("ping").args(["-c", "4", "8.8.8.8"]).stdout(Stdio::piped()).output().await;
    #[cfg(windows)]
    let cmd = Command::new("ping").args(["-n", "4", "8.8.8.8"]).stdout(Stdio::piped()).output().await;

    if let Ok(output) = cmd {
        let stdout = String::from_utf8_lossy(&output.stdout).to_lowercase();
        
        let mut latency = "N/A".to_string();
        let mut packet_loss = "100%".to_string();

        // Basic string matching to parse ping output across OS types
        for line in stdout.lines() {
            if line.contains("time=") {
                if let Some(t) = line.split("time=").nth(1) {
                    latency = t.split_whitespace().next().unwrap_or("N/A").to_string() + " ms";
                }
            }
            if line.contains("%") && (line.contains("loss") || line.contains("packet")) {
                let parts: Vec<&str> = line.split_whitespace().collect();
                for p in parts {
                    if p.contains("%") {
                        packet_loss = p.to_string();
                        break;
                    }
                }
            }
        }
        return (latency, packet_loss);
    }
    
    ("N/A".to_string(), "100%".to_string())
}


/// Fetches the process list
pub fn get_process_metrics(sys: &mut System, users: &mut Users) -> Vec<ProcessMetrics> {
    sys.refresh_processes_specifics(
        ProcessesToUpdate::All,
        true,
        ProcessRefreshKind::everything(),
    );
    users.refresh();

    // capture the total number of logical CPUs
    let cpu_count = sys.cpus().len() as f32;
    let normalized_cpu_count = if cpu_count > 0.0 { cpu_count } else { 1.0 };

    let mut processes: Vec<_> = sys.processes().values().collect();
    // Sort processes by raw CPU usage descending
    processes.sort_by(|a, b| b.cpu_usage().partial_cmp(&a.cpu_usage()).unwrap());
    processes.into_iter().take(50).map(|p| {
        let user_name = p.user_id()
            .and_then(|uid| users.get_user_by_id(uid))
            .map(|u| u.name().to_string())
            .unwrap_or_else(|| "unknown".to_string());

        // Process name and commands now use os-safe strings `&OsStr`
        let program = p.name().to_string_lossy().into_owned();
        let command = p.cmd()
            .iter()
            .map(|arg| arg.to_string_lossy())
            .collect::<Vec<_>>()
            .join(" ");

        // Normalize the multi core value
        let mut scaled_cpu = p.cpu_usage() / normalized_cpu_count;
        if scaled_cpu > 100.0 {
            scaled_cpu = 100.0;
        }

        ProcessMetrics {
            pid: p.pid().as_u32().to_string(),
            program,
            command, 
            user: user_name,
            memory: format_size(p.memory()),
            cpu_percent: format!("{:.1}%", scaled_cpu),
        }
    }).collect()
}

/// Fetches detailed battery states. Handles physical power math natively.
pub fn get_battery_metrics(battery_manager: &Option<Manager>) -> Vec<BatteryMetrics> {
    let mut metrics = Vec::new();

    if let Some(manager) = battery_manager {
        if let Ok(batteries) = manager.batteries() {
            for bat_res in batteries {
                if let Ok(bat) = bat_res {
                    // Extract strictly typed values into raw f32/f64 floats
                    let percent_val = bat.state_of_charge().get::<percent>();
                    let voltage_val = bat.voltage().get::<volt>();
                    let wattage_val = bat.energy_rate().get::<watt>();
                    
                    // Current = watts / volts
                    let amperage_val = if voltage_val > 0.0 {
                        wattage_val / voltage_val
                    } else {
                        0.0
                    };

                    metrics.push(BatteryMetrics {
                        state: format!("{}", bat.state()),
                        percentage: format!("{:.0}%", percent_val),
                        voltage: format!("{:.1} V", voltage_val),
                        wattage: format!("{:.1} W", wattage_val),
                        amperage: format!("{:.1} A", amperage_val),
                    });
                }
            }
        }
    }

    metrics
}
