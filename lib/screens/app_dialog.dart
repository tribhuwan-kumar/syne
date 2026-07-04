import 'dart:ui';
import 'package:flutter/material.dart';

enum DialogType { success, error, warning, info, loading }

class AppDialog {
  static Future<void> show({
    required BuildContext context,
    required String title,
    String? message,
    ValueNotifier<String>? dynamicMessage,
    ValueNotifier<double>? progressNotifier,
    DialogType type = DialogType.info,
    List<Widget>? actions,
    bool barrierDismissible = true,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible:
          barrierDismissible, // This disables the multiple taps issue
      barrierLabel: "",
      barrierColor: Colors.black.withValues(alpha: 0.4),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, _, _) {
        return PopScope(
          canPop: barrierDismissible,
          child: _DialogUI(
            title: title,
            message: message,
            dynamicMessage: dynamicMessage,
            progressNotifier: progressNotifier,
            type: type,
            actions: actions,
          ),
        );
      },

      transitionBuilder: (_, anim, _, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
        );

        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.1),
              end: Offset.zero,
            ).animate(curved),
            child: ScaleTransition(
              scale: Tween(begin: 0.95, end: 1.0).animate(curved),
              child: child,
            ),
          ),
        );
      },
    );
  }

  static Widget action(
    String text,
    VoidCallback onTap, {
    Color? color,
    bool isPrimary = false,
  }) {
    return Expanded(
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: color ?? Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: isPrimary ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _DialogUI extends StatelessWidget {
  final String title;
  final String? message;
  final ValueNotifier<String>? dynamicMessage;
  final ValueNotifier<double>? progressNotifier;
  final DialogType type;
  final List<Widget>? actions;

  const _DialogUI({
    required this.title,
    this.message,
    this.dynamicMessage,
    this.progressNotifier,
    required this.type,
    this.actions,
  });

  IconData _getIcon() {
    switch (type) {
      case DialogType.success:
        return Icons.check_circle_rounded;
      case DialogType.error:
        return Icons.cancel_rounded;
      case DialogType.warning:
        return Icons.warning_amber_rounded;
      case DialogType.info:
        return Icons.info_rounded;
      case DialogType.loading:
        return Icons.cloud_sync_rounded;
    }
  }

  Color _getColor() {
    switch (type) {
      case DialogType.success:
        return Colors.green;
      case DialogType.error:
        return Colors.red;
      case DialogType.warning:
        return Colors.orange;
      case DialogType.info:
      case DialogType.loading:
        return const Color(0xFFA2D9A1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor();

    return SafeArea(
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                width: 320,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 22,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E).withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    /// ICON
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: type == DialogType.loading
                        ? SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(color: color, strokeWidth: 3),
                        )
                        : Icon(_getIcon(), color: color, size: 32),
                    ),

                    const SizedBox(height: 16),

                    /// TITLE
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 10),

                    /// DYNAMIC OR STATIC MESSAGE
                    if (dynamicMessage != null)
                      ValueListenableBuilder<String>(
                        valueListenable: dynamicMessage!,
                        builder: (context, msg, _) {
                          return Text(
                            msg,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              height: 1.4,
                            ),
                          );
                        },
                      )
                    else if (message != null)
                      Text(
                        message!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),

                    /// PROGRESS BAR
                    if (progressNotifier != null && type == DialogType.loading) ...[
                      const SizedBox(height: 20),
                      ValueListenableBuilder<double>(
                        valueListenable: progressNotifier!,
                        builder: (context, progress, _) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor: Colors.white12,
                              color: color,
                              minHeight: 6,
                            ),
                          );
                        },
                      ),
                    ],

                    if (actions != null) ...[
                      const SizedBox(height: 20),

                      /// Divider
                      Container(
                        height: 1,
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                      const SizedBox(height: 10),

                      /// ACTIONS
                      Row(children: actions!),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

