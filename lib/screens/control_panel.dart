import 'package:flutter/material.dart';
import 'package:sleek_circular_slider/sleek_circular_slider.dart';

import 'package:syne/service/ssh_service.dart';

class ControlPanel extends StatefulWidget {
  final SSHService ssh;

  const ControlPanel({super.key, required this.ssh});

  @override
  State<ControlPanel> createState() => _ControlPanelState();
}

class _ControlPanelState extends State<ControlPanel> {
  double volume = 0;
  double brightness = 0;
  bool isMuted = false;
  int loginSession = 0;

  @override
  void initState() {
    super.initState();
    fetchInitialValues();
  }

  Future<void> run(String cmd) async {
    await widget.ssh.run(cmd);
  }

  Future<void> fetchInitialValues() async {
    /// GET VOLUME
    String volOutput = await widget.ssh.run(
      "pactl get-sink-volume @DEFAULT_SINK@",
    );

    /// GET MUTE STATUS
    String muteOutput = await widget.ssh.run(
      "pactl get-sink-mute @DEFAULT_SINK@",
    );

    /// GET BRIGHTNESS
    String brightnessOutput = await widget.ssh.run("brightnessctl -m");

    /// PARSE VOLUME
    double vol = double.parse(
      volOutput.split("/")[1].trim().replaceAll("%", ""),
    );

    /// PARSE MUTE
    bool muted = muteOutput.contains("yes");

    /// PARSE BRIGHTNESS
    double bright = double.parse(
      brightnessOutput.split(",")[3].replaceAll("%", ""),
    );

    /// GET LOGIN SESSION (SAFER)
    String loginctlRaw = await widget.ssh.run(
      "loginctl | grep tty | awk '{print \$1}'",
    );

    int loginctlOutput = int.tryParse(loginctlRaw.trim()) ?? 0;

    setState(() {
      volume = vol;
      brightness = bright;
      isMuted = muted;
      loginSession = loginctlOutput;
    });
  }

  Future<void> sudoCommand(String command) async {
    TextEditingController passController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.black,
          title: const Text(
            "Enter Sudo Password",
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: passController,
            obscureText: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: "Password",
              hintStyle: TextStyle(color: Colors.grey),
            ),
          ),
          actions: [
            TextButton(
              child: const Text("Cancel"),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
            ElevatedButton(
              child: const Text("Run"),
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
    required VoidCallback onTap,
    Color? backgroundColor,
  }) {
    return Column(
      children: [
        FloatingActionButton(
          onPressed: null, // Disabled click event logic
          backgroundColor: Colors.grey.shade800, // Grayed out container style
          child: Icon(icon, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(color: Colors.grey.shade500)),
      ],
    );
  }

  Widget brightnessSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Brightness",
          style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
        ),
        Slider(
          value: brightness,
          min: 0,
          max: 100,
          activeColor: Colors.grey.shade800, // Grayed out track interface
          inactiveColor: Colors.grey.shade900,
          label: brightness.round().toString(),
          onChanged: null, // Completely disables interactions
          onChangeEnd: null,
        ),
      ],
    );
  }

  Widget volumeCircular() {
    return Column(
      children: [
        Text(
          "Volume",
          style: TextStyle(color: Colors.grey.shade500, fontSize: 18),
        ),
        const SizedBox(height: 10),
        SleekCircularSlider(
          min: 0,
          max: 100,
          initialValue: volume,
          appearance: CircularSliderAppearance(
            size: 250,
            customWidths: CustomSliderWidths(
              progressBarWidth: 15,
              handlerSize: 0, // Hides interaction handle thumb structure
              trackWidth: 10,
            ),
            customColors: CustomSliderColors(
              progressBarColor: Colors.grey.shade800, // Muted colors
              trackColor: Colors.grey.shade900,
              dotColor: Colors.transparent,
              hideShadow: true,
            ),
            infoProperties: InfoProperties(
              modifier: (double value) {
                return "${value.round()}%";
              },
              mainLabelStyle: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 28,
              ),
            ),
          ),
          onChange: null, // Lock inputs from triggering changes
          onChangeEnd: null,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Control Panel"),
        backgroundColor: Colors.black,
				centerTitle: true,
      ),
      body: Stack(
        children: [
          /// BACKGROUND (MUTED & IGNORES GESTURES)
          IgnorePointer(
            ignoring: true,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    /// VOLUME CONTROL
                    volumeCircular(),
                    const SizedBox(height: 20),

                    /// ACTION BUTTONS
                    Wrap(
                      spacing: 30,
                      runSpacing: 30,
                      children: [
                        actionButton(
                          icon: Icons.lock,
                          label: "Lock",
                          onTap: () {},
                        ),
                        actionButton(
                          icon: Icons.power_settings_new,
                          label: "Shutdown",
                          onTap: () {},
                        ),
                        actionButton(
                          icon: Icons.restart_alt,
                          label: "Restart",
                          onTap: () {},
                        ),
                        actionButton(
                          icon: Icons.bedtime,
                          label: "Suspend",
                          onTap: () {},
                        ),
                        actionButton(
                          icon: Icons.volume_off,
                          label: "Mute",
                          onTap: () {},
                        ),
                        actionButton(
                          icon: Icons.monitor,
                          label: "Display Off",
                          onTap: () {},
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),

                    /// BRIGHTNESS CONTROL
                    brightnessSlider(),
                  ],
                ),
              ),
            ),
          ),

          /// FOREGROUND OVERLAY "COMING SOON" TEXT
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade800, width: 1),
              ),
              child: const Text(
                "Coming soon!!",
                style: TextStyle(
                  color: Color(
                    0xFFA2D9A1,
                  ), // Matches original design accent color
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
