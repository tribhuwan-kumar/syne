import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syne/screens/app_dialog.dart';
import 'package:syne/service/ssh_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:syne/screens/image_viewer.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syne/screens/video_player_page.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:android_path_provider/android_path_provider.dart';

enum ClipboardAction { copy, cut, none }

class FileExplorer extends StatefulWidget {
  final SSHService ssh;
  final String startingPath;

  const FileExplorer({
    super.key,
    required this.ssh,
    required this.startingPath,
  });

  @override
  State<FileExplorer> createState() => _FileExplorerState();
}

class _FileExplorerState extends State<FileExplorer> {
  List<SftpName> files = [];
  late String currentPath;

  bool isLoading = true;
  double downloadProgress = 0;
  bool isUploading = false;
  bool isDialogOpen = false;
  bool _isExiting = false;
  bool isDownloadCancelled = false;
  bool isFileUploadCancelled = false;
	bool isCompressCancelled = false;

  final ScrollController _breadcrumbController = ScrollController();

  // Selection & Clipboard State
  Set<SftpName> selectedFiles = {};
  List<String> clipboardPaths = [];
  ClipboardAction currentClipboardAction = ClipboardAction.none;

  bool get isSelectionMode => selectedFiles.isNotEmpty;
  bool get isWindows => widget.ssh.osType.toLowerCase() == 'windows';

