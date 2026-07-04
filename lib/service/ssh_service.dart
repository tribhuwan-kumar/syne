import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:msgpack_dart/msgpack_dart.dart';
import 'package:flutter/services.dart' show rootBundle;

class SSHService {
  SSHClient? client;
  SftpClient? sftp;

  String osType = "";

  Timer? _keepAliveTimer;

  String? _ip;
  int? _port;
  String? _user;
  String? _pass;

  VoidCallback? onConnectionLost;
  bool _isIntentionalDisconnect = false;

  bool get isConnected => client != null && !client!.isClosed && sftp != null;

  Future<void> connect(String ip, int port, String user, String pass) async {
    _ip = ip;
    _port = port;
    _user = user;
    _pass = pass;

    _isIntentionalDisconnect = false;

    final socket = await SSHSocket.connect(ip, port);
    client = SSHClient(socket, username: user, onPasswordRequest: () => pass);
    sftp = await client!.sftp();

    _startKeepAlive();
  }

  Future<void> reconnect() async {
    await disconnect();

    if (_ip == null || _port == null || _user == null || _pass == null) {
      throw Exception("Missing credentials");
    }

    await connect(_ip!, _port!, _user!, _pass!);
  }

  void _startKeepAlive() {
    _keepAliveTimer?.cancel();

    _keepAliveTimer = Timer.periodic(const Duration(seconds: 7), (timer) async {
      try {
        if (client == null || client!.isClosed) {
          timer.cancel();
          if (!_isIntentionalDisconnect) onConnectionLost?.call();
          return;
        }
        await client!.ping();
      } catch (_) {
        timer.cancel();
        if (!_isIntentionalDisconnect) onConnectionLost?.call();
      }
    });
  }

  Future<T> _safe<T>(Future<T> Function() fn) async {
    try {
      if (!isConnected) {
        await reconnect();
      }
      return await fn().timeout(const Duration(seconds: 15));
    } catch (_) {
      await reconnect();
      return await fn().timeout(const Duration(seconds: 15));
    }
  }

  Future<String> runCommand(String command) async {
    final marker = 'SYNE_DATA_START';
    final fullCommand = 'echo "$marker"; $command';
    final session = await _safe(() => client!.execute(fullCommand));
    final rawOutput = await session.stdout.cast<List<int>>().transform(utf8.decoder).join();
    return rawOutput.contains(marker) ? rawOutput.split(marker).last.trim() : rawOutput.trim();
  }

  Future<String> run(String s) async {
    return await runCommand(s);
  }

  Future<SSHSession> startShell() async {
    return await _safe(() => client!.shell(pty: SSHPtyConfig(width: 80, height: 24)));
  }

  Future<List<SftpName>> listDir(String path) async {
    final list = await _safe(() => sftp!.listdir(path));
    return list.where((file) {
      final name = file.filename;
      if (name == "." || name == "..") return false;
      if (name.startsWith(".")) return false;
      return true;
    }).toList();
  }

  Future<void> downloadFile({
    required String remotePath,
    required String localPath,
    required Function(double progress) onProgress,
    required Function() isCancelled,
  }) async {
    await _safe(() async {
      final remoteFile = await sftp!.open(remotePath);
      final stat = await remoteFile.stat();
      final totalSize = stat.size ?? 0;

      final file = File(localPath);
      final sink = file.openWrite();

      int received = 0;

      await for (final chunk in remoteFile.read()) {
        if (isCancelled()) {
          await sink.close();
          await remoteFile.close();
          if (await file.exists()) {
            await file.delete();
          }
          return;
        }

        received += chunk.length;
        sink.add(chunk);

        if (totalSize != 0) {
          onProgress(received / totalSize);
        }
      }

      await sink.close();
      await remoteFile.close();
    });
  }

  Future<void> createDirIfNotExists(String path) async {
    await _safe(() async {
      try {
        await sftp!.stat(path);
      } catch (_) {
        await _createRemoteDirs(path);
      }
    });
  }

  Future<void> resetSftp() async {
    try {
      sftp?.close();
    } catch (_) {}

    try {
      sftp = await client!.sftp();
    } catch (_) {}
  }

