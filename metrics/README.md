Need cross platform api for, 
    lock,
    restart,
    shutdown,
    sleep,
    hibernate,
    mute,
    display off,
    camera & mic off,

For linux audio
	amixer
	wpctl
	pactl

Display
	* Linux
	cat /sys/class/drm/card*-*/status
	* Windows
	Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorConnectionParams | Select-Object Active, InstanceName
	* Macos
	system_profiler SPDisplaysDataType | grep -E "Display Type|Resolution|Main Display"

Audio
	* Linux
	ls /sys/class/drm/card*-*
	* Windows
	Get-CimInstance Win32_SoundDevice | Select-Object Name, Status
	* Macos
	system_profiler SPAudioDataType | grep -A 3 "Devices:"


system_profiler SPDisplaysDataType | grep -q "Resolution:"
system_profiler SPAudioDataType | grep -q "Output Channels:"


