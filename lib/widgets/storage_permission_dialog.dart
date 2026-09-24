import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/permission_service.dart';
import '../theme/app_theme.dart';

enum StoragePermissionDialogResult {
  granted,
  pickFile,
  dismissed,
}

class StoragePermissionDialog extends StatefulWidget {
  const StoragePermissionDialog({super.key});

  static Future<StoragePermissionDialogResult?> show(BuildContext context) {
    return showDialog<StoragePermissionDialogResult>(
      context: context,
      barrierDismissible: true,
      builder: (context) => const StoragePermissionDialog(),
    );
  }

  @override
  State<StoragePermissionDialog> createState() => _StoragePermissionDialogState();
}

class _StoragePermissionDialogState extends State<StoragePermissionDialog> {
  bool _isRequesting = false;
  bool _isPermanentlyDenied = false;
  String? _statusMessage;

  Future<void> _handleGrantPermission() async {
    setState(() {
      _isRequesting = true;
      _statusMessage = null;
    });

    try {
      final status = await PermissionService.instance.requestStoragePermission();
      final hasPerm = await PermissionService.instance.hasStoragePermission();

      if (!mounted) return;

      if (status.isGranted || hasPerm) {
        Navigator.of(context).pop(StoragePermissionDialogResult.granted);
      } else if (status.isPermanentlyDenied || status.isRestricted) {
        setState(() {
          _isPermanentlyDenied = true;
          _statusMessage =
              'Access was permanently denied. Please enable "Allow access to manage all files" or Storage permission in System Settings.';
        });
      } else {
        setState(() {
          _statusMessage =
              'Permission was not granted. Tap "Grant Access" to retry or pick a file directly.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Unable to request permission: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isRequesting = false);
      }
    }
  }

  Future<void> _handleOpenSettings() async {
    final alreadyGranted = await PermissionService.instance.hasStoragePermission();
    if (mounted && alreadyGranted) {
      Navigator.of(context).pop(StoragePermissionDialogResult.granted);
      return;
    }
    await PermissionService.instance.openSettings();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final dialogBg = isDark ? const Color(0xFF151C2C) : Colors.white;
    final cardBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtextColor = isDark ? Colors.white70 : const Color(0xFF475569);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        decoration: BoxDecoration(
          color: dialogBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: borderColor, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Icon with Glow
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [AppTheme.primary, AppTheme.accent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withValues(alpha: 0.4),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.folder_open_rounded,
                    color: Colors.white,
                    size: 42,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Title
              Text(
                'Access Device PDF Files',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                  color: textColor,
                ),
              ),

              const SizedBox(height: 10),

              // Subtitle
              Text(
                'MYPDF needs your permission to read PDF documents stored on your device so you can view, search, and manage your books and files.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: subtextColor,
                ),
              ),

              const SizedBox(height: 20),

              // Benefit list
              _buildFeatureItem(
                icon: Icons.snippet_folder_rounded,
                title: 'Open Local PDFs',
                description: 'Browse documents from Downloads, internal storage & SD card.',
                isDark: isDark,
                cardBg: cardBg,
                borderColor: borderColor,
              ),

              const SizedBox(height: 10),

              _buildFeatureItem(
                icon: Icons.bolt_rounded,
                title: 'Fast Offline Reading',
                description: 'Instant loading, multi-page thumbnails, search & bookmarks.',
                isDark: isDark,
                cardBg: cardBg,
                borderColor: borderColor,
              ),

              const SizedBox(height: 10),

              _buildFeatureItem(
                icon: Icons.shield_outlined,
                title: '100% Private & Secure',
                description: 'Your documents never leave your device. No cloud uploads.',
                isDark: isDark,
                cardBg: cardBg,
                borderColor: borderColor,
              ),

              if (_statusMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _isPermanentlyDenied
                        ? Colors.redAccent.withValues(alpha: 0.15)
                        : Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isPermanentlyDenied
                          ? Colors.redAccent.withValues(alpha: 0.4)
                          : Colors.amber.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isPermanentlyDenied ? Icons.error_outline : Icons.info_outline,
                        color: _isPermanentlyDenied ? Colors.redAccent : Colors.amber,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _statusMessage!,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.3,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Primary Action Button
              ElevatedButton(
                onPressed: _isRequesting
                    ? null
                    : (_isPermanentlyDenied ? _handleOpenSettings : _handleGrantPermission),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isRequesting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isPermanentlyDenied
                                ? Icons.settings_rounded
                                : Icons.check_circle_outline_rounded,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isPermanentlyDenied ? 'Open Settings' : 'Allow Access',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
              ),

              const SizedBox(height: 10),

              // Secondary Action: Pick file directly
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop(StoragePermissionDialogResult.pickFile);
                },
                icon: const Icon(Icons.file_open_outlined, size: 18),
                label: const Text('Pick PDF File Directly'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? Colors.white : const Color(0xFF0F172A),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(color: borderColor),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),

              const SizedBox(height: 6),

              // Tertiary Action: Dismiss / View sample PDFs
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(StoragePermissionDialogResult.dismissed);
                },
                style: TextButton.styleFrom(
                  foregroundColor: subtextColor,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                child: const Text(
                  'Not Now / Cancel',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
    required String description,
    required bool isDark,
    required Color cardBg,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 20,
              color: AppTheme.primaryLight,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: isDark ? Colors.white60 : const Color(0xFF64748B),
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
