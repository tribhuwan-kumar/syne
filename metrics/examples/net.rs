// use pnet::datalink;
//
// fn main() {
//     // Fetch all network interfaces available on the system
//     let interfaces = datalink::interfaces();
//
//     println!("Active Network Interfaces:\n");
//
//     for interface in interfaces {
//         // Filter for interfaces that are up and running, ignoring down or loopback interfaces if desired
//         if interface.is_running() && !interface.is_loopback() {
//             println!("Name: {}", interface.name);
//             println!("Index: {}", interface.index);
//             println!("MAC Address: {:?}", interface.mac);
//             println!("IP Addresses: {:?}", interface.ips);
//             println!("Flags: {:?}", interface.flags);
//             println!("{:-<30}", "");
//         }
//     }
// }

// use std::collections::HashMap;
// use std::thread::sleep;
// use std::time::Duration;

// fn main() {
//     println!("Scanning for active data transmission... Please wait.");
//
//     // 1. Take the first snapshot of traffic stats
//     let mut initial_stats = HashMap::new();
//     for interface in netdev::get_interfaces() {
//         if let Some(stats) = interface.stats {
//             initial_stats.insert(interface.name.clone(), (stats.rx_bytes, stats.tx_bytes));
//         }
//     }
//
//     // 2. Wait a brief moment to allow packets to travel
//     sleep(Duration::from_millis(200));
//
//     // 3. Take a second snapshot and compare the delta
//     println!("\nInterfaces with active packet traffic:");
//     println!("{:<15} {:<12} {:<15} {:<15}", "Interface", "Type", "Received (Δ)", "Transmitted (Δ)");
//     println!("{:-<60}", "");
//
//     let mut found_active = false;
//
//     for interface in netdev::get_interfaces() {
//         // Skip loopback interfaces entirely to focus on real Wi-Fi/Ethernet hardware
//         if interface.is_loopback() {
//             continue;
//         }
//
//         if let Some(current_stats) = interface.stats {
//             if let Some(&(initial_rx, initial_tx)) = initial_stats.get(&interface.name) {
//                 
//                 // Calculate the difference in bytes over the 200ms window
//                 let rx_delta = current_stats.rx_bytes.saturating_sub(initial_rx);
//                 let tx_delta = current_stats.tx_bytes.saturating_sub(initial_tx);
//
//                 // If packets are actively transmitting or receiving
//                 if rx_delta > 0 || tx_delta > 0 {
//                     found_active = true;
//                     println!(
//                         "{:<15} {:<12} {:<15} {:<15}",
//                         interface.name,
//                         format!("{:?}", interface.if_type),
//                         format!("{} bytes", rx_delta),
//                         format!("{} bytes", tx_delta)
//                     );
//                 }
//             }
//         }
//     }
//
//     if !found_active {
//         println!("No interfaces are actively transmitting data right now.");
//     }
// }



// use std::collections::HashMap;
// use std::thread::sleep;
// use std::time::Duration;
// use sysinfo::Networks;
//
// fn main() {
//     println!("Scanning for active data transmission with sysinfo...");
//
//     // 1. Initialize and load the network interfaces list
//     let mut networks = Networks::new_with_refreshed_list();
//
//     // 2. Store the initial baseline bytes
//     let mut initial_stats = HashMap::new();
//     for (interface_name, data) in &networks {
//         initial_stats.insert(
//             interface_name.clone(),
//             (data.received(), data.transmitted()),
//         );
//     }
//
//     // 3. Wait a brief moment to allow packets to travel
//     sleep(Duration::from_millis(200));
//
//     // 4. Refresh the data of each network interface
//     networks.refresh(true);
//
//     println!("\nInterfaces with active packet traffic:");
//     println!("{:<15} {:<15} {:<15}", "Interface", "Received (Δ)", "Transmitted (Δ)");
//     println!("{:-<50}", "");
//
//     let mut found_active = false;
//
//     for (interface_name, data) in &networks {
//         // Skip loopback interfaces to focus on real Wi-Fi/Ethernet hardware
//         if interface_name.contains("lo") || interface_name.contains("loopback") {
//             continue;
//         }
//
//         if let Some(&(initial_rx, initial_tx)) = initial_stats.get(interface_name) {
//             // Calculate the difference over the 200ms window
//             let rx_delta = data.received().saturating_sub(initial_rx);
//             let tx_delta = data.transmitted().saturating_sub(initial_tx);
//
//             // If bytes are physically moving, it's the active interface
//             if rx_delta > 0 || tx_delta > 0 {
//                 found_active = true;
//                 println!(
//                     "{:<15} {:<15} {:<15}",
//                     interface_name,
//                     format!("{} bytes", rx_delta),
//                     format!("{} bytes", tx_delta)
//                 );
//             }
//         }
//     }
//
//     if !found_active {
//         println!("No interfaces are actively transmitting data right now.");
//     }
// }

