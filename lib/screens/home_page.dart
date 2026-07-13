import 'dart:async';
import 'package:flutter/material.dart';

import 'package:syne/service/ssh_service.dart';
import 'package:syne/screens/profile_page.dart';
import 'package:syne/screens/network_page.dart';
import 'package:syne/screens/file_explorer.dart';
import 'package:syne/screens/control_panel.dart';
import 'package:syne/screens/processes_page.dart';
import 'package:syne/screens/system_monitor.dart';
import 'package:syne/screens/terminal_screen.dart';
import 'package:syne/screens/server_list_page.dart';
import 'package:syne/screens/system_updates_page.dart';

class HomePage extends StatefulWidget {
  final SSHService ssh;

  const HomePage({super.key, required this.ssh});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int selectedIndex = 0;
  final List<int> _navigationStack = [0];

  String date = "--";
  String username = "Loading...";
  String hostname = "Loading...";
  String uptime = "Loading...";
  String memoryUsed = "--";
  String batteryState = "N/A";
  String batteryPercentage = "N/A";

  String cpuUsage = "--";
  String gpuUsage = "";
  String cpuTemp = "--";
  String gpuTemp = "";

  // Secondary hero state: stores the two main interfaces
  List<Map<String, dynamic>> topInterfaces = [];

  StreamSubscription<Map<String, dynamic>>? _metricsSubscription;

  @override
  void initState() {
    super.initState();
    setupMetricsStream();

    // Bind the connection lost callback
    widget.ssh.onConnectionLost = _showConnectionLostDialog;
  }

  @override
  void dispose() {
    _metricsSubscription?.cancel();
    // Clear the callback to avoid memory leaks
    widget.ssh.onConnectionLost = null;
    super.dispose();
  }

  void _onTabTapped(int index) {
    if (selectedIndex == index) return;

    setState(() {
      selectedIndex = index;
      _navigationStack.remove(index);
      _navigationStack.add(index);
    });
  }

  Future<bool> _onWillPop() async {
    if (_navigationStack.length > 1) {
      // Remove current tab
      _navigationStack.removeLast();
      // Go to previous tab
      setState(() {
        selectedIndex = _navigationStack.last;
      });
      return false;
    }
    return true; // Exit app if no history
  }

