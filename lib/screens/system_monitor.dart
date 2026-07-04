import 'dart:async';
import 'package:flutter/material.dart';

import 'package:syne/service/ssh_service.dart';

class SystemMonitor extends StatefulWidget {
  final SSHService ssh;

  const SystemMonitor({super.key, required this.ssh});

  @override
  State<SystemMonitor> createState() => _SystemMonitorState();
}

class _SystemMonitorState extends State<SystemMonitor> {
  // Identity
  String hostname = "--";
  String uptime = "--";
  String loadAvg = "--";

  // Hardware
  String cpuModel = "--";
  String cpuUsage = "--";
  String cpuTemp = "--";
  String gpuModel = "";
  String gpuUsage = "";
  String gpuTemp = "";

  // Memory
  String memTotal = "--";
  String memUsed = "--";
  String memAvailable = "--";
  String memCached = "--";
  String memFree = "--";
  double memoryPercent = 0.0;

  // Battery
  String batState = "";
  String batPercent = "";
  String batV = "";
  String batW = "";
  String batA = "";

  // Collections
  List<Map<String, dynamic>> sensors = [];
  List<Map<String, dynamic>> disks = [];
  List<Map<String, dynamic>> activeNetworks = [];

  StreamSubscription<Map<String, dynamic>>? _metricsSubscription;

  @override
  void initState() {
    super.initState();
    _metricsSubscription = widget.ssh.metricsStream.listen(_onMetricsUpdate);
  }

  @override
  void dispose() {
    _metricsSubscription?.cancel();
    super.dispose();
  }

  double _parseSizeToBytes(String sizeStr) {
    if (sizeStr.isEmpty) return 0.0;
    final numStr = sizeStr.replaceAll(RegExp(r'[^0-9.]'), '');
    double val = double.tryParse(numStr) ?? 0.0;

    if (sizeStr.contains('KiB')) return val * 1024;
    if (sizeStr.contains('MiB')) return val * 1024 * 1024;
    if (sizeStr.contains('GiB')) return val * 1024 * 1024 * 1024;
    if (sizeStr.contains('TiB')) return val * 1024 * 1024 * 1024 * 1024;
    return val;
  }

  String _formatUptime(int seconds) {
    int days = seconds ~/ (24 * 3600);
    int hours = (seconds % (24 * 3600)) ~/ 3600;
    int minutes = (seconds % 3600) ~/ 60;
    if (days > 0) return "${days}d ${hours}h";
    if (hours > 0) return "${hours}h ${minutes}m";
    return "${minutes}m";
  }

