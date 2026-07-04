import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:syne/types/server.dart';
import 'package:syne/screens/home_page.dart';
import 'package:syne/screens/app_dialog.dart';
import 'package:syne/service/ssh_service.dart';
import 'package:syne/service/server_storage.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final serverAddress = TextEditingController();
  final port = TextEditingController();
  final user = TextEditingController();
  final pass = TextEditingController();

  final ssh = SSHService();
  final storage = ServerStorage();

  @override
  void dispose() {
    serverAddress.dispose();
    port.dispose();
    user.dispose();
    pass.dispose();
    super.dispose();
  }

  Future<void> connect() async {
    FocusScope.of(context).unfocus(); // Dismiss keyboard

    final input = serverAddress.text.trim();
    String hostValue = input;
    int portValue = 22; 

    if (input.contains(':')) {
      final parts = input.split(':');
      hostValue = parts[0].trim();
      portValue = int.tryParse(parts[1].trim()) ?? 22;
    }

    if (hostValue.isEmpty || user.text.isEmpty || pass.text.isEmpty) {
      AppDialog.show(
        type: DialogType.warning,
        context: context,
        title: "Missing Fields",
        message: "Please fill out all login fields to continue.",
        actions: [AppDialog.action("OK", () => Navigator.pop(context))],
      );
      return;
    }

    // Initialize Progress Trackers
    final statusNotifier = ValueNotifier<String>("Authenticating with server...");
    final progressNotifier = ValueNotifier<double>(0.05);

    // Show the Loading Dialog (We don't await this, it runs in the foreground)
    AppDialog.show(
      context: context,
      title: "Connecting",
      type: DialogType.loading,
      dynamicMessage: statusNotifier,
      progressNotifier: progressNotifier,
      barrierDismissible: false, // Prevent user from tapping out
    );

    try {
      // Establish ssh connection
      await ssh.connect(hostValue, portValue, user.text, pass.text);
      
      // Deploy agent and update progress
      await ssh.startMetricsStream(
        onProgress: (status, progress) {
          statusNotifier.value = status;
          progressNotifier.value = progress;
        },
      );

      statusNotifier.value = "Finalizing setup...";
      progressNotifier.value = 1.0;
      await Future.delayed(const Duration(milliseconds: 300)); // Smooth animation finish

      String generateId() {
        return DateTime.now().millisecondsSinceEpoch.toString() +
            Random().nextInt(9999).toString();
      }

      // SAVE SERVER AFTER SUCCESSFUL LOGIN
      await storage.saveServer(
        Server(
          id: generateId(),
          name: hostValue, 
          host: hostValue,
          port: portValue,
          username: user.text,
          password: pass.text,
        ),
      );

      if (!mounted) return;

      // Close Loading Dialog
      Navigator.pop(context); 

      // Navigate to Home
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomePage(ssh: ssh)),
      );

    } catch (e) {
      await ssh.disconnect();
      if (!mounted) return;

      // Close the Loading Dialog
      Navigator.pop(context);

      // Show Error Dialog
      AppDialog.show(
        type: DialogType.error,
        context: context,
        title: "Connection Failed",
        message: e.toString().replaceAll("Exception: ", ""),
        actions: [
          AppDialog.action(
            "OK",
            () => Navigator.pop(context),
          ),
        ],
      );  
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 0, 0, 0),

      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(30),

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
                const SizedBox(height: 6),

                const Text(
                  'Please log in to continue',
                  style: TextStyle(fontSize: 18, color: Colors.white),
                ),
                const SizedBox(height: 26),

                TextField(
                  controller: serverAddress,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'IP Address',
                    hintText: 'Eg: 192.168.1.1:2222',
                    helperText: 'Leave out port to default to 22',
                    helperStyle: TextStyle(color: Colors.white60),
                    hintStyle: TextStyle(color: Colors.white30),
                    labelStyle: TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: user,
                  style: const TextStyle(color: Colors.white),

                  decoration: const InputDecoration(
                    labelText: 'Username',
                    labelStyle: TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: pass,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),

                  decoration: const InputDecoration(
                    labelText: 'Password',
                    labelStyle: TextStyle(color: Colors.white70),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 26),

                SizedBox(
                  width: double.infinity,
                  height: 49,

                  child: ElevatedButton(
                    onPressed: connect,

                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFA2D9A1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Login',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
