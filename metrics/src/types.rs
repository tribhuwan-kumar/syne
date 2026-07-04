use serde::Serialize;

#[derive(Serialize, Debug)]
pub struct MemoryMetrics {
    pub total: String,
    pub used: String,
    pub available: String,
    pub cached: String,
    pub free: String,
}

#[derive(Serialize, Debug)]
pub struct DiskMetrics {
    pub mount_point: String,
    pub size: String,
    pub used: String,
    pub use_percent: String,
}

#[derive(Serialize, Debug)]
pub struct NetworkInterfaceMetrics {
    pub name: String,
    pub ip_addresses: Vec<String>,
    pub mac_address: String,
    pub download_speed: String,
    pub upload_speed: String,
    pub total_downloaded: String,
    pub total_uploaded: String,
    pub is_active: bool,
    pub is_default: bool,
}

#[derive(Serialize, Debug)]
pub struct SystemIdentity {
    pub os: String,
    pub os_name: String,
    pub username: String,
    pub date_time: String,
    pub kernel_name: String,
    pub architecture: String,
    pub hostname: String,
    pub uptime_secs: u64,
    pub load_average: [f64; 3],
}

#[derive(Serialize, Debug)]
pub struct BatteryMetrics {
    pub state: String,
    pub percentage: String,
    pub voltage: String,
    pub wattage: String,
    pub amperage: String,
}

#[derive(Serialize, Debug)]
pub struct TemperatureMetrics {
    pub label: String,
    pub temperature_c: f32,
}

#[derive(Serialize, Debug)]
pub struct HardwareMetrics {
    pub cpu_model: String,
    pub avg_cpu_temp: f32,
    pub global_cpu_usage: String,
    /// too hard to compile for gpu
    #[cfg(feature = "gpu")]
    pub gpu_model: String,
    #[cfg(feature = "gpu")]
    pub global_gpu_usage: String,
    #[cfg(feature = "gpu")]
    pub avg_gpu_temp: f32,
    pub sensors: Vec<TemperatureMetrics>,
}

#[derive(Serialize, Debug)]
pub struct ProcessMetrics {
    pub pid: String,
    pub program: String,
    pub command: String,
    pub user: String,
    pub memory: String,
    pub cpu_percent: String,
}

#[derive(Serialize, Debug, Clone, Default)]
pub struct NetworkExternalStats {
    pub public_ip: String,
    pub latency_ms: String,
    pub packet_loss: String,
}

#[derive(Serialize, Debug)]
pub struct OpenPortMetrics {
    pub protocol: String,
    pub state: String,
    pub local_address: String,
    pub peer_address: String,
}

#[derive(Serialize, Debug)]
pub struct SystemStats {
    pub memory: MemoryMetrics,
    pub disks: Vec<DiskMetrics>,
    pub networks: Vec<NetworkInterfaceMetrics>,
    pub identity: SystemIdentity,
    pub hardware: HardwareMetrics,
    pub external_network: NetworkExternalStats,
    pub open_ports: Vec<OpenPortMetrics>,
    pub processes: Vec<ProcessMetrics>,
    pub batteries: Vec<BatteryMetrics>,
}
