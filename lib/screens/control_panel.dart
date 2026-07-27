import 'package:flutter/material.dart';
import 'package:syne/service/ssh_service.dart';
import 'package:sleek_circular_slider/sleek_circular_slider.dart';

// very beta version
class ControlPanel extends StatefulWidget {
  final SSHService ssh;

  const ControlPanel({super.key, required this.ssh});

  @override
  State<ControlPanel> createState() => _ControlPanelState();
}

class _ControlPanelState extends State<ControlPanel> {
  bool isLoading = true;

  // Hardware Capabilities
  bool hasDisplay = false;
  bool hasAudio = false;

  // States
  double volume = 0;
  double brightness = 0;
  bool isMuted = false;

  String get os => widget.ssh.osType.toLowerCase();

  @override
  void initState() {
    super.initState();
    _initializePanel();
  }

  Future<void> _initializePanel() async {
    setState(() => isLoading = true);
    await _detectHardware();
    if (hasAudio || hasDisplay) {
      await _fetchMediaValues();
    }
    if (mounted) {
      setState(() => isLoading = false);
    }
  }

  Future<String> run(String cmd) async {
    try {
      return await widget.ssh.run(cmd);
    } catch (e) {
      debugPrint("Command failed: $cmd\nError: $e");
      return "";
    }
  }

  Future<void> _detectHardware() async {
    String displayCmd = "";
    String audioCmd = "";

    if (os == "windows") {
      displayCmd = "powershell -Command \"if(Get-CimInstance -Namespace root\\wmi -ClassName WmiMonitorConnectionParams -ErrorAction SilentlyContinue){echo 'true'}else{echo 'false'}\"";
      audioCmd = "powershell -Command \"if(Get-CimInstance Win32_SoundDevice -ErrorAction SilentlyContinue){echo 'true'}else{echo 'false'}\"";
    } else if (os == "macos") {
      displayCmd = "system_profiler SPDisplaysDataType | grep -q 'Resolution:' && echo 'true' || echo 'false'";
      audioCmd = "system_profiler SPAudioDataType | grep -q 'Devices:' && echo 'true' || echo 'false'";
    } else {
      // Linux
      displayCmd = "ls /sys/class/drm/card*-*/status 2>/dev/null | xargs grep -l '^connected' >/dev/null 2>&1 && echo 'true' || echo 'false'";
      audioCmd = "ls -d /sys/class/sound/card* >/dev/null 2>&1 && echo 'true' || echo 'false'";
    }

    final d = await run(displayCmd);
    final a = await run(audioCmd);

    hasDisplay = d.trim() == 'true';
    hasAudio = a.trim() == 'true';
  }

  Future<void> _fetchMediaValues() async {
    if (hasAudio) {
      if (os == "linux") {
        String volOutput = await run("pactl get-sink-volume @DEFAULT_SINK@ || wpctl get-volume @DEFAULT_AUDIO_SINK@ || amixer sget Master");
        String muteOutput = await run("pactl get-sink-mute @DEFAULT_SINK@ || wpctl get-volume @DEFAULT_AUDIO_SINK@ || amixer sget Master");

        if (volOutput.contains("%")) {
          try {
            final match = RegExp(r'(\d+)%').firstMatch(volOutput);
            if (match != null) volume = double.parse(match.group(1)!);
          } catch (_) {}
        } else if (volOutput.contains("Volume:")) {
           try {
            final match = RegExp(r'Volume:\s*([0-9.]+)').firstMatch(volOutput);
            if (match != null) volume = double.parse(match.group(1)!) * 100;
          } catch (_) {}
        }
        isMuted = muteOutput.contains("yes") || muteOutput.contains("[off]") || muteOutput.contains("[MUTED]");
      }
      else if (os == "macos") {
        String volOutput = await run("osascript -e 'output volume of (get volume settings)'");
        String muteOutput = await run("osascript -e 'output muted of (get volume settings)'");
        volume = double.tryParse(volOutput.trim()) ?? 0;
        isMuted = muteOutput.trim() == "true";
      }
    }

    if (hasDisplay) {
      if (os == "linux") {
        String brightOutput = await run("brightnessctl -m");
        if (brightOutput.isNotEmpty) {
          try {
            brightness = double.parse(brightOutput.split(",")[3].replaceAll("%", ""));
          } catch (_) {}
        }
      }
    }
  }