  static const imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
    '.tiff',
    '.ico',
  };
  static const videoExtensions = {
    '.mp4',
    '.mkv',
    '.mov',
    '.webm',
    '.avi',
    '.flv',
    '.wmv',
    '.m4v',
  };
  static const audioExtensions = {
    '.mp3',
    '.wav',
    '.flac',
    '.ogg',
    '.m4a',
    '.aac',
    '.wma',
    '.opus',
  };
  static const docExtensions = {
    '.pdf',
    '.txt',
    '.doc',
    '.docx',
    '.xls',
    '.xlsx',
    '.ppt',
    '.pptx',
    '.md',
    '.json',
    '.csv',
    '.yaml',
  };
  static const execExtensions = {
    '.sh',
    '.bash',
    '.exe',
    '.bat',
    '.msi',
    '.bin',
    '.app',
    '.deb',
    '.rpm',
  };

  @override
  void initState() {
    super.initState();
    currentPath = widget.startingPath;
    loadFiles(currentPath);
  }

  @override
  void dispose() {
    _breadcrumbController.dispose();
    super.dispose();
  }

  bool _isRoot(String path) {
    return path == "/" || (path.length <= 3 && path.endsWith(":/"));
  }

  String _getParentPath(String path) {
    if (_isRoot(path)) return path;
    final lastSlash = path.lastIndexOf("/");
    if (lastSlash <= 0) return "/";

    final parent = path.substring(0, lastSlash);
    if (parent.endsWith(":")) return "$parent/";
    return parent;
  }

  // Formatting size
  String _formatSize(int? bytes) {
    if (bytes == null) return "Unknown Size";
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(2)} KB";
    if (bytes < 1024 * 1024 * 1024) return "${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB";
    if (bytes < 1024 * 1024 * 1024 * 1024) return "${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB";
    return "${(bytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(2)} TB";
  }

  String _truncateMiddle(String text, {int maxLength = 35}) {
    if (text.length <= maxLength) return text;
    int half = (maxLength ~/ 2) - 2;
    return "${text.substring(0, half)}...${text.substring(text.length - half)}";
  }

  Future<void> loadFiles(String path) async {
    setState(() {
      isLoading = true;
      selectedFiles.clear();
    });

    try {
      final list = await widget.ssh.listDir(path);
      list.removeWhere((item) => item.filename == '.' || item.filename == '..');

      list.sort((a, b) {
        final aIsDir = isDirectory(a);
        final bIsDir = isDirectory(b);
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        return a.filename.compareTo(b.filename);
      });

      if (!mounted) return;
      setState(() {
        currentPath = path;
        files = list;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      AppDialog.show(
        type: DialogType.error,
        context: context,
        title: "Failed to load directory",
        message: e.toString().toLowerCase(),
        actions: [AppDialog.action("OK", () => Navigator.pop(context))],
      );
      await widget.ssh.reconnect();
    }
  }

  bool isDirectory(SftpName file) => file.longname.startsWith("d");

  String _getExtension(String filename) {
    final dotIndex = filename.lastIndexOf('.');
    if (dotIndex == -1) return '';
    return filename.substring(dotIndex).toLowerCase();
  }

  IconData getFileIcon(String name) {
    final ext = _getExtension(name);
    if (imageExtensions.contains(ext)) return Icons.image;
    if (videoExtensions.contains(ext)) return Icons.video_file;
    if (audioExtensions.contains(ext)) return Icons.audiotrack;
    if (docExtensions.contains(ext)) return Icons.description;
    if (execExtensions.contains(ext)) return Icons.terminal;
    return Icons.insert_drive_file;
  }

  Color getIconColor(String name) {
    final ext = _getExtension(name);
    if (imageExtensions.contains(ext)) return const Color(0xFF90CAF9);
    if (videoExtensions.contains(ext)) return const Color(0xFFCE93D8);
    if (audioExtensions.contains(ext)) return const Color(0xFFFFF59D);
    if (execExtensions.contains(ext)) return const Color(0xFFFFAB91);
    return const Color(0xFFA2D9A1);
  }

  Widget leadingWidget(SftpName file) {
    if (isDirectory(file)) {
      return const Icon(Icons.folder, size: 40, color: Color(0xFFA2D9A1));
    }
    return Icon(
      getFileIcon(file.filename),
      size: 35,
      color: getIconColor(file.filename),
    );
  }

  void toggleSelection(SftpName file) {
    setState(() {
      if (selectedFiles.contains(file)) {
        selectedFiles.remove(file);
      } else {
        selectedFiles.add(file);
      }
    });
  }

  void openItem(SftpName file) {
    final path = "$currentPath/${file.filename}";
    final ext = _getExtension(file.filename);

    if (isDirectory(file)) {
      loadFiles(path);
      return;
    }

    if (imageExtensions.contains(ext)) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ImageViewer(ssh: widget.ssh, path: path),
        ),
      );
      return;
    }

    if (videoExtensions.contains(ext)) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoPlayerPage(
            ssh: widget.ssh,
            remotePath: path,
            fileName: file.filename,
          ),
        ),
      );
      return;
    }
  }

  Future<void> _runLongCommand({
    required String title,
    required String filesListStr,
    required String command,
    bool enableBackground = true,
  }) async {
    bool runInBackground = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LinearProgressIndicator(color: Color(0xFFA2D9A1)),
            const SizedBox(height: 15),
            const Text(
              "Items:",
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 4),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                filesListStr,
                style: const TextStyle(
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (enableBackground)
            TextButton(
              onPressed: () {
                runInBackground = true;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("$title running in background...")),
                );
              },
              child: const Text(
                "Run in background",
                style: TextStyle(color: Colors.white54),
              ),
            ),
        ],
      ),
    );

    try {
      await widget.ssh.runCommand(command);
      if (!runInBackground && mounted) Navigator.pop(context);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$title completed.")));
      loadFiles(currentPath);
    } catch (e) {
      if (!runInBackground && mounted) Navigator.pop(context);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  void _showFileInfo(SftpName file) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: Text(
          "Details",
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Text(
            "Name: ${file.filename}\nType: ${isDirectory(file) ? "Folder" : "File"}\nSize: ${_formatSize(file.attr.size)}\n\nDetails:\n${file.longname}",
            style: const TextStyle(color: Colors.white70),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "Close",
              style: TextStyle(color: Color(0xFFA2D9A1)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _renameFile(SftpName file) async {
    final controller = TextEditingController(text: file.filename);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text("Rename", style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text(
              "Rename",
              style: TextStyle(color: Color(0xFFA2D9A1)),
            ),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != file.filename) {
      try {
        await widget.ssh.sftp!.rename(
          "$currentPath/${file.filename}",
          "$currentPath/$newName",
        );
        loadFiles(currentPath);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Rename failed: $e")));
      }
    }
  }

  Future<void> _createFile() async {
    final controller = TextEditingController();
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text("Create file...",
					style: TextStyle(
					color: Colors.white,
					fontSize: 20,
					fontWeight: FontWeight.bold
				)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "example.txt",
            hintStyle: TextStyle(color: Colors.white30),
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text(
              "Create",
              style: TextStyle(color: Color(0xFFA2D9A1)),
            ),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty) {
      try {
        final cmd = isWindows
            ? 'powershell -Command "New-Item -Path \'$currentPath/$newName\' -ItemType File"'
            : "touch '$currentPath/$newName'";
        await widget.ssh.runCommand(cmd);
        loadFiles(currentPath);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to create file: $e")));
      }
    }
  }

  Future<void> _deleteSelectedFiles() async {
    bool step1 =
			await showDialog(
				context: context,
				builder: (ctx) => AlertDialog(
					backgroundColor: const Color(0xFF1C1C1E),
					title: const Text(
						"Delete items?",
						style: TextStyle(color: Colors.white),
					),
					content: Text(
						"Are you sure you want to delete ${selectedFiles.length} item(s)?",
						style: const TextStyle(color: Colors.white70),
					),
					actions: [
						TextButton(
							onPressed: () => Navigator.pop(ctx, false),
							child: const Text(
								"Cancel",
								style: TextStyle(color: Colors.white54),
							),
						),
						TextButton(
							onPressed: () => Navigator.pop(ctx, true),
							child: const Text(
								"Yes, delete",
								style: TextStyle(color: Colors.redAccent),
							),
						),
					],
				),
			) ??
			false;

    if (!step1 || !mounted) return;

    bool step2 =
			await showDialog(
				context: context,
				builder: (ctx) => AlertDialog(
					backgroundColor: const Color(0xFF1C1C1E),
					title: const Text(
						"Final confirmation",
						style: TextStyle(color: Colors.redAccent),
					),
					content: const Text(
						"This action cannot be undone. Proceed?",
						style: TextStyle(color: Colors.white70),
					),
					actions: [
						TextButton(
							onPressed: () => Navigator.pop(ctx, false),
							child: const Text(
								"Cancel",
								style: TextStyle(color: Colors.white54),
							),
						),
						TextButton(
							onPressed: () => Navigator.pop(ctx, true),
							child: const Text(
								"Permanently delete",
								style: TextStyle(
									color: Colors.redAccent,
									fontWeight: FontWeight.bold,
								),
							),
						),
					],
				),
			) ??
			false;

    if (!step2 || !mounted) return;

    final names = selectedFiles.map((f) => f.filename).join(", ");
    final cmd = isWindows
        ? "powershell -Command \"Remove-Item -Path ${selectedFiles.map((f) => "'$currentPath/${f.filename}'").join(",")} -Force -Recurse\""
        : "cd '$currentPath' && rm -rf ${selectedFiles.map((f) => "'${f.filename}'").join(" ")}";

    await _runLongCommand(
      title: "Deleting files",
      filesListStr: names,
      command: cmd,
    );
  }

  void _handleClipboard(ClipboardAction action) {
    clipboardPaths = selectedFiles
        .map((f) => "$currentPath/${f.filename}")
        .toList();
    currentClipboardAction = action;
    setState(() => selectedFiles.clear());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "${clipboardPaths.length} item(s) ${action == ClipboardAction.copy ? 'copied' : 'cut'}. Navigate to destination and paste.",
        ),
      ),
    );
  }

  void _cancelClipboard() {
    setState(() {
      clipboardPaths.clear();
      currentClipboardAction = ClipboardAction.none;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Clipboard cleared.")));
  }

  Future<void> _pasteItems() async {
    if (clipboardPaths.isEmpty || currentClipboardAction == ClipboardAction.none) return;

    final names = clipboardPaths.map((p) => p.split('/').last).join(", ");
    final srcPathsWin = clipboardPaths.map((p) => "'$p'").join(",");
    final srcPathsUnix = clipboardPaths.map((p) => "'$p'").join(" ");

    String cmd = "";

    if (currentClipboardAction == ClipboardAction.copy) {
      cmd = isWindows
          ? "powershell -Command \"Copy-Item -Path $srcPathsWin -Destination '$currentPath' -Recurse\""
          : "cp -r $srcPathsUnix '$currentPath/'";
    } else {
      cmd = isWindows
          ? "powershell -Command \"Move-Item -Path $srcPathsWin -Destination '$currentPath'\""
          : "mv $srcPathsUnix '$currentPath/'";
    }

    await _runLongCommand(
      title: currentClipboardAction == ClipboardAction.copy
          ? "Copying files"
          : "Moving files",
      filesListStr: names,
      command: cmd,
    );

    if (currentClipboardAction == ClipboardAction.cut) {
      setState(() {
        clipboardPaths.clear();
        currentClipboardAction = ClipboardAction.none;
      });
    }
  }

  Future<void> _downloadSelected() async {
    if (selectedFiles.isEmpty) return;
    // If exactly one file (not a folder), download it directly without archiving
    if (selectedFiles.length == 1 && !isDirectory(selectedFiles.first)) {
      final file = selectedFiles.first;
      setState(() => selectedFiles.clear());
      await _executeDownload("$currentPath/${file.filename}", file.filename);
      return;
    }

    await _archiveAndDownload();
  }

	Future<void> _archiveAndDownload() async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final archiveExt = isWindows ? "zip" : "tar.gz";

    // Store to avoid os-specific temp directory permission issues
    final remoteArchivePath = isWindows
        ? "$currentPath\\syne-export_$timestamp.$archiveExt"
        : "$currentPath/syne-export_$timestamp.$archiveExt";
    final archiveName = "syne-export_$timestamp.$archiveExt";

    double compressProgress = 0.0;
    late StateSetter setDialogState;
    isCompressCancelled = false;
    SSHSession? compressSession;

    // Archiving dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            setDialogState = setState;
            return AlertDialog(
              backgroundColor: const Color(0xFF1C1C1E),
              title: const Text(
                "Compressing...",
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isWindows) ...[
                    const LinearProgressIndicator(color: Color(0xFFA2D9A1)),
                    const SizedBox(height: 15),
                    const Text(
                      "Archiving files for windows...",
                      style: TextStyle(color: Colors.white),
                    ),
                  ] else ...[
                    LinearProgressIndicator(
                      value: compressProgress,
                      color: const Color(0xFFA2D9A1),
                    ),
                    const SizedBox(height: 15),
                    Text(
                      "${(compressProgress * 100).toStringAsFixed(0)}%",
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    isCompressCancelled = true;
                    // Kill the remote 'tar' process
                    try { compressSession?.kill(SSHSignal.KILL); } catch (_) {}
                    if (Navigator.canPop(context)) Navigator.pop(context);
                  },
                  child: const Text(
                    "Cancel",
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    try {
      if (!isWindows) {
        final fileArgs = selectedFiles.map((f) => "'${f.filename}'").join(" ");

        // Count total files to calculate percentage
        final countCmd = "cd '$currentPath' && find $fileArgs -type f | wc -l";
        final countOut = await widget.ssh.runCommand(countCmd);
        final totalFiles = int.tryParse(countOut.trim()) ?? 1;

        // Run tar verbose and stream stdout
        final tarCmd = "cd '$currentPath' && tar -czvf '$remoteArchivePath' $fileArgs";
        compressSession = await widget.ssh.client!.execute(tarCmd);

        int processed = 0;
        compressSession.stdout.cast<List<int>>().transform(utf8.decoder).listen((data) {
          if (isCompressCancelled) return; // Stop processing if canceled
          final lines = data.split('\n').where((l) => l.trim().isNotEmpty).length;
          processed += lines;
          if (mounted) {
            setDialogState(() {
              compressProgress = (processed / totalFiles).clamp(0.0, 1.0).toDouble();
            });
          }
        });

        await compressSession.done; // Wait for compression to finish
      } else {
        // WINDOWS: zip compression
        final fileArgs = selectedFiles.map((f) => "'$currentPath\\${f.filename}'").join(",");
        final zipCmd = "powershell -Command \"Compress-Archive -Path $fileArgs -DestinationPath '$remoteArchivePath' -Force\"";
        await widget.ssh.runCommand(zipCmd);
      }

      // If user clicked `cancel` during the await phase, abort early
      if (isCompressCancelled) return;

      if (!mounted) return;
      Navigator.pop(context);															// Close compression dialog
      setState(() => selectedFiles.clear());

      // Trigger the actual sftp download
      await _executeDownload(remoteArchivePath, archiveName);

    } catch (e) {
      if (!mounted) return;
      // Only show the error dialog if it wasn't a deliberate cancellation/kill
      if (!isCompressCancelled) {
        Navigator.pop(context); // Close compression dialog
        AppDialog.show(
          type: DialogType.error,
          context: context,
          title: "Compression Failed",
          message: e.toString().toLowerCase(),
          actions: [AppDialog.action("OK", () => Navigator.pop(context))],
        );
      }
    } finally {
      // Cleanup remote archive regardless of success or failure
      try {
        final rmCmd = isWindows
            ? "powershell -Command \"Remove-Item -Path '$remoteArchivePath' -Force\""
            : "rm -f '$remoteArchivePath'";
        await widget.ssh.runCommand(rmCmd);
      } catch (_) {
        // Ignore silent cleanup errors
      }
    }
  }

  Future<bool> _requestStoragePermission() async {
    if (!Platform.isAndroid) return true;
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    // Android 10 (SDK 29) or lower requires explicit legacy storage permission
    if (androidInfo.version.sdkInt <= 29) {
      final status = await Permission.storage.request();
      return status.isGranted;
    }
    // Android 11+ (SDK 30+) allows apps to write files to the public
    // Downloads folder without requesting global storage permissions.
    return true;
  }

  Future<void> _executeDownload(String remotePath, String saveAsName) async {
    double progress = 0;
    late StateSetter setDialogState;
    isDownloadCancelled = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            setDialogState = setState;
            return AlertDialog(
              backgroundColor: const Color(0xFF1C1C1E),
              title: const Text(
                "Downloading...",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    value: progress,
                    color: const Color(0xFFA2D9A1),
                  ),
                  const SizedBox(height: 15),
                  Text(
                    "${(progress * 100).toStringAsFixed(0)}%",
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    isDownloadCancelled = true;
                    if (Navigator.canPop(context)) Navigator.pop(context);
                  },
                  child: const Text(
                    "Cancel",
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    try {
      bool hasPermission = await _requestStoragePermission();
      if (!hasPermission) {
        if (!mounted) return;
        AppDialog.show(
          type: DialogType.error,
          context: context,
          title: "Download failed:",
          message: "Please grant storage permission to continue.",
          actions: [
            AppDialog.action(
              "Grant now",
              () async => await Permission.storage.request(),
            ),
          ],
        );
        return;
      }
      Directory downloadsDir;
      if (Platform.isAndroid) {
        final String androidDownloadPath =
            await AndroidPathProvider.downloadsPath;
        downloadsDir = Directory(androidDownloadPath);
      } else {
        downloadsDir = await getApplicationDocumentsDirectory();
      }

      if (!await downloadsDir.exists()) await downloadsDir.create(recursive: true);

      String filePath = "${downloadsDir.path}/$saveAsName";
      if (await File(filePath).exists()) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        filePath = "${downloadsDir.path}/${timestamp}_$saveAsName";
      }

      await widget.ssh.downloadFile(
        remotePath: remotePath,
        localPath: filePath,
        onProgress: (p) {
          progress = p;
          if (mounted) setDialogState(() {});
        },
        isCancelled: () => isDownloadCancelled,
      );

      if (!mounted) return;
      if (Navigator.canPop(context)) Navigator.pop(context);

      if (isDownloadCancelled) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Download cancelled")));
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Downloaded to: $filePath")));
    } catch (e) {
      if (!mounted) return;
      if (Navigator.canPop(context)) Navigator.pop(context);
      final errorString = e.toString().replaceAll("Exception: ", "");
			debugPrint("ERROR STRING: $errorString");
			AppDialog.show(
				type: DialogType.error,
				context: context,
				title: "Download failed:",
        message: errorString,
				actions: [
					AppDialog.action("Ok", () => Navigator.pop(context)),
					AppDialog.action("Report on github", () async {
						final Uri url = Uri.parse('https://github.com/tribhuwan-kumar/syne/issues/new').replace(
              queryParameters: {
                'title': 'Download failed: ${errorString.split('\n').first}',
                'body': '### Error Details\n```\n$errorString\n```\n\n### Environment\n- Server: ${widget.ssh.osType.toString()}',
              },
            );
						if (await canLaunchUrl(url)) {
							await launchUrl(url, mode: LaunchMode.externalApplication);
						} else {
								// Fallback handle if it fails to open
								if (mounted) {
									ScaffoldMessenger.of(context).showSnackBar(
										const SnackBar(content: Text('Could not open gitHub link')),
									);
								}
							}
						},
					)
				],
			);
    }
  }

  Future<void> uploadFile() async {
    if (isUploading) return;
    isFileUploadCancelled = false;

    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );

      if (!mounted) return;
      if (result == null || result.files.isEmpty) return;

      await widget.ssh.reconnect();
      isUploading = true;
      isDialogOpen = true;

      final pickedFiles = result.files;
      double progress = 0;
      int lastUpdate = 0;
      int totalFiles = pickedFiles.length;
      int completedFiles = 0;

      late StateSetter setDialogState;

			if(!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setState) {
              setDialogState = setState;
              return AlertDialog(
                backgroundColor: const Color(0xFF1C1C1E),
                title: const Text(
                  "Uploading...",
                  style: TextStyle(color: Colors.white),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(
                      value: progress,
                      color: const Color(0xFFA2D9A1),
                    ),
                    const SizedBox(height: 15),
                    Text(
                      "${(progress * 100).toStringAsFixed(0)}%",
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      isFileUploadCancelled = true;
                      if (Navigator.canPop(context)) Navigator.pop(context);
                      isDialogOpen = false;
                    },
                    child: const Text(
                      "Cancel",
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                ],
              );
            },
          );
        },
      );

      await widget.ssh.createDirIfNotExists(currentPath);

      for (var picked in pickedFiles) {
        if (picked.path == null || isFileUploadCancelled) break;
        final file = File(picked.path!);
        final remotePath = "$currentPath/${picked.name}";

        await widget.ssh.uploadFile(
          localPath: file.path,
          remotePath: remotePath,
          onProgress: (p) {
            final now = DateTime.now().millisecondsSinceEpoch;
            if (now - lastUpdate > 100) {
              lastUpdate = now;
              progress = (completedFiles + p) / totalFiles;
              if (isDialogOpen && mounted) setDialogState(() {});
            }
          },
          isCancelled: () => isFileUploadCancelled,
        );

        completedFiles++;
        progress = completedFiles / totalFiles;
        if (isDialogOpen && mounted) setDialogState(() {});
      }

      if (!mounted) return;
      if (Navigator.canPop(context)) Navigator.pop(context);
      isDialogOpen = false;

      if (isFileUploadCancelled) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Upload cancelled")));
        return;
      }
      await loadFiles(currentPath);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("$completedFiles file(s) uploaded")),
      );
    } catch (e) {
      if (!mounted) return;
      if (Navigator.canPop(context)) Navigator.pop(context);
      isDialogOpen = false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Upload failed: $e")));
    } finally {
      isUploading = false;
    }
  }

  void openUploadMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SizedBox(
          height: 140,
          child: Column(
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 4,
                ),
                leading: const Icon(
                  Icons.upload_file,
                  color: Color(0xFFA2D9A1),
                ),
                title: const Text(
                  "Upload File",
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  if (Navigator.canPop(context)) Navigator.pop(context);
                  await Future.delayed(const Duration(milliseconds: 200));
                  if (!mounted) return;
                  uploadFile();
                },
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 4,
                ),
                leading: const Icon(Icons.note_add, color: Color(0xFFA2D9A1)),
                title: const Text(
                  "Create an empty file",
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  if (Navigator.canPop(context)) Navigator.pop(context);
                  await Future.delayed(const Duration(milliseconds: 200));
                  if (!mounted) return;
                  _createFile();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _breadcrumbNode(String label, String path, {required bool isLast}) {
    return Row(
      children: [
        InkWell(
          onTap: () {
            if (!isLast && !isLoading) {
              setState(() => selectedFiles.clear());
              loadFiles(path);
            }
          },
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Text(
              label,
              style: TextStyle(
                color: isLast ? const Color(0xFFA2D9A1) : Colors.white70,
                fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          ),
        ),
        if (!isLast)
          const Text(
            "/",
            style: TextStyle(color: Colors.white30, fontSize: 14),
          ),
      ],
    );
  }

  Widget _buildBreadcrumbs() {
    final nodes = <Widget>[];
    final startsWithSlash = currentPath.startsWith('/');
    final segments = currentPath.split('/').where((s) => s.isNotEmpty).toList();
    String tempPath = "";

    if (startsWithSlash) {
      nodes.add(_breadcrumbNode("root", "/", isLast: segments.isEmpty));
    }

    for (int i = 0; i < segments.length; i++) {
      String seg = segments[i];
      if (startsWithSlash) {
        tempPath = "$tempPath/$seg";
      } else {
        tempPath = i == 0 ? seg : "$tempPath/$seg";
        if (i == 0 && seg.endsWith(":")) tempPath = "$seg/";
      }
      nodes.add(
        _breadcrumbNode(seg, tempPath, isLast: i == segments.length - 1),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_breadcrumbController.hasClients) {
        _breadcrumbController.animateTo(
          _breadcrumbController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      }
    });

    return Container(
      width: double.infinity,
      color: const Color(0xFF121212),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: SingleChildScrollView(
        controller: _breadcrumbController,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(children: nodes),
      ),
    );
  }

  Widget deviceCard({required SftpName file}) {
    final isSelected = selectedFiles.contains(file);
    final fileSizeString = _formatSize(file.attr.size);

    var modifiedDateString = "Unknown Date";
    if (file.attr.modifyTime != null) {
      var modifiedDate = DateTime.fromMillisecondsSinceEpoch(
        file.attr.modifyTime! * 1000,
      );
      modifiedDateString =
          "${modifiedDate.year}-${modifiedDate.month.toString().padLeft(2, '0')}-${modifiedDate.day.toString().padLeft(2, '0')}";
    }

    return GestureDetector(
      onLongPress: () => toggleSelection(file),
      onTap: () {
        if (isSelectionMode) {
          toggleSelection(file);
          return;
        }
        openItem(file);
      },
      child: Container(
        color: isSelected
            ? const Color(0xFFA2D9A1).withValues(alpha: 0.15)
            : Colors.transparent,
        child: ListTile(
          leading: Stack(
            children: [
              leadingWidget(file),
              if (isSelected)
                const Positioned(
                  bottom: 0,
                  right: 0,
                  child: Icon(
                    Icons.check_circle,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
            ],
          ),
          title: Text(
            _truncateMiddle(file.filename),
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          subtitle: Text(
            isDirectory(file)
                ? modifiedDateString
                : "$fileSizeString | $modifiedDateString",
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    if (isSelectionMode) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => setState(() => selectedFiles.clear()),
        ),
        title: Text(
          "${selectedFiles.length} selected",
          style: const TextStyle(fontSize: 18),
        ),
        backgroundColor: const Color(0xFF1C1C1E),
        actions: [
          if (selectedFiles.length == 1) ...[
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: "Info",
              onPressed: () => _showFileInfo(selectedFiles.first),
            ),
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: "Rename",
              onPressed: () => _renameFile(selectedFiles.first),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: "Download",
            onPressed: _downloadSelected,
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: "Copy",
            onPressed: () => _handleClipboard(ClipboardAction.copy),
          ),
          IconButton(
            icon: const Icon(Icons.cut),
            tooltip: "Cut",
            onPressed: () => _handleClipboard(ClipboardAction.cut),
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.redAccent),
            tooltip: "Delete",
            onPressed: _deleteSelectedFiles,
          ),
        ],
      );
    }

    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () {
          if (isUploading) return;
          setState(() => _isExiting = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).pop();
          });
        },
      ),
      title: const Text("File Explorer"),
      backgroundColor: Colors.black,
      centerTitle: true,
      elevation: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: isUploading ? false : (_isExiting || _isRoot(currentPath)),
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (isUploading) return;
        if (isSelectionMode) {
          setState(() => selectedFiles.clear());
          return;
        }

        if (!_isRoot(currentPath)) {
          final parent = _getParentPath(currentPath);
          await loadFiles(parent);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,

        floatingActionButton: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (clipboardPaths.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16, right: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FloatingActionButton.extended(
                      heroTag: "btn_cancel_clip",
                      backgroundColor: const Color(0xFF3A3A3C),
                      icon: const Icon(Icons.close, color: Colors.white),
                      label: const Text(
                        "Cancel",
                        style: TextStyle(color: Colors.white),
                      ),
                      onPressed: _cancelClipboard,
                    ),
                    const SizedBox(width: 10),
                    FloatingActionButton.extended(
                      heroTag: "btn_paste",
                      backgroundColor: const Color(0xFFA2D9A1),
                      icon: const Icon(Icons.paste, color: Colors.black),
                      label: Text(
                        "Paste ${clipboardPaths.length}",
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: _pasteItems,
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 40, right: 20),
              child: SizedBox(
                width: 54,
                height: 54,
                child: FloatingActionButton(
                  heroTag: "btn_add",
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(50),
                  ),
                  onPressed: openUploadMenu,
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.add, color: Colors.black, size: 28),
                ),
              ),
            ),
          ],
        ),
        appBar: _buildAppBar(),
        body: Column(
          children: [
            _buildBreadcrumbs(),
            Expanded(
              child: isLoading
								? const Center(
										child: CircularProgressIndicator(
											color: Color(0xFFA2D9A1),
										),
									)
								: RefreshIndicator(
										color: Colors.black,
										backgroundColor: const Color(0xFFA2D9A1),
										onRefresh: () => loadFiles(currentPath),
										child: files.isEmpty
												? ListView(
														physics: const AlwaysScrollableScrollPhysics(),
														children: [
															SizedBox(
																height:
																		MediaQuery.of(context).size.height * 0.6,
																child: const Center(
																	child: Text(
																		"Empty directory",
																		style: TextStyle(color: Colors.white60),
																	),
																),
															),
														],
													)
												: ListView.builder(
														physics: const AlwaysScrollableScrollPhysics(),
														itemCount: files.length,
														itemBuilder: (context, index) =>
																deviceCard(file: files[index]),
													),
									),
            ),
          ],
        ),
      ),
    );
  }
}
