/// Dynamically formats bytes into human-readable strings (B, KiB, MiB, GiB, TiB)
pub fn format_size(bytes: u64) -> String {
    let kb = 1024_f64;
    let mb = kb * 1024.0;
    let gb = mb * 1024.0;
    let tb = gb * 1024.0;
    let b = bytes as f64;

    if b >= tb {
        format!("{:.2} TiB", b / tb)
    } else if b >= gb {
        format!("{:.2} GiB", b / gb)
    } else if b >= mb {
        format!("{:.2} MiB", b / mb)
    } else if b >= kb {
        format!("{:.2} KiB", b / kb)
    } else {
        format!("{} B", bytes)
    }
}
