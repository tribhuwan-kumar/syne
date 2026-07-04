fn main() {
    // Queries the system's active routing table natively
    match default_net::get_default_interface() {
        Ok(default_interface) => {
            // Prints the exact interface name (e.g., wlp0s20f3)
            println!("{}", default_interface.name);
            println!("{:?}", default_interface.ipv4);
        }
        Err(err) => {
            eprintln!("Error retrieving default interface: {}", err);
            std::process::exit(1);
        }
    }
}
