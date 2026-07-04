import 'screens/login_page.dart';
import 'service/server_storage.dart';

import 'package:flutter/material.dart';
import 'package:syne/screens/server_list_page.dart';

void main() {
  runApp(Syne());
}

class Syne extends StatefulWidget {
  const Syne({super.key});

  @override
  State<Syne> createState() => SyneState();
}

class SyneState extends State<Syne> {
  final storage = ServerStorage();
  bool loading = true;
  bool hasServers = false;

  @override
  void initState() {
    super.initState();
    checkServers();
  }

  void checkServers() async {

    final servers = await storage.getServers();

    setState(() {
      hasServers = servers.isNotEmpty;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: hasServers ? ServerListPage() : LoginPage(),
    );
  }
}
