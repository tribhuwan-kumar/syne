import 'dart:async';
import 'package:flutter/material.dart';
import 'package:syne/service/ssh_service.dart';

class ProcessPage extends StatefulWidget {
  final SSHService ssh;

  const ProcessPage({super.key, required this.ssh});

  @override
  State<ProcessPage> createState() => _ProcessPageState();
}

enum SortMode { alphabetical, cpu, ram }

class _ProcessPageState extends State<ProcessPage> {
  List<Map<String, dynamic>> allProcesses = [];
  List<Map<String, dynamic>> filteredProcesses = [];

  SortMode _currentSort = SortMode.cpu; 
  String _searchQuery = "";

  StreamSubscription<Map<String, dynamic>>? _metricsSubscription;

  @override
  void initState() {
    super.initState();
    // Subscribe to the stream that is already running
    _metricsSubscription = widget.ssh.metricsStream.listen(_onMetricsUpdate);
  }

  @override
  void dispose() {
    _metricsSubscription?.cancel();
    super.dispose();
  }

  void _applySortAndFilter() {
    List<Map<String, dynamic>> data = List.from(allProcesses);

    // 1. Filter
    if (_searchQuery.isNotEmpty) {
      data = data.where((p) {
        final name = (p['program'] ?? "").toLowerCase();
        final user = (p['user'] ?? "").toLowerCase();
        return name.contains(_searchQuery) || user.contains(_searchQuery);
      }).toList();
    }

    // 2. Sort
    data.sort((a, b) {
      switch (_currentSort) {
        case SortMode.alphabetical:
          return (a['program'] as String).compareTo(b['program'] as String);
        case SortMode.cpu:
          return _parsePercent(b['cpu_percent']).compareTo(_parsePercent(a['cpu_percent']));
        case SortMode.ram:
          return _parseSize(b['memory']).compareTo(_parseSize(a['memory']));
      }
    });

    setState(() {
      filteredProcesses = data;
    });
  }

  double _parsePercent(String s) => double.tryParse(s.replaceAll('%', '')) ?? 0.0;
  double _parseSize(String sizeStr) {
    double val = double.tryParse(sizeStr.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
    if (sizeStr.contains('KiB')) return val;
    if (sizeStr.contains('MiB')) return val * 1024;
    if (sizeStr.contains('GiB')) return val * 1024 * 1024;
    return val;
  }

  void _onMetricsUpdate(Map<String, dynamic> data) {
    if (!mounted || data['processes'] == null) return;
    allProcesses = (data['processes'] as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    _applySortAndFilter(); // Sort whenever new data arrives
  }

  void filterProcesses(String query) {
    setState(() {
      filteredProcesses = allProcesses.where((p) {
        final name = (p['program'] ?? "").toLowerCase();
        final user = (p['user'] ?? "").toLowerCase();
        final search = query.toLowerCase();
        return name.contains(search) || user.contains(search);
      }).toList();
    });
  }

  Future<void> performAction(String pid, String actionType) async {
    // Close bottom sheet
    Navigator.pop(context); 

    try {
      if (widget.ssh.osType == "windows") {
        await widget.ssh.run("taskkill /F /PID $pid /T");
      } else {
        await widget.ssh.run("kill -$actionType $pid");
      }
    } catch (e) {
      // Handle or log potential errors if the process was already closed
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to terminate process: $e")),
        );
      }
    }
  }

  void showProcessOptions(Map<String, dynamic> p) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      builder: (_) => Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(p['program'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
            ListTile(
              leading: const Icon(Icons.stop_circle, color: Colors.red),
              title: const Text("Terminate (SIGTERM)", style: TextStyle(color: Colors.white)),
              onTap: () => performAction(p['pid'], "15"),
            ),
            ListTile(
              leading: const Icon(Icons.highlight_remove, color: Colors.redAccent),
              title: const Text("Force Kill (SIGKILL)", style: TextStyle(color: Colors.white)),
              onTap: () => performAction(p['pid'], "9"),
            ),
          ],
        ),
      ),
    );
  }

@override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Processes"),
        backgroundColor: Colors.black,
        centerTitle: true,
        actions: [
          PopupMenuButton<SortMode>(
            icon: const Icon(Icons.sort),
            onSelected: (mode) { setState(() => _currentSort = mode); _applySortAndFilter(); },
            itemBuilder: (_) => [
              const PopupMenuItem(value: SortMode.alphabetical, child: Text("A-Z")),
              const PopupMenuItem(value: SortMode.cpu, child: Text("CPU usage")),
              const PopupMenuItem(value: SortMode.ram, child: Text("RAM usage")),
            ],
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(
              style: const TextStyle(color: Colors.white),
              onChanged: (val) { _searchQuery = val; _applySortAndFilter(); },
              decoration: InputDecoration(
                hintText: "Search...",
                prefixIcon: const Icon(Icons.search, color: Color(0xFFA2D9A1)),
                filled: true,
                fillColor: const Color(0xFF1C1C1E),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(50), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              physics: const BouncingScrollPhysics(), // Smooth scrolling physics
              padding: const EdgeInsets.all(10),
              itemCount: filteredProcesses.length,
              itemBuilder: (context, index) {
                final p = filteredProcesses[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(12)),
                  child: Material(
                    type: MaterialType.transparency,
                    child: ListTile(
                      onTap: () => showProcessOptions(p),
                      title: Text(p['program'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      subtitle: Text("PID: ${p['pid']} • User: ${p['user']}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(p['cpu_percent'], style: const TextStyle(color: Colors.greenAccent, fontSize: 12)),
                          Text(p['memory'], style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
