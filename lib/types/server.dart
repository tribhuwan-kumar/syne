class Server {
  final String id;
  final int port;
  final String name;
  final String host;
  final String username;
  final String password;

  Server({
    required this.id,
    required this.port,
    required this.name,
    required this.host,
    required this.username,
    required this.password,
  });

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "port": port,
      "name": name,
      "host": host,
      "username": username,
    };
  }

  factory Server.fromJson(Map<String, dynamic> json, String password) {
    return Server(
      id: json["id"],
      port: json["port"],
      name: json["name"],
      host: json["host"],
      username: json["username"],
      password: password,
    );
  }
}

