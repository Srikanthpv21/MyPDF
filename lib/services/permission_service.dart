import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

class PermissionService {
  PermissionService._();
  static final PermissionService instance = PermissionService._();

  int? _cachedSdkInt;

  Future<int> _getAndroidSdkInt() async {
    if (_cachedSdkInt != null) return _cachedSdkInt!;
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    _cachedSdkInt = androidInfo.version.sdkInt;
    return _cachedSdkInt!;
  }

  /// Check whether the app currently has permission to access PDF files on device.
  Future<bool> hasStoragePermission() async {
    if (kIsWeb) return true;

    if (Platform.isAndroid) {
      try {
        final sdkInt = await _getAndroidSdkInt();

        if (sdkInt >= 30) {
          final isManageGranted = await Permission.manageExternalStorage.isGranted;
          if (isManageGranted) return true;

          final isStorageGranted = await Permission.storage.isGranted;
          return isStorageGranted;
        } else {
          return await Permission.storage.isGranted;
        }
      } catch (e) {
        debugPrint('Error checking storage permission: $e');
        return false;
      }
    } else if (Platform.isIOS) {
      return true;
    }

    return true;
  }

  /// Request access to storage / PDF files from the operating system.
  Future<PermissionStatus> requestStoragePermission() async {
    if (kIsWeb) return PermissionStatus.granted;

    if (Platform.isAndroid) {
      try {
        final sdkInt = await _getAndroidSdkInt();

        if (sdkInt >= 30) {
          // On Android 11+ (API 30+), try manageExternalStorage for complete file access
          final manageStatus = await Permission.manageExternalStorage.request();
          if (manageStatus.isGranted) {
            return manageStatus;
          }

          // Fallback to storage permission
          final storageStatus = await Permission.storage.request();
          if (storageStatus.isGranted) {
            return storageStatus;
          }

          return manageStatus;
        } else {
          return await Permission.storage.request();
        }
      } catch (e) {
        debugPrint('Error requesting storage permission: $e');
        return PermissionStatus.denied;
      }
    }

    return PermissionStatus.granted;
  }

  /// Open application system settings page.
  Future<bool> openSettings() async {
    return await openAppSettings();
  }
}
