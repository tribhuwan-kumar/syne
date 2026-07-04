use alsa::mixer::{Mixer, SelemId, SelemChannelId};
use std::error::Error;

fn main() -> Result<(), Box<dyn Error>> {
    let mixer = Mixer::new("default", false)?;
    let selem_id = SelemId::new("Master", 0);
    let selem = mixer.find_selem(&selem_id)
        .ok_or("Native OS 'Master' volume channel not found.")?;
    let (min, max) = selem.get_playback_volume_range();
    let raw_volume: i64 = selem.get_playback_volume(SelemChannelId::FrontLeft)?;
    let range = max - min;
    let percentage = if range > 0 {
        ((raw_volume - min) as f64 / range as f64) * 100.0
    } else {
        0.0
    };

    println!("Hardware Volume Steps: {} (Range: {} - {})", raw_volume, min, max);
    println!("Calculated Volume:     {:.0}%", percentage);

    Ok(())
}
