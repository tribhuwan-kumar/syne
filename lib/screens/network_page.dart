import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import 'package:syne/service/ssh_service.dart';

class NetworkPage extends StatefulWidget {
  final SSHService ssh;
  const NetworkPage({super.key, required this.ssh});

  @override
  State<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends State<NetworkPage> {
  Map<String, dynamic> netStats = {};
  List<FlSpot> downloadSpots = [];
  List<FlSpot> uploadSpots = [];
  double time = 0;

  // Store all interfaces for the list view
  List<Map<String, dynamic>> allInterfaces = [];

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

  void _onMetricsUpdate(Map<String, dynamic> data) {
    if (!mounted) return;

    setState(() {
      if (data['external_network'] != null) netStats['external'] = data['external_network'];
      if (data['open_ports'] != null) netStats['ports'] = data['open_ports'];

      if (data['networks'] != null) {
        allInterfaces = (data['networks'] as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        // Sort: Active interfaces first
        allInterfaces.sort(
          (a, b) => (b['is_active'] ? 1 : 0).compareTo(a['is_active'] ? 1 : 0),
        );

        final defaultIface = allInterfaces.firstWhere(
          (n) => n['is_default'] == true,
          orElse: () => allInterfaces.first,
        );

        netStats['default_iface'] = defaultIface;

        double d =
            double.tryParse(defaultIface['download_speed'].split(" ")[0]) ?? 0;
        double u =
            double.tryParse(defaultIface['upload_speed'].split(" ")[0]) ?? 0;

        time++;
        downloadSpots.add(FlSpot(time, d));
        uploadSpots.add(FlSpot(time, u));
        if (downloadSpots.length > 30) {
          downloadSpots.removeAt(0);
          uploadSpots.removeAt(0);
        }
      }
    });
  }

  Widget _buildTrafficChart() {
    final active = netStats['default_iface'] ?? {};
    List<FlSpot> getSafeSpots(List<FlSpot> spots) {
      if (spots.isEmpty) return [const FlSpot(0, 0)];
      return spots;
    }

    return glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Traffic",
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              Text(
                active['name'] ?? "...",
                style: const TextStyle(
                  color: Color(0xFFA2D9A1),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: false),
                titlesData: FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: getSafeSpots(downloadSpots),
                    color: Colors.greenAccent,
                    isCurved: true,
                    dotData: FlDotData(show: false),
                    isStrokeCapRound: true,
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.green.withValues(alpha: 0.1),
                    ),
                  ),
                  LineChartBarData(
                    spots: getSafeSpots(uploadSpots),
                    color: Colors.blueAccent,
                    isCurved: true,
                    dotData: FlDotData(show: false),
                    isStrokeCapRound: true,
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.blue.withValues(alpha: 0.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInterfaceList() {
    return glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Interfaces",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),

          // Restricts height to a maximum of 400 pixels
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 350),
            child: ListView.builder(
              shrinkWrap: true,
              physics: const BouncingScrollPhysics(),
              itemCount: allInterfaces.length,
              itemBuilder: (context, index) {
                final iface = allInterfaces[index];

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1E),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                iface['is_active']
                                  ? Icons.settings_ethernet
                                  : Icons.signal_wifi_off,
																	color: iface['is_active']
                                  ? Colors.green
                                  : Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                iface['name'],
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          iface['is_default']
														? Container(
																padding: const EdgeInsets.symmetric(
																		horizontal: 4, vertical: 2),
																decoration: BoxDecoration(
																	color: Colors.green.withValues(alpha: 0.15),
																	borderRadius: BorderRadius.circular(4),
																	border: Border.all(
																			color: Colors.green.withValues(alpha: 0.5)),
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
															)
														: const SizedBox(),
                        ],
                      ),
                      const SizedBox(height: 8),
											Row(
													mainAxisAlignment: MainAxisAlignment.spaceBetween,
													crossAxisAlignment: CrossAxisAlignment.start,
													children: [
													Flexible(
														child: Text(
															"IP: ${iface['ip_addresses'].firstWhere(
																(ip) => !ip.toString().contains(':'), // IPv4 addresses never contain colons
																orElse: () => iface['ip_addresses'].isNotEmpty ? iface['ip_addresses'][0] : 'N/A',
															)}",
															style: const TextStyle(
																color: Colors.white54,
																fontSize: 12,
																),
															),
														),
													const SizedBox(width: 8),
													Text(
														"${iface['download_speed']} ↓  ${iface['upload_speed']} ↑",
														style: const TextStyle(
															color: Colors.white70,
															fontSize: 12,
														),
													),
												],
											)
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOpenPortsCard() {
    final ports = netStats['ports'] as List? ?? [];
    if (ports.isEmpty) return const SizedBox.shrink();

    return glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Open ports",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          // Scrollable container for ports
          Container(
            constraints: const BoxConstraints(maxHeight: 300),
            child: ListView.builder(
              shrinkWrap: true,
              physics: const BouncingScrollPhysics(),
              itemCount: ports.length,
              itemBuilder: (context, index) {
                final p = ports[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.hub, color: Color(0xFFA2D9A1)),
                  title: Text(
                    "Port ${p['local_address'].split(':').last}",
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    p['state'],
                    style: const TextStyle(color: Colors.white54),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ext = netStats['external'] ?? {};
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Network"),
        backgroundColor: Colors.black,
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        physics: const BouncingScrollPhysics(),
        children: [
          _buildTrafficChart(),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  "Latency",
                  ext['latency_ms'] ?? "--",
                  Icons.timer,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildStatCard(
                  "Loss",
                  ext['packet_loss'] ?? "--",
                  Icons.warning_amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          _buildInterfaceList(),
          const SizedBox(height: 15),
          _buildOpenPortsCard(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget glassCard({required Widget child}) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xFF1C1C1E),
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );

  Widget _buildStatCard(String label, String value, IconData icon) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF1C1C1E),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(icon, color: const Color(0xFFA2D9A1)),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

