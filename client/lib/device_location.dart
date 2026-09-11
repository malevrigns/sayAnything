import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class DeviceLocation {
  final double latitude, longitude;
  const DeviceLocation(this.latitude, this.longitude);
}

class DeviceLocationError implements Exception {
  final String message;
  final bool openSettings;
  const DeviceLocationError(this.message, {this.openSettings = false});
  @override
  String toString() => message;
}

Future<DeviceLocation> requestDeviceLocation() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const DeviceLocationError('请先开启设备的定位服务', openSettings: true);
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.deniedForever) {
    throw const DeviceLocationError(
      '定位权限已关闭，可以到应用设置中允许大致位置',
      openSettings: true,
    );
  }
  if (permission == LocationPermission.denied) {
    throw const DeviceLocationError('没有获得定位权限，尚未开启附近展示');
  }
  final LocationSettings settings =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? AndroidSettings(
          accuracy: LocationAccuracy.low,
          forceLocationManager: true,
          timeLimit: const Duration(seconds: 25),
        )
      : const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 25),
        );
  try {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: settings,
    );
    return DeviceLocation(position.latitude, position.longitude);
  } on TimeoutException {
    throw const DeviceLocationError('暂时没有获取到位置，请检查定位服务后重试');
  }
}

Future<bool> openDeviceLocationSettings() => Geolocator.openAppSettings();
