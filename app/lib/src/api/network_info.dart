// ICD360SVPN — lib/src/api/network_info.dart
//
// Detect connection type (WiFi, Ethernet, Cellular) using
// connectivity_plus. Used by the speed test to tag results
// with the network type.

import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkInfo {
  NetworkInfo._();
  static final NetworkInfo instance = NetworkInfo._();

  final Connectivity _connectivity = Connectivity();

  Future<String> detectType() async {
    try {
      final results = await _connectivity.checkConnectivity();
      if (results.contains(ConnectivityResult.ethernet)) return 'Ethernet';
      if (results.contains(ConnectivityResult.wifi)) return 'WiFi';
      if (results.contains(ConnectivityResult.mobile)) return 'Cellular';
      if (results.contains(ConnectivityResult.vpn)) return 'VPN';
      if (results.contains(ConnectivityResult.bluetooth)) return 'Bluetooth';
      if (results.contains(ConnectivityResult.none)) return 'Offline';
      return 'Unknown';
    } catch (_) {
      return 'Unknown';
    }
  }
}
