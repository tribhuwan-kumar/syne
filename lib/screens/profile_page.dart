import 'dart:async';
import 'package:flutter/material.dart';
import 'package:syne/service/ssh_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

class ProfilePage extends StatefulWidget {
  final SSHService ssh;
  const ProfilePage({super.key, required this.ssh});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
	String _appVersion = "Loading...";
  Map<String, dynamic> identity = {};
  Map<String, dynamic> hardware = {};
  StreamSubscription<Map<String, dynamic>>? _metricsSubscription;

  @override
  void initState() {
    super.initState();
    _metricsSubscription = widget.ssh.metricsStream.listen(_onMetricsUpdate);
		_loadAppVersion();
  }

  @override
  void dispose() {
    _metricsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadAppVersion() async {
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _appVersion = packageInfo.version;
    });
  }

  void _onMetricsUpdate(Map<String, dynamic> data) {
    if (!mounted) return;

    // Create a helper to safely cast dynamic maps
    Map<String, dynamic> castMap(dynamic m) {
      if (m is Map) {
        return Map<String, dynamic>.from(m.map((k, v) => MapEntry(k.toString(), v)));
      }
      return {};
    }

    setState(() {
      if (data['identity'] != null) identity = castMap(data['identity']);
      if (data['hardware'] != null) hardware = castMap(data['hardware']);
    });
  }

  String _formatUptime(int seconds) {
    int d = seconds ~/ 86400;
    int h = (seconds % 86400) ~/ 3600;
    int m = (seconds % 3600) ~/ 60;
    return "${d}d ${h}h ${m}m";
  }

  Widget sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(top: 25, bottom: 12),
    child: Text(
      title,
      style: const TextStyle(
        color: Color(0xFFA2D9A1),
        fontSize: 14,
        fontWeight: FontWeight.bold,
        letterSpacing: 1,
      )
    ),
  );

  Widget infoTile(String title, String value) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFF1C1C1E),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(color: Colors.grey, fontSize: 13),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text("System profile"),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const CircleAvatar(
            radius: 40,
            backgroundColor: Color(0xFFA2D9A1),
            child: Icon(Icons.dns, size: 40, color: Colors.black),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              identity['hostname'] ?? "Connecting...",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          sectionTitle("System"),
          infoTile("OS:", identity['os_name'] ?? "--"),
          infoTile("Kernel:", identity['kernel_name'] ?? "--"),
          infoTile("Architecture:", identity['architecture'] ?? "--"),
          infoTile("Uptime:", _formatUptime(identity['uptime_secs'] ?? 0)),
          infoTile(
            "Load avg:",
            (identity['load_average'] as List?)?.join(", ") ?? "--",
          ),

          sectionTitle("Hardware"),
          infoTile("Processor:", hardware['cpu_model'] ?? "--"),
          if (hardware['gpu_model'] != null && hardware['gpu_model'].toString().isNotEmpty)
						infoTile("Graphics:", hardware['gpu_model'].toString()),
          infoTile("Sensors count:", "${(hardware['sensors'] as List?)?.length ?? 0}"),

          sectionTitle("App info"),
          Material(
            type: MaterialType.transparency,
						child: ListTile(
								contentPadding: EdgeInsets.zero,
								title: const Text(
									"GitHub",
									style: TextStyle(color: Colors.grey, fontSize: 14),
									),
								subtitle: const Text(
									"View project source code",
									style: TextStyle(color: Colors.white, fontSize: 16),
									),
								trailing: IconButton(
									icon: const Icon(Icons.open_in_new, color: Color(0xFFA2D9A1)),
									onPressed: () async {
									final Uri url = Uri.parse('https://github.com/tribhuwan-kumar/syne');
										if (await canLaunchUrl(url)) {
											await launchUrl(url, mode: LaunchMode.externalApplication);
										} else {
										// Fallback handle if it fails to open
										if (mounted) {
											ScaffoldMessenger.of(context).showSnackBar(
											const SnackBar(content: Text('Could not open GitHub link')),
										);
										}
									}
								},
							),
						),
					),

          const SizedBox(height: 40),
          Center(
            child: Text(
              "Syne v$_appVersion",
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

