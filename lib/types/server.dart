class Server {
  final String id;
  final int port;
  final String name;        // Hostname
  final String host;				// Server's ip
  final String username;
  final String password;
	final String defaultPath; // PWD

  Server({
    required this.id,
    required this.port,
    required this.name,
    required this.host,
    required this.username,
    required this.password,
		required this.defaultPath,
  });

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "port": port,
      "name": name,
      "host": host,
      "username": username,
			"defaultPath": defaultPath,
    };
  }

  factory Server.fromJson(Map<String, dynamic> json, String password) {
    return Server(
      id: json["id"],
      port: json["port"],
      name: json["name"],
      host: json["host"],
      username: json["username"],
			defaultPath: json["defaultPath"],
      password: password,
    );
  }
}

