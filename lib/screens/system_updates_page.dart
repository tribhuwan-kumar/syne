import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

import 'package:syne/service/ssh_service.dart';

class SystemUpdatesPage extends StatefulWidget {
  final SSHService ssh;

  const SystemUpdatesPage({super.key, required this.ssh});

  @override
  State<SystemUpdatesPage> createState() => _SystemUpdatesPage();
}

class _SystemUpdatesPage extends State<SystemUpdatesPage> {
  bool isLoading = true;
  String osType = "Detecting...";

  List<Map<String, String>> updates = [];
  List<Map<String, String>> filteredUpdates = [];
  Set<String> selectedPackages = {};

  String error = "";
  String searchQuery = "";

  // Unified Package Manager Configuration
  final Map<String, Map<String, String>> pmConfig = {
    // Arch based
    "Arch Linux": {"list": "pacman -Qu", "upgrade": "pacman -S --noconfirm"},
    "Manjaro": {"list": "pacman -Qu", "upgrade": "pacman -S --noconfirm"},
    "EndeavourOS": {"list": "pacman -Qu", "upgrade": "pacman -S --noconfirm"},

    // Debian based
    "Debian/Ubuntu": {
      "list": "apt list --upgradable",
      "upgrade": "apt-get install --only-upgrade -y",
    },
    "Linux Mint": {
      "list": "apt list --upgradable",
      "upgrade": "apt-get install --only-upgrade -y",
    },
    "Pop!_OS": {
      "list": "apt list --upgradable",
      "upgrade": "apt-get install --only-upgrade -y",
    },

    // RPM based
    "Fedora": {"list": "dnf check-update", "upgrade": "dnf upgrade -y"},
    "Red Hat": {"list": "dnf check-update", "upgrade": "dnf upgrade -y"},

    // APK based
    "Alpine Linux": {"list": "apk version -l '<'", "upgrade": "apk add -u"},
    "postmarketOS": {"list": "apk version -l '<'", "upgrade": "apk add -u"},

    // Zypper based
    "openSUSE": {"list": "zypper lu", "upgrade": "zypper in -y"},

    // Non Linux
    "macOS": {"list": "brew outdated", "upgrade": "brew upgrade"},
    "Windows": {"list": "winget upgrade", "upgrade": "winget upgrade --exact --id"},
  };

  @override
  void initState() {
    super.initState();
    fetchUpdates();
  }

  Future<void> fetchUpdates() async {
    setState(() {
      isLoading = true;
      error = "";
      selectedPackages.clear();
    });

    try {
      final baseOs = widget.ssh.osType.toLowerCase();

      if (baseOs == "macos") {
        osType = "macOS";
      } else if (baseOs == "windows") {
        osType = "Windows";
      } else if (baseOs == "linux") {
        // Detailed os detection via /etc/os-release
        final osRelease = await widget.ssh.runCommand("cat /etc/os-release");

        // Order matters, check derivatives before upstreams.
        if (osRelease.contains("ID=linuxmint") ||
            osRelease.contains("Linux Mint")) {
          osType = "Linux Mint";
        } else if (osRelease.contains("ID=pop") ||
            osRelease.contains("Pop!_OS")) {
          osType = "Pop!_OS";
        } else if (osRelease.contains("Ubuntu") ||
            osRelease.contains("Debian")) {
          osType = "Debian/Ubuntu";
        } else if (osRelease.contains("Manjaro")) {
          osType = "Manjaro";
        } else if (osRelease.contains("EndeavourOS")) {
          osType = "EndeavourOS";
        } else if (osRelease.contains("Arch")) {
          osType = "Arch Linux";
        } else if (osRelease.contains("Fedora")) {
          osType = "Fedora";
        } else if (osRelease.contains("Red Hat") ||
            osRelease.contains("RHEL")) {
          osType = "Red Hat";
        } else if (osRelease.contains("Alpine Linux") ||
            osRelease.contains("ID=alpine")) {
          osType = "Alpine Linux";
        } else if (osRelease.contains("postmarketOS")) {
          osType = "postmarketOS";
        } else if (osRelease.contains("openSUSE") ||
            osRelease.contains("SUSE")) {
          osType = "openSUSE";
        } else {
          osType = "Unknown";
          throw "Unsupported Linux distribution";
        }
      } else {
        osType = "Unknown";
        throw "Unsupported OS";
      }

      // Fetch List
      final cmd = pmConfig[osType]!['list']!;
      final rawOutput = await widget.ssh.runCommand(cmd);

      // Parse Output
      _parseUpdates(rawOutput);
    } catch (e) {
      setState(() {
        error = e.toString();
        isLoading = false;
      });
    }
  }