  void _onMetricsUpdate(Map<String, dynamic> data) {
    if (!mounted) return;

    setState(() {
      // Identity
      if (data['identity'] != null) {
        final id = data['identity'];
        hostname = id['hostname'] ?? hostname;
        int up = id['uptime_secs'] ?? 0;
        uptime = _formatUptime(up);

        List<dynamic> loads = id['load_average'] ?? [];
        loadAvg = loads.isNotEmpty ? loads.join(", ") : "--";
      }

      // Hardware
      if (data['hardware'] != null) {
        final hw = data['hardware'];
        cpuModel = hw['cpu_model'] ?? cpuModel;
        cpuUsage = hw['global_cpu_usage'] ?? cpuUsage;
        double rCpuTemp = (hw['avg_cpu_temp'] ?? 0.0).toDouble();
        cpuTemp = rCpuTemp > 0 ? "${rCpuTemp.toStringAsFixed(1)}°C" : "N/A";

        gpuModel = hw['gpu_model'] ?? "";
        gpuUsage = hw['global_gpu_usage'] ?? "";
        double rGpuTemp = (hw['avg_gpu_temp'] ?? 0.0).toDouble();
        gpuTemp = rGpuTemp > 0 ? "${rGpuTemp.toStringAsFixed(1)}°C" : "";

        if (hw['sensors'] != null) {
          sensors = (hw['sensors'] as List)
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }

      // Memory
      if (data['memory'] != null) {
        final mem = data['memory'];
        memTotal = mem['total'] ?? memTotal;
        memUsed = mem['used'] ?? memUsed;
        memAvailable = mem['available'] ?? memAvailable;
        memCached = mem['cached'] ?? memCached;
        memFree = mem['free'] ?? memFree;

        double u = _parseSizeToBytes(memUsed);
        double t = _parseSizeToBytes(memTotal);
        memoryPercent = t > 0 ? (u / t) : 0.0;
      }

      // Battery
      if (data['batteries'] != null && (data['batteries'] as List).isNotEmpty) {
        final bat = data['batteries'][0];
        batState = bat['state'] ?? "";
        batPercent = bat['percentage'] ?? "";
        batV = bat['voltage'] ?? "";
        batW = bat['wattage'] ?? "";
        batA = bat['amperage'] ?? "";
      } else {
        batState = "";
      }

      // Disks
      if (data['disks'] != null) {
        disks = (data['disks'] as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }

      // Networks
      if (data['networks'] != null) {
        activeNetworks = (data['networks'] as List)
            .map((e) => Map<String, dynamic>.from(e))
            .where((n) => n['name'] != 'lo' && n['is_active'] == true)
            .toList();
      }
    });
  }

  // --- UI Components ---

  Widget glassCard({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: child,
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isMonospace = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(width: 16),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFamily: isMonospace ? 'monospace' : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityCard() {
    return glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.dns_rounded, color: Color(0xFFA2D9A1), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hostname,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoRow("CPU", cpuModel),
          if (gpuModel.isNotEmpty) _buildInfoRow("GPU", gpuModel),
          _buildInfoRow("Load Avg", loadAvg, isMonospace: true),
        ],
      ),
    );
  }

  Widget _buildHardwareGauges() {
    bool hasGpu = gpuModel.isNotEmpty && gpuUsage.isNotEmpty;
    return glassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // CPU Gauge
          Expanded(
            child: _buildGaugeItem(Icons.memory, "CPU", cpuUsage, cpuTemp),
          ),

          // Uptime
          Expanded(
            child: Column(
              children: [
                const Icon(Icons.schedule_rounded, color: Color(0xFFA2D9A1)),
                const SizedBox(height: 8),
                Text(
                  uptime,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  "Uptime",
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),

          // GPU Gauge (Conditionally rendered)
          if (hasGpu)
            Expanded(
              child: _buildGaugeItem(
                Icons.developer_board,
                "GPU",
                gpuUsage,
                gpuTemp,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGaugeItem(
    IconData icon,
    String label,
    String usage,
    String temp,
  ) {
    return Column(
      children: [
        Icon(
          icon,
          color: label == "CPU" ? Color(0xFFA2D9A1) : Color(0xFFA2D9A1),
        ),
        const SizedBox(height: 8),
        Text(
          usage,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          "$label: $temp",
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildActiveNetworksCard() {
    if (activeNetworks.isEmpty) return const SizedBox.shrink();
    return glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.settings_ethernet, color: Color(0xFFA2D9A1), size: 18),
              SizedBox(width: 8),
              Text(
                "Network interfaces",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...activeNetworks.map((net) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        net['name'] ?? "Unknown",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        (net['ip_addresses'] as List).isNotEmpty
                            ? net['ip_addresses'][0]
                            : "No IP",
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.arrow_downward,
                            color: Colors.greenAccent,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            net['download_speed'] ?? "0",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          const Icon(
                            Icons.arrow_upward,
                            color: Colors.orangeAccent,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            net['upload_speed'] ?? "0",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(color: Colors.white12, height: 1),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildBatteryCard() {
    if (batState.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: glassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  batState.toLowerCase() == "charging"
                      ? Icons.battery_charging_full
                      : Icons.battery_std,
                  color: Color(0xFFA2D9A1),
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  "Battery stats",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  batPercent,
                  style: const TextStyle(
                    color: Color(0xFFA2D9A1),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow("State", batState),
            _buildInfoRow("Voltage", batV, isMonospace: true),
            _buildInfoRow("Wattage", batW, isMonospace: true),
            _buildInfoRow("Amperage", batA, isMonospace: true),
          ],
        ),
      ),
    );
  }

  Widget _buildMemoryCard() {
    return glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.memory, color: Color(0xFFA2D9A1), size: 18),
              SizedBox(width: 8),
              Text(
                "Memory usage",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: memoryPercent.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: Colors.grey.shade800,
            color: const Color(0xFFA2D9A1),
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 12),
          _buildInfoRow("Total", memTotal, isMonospace: true),
          _buildInfoRow("Used", memUsed, isMonospace: true),
          _buildInfoRow("Cached", memCached, isMonospace: true),
          _buildInfoRow("Available", memAvailable, isMonospace: true),
          _buildInfoRow("Free", memFree, isMonospace: true),
        ],
      ),
    );
  }

  Widget _buildStorageCard() {
    if (disks.isEmpty) return const SizedBox.shrink();
    return glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.storage, color: Colors.white70, size: 18),
              SizedBox(width: 8),
              Text(
                "Disk storage",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: disks.map((d) {
                  double p =
                      (double.tryParse(d['use_percent'].replaceAll("%", "")) ??
                          0) /
                      100;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Scroll ONLY the text row so the progress bar stays constrained
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: constraints.maxWidth,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  d['mount_point'] == "/"
                                      ? "/root"
                                      : d['mount_point'],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Text(
                                  "${d['used']} / ${d['size']}",
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: p.clamp(0.0, 1.0),
                          minHeight: 4,
                          backgroundColor: Colors.grey.shade800,
                          color: p > 0.85
                              ? Colors.redAccent
                              : const Color(0xFFA2D9A1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSensorsCard() {
    if (sensors.isEmpty) return const SizedBox.shrink();
    return glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.thermostat, color: Color(0xFFA2D9A1), size: 18),
              SizedBox(width: 8),
              Text(
                "Hardware sensors",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(maxHeight: 250),
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              physics: const BouncingScrollPhysics(),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: constraints.maxWidth,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: sensors.map((s) {
                          double t = (s['temperature_c'] ?? 0.0).toDouble();
                          return _buildInfoRow(
                            "${s['label']}:",
                            "${t.toStringAsFixed(1)}°C",
                            isMonospace: true,
                          );
                        }).toList(),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          "System details",
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        physics: const BouncingScrollPhysics(),
        children: [
          _buildIdentityCard(),
          const SizedBox(height: 15),

          _buildHardwareGauges(),
          const SizedBox(height: 15),

          _buildActiveNetworksCard(),
          const SizedBox(height: 15),

          _buildBatteryCard(),
          _buildMemoryCard(),
          const SizedBox(height: 15),

          _buildStorageCard(),
          const SizedBox(height: 15),

          _buildSensorsCard(),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}
