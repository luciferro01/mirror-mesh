import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';

class NetworkUtils {
  static final NetworkInfo _networkInfo = NetworkInfo();

  /// Gets the local IP address of the device
  static Future<String?> getLocalIPAddress() async {
    try {
      // Try to get WiFi IP first
      final wifiIP = await _networkInfo.getWifiIP();
      if (wifiIP != null && wifiIP.isNotEmpty) {
        return wifiIP;
      }

      // Fallback to network interfaces
      final interfaces = await NetworkInterface.list();
      for (final interface in interfaces) {
        if (interface.name.contains('en') ||
            interface.name.contains('eth') ||
            interface.name.contains('wlan')) {
          for (final address in interface.addresses) {
            if (address.type == InternetAddressType.IPv4 &&
                !address.isLoopback) {
              return address.address;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error getting local IP: $e');
    }
    return null;
  }

  /// Gets the WiFi name/SSID
  static Future<String?> getWifiName() async {
    try {
      return await _networkInfo.getWifiName();
    } catch (e) {
      debugPrint('Error getting WiFi name: $e');
      return null;
    }
  }

  /// Gets the WiFi BSSID
  static Future<String?> getWifiBSSID() async {
    try {
      return await _networkInfo.getWifiBSSID();
    } catch (e) {
      debugPrint('Error getting WiFi BSSID: $e');
      return null;
    }
  }

  /// Checks if the device is connected to WiFi
  static Future<bool> isConnectedToWifi() async {
    try {
      // Try multiple methods to detect WiFi connection
      final wifiName = await getWifiName();
      final wifiIP = await _networkInfo.getWifiIP();

      debugPrint('WiFi Detection - Name: $wifiName, IP: $wifiIP');

      // Check if we have WiFi name (excluding placeholder values)
      if (wifiName != null &&
          wifiName.isNotEmpty &&
          wifiName != '<unknown ssid>' &&
          wifiName != 'null' &&
          wifiName.toLowerCase() != 'unknown') {
        debugPrint('WiFi connected via name: $wifiName');
        return true;
      }

      // Check if we have WiFi IP
      if (wifiIP != null &&
          wifiIP.isNotEmpty &&
          wifiIP != '0.0.0.0' &&
          wifiIP != 'null' &&
          isValidIPAddress(wifiIP)) {
        debugPrint('WiFi connected via IP: $wifiIP');
        return true;
      }

      // Fallback: check network interfaces for active connections
      final interfaces = await NetworkInterface.list();
      for (final interface in interfaces) {
        // More comprehensive interface name checking
        final interfaceName = interface.name.toLowerCase();
        if (interfaceName.contains('en') || // macOS/iOS Ethernet/WiFi
            interfaceName.contains('wlan') || // Linux WiFi
            interfaceName.contains('wifi') || // Windows WiFi
            interfaceName.contains('wlp') || // Linux wireless
            interfaceName.contains('wlo')) {
          // Linux wireless

          for (final address in interface.addresses) {
            if (address.type == InternetAddressType.IPv4 &&
                !address.isLoopback &&
                address.address != '0.0.0.0' &&
                !address.address.startsWith('169.254.')) {
              // Exclude APIPA addresses
              debugPrint(
                'Network connected via interface ${interface.name}: ${address.address}',
              );
              return true;
            }
          }
        }
      }

      // Additional check: if we have any local IP, we're likely connected
      final localIP = await getLocalIPAddress();
      if (localIP != null &&
          localIP.isNotEmpty &&
          localIP != '0.0.0.0' &&
          !localIP.startsWith('169.254.')) {
        debugPrint('Network connected via local IP: $localIP');
        return true;
      }

      debugPrint('No network connection detected');
      return false;
    } catch (e) {
      debugPrint('Error checking WiFi connection: $e');
      // If we can get local IP, assume we're connected
      final localIP = await getLocalIPAddress();
      final isConnected = localIP != null && localIP.isNotEmpty;
      debugPrint('Fallback connection check: $isConnected (IP: $localIP)');
      return isConnected;
    }
  }

  /// Validates if an IP address is valid
  static bool isValidIPAddress(String ip) {
    final ipRegex = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');
    if (!ipRegex.hasMatch(ip)) return false;

    final parts = ip.split('.');
    return parts.every((part) {
      final num = int.tryParse(part);
      return num != null && num >= 0 && num <= 255;
    });
  }

  /// Checks if a port is available on the local machine
  static Future<bool> isPortAvailable(int port) async {
    try {
      final socket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      await socket.close();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Finds an available port within a range
  static Future<int?> findAvailablePort({
    int start = 3000,
    int end = 3100,
  }) async {
    for (int port = start; port <= end; port++) {
      if (await isPortAvailable(port)) {
        return port;
      }
    }
    return null;
  }

  /// Gets network information summary
  static Future<DeviceNetworkInfo> getNetworkInfo() async {
    final ipAddress = await getLocalIPAddress();
    final wifiName = await getWifiName();
    final wifiBSSID = await getWifiBSSID();
    final isWifiConnected = await isConnectedToWifi();

    return DeviceNetworkInfo(
      ipAddress: ipAddress,
      wifiName: wifiName,
      wifiBSSID: wifiBSSID,
      isWifiConnected: isWifiConnected,
    );
  }
}

class DeviceNetworkInfo {
  final String? ipAddress;
  final String? wifiName;
  final String? wifiBSSID;
  final bool isWifiConnected;

  DeviceNetworkInfo({
    this.ipAddress,
    this.wifiName,
    this.wifiBSSID,
    this.isWifiConnected = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'ipAddress': ipAddress,
      'wifiName': wifiName,
      'wifiBSSID': wifiBSSID,
      'isWifiConnected': isWifiConnected,
    };
  }

  @override
  String toString() {
    return 'DeviceNetworkInfo(ipAddress: $ipAddress, wifiName: $wifiName, wifiBSSID: $wifiBSSID, isWifiConnected: $isWifiConnected)';
  }
}