  void _parseUpdates(String raw) {
    List<Map<String, String>> parsedList = [];
    final lines = raw
        .split("\n")
        .where((line) => line.trim().isNotEmpty)
        .toList();

    for (var line in lines) {
      try {
        if (["Arch Linux", "Manjaro", "EndeavourOS"].contains(osType)) {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 4) {
            parsedList.add({
              'name': parts[0],
              'current': parts[1],
              'latest': parts[3],
            });
          }
        } else if ([
          "Debian/Ubuntu",
          "Linux Mint",
          "Pop!_OS",
        ].contains(osType)) {
          if (line.startsWith("Listing")) continue;
          final parts = line.split(RegExp(r'\s+'));
          final name = parts[0].split('/')[0];
          final latest = parts[1];
          final current = line.contains("upgradable from:")
              ? line.split("upgradable from:")[1].replaceAll("]", "").trim()
              : "--";
          parsedList.add({'name': name, 'current': current, 'latest': latest});
        } else if (["Fedora", "Red Hat"].contains(osType)) {
          if (line.startsWith("Last metadata")) continue;
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 3) {
            parsedList.add({
              'name': parts[0].split('.')[0],
              'current': "--",
              'latest': parts[1],
            });
          }
        } else if (["Alpine Linux", "postmarketOS"].contains(osType)) {
          // Format: pkgname-1.0-r0 < 1.1-r0
          final parts = line.split(" < ");
          if (parts.length == 2) {
            final latest = parts[1].trim();
            final currentStr = parts[0].trim();
            // Extract package name from the trailing version string
            final match = RegExp(r'^(.+)-([0-9].*)$').firstMatch(currentStr);
            final name = match != null ? match.group(1)! : currentStr;
            final current = match != null ? match.group(2)! : "--";

            parsedList.add({
              'name': name,
              'current': current,
              'latest': latest,
            });
          }
        } else if (osType == "openSUSE") {
          // Format: v | repo | pkg_name | current_ver | latest_ver | arch
          final parts = line.split('|').map((e) => e.trim()).toList();
          if (parts.length >= 5 &&
              parts[2] != "Name" &&
              !line.startsWith("Repository")) {
            parsedList.add({
              'name': parts[2],
              'current': parts[3],
              'latest': parts[4],
            });
          }
        } else if (osType == "macOS") {
          final parts = line.split(RegExp(r'\s+'));
          parsedList.add({
            'name': parts[0],
            'current': parts.length > 1
                ? parts[1].replaceAll(RegExp(r'[\(\)]'), '')
                : "--",
            'latest': parts.length > 3 ? parts[3] : parts.last,
          });
        } else if (osType == "Windows") {
          if (line.contains("---") || line.contains("Name")) continue;
          final parts = line.split(RegExp(r'\s{2,}'));
          if (parts.length >= 4) {
            parsedList.add({
              'name': parts[1],
              'current': parts[2],
              'latest': parts[3],
            });
          }
        }
      } catch (_) {
        // Skip malformed lines silently
      }
    }

    final validPackageNames = parsedList.map((e) => e['name']!).toSet();
    selectedPackages.retainAll(validPackageNames);

    setState(() {
      updates = parsedList;
      filteredUpdates = parsedList;
      isLoading = false;
    });
  }

  void applySearch(String query) {
    setState(() {
      searchQuery = query;

      if (query.isEmpty) {
        filteredUpdates = updates;
      } else {
        filteredUpdates = updates
            .where(
              (item) =>
                  item['name']!.toLowerCase().contains(query.toLowerCase()),
            )
            .toList();
      }
    });
  }

  void toggleSelection(String pkgName) {
    setState(() {
      if (selectedPackages.contains(pkgName)) {
        selectedPackages.remove(pkgName);
      } else {
        selectedPackages.add(pkgName);
      }
    });
  }

  Future<String?> showSudoPasswordDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text(
          "Authentication required",
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: TextField(
          controller: controller,
          obscureText: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Enter sudo password",
            hintStyle: TextStyle(color: Colors.white54),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFA2D9A1)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "Cancel",
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFA2D9A1),
            ),
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text(
              "Confirm",
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showProgressDialog(
    int count,
    Completer<Map<String, dynamic>> targetCompleter,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return FutureBuilder<Map<String, dynamic>>(
          future: targetCompleter.future,
          builder: (context, snapshot) {
            bool logicFinished =
                snapshot.connectionState == ConnectionState.done;
            bool totalSuccess =
                logicFinished && (snapshot.data?['success'] ?? false);
            String displayMsg = !logicFinished
                ? "Upgrading $count selected package(s). Please wait..."
                : (totalSuccess
                      ? "All packages upgraded successfully!"
                      : "Some updates failed or encountered errors.");

            return AlertDialog(
              backgroundColor: const Color(0xFF1C1C1E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  if (!logicFinished)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFFA2D9A1),
                      ),
                    )
                  else
                    Icon(
                      totalSuccess ? Icons.check_circle : Icons.error_outline,
                      color: totalSuccess
                          ? Colors.greenAccent
                          : Colors.redAccent,
                    ),
                  const SizedBox(width: 12),
                  Text(
                    logicFinished ? "Process finished" : "Updating packages",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayMsg,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    if (logicFinished &&
                        !totalSuccess &&
                        snapshot.data?['error'] != null) ...[
                      const SizedBox(height: 12),
                      const Text(
                        "Error Output:",
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          snapshot.data!['error'].toString(),
                          style: const TextStyle(
                            color: Colors.white60,
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                if (logicFinished)
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text(
                      "Close",
                      style: TextStyle(
                        color: Color(0xFFA2D9A1),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> runUpgrade() async {
    if (selectedPackages.isEmpty) return;

    // Only Linux distros require sudo in this workflow (macOS brew/winget do not)
    bool requiresSudo = !["macOS", "Windows"].contains(osType);
    String? password;

    if (requiresSudo) {
      password = await showSudoPasswordDialog();
      if (password == null) return; // User cancelled
    }

    final completer = Completer<Map<String, dynamic>>();
    _showProgressDialog(selectedPackages.length, completer);

    try {
      final baseCmd = pmConfig[osType]!['upgrade']!;
      final pkgString = selectedPackages.join(" ");
      String commandOutput = "";

      if (requiresSudo) {
        final fullCmd = "sudo -S -k $baseCmd $pkgString";
        final session = await widget.ssh.client!.execute(fullCmd);

        // Safely pass the password directly to the stdin stream
        session.stdin.add(Uint8List.fromList(utf8.encode("$password\n")));
        await session.stdin.close();

        commandOutput = await session.stdout.cast<List<int>>().transform(utf8.decoder).join();

        final errorOutput = await session.stderr.cast<List<int>>().transform(utf8.decoder).join();

        if (errorOutput.toLowerCase().contains("incorrect password") || 
            errorOutput.toLowerCase().contains("try again")) {
          throw "Authentication failed: Incorrect sudo password.";
        }

        if (errorOutput.trim().isNotEmpty && !errorOutput.toLowerCase().contains("warning")) {
          commandOutput += "\n$errorOutput";
        }

      } else {
        // macOS or Windows
        final fullCmd = "$baseCmd $pkgString";
        commandOutput = await widget.ssh.runCommand(fullCmd);
      }

      // Check common exit errors or standard error indicators from package interfaces
      if (commandOutput.toLowerCase().contains("failed") ||
          commandOutput.toLowerCase().contains("error")) {
        throw commandOutput;
      }

      completer.complete({'success': true, 'error': null});
      selectedPackages.clear();

    } catch (e) {
      completer.complete({'success': false, 'error': e.toString()});
    } finally {
      await fetchUpdates();
    }
  }

  Widget summaryCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2A2A2D), Color(0xFF1C1C1E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "System updates",
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 10),

          Text(
            "${updates.length} Available",
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),

          Row(
            children: [
              const Icon(
                Icons.laptop_mac_rounded,
                color: Color(0xFFA2D9A1),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                osType,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 20),

          TextField(
            onChanged: applySearch,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "Search packages...",
              hintStyle: const TextStyle(color: Colors.grey),
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.25),
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget updatesList() {
    if (isLoading) {
      return const Expanded(
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFFA2D9A1)),
        ),
      );
    }

    if (error.isNotEmpty) {
      return Expanded(
        child: Center(
          child: Text(error, style: const TextStyle(color: Colors.red)),
        ),
      );
    }

    if (filteredUpdates.isEmpty) {
      return Expanded(
        child: Center(
          child: Text(
            updates.isEmpty ? "System is up to date!" : "No packages found",
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return Expanded(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filteredUpdates.length,
        itemBuilder: (context, index) {
          final pkg = filteredUpdates[index];
          final name = pkg['name']!;
          final isSelected = selectedPackages.contains(name);

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.green.withValues(alpha: 0.05)
                  : const Color(0xFF1C1C1E),
              borderRadius: BorderRadius.circular(18),
              border: isSelected
                  ? Border.all(color: const Color(0xFFA2D9A1), width: 1)
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Material(
                type: MaterialType.transparency,
                child: CheckboxListTile(
                  value: isSelected,
                  activeColor: const Color(0xFFA2D9A1),
                  checkColor: Colors.black,
                  onChanged: (_) => toggleSelection(name),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    "Current: ${pkg['current']}",
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  secondary: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start, 
                    children: [
                      const Text(
                        "Latest",
                        style: TextStyle(
                          color: Color(0xFFA2D9A1),
                          fontWeight: FontWeight.w500,
                          fontSize: 10,
                        ),
                      ),
                      Text(
                        pkg['latest']!,
                        style: const TextStyle(
                          color: Color(0xFFA2D9A1),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text("System updates"),
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.select_all),
            tooltip: "Select All",
            onPressed: () {
              setState(() {
                if (selectedPackages.length == filteredUpdates.length) {
                  selectedPackages.clear();
                } else {
                  selectedPackages.addAll(
                    filteredUpdates.map((e) => e['name']!),
                  );
                }
              });
            },
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: fetchUpdates),
        ],
      ),
      body: Column(children: [summaryCard(), updatesList()]),
      floatingActionButton: selectedPackages.isNotEmpty
        ? FloatingActionButton.extended(
          onPressed: isLoading ? null : runUpgrade,
          backgroundColor: const Color(0xFFA2D9A1),
          icon: const Icon(Icons.upload_rounded, color: Colors.black),
          label: Text(
            "Upgrade ${selectedPackages.length}",
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
        )
        : null,
    );
  }
}