  Future<void> _executeSystemAction(String actionName) async {
    String cmd = "";
    bool requiresSudo = false;

    switch (actionName) {
      case "Lock":
        if (os == "windows") {
          cmd = "rundll32.exe user32.dll,LockWorkStation";
        } else if (os == "macos") {
				 cmd = "pmset displaysleepnow"; // Best standard CLI lock equivalent
				}
        else if (os == "linux") {
					debugPrint("LOCKING");
					cmd = "loginctl lock-session || xdg-screensaver lock || gnome-screensaver-command -l";
				}
        break;

      case "Shutdown":
        requiresSudo = (os != "windows");
        if (os == "windows") {
          cmd = "shutdown /s /t 0";
        } else {
          cmd = "shutdown -h now || systemctl poweroff";
        }
        break;

      case "Restart":
        requiresSudo = (os != "windows");
        if (os == "windows") {
          cmd = "shutdown /r /t 0";
        } else {
          cmd = "shutdown -r now || systemctl reboot";
        }
        break;

      case "Sleep":
        if (os == "windows") {
          cmd = "rundll32.exe powrprof.dll,SetSuspendState 0,1,0";
        } else if (os == "macos") {
					cmd = "pmset sleepnow";
				}
        else {
					cmd = "systemctl suspend";
				}
        break;

      case "Hibernate":
        if (os == "windows") {
          cmd = "shutdown /h";
        } else if (os == "linux") {
          cmd = "systemctl hibernate";
          requiresSudo = true;
        }
        // macOS doesn't have a simple, standard hibernation CLI toggle
        break;

      case "Mute":
        if (os == "windows") {
          cmd = "powershell -Command \"(New-Object -ComObject WScript.Shell).SendKeys([char]173)\"";
        } else if (os == "macos") {
          cmd = isMuted ? "osascript -e 'set volume output muted false'" : "osascript -e 'set volume output muted true'";
        } else {
          cmd = "pactl set-sink-mute @DEFAULT_SINK@ toggle || wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle || amixer set Master toggle";
        }
        break;
    }

    if (cmd.isEmpty) return;

    if (requiresSudo) {
      _showSudoDialog(cmd);
    } else {
      await widget.ssh.runCommand(cmd);
      if (actionName == "Mute") {
        await Future.delayed(const Duration(milliseconds: 200)); // Allow OS to register change
        _initializePanel();
      }
    }
  }

