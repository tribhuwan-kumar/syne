import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import 'package:dartssh2/dartssh2.dart';

import 'package:syne/service/ssh_service.dart';

class TerminalScreen extends StatefulWidget {
  final SSHService ssh;

  const TerminalScreen({super.key, required this.ssh});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final terminal = Terminal(maxLines: 10000);
  final FocusNode _terminalFocusNode = FocusNode();
  SSHSession? _session;

  // Sticky Modifier States
  bool _isCtrlActive = false;
  bool _isAltActive = false;

  @override
  void initState() {
    super.initState();
    startTerminal();
  }

  @override
  void dispose() {
    _terminalFocusNode.dispose();
    super.dispose();
  }

  Future<void> startTerminal() async {
    final client = widget.ssh.client;
    if (client == null) return;

    final session = await client.shell(
      pty: SSHPtyConfig(width: 90, height: 30),
    );

    if (!mounted) return;
    setState(() => _session = session);

    // Read from SSH -> Write to Terminal
    session.stdout.cast<List<int>>().transform(utf8.decoder).listen((data) {
      terminal.write(data);
    });

    session.stderr.cast<List<int>>().transform(utf8.decoder).listen((data) {
      terminal.write(data);
    });

    // Read from Terminal -> Intercept Modifiers -> Write to SSH
    terminal.onOutput = (String data) {
      if (data.isEmpty) return;

      List<int> bytes = utf8.encode(data);

      // Apply Sticky Modifiers if a single standard character is typed
      if (bytes.length == 1) {
        int charCode = bytes[0];

        if (_isCtrlActive) {
          if (charCode >= 97 && charCode <= 122) {
            // Lowercase a-z -> 1-26
            charCode = charCode - 96;
          } else if (charCode >= 65 && charCode <= 90) {
            // Uppercase A-Z -> 1-26
            charCode = charCode - 64;
          } else if (charCode == 91) {
            // Ctrl + [ -> Escape
            charCode = 27;
          } else if (charCode == 99) {
            // Ctrl + C 
            charCode = 3;
          }
          
          bytes = [charCode];
          setState(() => _isCtrlActive = false);
        } else if (_isAltActive) {
          // Alt/Meta prefix is an Escape character followed by the key
          bytes = [27, charCode];
          setState(() => _isAltActive = false);
        }
      }

      _session?.stdin.add(Uint8List.fromList(bytes));
    };
  }

  // Sends specialized xterm.dart sequences directly (Arrows, Tab, Esc)
  void _sendExtraKey(TerminalKey key) {
    terminal.keyInput(key);
    // Ensure the keyboard stays open when interacting with the extra keys row
    if (!_terminalFocusNode.hasFocus) {
      _terminalFocusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Terminal", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: TerminalView(
                terminal,
                focusNode: _terminalFocusNode,
                autofocus: true,
                keyboardType: TextInputType.visiblePassword,
                textStyle: const TerminalStyle(
                  fontFamily: 'FiraCodeNerd',
                  fontSize: 13,
                  fontFamilyFallback: ['monospace'],
                ),
              ),
            ),

            // Termux-style Extra Keys Row
            Container(
              color: const Color(0xFF1C1C1E),
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    _buildTextButton("ESC", () => _sendExtraKey(TerminalKey.escape)),
                    _buildTextButton("TAB", () => _sendExtraKey(TerminalKey.tab)),
                    
                    _buildTextButton(
                      "CTRL",
                      () => setState(() => _isCtrlActive = !_isCtrlActive),
                      isActive: _isCtrlActive,
                    ),
                    _buildTextButton(
                      "ALT",
                      () => setState(() => _isAltActive = !_isAltActive),
                      isActive: _isAltActive,
                    ),
                    
                    const SizedBox(width: 12),
                    
                    _buildIconButton(Icons.arrow_upward_rounded, () => _sendExtraKey(TerminalKey.arrowUp)),
                    _buildIconButton(Icons.arrow_downward_rounded, () => _sendExtraKey(TerminalKey.arrowDown)),
                    _buildIconButton(Icons.arrow_back_rounded, () => _sendExtraKey(TerminalKey.arrowLeft)),
                    _buildIconButton(Icons.arrow_forward_rounded, () => _sendExtraKey(TerminalKey.arrowRight)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  ButtonStyle _buttonStyle({bool isActive = false}) {
    return OutlinedButton.styleFrom(
      backgroundColor: isActive ? const Color(0xFFA2D9A1) : Colors.transparent,
      foregroundColor: isActive ? Colors.black : const Color(0xFFA2D9A1),
      side: BorderSide(color: isActive ? const Color(0xFFA2D9A1) : const Color(0xFF3A3A3C)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  Widget _buildTextButton(String label, VoidCallback onPressed, {bool isActive = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: OutlinedButton(
        style: _buttonStyle(isActive: isActive),
        onPressed: onPressed,
        child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildIconButton(IconData icon, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: OutlinedButton(
        style: _buttonStyle(),
        onPressed: onPressed,
        child: Icon(icon, size: 16),
      ),
    );
  }
}