  Future<void> uploadFile({
    required String localPath,
    required String remotePath,
    required Function(double progress) onProgress,
    required Function() isCancelled,
  }) async {
    await _safe(() async {
      final file = File(localPath);
      final totalSize = await file.length();

      final remoteFile = await sftp!.open(
        remotePath,
        mode:
            SftpFileOpenMode.create |
            SftpFileOpenMode.write |
            SftpFileOpenMode.truncate,
      );

      int sent = 0;
      int lastUpdate = 0;

      final controller = StreamController<Uint8List>();

      try {
        final writeFuture = remoteFile.write(controller.stream);
        final stream = file.openRead();

        await for (final chunk in stream) {
          if (isCancelled()) {
            await controller.close();
            await remoteFile.close();
            throw Exception("Upload cancelled");
          }

          final data = Uint8List.fromList(chunk);
          controller.add(data);

          sent += data.length;

          final now = DateTime.now().millisecondsSinceEpoch;

          if (now - lastUpdate > 100) {
            lastUpdate = now;
            if (totalSize != 0) {
              onProgress(sent / totalSize);
            }
          }

          await Future.delayed(const Duration(milliseconds: 1));
        }

        await controller.close();
        await writeFuture.timeout(const Duration(seconds: 30));
      } catch (e) {
        try {
          await controller.close();
        } catch (_) {}

        try {
          await remoteFile.close();
        } catch (_) {}

        try {
          await sftp!.remove(remotePath);
        } catch (_) {}

        await resetSftp();
        rethrow;
      } finally {
        try {
          await remoteFile.close();
        } catch (_) {}
      }
    });
  }

  Future<void> _createRemoteDirs(String path) async {
    final parts = path.split("/");
    String current = "";

    for (final part in parts) {
      if (part.isEmpty) continue;
      current += "/$part";
      try {
        await sftp!.mkdir(current);
      } catch (_) {}
    }
  }

  Future<void> disconnect() async {
    _isIntentionalDisconnect = true;
    _keepAliveTimer?.cancel();
    // Kill the agent before disconnecting
    if (client != null && !client!.isClosed) {
      final remotePath = '.syne_metrics${osType == "windows" ? ".exe" : ""}';
      try {
        if (osType == "windows") {
          await client!.execute("taskkill /F /IM $remotePath");
        } else {
          await client!.execute("pkill -f $remotePath");
        }
      } catch (_) {
        // Ignore errors during disconnect cleanup
      }
    }

    try {
      client?.close();
    } catch (_) {
      // Ignore errors
    }
    client = null;
    sftp = null;
  }

  /// Metrics stream controller
  final StreamController<Map<String, dynamic>> _metricsController = StreamController.broadcast();
  Stream<Map<String, dynamic>> get metricsStream => _metricsController.stream;
  SSHSession? _metricsSession;

