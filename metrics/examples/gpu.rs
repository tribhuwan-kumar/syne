use gfxinfo::active_gpu;

fn main() {
    let gpu = active_gpu().unwrap();
    let info = gpu.info();
    
    // gfxinfo returns the temperature multiplied by 1000
    let temp_celsius = info.temperature() / 1000; 
    
    println!("GPU Model: {}", gpu.model());
    println!("GPU Temperature: {}°C", temp_celsius);
}
