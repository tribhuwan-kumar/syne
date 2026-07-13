import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'home_page.dart';
import 'login_page.dart';
import 'app_dialog.dart';

import 'package:syne/types/server.dart';
import 'package:syne/service/ssh_service.dart';
import 'package:syne/service/server_storage.dart';

class ServerListPage extends StatefulWidget {
  const ServerListPage({super.key});

  @override
  State<ServerListPage> createState() => _ServerListPageState();
}

class _ServerListPageState extends State<ServerListPage> {
  final storage = ServerStorage();
  List<Server> servers = [];
  bool loading = true;
  bool connecting = false;

  @override
  void initState() {
    super.initState();
    loadServers();
  }

  void loadServers() async {
    final data = await storage.getServers();

    setState(() {
      servers = data;
      loading = false;
    });
  }

  void connect(Server server) async {
    final ssh = SSHService();

    try {
      await ssh.connect(server.host, server.port, server.username, server.password);
      await ssh.startMetricsStream();

      if (!mounted) return;

      // Close the "Connecting..." dialog
      Navigator.pop(context);

      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => HomePage(ssh: ssh)),
      );
    } catch (e) {
      await ssh.disconnect();
      if (!mounted) return;

      Navigator.pop(context);

      AppDialog.show(
        type: DialogType.error,
        context: context,
        title: "Connection Failed",
        message: e.toString(),
        actions: [
          AppDialog.action(
            "OK",
            () => Navigator.pop(context)),
        ],
      );
    }

    if (mounted) {
      setState(() => connecting = false);
    }
  }

  Widget serverCard(Server server) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),

      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(12),
      ),

      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFA2D9A1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.dns, color: Colors.black),
          ),

          const SizedBox(width: 16),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  server.name,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 4),

								Row(
									children:[
										Text(
										"User: ${server.username}",
										style: TextStyle(color: Colors.grey, fontSize: 12),
										),
									const SizedBox(width: 2),
									Text(" | ", style: TextStyle(color: Colors.grey, fontSize: 12)),
									const SizedBox(width: 2),
									Text(
										"IP: ${server.host}",
										style: TextStyle(
											color: Colors.grey,
											fontSize: 12,
										)),
									]
								)
              ],
            ),
          ),

          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: () async {
              AppDialog.show(
                context: context,
                title: "Delete Server",
                message: "Are you sure you want to delete below server?\n User: ${server.username}\n IP: ${server.host}",
                type: DialogType.warning,
                actions: [
                  AppDialog.action("Cancel", () => Navigator.pop(context)),
                  AppDialog.action("Delete", () {
                    storage.deleteServer(server.id);
                    Navigator.pop(context);
                    loadServers();
                  }),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),

          child: Column(
            children: [
              Text(
                "Syne",
                style: GoogleFonts.lobsterTwo(
                  fontWeight: FontWeight.bold,
                  fontSize: 50,
                  color: Colors.white,
                ),
              ),

              Text(
                textAlign: TextAlign.center,
                "Stats asynchronously!!",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontStyle: FontStyle.normal,
                ),
              ),

              SizedBox(height: 16),

              Expanded(
                child: servers.isEmpty
                  ? const Center(
                    child: Text(
                      "No servers added",
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                  : ListView.builder(
                    itemCount: servers.length,
                    itemBuilder: (context, index) {
                      return GestureDetector(
                        onTap: connecting
                          ? null
                          : () {
                            if(connecting) return;
                            setState(() => connecting = true);
                            AppDialog.show(
                              barrierDismissible: false,
                              context: context,
                              title: "Connecting to ${servers[index].host} as ${servers[index].username}...",
                              message: "Wait a sec, establishing connection...",
                            );

                            connect(servers[index]);
                          },
                        child: serverCard(servers[index]),
                      );
                    },
                  ),
              ),
              const SizedBox(height: 10),


              SizedBox(
                width: double.infinity,
                height: 54,

                child: ElevatedButton(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginPage()),
                    );

                    loadServers();
                  },

                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFA2D9A1),
                    shape: CircleBorder(),
                  ),

                  child: Icon(Icons.add, color: Colors.black, size: 35),
                ),
              ),
              SizedBox(height: 10),


              Text(
                "Add server",
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              SizedBox(height: 15),

            ],
          ),
        ),
      ),
    );
  }
}