  /// Deploys the cross-platform Rust binary and starts the MessagePack stream
  Future<void> startMetricsStream({void Function(String step, double progress)? onProgress}) async {
    if (!isConnected) return;
    if (_metricsSession != null) return; // Stream already running

    try {
      onProgress?.call("Detecting Remote OS...", 0.1);
      // Determine OS and architecture
      String detectedOs = "linux";
      String archString = "x86_64";
      String binaryExtension = "";

      // Avoids shell-specific chained commands, like ';' vs '&'
      final osSession = await client!.execute("uname -s");
      final osOutput = await osSession.stdout.cast<List<int>>().transform(utf8.decoder).join();
      final osName = osOutput.trim().toLowerCase();

      if (osName.contains("linux")) {
        detectedOs = "linux";
        final archOut = (await runCommand("uname -m")).trim().toLowerCase();
        archString = (archOut.contains("aarch64") || archOut.contains("arm")) ? "aarch64" : "x86_64";
      } else if (osName.contains("darwin")) {
        detectedOs = "macos";
        final archOut = (await runCommand("uname -m")).trim().toLowerCase();
        archString = (archOut.contains("arm64") || archOut.contains("aarch64") || archOut.contains("arm")) ? "aarch64" : "x86_64";
      } else {
        // If `uname -s` fails or is unrecognized, it's a Windows machine
        detectedOs = "windows";
        binaryExtension = ".exe";
        // Windows CMD uses %PROCESSOR_ARCHITECTURE%,
        // PowerShell uses $env:PROCESSOR_ARCHITECTURE
        // Sending a generic check that usually captures AMD64 or ARM64
        final archSession = await client!.execute("echo %PROCESSOR_ARCHITECTURE%");
        final archOut = await archSession.stdout.cast<List<int>>().transform(utf8.decoder).join();

        archString = archOut.toLowerCase().contains("arm") ? "aarch64" : "x86_64";
      }

      osType = detectedOs;

      // Map to the exact binary name in your Flutter assets folder
      final assetPath = 'assets/bin/metrics-$detectedOs-$archString$binaryExtension';
      final remotePath = '.syne_metrics$binaryExtension';

      // Load from Flutter assets
      onProgress?.call("Loading internal binary...", 0.3);
      final binaryData = await rootBundle.load(assetPath);
      final binaryBytes = binaryData.buffer.asUint8List();
      final localSize = binaryBytes.length;

      bool needsUpload = true;
      try {
        // Fetch remote file metadata safely via SFTP
        final remoteStat = await sftp!.stat(remotePath);
        if (remoteStat.size == localSize) {
          // Binary exists and sizes match, skip upload
          needsUpload = false;
        }
      } catch (_) {
        // Binary doesn't exist on the remote server
      }

      onProgress?.call("Cleaning previous sessions...", 0.4);
      // If Linux is currently executing the binary, sftp will throw a `file busy` error
      if (detectedOs != "windows") {
        await runCommand("pkill -f $remotePath");
      } else {
        await runCommand("taskkill /F /IM $remotePath");
      }

      if (needsUpload) {
        onProgress?.call("Deploying metrics agent...", 0.7);
        final remoteFile = await sftp!.open(
          remotePath,
          mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate,
        );

        await remoteFile.writeBytes(binaryBytes);
        await remoteFile.close();

        // Make executable (Unix only)
        if (detectedOs != "windows") {
          await runCommand("chmod +x $remotePath");
        }
      }

      // Execute using the correct OS path format
      onProgress?.call("Initializing metrics stream...", 0.9);
      final execCommand = detectedOs == "windows" ? ".\\$remotePath" : "./$remotePath";
      _metricsSession = await client!.execute(execCommand);

      // Parse the length-prefixed MessagePack stream
      final List<int> buffer = [];
      int? expectedPayloadLength;

      // The exact ascii byte values for "S", "Y", "N", "E"
      final markerBytes = [0x53, 0x59, 0x4E, 0x45];

      _metricsSession!.stdout.listen((List<int> chunk) {
        buffer.addAll(chunk);

        while (true) {
          if (expectedPayloadLength == null) {
            int magicIndex = -1;

            // At least 8 bytes (4 marker + 4 header) to proceed safely
            for (int i = 0; i <= buffer.length - 8; i++) {
              if (buffer[i] == markerBytes[0] &&
                buffer[i + 1] == markerBytes[1] &&
                buffer[i + 2] == markerBytes[2] &&
                buffer[i + 3] == markerBytes[3]) {
                magicIndex = i;
                break;
              }
            }

            if (magicIndex != -1) {
              buffer.removeRange(0, magicIndex);
              final headerBytes = Uint8List.fromList(buffer.sublist(4, 8));
              expectedPayloadLength = ByteData.sublistView(headerBytes).getUint32(0, Endian.big);
              buffer.removeRange(0, 8);
            } else {
              break;
            }
          }

          if (expectedPayloadLength != null && buffer.length >= expectedPayloadLength!) {
            final payload = buffer.sublist(0, expectedPayloadLength!);
            buffer.removeRange(0, expectedPayloadLength!);

            try {
              final Uint8List payloadBytes = Uint8List.fromList(payload);
              final dynamic decoded = deserialize(payloadBytes);

              if (decoded is Map) {
                final Map<String, dynamic> metricsMap = Map<String, dynamic>.from(
                  decoded.map((k, v) => MapEntry(k.toString(), v))
                );
                _metricsController.add(metricsMap);
              } else {
                throw Exception("MsgPack Decode Error");
              }
            } catch (e) {
              throw Exception("MsgPack Decode Error: $e");
            }
            expectedPayloadLength = null;
          } else {
            break;
          }
        }
      }, onDone: () {
        _metricsSession = null;
      });

    } catch (e) {
      throw Exception("Metrics Agent Deployment Failed: $e");
    }
  }
}