  void _showSudoDialog(String command) {
    TextEditingController passController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1C1C1E),
          title: const Text("Enter sudo password",
						style: TextStyle(
							color: Colors.white,
							fontSize: 20, fontWeight: FontWeight.bold
						)),
          content: TextField(
            controller: passController,
            obscureText: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: "Password",
              hintStyle: TextStyle(color: Colors.grey),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFA2D9A1))),
            ),
          ),
          actions: [
            TextButton(
              child: const Text("Cancel", style: TextStyle(color: Colors.white54)),
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFA2D9A1)),
              child: const Text("Run", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              onPressed: () async {
                String pass = passController.text;
                Navigator.pop(context);
                await run("echo '$pass' | sudo -S $command");
              },
            ),
          ],
        );
      },
    );
  }

  Widget actionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    final isEnabled = onTap != null;
    return Column(
      children: [
        FloatingActionButton(
          heroTag: label,
          onPressed: onTap,
          backgroundColor: isEnabled ? const Color(0xFF2C2C2E) : Colors.grey.shade900,
          elevation: isEnabled ? 4 : 0,
          child: Icon(icon, color: isEnabled ? const Color(0xFFA2D9A1) : Colors.grey.shade700),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: isEnabled ? Colors.white70 : Colors.grey.shade700,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget brightnessSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("Brightness", style: TextStyle(color: Colors.grey.shade400, fontSize: 16)),
            Text("${brightness.round()}%", style: const TextStyle(color: Color(0xFFA2D9A1), fontSize: 16)),
          ],
        ),
        Slider(
          value: brightness,
          min: 0,
          max: 100,
          activeColor: const Color(0xFFA2D9A1),
          inactiveColor: Colors.grey.shade900,
          // Currently relies on `brightnessctl` which is Linux specific
          onChanged: hasDisplay && os == "linux" ? (val) => setState(() => brightness = val) : null,
          onChangeEnd: (val) async {
            if (hasDisplay && os == "linux") {
              await run("brightnessctl set ${val.round()}%");
            }
          },
        ),
      ],
    );
  }

  Widget volumeCircular() {
    bool canControlVolume = hasAudio && (os == "linux" || os == "macos");

    return Column(
      children: [
        Text("Volume", style: TextStyle(color: Colors.grey.shade400, fontSize: 18)),
        const SizedBox(height: 10),
        SleekCircularSlider(
          min: 0,
          max: 100,
          initialValue: volume,
          appearance: CircularSliderAppearance(
            size: 220,
            customWidths: CustomSliderWidths(
              progressBarWidth: 12,
              handlerSize: canControlVolume ? 10 : 0,
              trackWidth: 10,
            ),
            customColors: CustomSliderColors(
              progressBarColor: hasAudio ? const Color(0xFFA2D9A1) : Colors.grey.shade800,
              trackColor: const Color(0xFF2C2C2E),
              dotColor: Colors.white,
              hideShadow: true,
            ),
            infoProperties: InfoProperties(
              modifier: (double value) => "${value.round()}%",
              mainLabelStyle: TextStyle(
                color: hasAudio ? Colors.white : Colors.grey.shade700,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // onChanged: canControlVolume ? (val) => setState(() => volume = val) : null,
          onChangeEnd: (val) async {
            if (canControlVolume) {
              if (os == "linux") {
                await run("pactl set-sink-volume @DEFAULT_SINK@ ${val.round()}% || wpctl set-volume @DEFAULT_AUDIO_SINK@ ${val / 100} || amixer sset Master ${val.round()}%");
              } else if (os == "macos") {
                await run("osascript -e 'set volume output volume ${val.round()}'");
              }
            }
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Color(0xFFA2D9A1))),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Control Panel"),
        backgroundColor: Colors.black,
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          child: Column(
            children: [
              if (hasAudio) ...[
                volumeCircular(),
                const SizedBox(height: 30),
              ],

              // ACTION BUTTONS GRID (Forced 3 per row)
              LayoutBuilder(
                builder: (context, constraints) {
                  final double totalSpacing = 25 * 2;
                  final double itemWidth = (constraints.maxWidth - totalSpacing) / 3;

                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      SizedBox(
                        width: itemWidth,
                        child: actionButton(
                          icon: Icons.lock,
                          label: "Lock",
                          onTap: hasDisplay ? () => _executeSystemAction("Lock") : null,
                        ),
                      ),
                      SizedBox(
                        width: itemWidth,
                        child: actionButton(
                          icon: Icons.restart_alt,
                          label: "Restart",
                          onTap: () => _executeSystemAction("Restart"),
                        ),
                      ),
                      SizedBox(
                        width: itemWidth,
                        child: actionButton(
                          icon: Icons.power_settings_new,
                          label: "Shutdown",
                          onTap: () => _executeSystemAction("Shutdown"),
                        ),
                      ),
                      SizedBox(
                        width: itemWidth,
                        child: actionButton(
                          icon: Icons.bedtime,
                          label: "Sleep",
                          onTap: () => _executeSystemAction("Sleep"),
                        ),
                      ),
                      SizedBox(
                        width: itemWidth,
                        child: actionButton(
                          icon: Icons.nightlight_round,
                          label: "Hibernate",
                          onTap: os != "macos" ? () => _executeSystemAction("Hibernate") : null,
                        ),
                      ),
                      SizedBox(
                        width: itemWidth,
                        child: actionButton(
                          icon: isMuted ? Icons.volume_off : Icons.volume_up,
                          label: isMuted ? "Unmute" : "Mute",
                          onTap: hasAudio ? () => _executeSystemAction("Mute") : null,
                        ),
                      ),
                    ],
                  );
                },
              ),

              if (hasDisplay) ...[
                const SizedBox(height: 40),
                brightnessSlider(),
              ],

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