  void _showConnectionLostDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false, // Forces the user to click the button
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1C1C1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.wifi_off_rounded, color: Colors.redAccent),
              SizedBox(width: 10),
              Text("Connection Lost", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Text(
            "The SSH connection to the server dropped. This may be due to a network interruption or server timeout.",
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () {
                // Ensure backend resources are cleared
                widget.ssh.disconnect();

                // Clear the entire navigation stack and return to the Server list
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const ServerListPage()),
                  (route) => false,
                );
              },
              child: const Text(
                "Okay",
                style: TextStyle(color: Color(0xFFA2D9A1),
                fontWeight: FontWeight.bold, fontSize: 16)
              ),
            ),
          ],
        );
      },
    );
  }

  /// Listens to the high-performance MessagePack Rust stream
  Future<void> setupMetricsStream() async {
    _metricsSubscription = widget.ssh.metricsStream.listen((data) {
      if (!mounted) return;

      setState(() {
        if (data['identity'] != null) {
          hostname = data['identity']['hostname'] ?? hostname;
          int uptimeSecs = data['identity']['uptime_secs'] ?? 0;
          uptime = _formatUptime(uptimeSecs);
          date = data['identity']['date_time'] ?? date;
          username = data['identity']['username'] ?? username;
        }

        // Parse Memory (rust pre-formats this to MiB/GiB/etc)
        if (data['memory'] != null) {
          memoryUsed = data['memory']['used'] ?? memoryUsed;
        }

        if (data['hardware'] != null) {
          cpuUsage = data['hardware']['global_cpu_usage'] ?? cpuUsage;

          String rawGpuUsage = data['hardware']['global_gpu_usage'] ?? "";
          gpuUsage = (rawGpuUsage != "N/A" && rawGpuUsage.isNotEmpty) ? rawGpuUsage : "";

          double rawCpuTemp = (data['hardware']['avg_cpu_temp'] ?? 0.0).toDouble();
          cpuTemp = "${rawCpuTemp.toStringAsFixed(1)}°C";

          double rawGpuTemp = (data['hardware']['avg_gpu_temp'] ?? 0.0).toDouble();
          gpuTemp = rawGpuTemp > 0 ? "${rawGpuTemp.toStringAsFixed(1)}°C" : "";
        }

        if (data['batteries'] != null && (data['batteries'] as List).isNotEmpty) {
          batteryPercentage = data['batteries'][0]['percentage'] ?? "N/A";
          batteryState = data['batteries'][0]['state'] ?? "N/A";
        } else {
          batteryPercentage = "N/A";
          batteryState = "N/A";
        }

        // Parse and prioritize network interfaces
        if (data['networks'] != null) {
          final List<dynamic> allNetworks = data['networks'];

          // Filter out loopback ('lo') and only keep actively transmitting interfaces
          final filteredNets = allNetworks
            .map((e) => Map<String, dynamic>.from(e))
            .where((net) => net['name'] != 'lo' && net['is_default'] == true)
            .toList();

          // Fallback: If no interface is actively moving data right this second,
          // just show the primary physical interfaces (excluding 'lo')
          final referenceList = filteredNets.isNotEmpty
            ? filteredNets
            : allNetworks
            .map((e) => Map<String, dynamic>.from(e))
            .where((net) => net['name'] != 'lo')
            .toList();

          // Isolate the top two prioritized interfaces
          topInterfaces = referenceList.take(2).toList();
        }
      });
    });
  }

  String _formatUptime(int seconds) {
    int days = seconds ~/ (24 * 3600);
    int hours = (seconds % (24 * 3600)) ~/ 3600;
    int minutes = (seconds % 3600) ~/ 60;

    if (days > 0) return "${days}d ${hours}h";
    if (hours > 0) return "${hours}h ${minutes}m";
    return "${minutes}m";
  }

  Widget batteryChip() {
    if (batteryPercentage.toLowerCase().contains('nan')) {
      return const SizedBox.shrink();
    }

    bool isCharging = batteryState.toLowerCase().contains("charging");

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            batteryPercentage,
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            isCharging ? Icons.battery_charging_full : Icons.battery_std,
            color: Colors.black,
            size: 18,
          ),
        ],
      ),
    );
  }

  Widget deviceCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFFA2D9A1), size: 50),
            const Spacer(),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            Text(subtitle, style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }

  Widget systemAndUpdatesCards(String name, VoidCallback onTap) {
    return Container(
      height: 80,
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFFA2D9A1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            child: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.black),
          ),
        ],
      ),
    );
  }

  Widget systemCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFA2D9A1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  hostname,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.thermostat, color: Colors.black, size: 18),
                    const SizedBox(width: 2),
                    Text(
                      cpuTemp,
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    if (gpuTemp.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.developer_board, color: Colors.black, size: 18),
                      const SizedBox(width: 2),
                      Text(
                        gpuTemp,
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ]
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),

          Container(
            height: 2,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 172, 240, 1),
              borderRadius: BorderRadius.circular(100),
            ),
          ),
          const SizedBox(height: 15),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cpuUsage,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.black,
                    ),
                  ),
                  const Text("CPU", style: TextStyle(color: Colors.black54)),
                ],
              ),

              if (gpuUsage.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      gpuUsage,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.black,
                      ),
                    ),
                    const Text("GPU", style: TextStyle(color: Colors.black54)),
                  ],
                ),

              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    uptime,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.black,
                    ),
                  ),
                  const Text("Uptime", style: TextStyle(color: Colors.black54)),
                ],
              ),

              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    memoryUsed,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.black,
                    ),
                  ),
                  const Text("Memory used", style: TextStyle(color: Colors.black54)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Displays traffic metrics
  Widget networkTrafficCard() {
    if (topInterfaces.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.settings_ethernet, color: Color(0xFFA2D9A1), size: 22),
              const SizedBox(width: 8),
              Text(
                "Network interfaces",
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: topInterfaces.length,
            separatorBuilder: (context, index) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              child: Divider(color: Colors.white.withValues(alpha: 0.05), height: 1),
            ),
            itemBuilder: (context, index) {
              final iface = topInterfaces[index];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Row: Interface Name & IP Address
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            iface['name'] ?? "Unknown",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          // Inject the ACTIVE tag if true
                          if (iface['is_default'] == true) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
                              ),
                              child: const Text(
                                "DEFAULT",
                                style: TextStyle(
                                  color: Colors.greenAccent,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),

                      Text(
												"IP: ${iface['ip_addresses'].firstWhere(
													(ip) => !ip.toString().contains(':'), // IPv4 addresses never contain colons
													orElse: () => iface['ip_addresses'].isNotEmpty ? iface['ip_addresses'][0] : 'No IP Binding',
												)}",
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Bottom Row: Real-time download/upload speeds spanning full width
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Download Speed Component
                      Row(
                        children: [
                          const Icon(Icons.arrow_downward_rounded, color: Colors.greenAccent, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            iface['download_speed'] ?? "0 B/s",
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),

                      // Upload Speed Component
                      Row(
                        children: [
                          const Icon(Icons.arrow_upward_rounded, color: Colors.orangeAccent, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            iface['upload_speed'] ?? "0 B/s",
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget homePage() {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: setupMetricsStream,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          children: [
            const SizedBox(height: 10),

            /// HEADER
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      radius: 22,
                      backgroundImage: AssetImage("assets/avatar.png"),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Hi $username!!",
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(date, style: const TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    batteryChip(),
                    const SizedBox(width: 8),
                    CircleAvatar(
                      backgroundColor: Colors.black,
                      child: IconButton(
                        icon: const Icon(Icons.logout, color: Colors.white),
                        onPressed: () {
                          widget.ssh.disconnect();
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ServerListPage(),
                            ),
                            (route) => false,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            systemCard(),
            const SizedBox(height: 12),

            networkTrafficCard(),
            const SizedBox(height: 20),

            /// GRID
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              children: [
                deviceCard(
                  title: "System monitor",
                  subtitle: "Performance",
                  icon: Icons.computer,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SystemMonitor(ssh: widget.ssh),
                      ),
                    );
                  },
                ),
                deviceCard(
                  title: "File explorer",
                  subtitle: "Browse files",
                  icon: Icons.folder,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FileExplorer(ssh: widget.ssh),
                      ),
                    );
                  },
                ),
                deviceCard(
                  title: "Control panel",
                  subtitle: "Settings",
                  icon: Icons.settings,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ControlPanel(ssh: widget.ssh),
                      ),
                    );
                  },
                ),
                deviceCard(
                  title: "Terminal",
                  subtitle: "Shell access",
                  icon: Icons.terminal,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TerminalScreen(ssh: widget.ssh),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 25),

            const Text(
              "Updates",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),

            systemAndUpdatesCards("System updates", () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SystemUpdatesPage(ssh: widget.ssh),
                ),
              );
            }),
            const SizedBox(height: 25),
          ],
        ),
      ),
    );
  }

  Widget getPage() {
    switch (selectedIndex) {
      case 0:
        return homePage();
      case 1:
        return ProcessPage(ssh: widget.ssh);
      case 2:
        return NetworkPage(ssh: widget.ssh);
      case 3:
        return ProfilePage(ssh: widget.ssh);
      default:
        return homePage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _navigationStack.length <= 1,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onWillPop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: IndexedStack(
          index: selectedIndex,
          children: [
            homePage(),
            ProcessPage(ssh: widget.ssh),
            NetworkPage(ssh: widget.ssh),
            ProfilePage(ssh: widget.ssh),
          ],
        ),
        bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 25),
        color: Colors.black,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              navItem(Icons.home_rounded, "Home", 0),
              navItem(Icons.analytics_rounded, "Processes", 1),
              navItem(Icons.wifi_tethering_rounded, "Network", 2),
              navItem(Icons.person, "Profile", 3),
            ],
          ),
        ),
      ),
    );
  }

  Widget navItem(IconData icon, String label, int index) {
    bool selected = selectedIndex == index;

    return GestureDetector(
        onTap: () => _onTabTapped(index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: selected
              ? const Color.fromARGB(255, 255, 255, 255)
              : Colors.grey,
            size: 28,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: selected
                  ? const Color.fromARGB(255, 255, 255, 255)
                  : Colors.grey,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

