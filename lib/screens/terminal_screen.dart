import 'dart:convert';
import 'package:xterm/xterm.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
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
  TextInputConnection? _textInputConnection;

  // Sticky Modifier States
  bool _isCtrlActive = false;
  bool _isAltActive = false;
  bool _isShiftActive = false; // Added Shift support

  @override
  void initState() {
    super.initState();
    startTerminal();
    _terminalFocusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _closeTextInputConnection();
    _terminalFocusNode.removeListener(_handleFocusChange);
    _terminalFocusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (_terminalFocusNode.hasFocus) {
      _openTextInputConnection();
    } else {
      _closeTextInputConnection();
    }
  }

  void _openTextInputConnection() {
    if (_textInputConnection != null && _textInputConnection!.attached) return;
    
    _textInputConnection = TextInput.attach(
      _TerminalInputClient(onCharacter: _handleOnScreenKeyEvent),
      const TextInputConfiguration(
        enableDeltaModel: false,
        inputType: TextInputType.text,
        inputAction: TextInputAction.none,
      ),
    );
    _textInputConnection?.show();
  }

  void _closeTextInputConnection() {
    _textInputConnection?.close();
    _textInputConnection = null;
  }

  Future<void> startTerminal() async {
    final client = widget.ssh.client;

    final session = await client?.shell(
      pty: SSHPtyConfig(
        width: 90,
        height: 30,
      ),
    );

    if (session == null) return;
    setState(() {
      _session = session;
    });

    session.stdout.listen((data) {
      terminal.write(utf8.decode(data, allowMalformed: true));
    });

    session.stderr.listen((data) {
      terminal.write(utf8.decode(data, allowMalformed: true));
    });

    terminal.onOutput = (data) {
      _session?.stdin.add(Uint8List.fromList(data.codeUnits));
    };
  }

  void _sendRawSequence(List<int> bytes) {
    _session?.stdin.add(Uint8List.fromList(bytes));
    _terminalFocusNode.requestFocus();
    _openTextInputConnection(); 
  }

  void _handleOnScreenKeyEvent(String character) {
    if (character.isEmpty) return;
    
    // Apply shift transformation to string data before pulling character codes
    if (_isShiftActive) {
      character = character.toUpperCase();
    }

    int charCode = character.codeUnitAt(0);
    List<int> bytesToTransmit = [];

    if (_isCtrlActive) {
      if (charCode >= 97 && charCode <= 122) {
        bytesToTransmit.add(charCode - 96); // Lowercase Ctrl bitmask
      } else if (charCode >= 65 && charCode <= 90) {
        bytesToTransmit.add(charCode - 64); // Uppercase Ctrl bitmask
      } else {
        bytesToTransmit.add(charCode);
      }
      
      // Auto-execute combo command sequences instantly via terminal-break bypass codes
      bytesToTransmit.addAll([13, 10]); 
    } else if (_isAltActive) {
      bytesToTransmit.addAll([27, charCode]);
    } else {
      bytesToTransmit.add(charCode);
    }

    // Toggle states back off automatically
    if (_isCtrlActive || _isAltActive || _isShiftActive) {
      setState(() {
        _isCtrlActive = false;
        _isAltActive = false;
        _isShiftActive = false;
      });
    }

    if (bytesToTransmit.isNotEmpty) {
      _sendRawSequence(bytesToTransmit);
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
              child: GestureDetector(
                onTap: () {
                  _terminalFocusNode.requestFocus();
                  _openTextInputConnection();
                },
                child: TerminalView(
                  terminal,
                  focusNode: _terminalFocusNode,
                  backgroundOpacity: 1,
                  textStyle: const TerminalStyle(
                    fontFamily: 'FiraCodeNerd',
                    fontSize: 13,
                    fontFamilyFallback: ['FiraCodeNerd', 'monospace'],
                  ),
                ),
              ),
            ),
            
            // Fixed Soft Keyboard Control Deck - Moves perfectly with typing line updates
            Container(
              color: const Color(0xFF1C1C1E),
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildTextButton("ESC", () => _sendRawSequence([27])),
                    _buildTextButton("TAB", () => _sendRawSequence([9])),
                    
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
                    _buildTextButton(
                      "SHIFT", 
                      () => setState(() => _isShiftActive = !_isShiftActive),
                      isActive: _isShiftActive,
                    ),
                    
                    const SizedBox(width: 12),
                    
                    _buildIconButton(Icons.arrow_upward_rounded, () => _sendRawSequence([27, 91, 65])),
                    _buildIconButton(Icons.arrow_downward_rounded, () => _sendRawSequence([27, 91, 66])),
                    _buildIconButton(Icons.arrow_back_rounded, () => _sendRawSequence([27, 91, 68])),
                    _buildIconButton(Icons.arrow_forward_rounded, () => _sendRawSequence([27, 91, 67])),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    );
  }

  Widget _buildTextButton(String label, VoidCallback onPressed, {bool isActive = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: OutlinedButton(
        style: _buttonStyle(isActive: isActive),
        onPressed: onPressed,
        child: Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildIconButton(IconData icon, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: OutlinedButton(
        style: _buttonStyle(),
        onPressed: onPressed,
        child: Icon(icon, size: 14),
      ),
    );
  }
}

/// Robust text pipeline implementation matching all modern Flutter SDK contract standards cleanly
class _TerminalInputClient with TextInputClient {
  final ValueChanged<String> onCharacter;

  _TerminalInputClient({required this.onCharacter});

  @override
  void updateEditingValue(TextEditingValue value) {
    if (value.text.isNotEmpty) {
      onCharacter(value.text);
      // Fixed type reference to match standard text configuration parameters cleanly
      TextInput.updateEditingValue(TextEditingValue.empty);
    }
  }

  @override
  TextEditingValue? get currentTextEditingValue => TextEditingValue.empty;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void performAction(TextInputAction action) {}

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}
  
  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}
  
  @override
  void showAutofitOptions() {}
  
  @override
  void connectionClosed() {}

  @override
  void showToolbar() {}

  @override
  void insertTextPlaceholder(Size size) {}

  @override
  void removeTextPlaceholder() {}

  @override
  void didChangeAreaSize(Size size) {}
}

