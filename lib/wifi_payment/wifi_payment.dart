import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:app_settings/app_settings.dart';
import 'package:card_app/ui/payment_successful_page.dart';
import 'package:card_app/ui/success_bottom_sheet.dart';
import 'package:card_app/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:location/location.dart' hide PermissionStatus;
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:shared_preferences/shared_preferences.dart';

enum DeviceType { advertiser, browser }

enum SessionState { notConnected, connecting, connected }

class Device {
  final String deviceId;
  final String fullName;
  final String username;
  final String profileImage;
  SessionState state;
  Device(
    this.deviceId, {
    required this.fullName,
    required this.username,
    required this.profileImage,
    this.state = SessionState.notConnected,
  });
}

class DevicesListScreen extends StatefulWidget {
  const DevicesListScreen({super.key, required this.deviceType});
  final DeviceType deviceType;
  @override
  State<DevicesListScreen> createState() => _DevicesListScreenState();
}

class _DevicesListScreenState extends State<DevicesListScreen>
    with TickerProviderStateMixin {
  List<Device> devices = [];
  List<Device> connectedDevices = [];
  final Strategy strategy = Strategy.P2P_STAR;
  bool isInit = false;
  String? errorMessage;
  List<String> missingServices = [];
  final Map<String, Map<String, dynamic>> pendingDeviceInfos = {};
  late AnimationController _controller;
  final _amountController = TextEditingController();
  final _purposeController = TextEditingController();
  bool _isWaiting = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
    init();
  }

  @override
  void dispose() {
    _controller.dispose();
    for (var device in connectedDevices) {
      Nearby().disconnectFromEndpoint(device.deviceId);
    }
    Nearby().stopAdvertising();
    Nearby().stopDiscovery();
    Nearby().stopAllEndpoints();
    devices.clear();
    connectedDevices.clear();
    super.dispose();
  }

  int getItemCount() {
    return devices.length + connectedDevices.length;
  }

  Future<bool> isLocationEnabled() async {
    try {
      return await Location().serviceEnabled();
    } catch (e) {
      return false;
    }
  }

  IconData getServiceIcon(String service) {
    switch (service) {
      case 'Bluetooth':
        return Icons.bluetooth;
      case 'Location':
        return Icons.location_on;
      case 'WiFi':
        return Icons.wifi;
      default:
        return Icons.settings;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (errorMessage != null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(bottom: true,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              SizedBox(height: 25),
              Padding(
                padding: EdgeInsets.all(25),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).pop();
                      },
                      child: Icon(
                        Icons.arrow_back_ios,
                        color: Colors.black87,
                        size: 20,
                      ),
                    ),
                    Spacer(),
                    Text(
                      "Wifi Transfer",
                      style: TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    Spacer(),
                  ],
                ),
              ),

              const SizedBox(height: 30),
              Padding(
                padding: EdgeInsets.all(8),
                child: Column(
                  children: [
                    Text(
                      errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 20),
                    if (errorMessage!.toLowerCase().contains('permission'))
                      ElevatedButton(
                        onPressed: () => AppSettings.openAppSettings(),
                        child: const Text('Open App Settings'),
                      ),
                    Row(
                      children: [
                        ...missingServices.map(
                          (s) => Container(
                            margin: EdgeInsets.all(10),
                            child: ElevatedButton(
                              onPressed: () {
                                if (s == 'Bluetooth') {
                                  AppSettings.openAppSettings(
                                    type: AppSettingsType.bluetooth,
                                  );
                                }
                                if (s == 'Location') {
                                  AppSettings.openAppSettings(
                                    type: AppSettingsType.location,
                                  );
                                }
                                if (s == 'WiFi') {
                                  AppSettings.openAppSettings(
                                    type: AppSettingsType.wifi,
                                  );
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                minimumSize: const Size(75, 50),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: Icon(
                                getServiceIcon(s),
                                color: Colors.white,
                                size: 30,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      margin: EdgeInsets.all(10),
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            errorMessage = null;
                            missingServices = [];
                            isInit = false;
                          });
                          init();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.refresh, color: Colors.white, size: 30),
                            SizedBox(width: 5),
                            Text(
                              'Reconnect',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (!isInit) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            children: [
              SizedBox(height: 25),
              Padding(
                padding: EdgeInsets.all(25),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).pop();
                      },
                      child: Icon(
                        Icons.arrow_back_ios,
                        color: Colors.black87,
                        size: 20,
                      ),
                    ),
                    Spacer(),
                    Text(
                      "Wifi Transfer",
                      style: TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    Spacer(),
                  ],
                ),
              ),
              Spacer(),
              CircularProgressIndicator(color: primaryColor),
              Spacer(),
            ],
          ),
        ),
      );
    }
    return SafeArea(bottom: true,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            SizedBox(height: 25),
            Padding(
              padding: EdgeInsets.all(25),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).pop();
                    },
                    child: Icon(
                      Icons.arrow_back_ios,
                      color: Colors.black87,
                      size: 20,
                    ),
                  ),
                  Spacer(),
                  Text(
                    "Wifi Transfer",
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  Spacer(),
                ],
              ),
            ),
            const SizedBox(height: 30),
            Expanded(
              child: getItemCount() == 0
                  ? _buildSearchingUI()
                  : _buildFoundUI(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchingUI() {
    final isAdvertiser = widget.deviceType == DeviceType.advertiser;
    final searchText = isAdvertiser
        ? "Broadcasting\nWaiting for nearby devices"
        : "Searching for nearby devices";
    final centerIcon = isAdvertiser ? Icons.wifi_tethering : Icons.search;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: 300,
            width: 300,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (!isAdvertiser)
                  Container(
                    width: 300,
                    height: 300,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Colors.blue.withOpacity(0.1),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                if (!isAdvertiser)
                  Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.blue.withOpacity(0.2)),
                    ),
                  ),
                if (!isAdvertiser)
                  Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.blue.withOpacity(0.2)),
                    ),
                  ),
                if (!isAdvertiser)
                  Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.blue.withOpacity(0.2)),
                    ),
                  ),
                if (!isAdvertiser)
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                  ),
                if (isAdvertiser)
                  RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            Transform.scale(
                              scale: _controller.value * 3,
                              child: Opacity(
                                opacity: (1 - _controller.value) * 0.3,
                                child: Container(
                                  width: 100,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.blue),
                                  ),
                                ),
                              ),
                            ),
                            Transform.scale(
                              scale: (_controller.value + 1) * 2,
                              child: Opacity(
                                opacity:
                                    (0.5 - (_controller.value - 0.5).abs()) * 0.3,
                                child: Container(
                                  width: 100,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.blue),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                Container(
                  width: 60,
                  height: 60,
                  decoration: const BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(centerIcon, color: Colors.white, size: 30),
                  ),
                ),
                if (!isAdvertiser)
                  RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        return Transform.rotate(
                          angle: _controller.value * 2 * pi,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // 🌟 The radar sweep (shaded fan)
                              ClipPath(
                                clipper: RadarSweepClipper(
                                  startAngle: -pi / 2,
                                ), // 👈 start at top
                                child: Container(
                                  width: 300,
                                  height: 300,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: SweepGradient(
                                      startAngle: -pi / 2,
                                      endAngle: -pi / 2 + pi / 6, // 30° fan
                                      colors: [
                                        Colors.blue.withOpacity(0.4),
                                        Colors.blue.withOpacity(0.0),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                              // 🔹 The scanning line (beam edge)
                              Align(
                                alignment: Alignment.topCenter,
                                child: Container(
                                  margin: const EdgeInsets.only(top: 20),
                                  width: 4,
                                  height: 110,
                                  decoration: BoxDecoration(
                                    color: Colors.blue,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 50),
          Text(
            searchText,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.blueGrey,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 50),
            child: Text(
              "Tip: Take charge of your money, or risk letting others do it poorly on your behalf.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blueGrey, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFoundUI() {
    final isAdvertiser = widget.deviceType == DeviceType.advertiser;
    final allDevices = isAdvertiser
        ? connectedDevices
        : [...devices, ...connectedDevices];
    final count = allDevices.length;
    final countText = isAdvertiser
        ? (count > 1 ? "$count people connected" : "$count person connected")
        : (count > 1 ? "$count people found" : "$count person found");

    if (!isAdvertiser && connectedDevices.isNotEmpty) {
      final device = connectedDevices.first;
      return SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('Connected to ${device.fullName}', style: const TextStyle(color: Colors.blue)),
              ),
            ),
            const SizedBox(height: 20),
            CircleAvatar(
              radius: 50,
              backgroundImage: device.profileImage.isNotEmpty
                  ? NetworkImage(device.profileImage)
                  : null,
              child: device.profileImage.isEmpty
                  ? Text(_getInitials(device.fullName))
                  : null,
            ),
            const SizedBox(height: 8),
            Text(
              device.fullName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              '@${device.username}',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: TextField(
                controller: _amountController,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  prefixText: '₦ ',
                  labelText: 'Enter Amount',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: const BorderSide(color: Colors.blue),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: const BorderSide(color: Colors.blue, width: 2),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: TextField(
                
                controller: _purposeController,
                decoration: InputDecoration(
                  hintText: 'Payment Purpose (Optional)',
                  hintStyle: TextStyle(color: Colors.grey.shade600),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: BorderSide.none,
                  ),
                  fillColor: Colors.grey.shade50,
                  filled: true,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: ElevatedButton(
                onPressed: _isWaiting ? null : () => _sendPayment(device.deviceId),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                ),
                child: _isWaiting
                    ? const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.white))
                    : const Text(
                        'Send',
                        style: TextStyle(color: Colors.white),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => _onButtonClicked(device),
              child: const Text('Disconnect',style: TextStyle(color: Colors.red),),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 25),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(countText, style: const TextStyle(color: Colors.blue)),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 300,
          width: 300,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (isAdvertiser)
                RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          Transform.scale(
                            scale: _controller.value * 3,
                            child: Opacity(
                              opacity: (1 - _controller.value) * 0.3,
                              child: Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.blue),
                                ),
                              ),
                            ),
                          ),
                          Transform.scale(
                            scale: (_controller.value + 1) * 2,
                            child: Opacity(
                              opacity:
                                  (0.5 - (_controller.value - 0.5).abs()) * 0.3,
                              child: Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.blue),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                )
              else
                Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.blue.withOpacity(0.1),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              if (!isAdvertiser)
                Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.blue.withOpacity(0.2)),
                  ),
                ),
              if (!isAdvertiser)
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                ),
              Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    Icons.wifi_tethering,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ),
              ...List.generate(count, (index) {
                final device = allDevices[index];
                final angle = index * 2 * pi / count;
                final x = 120 * cos(angle);
                final y = 120 * sin(angle);
                return Positioned(
                  left: 150 + x - 20,
                  top: 150 + y - 20,
                  child: CircleAvatar(
                    radius: 20,
                    backgroundImage: device.profileImage.isNotEmpty
                        ? NetworkImage(device.profileImage)
                        : null,
                    child: device.profileImage.isEmpty
                        ? Text(_getInitials(device.fullName))
                        : null,
                  ),
                );
              }),
            ],
          ),
        ),
        if (!isAdvertiser)
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: allDevices.map((device) {
                  return Container(
                    width: 225,
                    height: 220,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 30,
                      vertical: 20,
                    ),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundImage: device.profileImage.isNotEmpty
                              ? NetworkImage(device.profileImage)
                              : null,
                          child: device.profileImage.isEmpty
                              ? Text(
                                  _getInitials(device.fullName),
                                  style: const TextStyle(fontSize: 20),
                                )
                              : null,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          device.fullName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '@${device.username}',
                          style: const TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: () => _onButtonClicked(device),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: getButtonColor(device.state),
                            foregroundColor: getTextColor(device.state),
                            minimumSize: const Size(double.infinity, 44),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          child: Text('${getButtonStateName(device.state)}  →'),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
      ],
    );
  }

  String _getInitials(String name) {
    final parts = name.split(' ');
    if (parts.isEmpty) return '';
    return parts
        .map((p) => p.isNotEmpty ? p[0].toUpperCase() : '')
        .join()
        .substring(0, min(2, parts.length));
  }

  String getStateName(SessionState state) {
    switch (state) {
      case SessionState.notConnected:
        return "disconnected";
      case SessionState.connecting:
        return "waiting";
      case SessionState.connected:
        return "connected";
    }
  }

  String getButtonStateName(SessionState state) {
    switch (state) {
      case SessionState.notConnected:
        return "Connect";
      case SessionState.connecting:
        return "Connecting";
      case SessionState.connected:
        return "Disconnect";
    }
  }

  Color getButtonColor(SessionState state) {
    switch (state) {
      case SessionState.notConnected:
        return primaryColor;
      case SessionState.connecting:
        return primaryColor.withValues(alpha: 0.2);
      case SessionState.connected:
        return primaryColor;
    }
  }

  Color getTextColor(SessionState state) {
    switch (state) {
      case SessionState.notConnected:
        return Colors.white;
      case SessionState.connecting:
        return Colors.white;
      case SessionState.connected:
        return Colors.white;
    }
  }

  Color getStateColor(SessionState state) {
    switch (state) {
      case SessionState.notConnected:
        return Colors.red;
      case SessionState.connecting:
        return Colors.yellow;
      case SessionState.connected:
        return Colors.green;
    }
  }

  _onButtonClicked(Device device) async {
    switch (device.state) {
      case SessionState.notConnected:
        if (widget.deviceType == DeviceType.browser &&
            connectedDevices.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Can only connect to one at a time")),
          );
          return;
        }
        setState(() {
          device.state = SessionState.connecting;
        });
        final userInfoJson = jsonEncode(await _getUserInfo());
        Nearby().requestConnection(
          userInfoJson,
          device.deviceId,
          onConnectionInitiated: (String id, ConnectionInfo info) {
            Nearby().acceptConnection(
              id,
              onPayLoadRecieved: _onPayloadReceived,
            );
          },
          onConnectionResult: (String id, Status status) {
            setState(() {
              device.state = SessionState.connected;
              connectedDevices.add(device);
              devices.removeWhere((d) => d.deviceId == id);
            });
          },
          onDisconnected: (String id) {
            setState(() {
              connectedDevices.removeWhere((d) => d.deviceId == id);
              device.state = SessionState.notConnected;
              devices.add(device);
            });
          },
        );
        break;
      case SessionState.connected:
        Nearby().disconnectFromEndpoint(device.deviceId);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Disconnected")));
        break;
      case SessionState.connecting:
        break;
    }
  }

  void _onPayloadReceived(String id, Payload payload) async {
    if (payload.type == PayloadType.BYTES) {
      String msg = utf8.decode(payload.bytes!);
      final Map<String, dynamic> parsed = (jsonDecode(msg) as Map).cast<String, dynamic>();
      String? type = parsed['type'];
      if (type == 'payment_request') {
        double amount = parsed['amount'];
        String senderId = parsed['senderId'];
        String purpose = parsed['purpose'] ?? '';

        DocumentSnapshot senderDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(senderId)
            .get();
        String senderName =
            '${senderDoc['firstName']} ${senderDoc['lastName']}';

        final prefs = await SharedPreferences.getInstance();
        bool paymentConfirmation = prefs.getBool('paymentConfirmation') ?? false;

        if (!paymentConfirmation) {
          // Auto-accept: include receiver VA details in the reply so the sender can settle the payment.
          final currentUser = FirebaseAuth.instance.currentUser!;
          final userDoc = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();
          final vaData = userDoc.data()?['getAnchorData']?['virtualAccount']?['data'];
          if (vaData == null) {
            // cannot accept — inform sender
            Nearby().sendBytesPayload(id, utf8.encode(jsonEncode({'type': 'payment_rejected', 'reason': 'receiver_account_missing'})));
            showSimpleDialog('Your account is not configured to receive payments', Colors.red);
            return;
          }
          final accountNumber = vaData['attributes']?['accountNumber'];
          final bankId = vaData['attributes']?['bank']?['id']?.toString();
          final bankName = vaData['attributes']?['bank']?['name'];
          final accountName = vaData['attributes']?['accountName'];
          final accountId = vaData['id']?.toString();
          final accountType = vaData['type']?.toString();

          // create a pending transaction locally — final success will be marked by sender's settlement
          await FirebaseFirestore.instance.collection('transactions').add({
            'senderId': senderId,
            'receiverId': currentUser.uid,
            'amount': amount,
            'purpose': purpose,
            'timestamp': Timestamp.now(),
            'status': 'pending',
            'type': 'wifi',
          });

          showSimpleDialog('Received request for ₦$amount from $senderName', Colors.green);
          Nearby().sendBytesPayload(
              id,
              utf8.encode(jsonEncode({
                'type': 'payment_accepted',
                'receiverId': currentUser.uid,
                'accountNumber': accountNumber,
                'bankId': bankId,
                'bankName': bankName,
                'accountName': accountName,
                'accountId': accountId,
                'accountType': accountType,
              })));
        } else {
          showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Payment Confirmation'),
              content: Text('Do you want to accept ₦$amount from $senderName?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Reject'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Accept'),
                ),
              ],
            ),
          ).then((accept) async {
            if (accept == true) {
              final currentUser = FirebaseAuth.instance.currentUser!;
              final userDoc = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();
              final vaData = userDoc.data()?['getAnchorData']?['virtualAccount']?['data'];
              if (vaData == null) {
                Nearby().sendBytesPayload(id, utf8.encode(jsonEncode({'type': 'payment_rejected', 'reason': 'receiver_account_missing'})));
                showSimpleDialog('Your account is not configured to receive payments', Colors.red);
                return;
              }

              final accountNumber = vaData['attributes']?['accountNumber'];
              final bankId = vaData['attributes']?['bank']?['id']?.toString();
              final bankName = vaData['attributes']?['bank']?['name'];
              final accountName = vaData['attributes']?['accountName'];
              final accountId = vaData['id']?.toString();
              final accountType = vaData['type']?.toString();

              await FirebaseFirestore.instance.collection('transactions').add({
                'senderId': senderId,
                'receiverId': currentUser.uid,
                'amount': amount,
                'purpose': purpose,
                'timestamp': Timestamp.now(),
                'status': 'pending',
                'type': 'wifi',
              });
              showSimpleDialog('Accepted ₦$amount from $senderName', Colors.green);
              Nearby().sendBytesPayload(
                  id,
                  utf8.encode(jsonEncode({
                    'type': 'payment_accepted',
                    'receiverId': currentUser.uid,
                    'accountNumber': accountNumber,
                    'bankId': bankId,
                    'bankName': bankName,
                    'accountName': accountName,
                    'accountId': accountId,
                    'accountType': accountType,
                  })));
            } else if (accept == false) {
              Nearby().sendBytesPayload(id, utf8.encode(jsonEncode({'type': 'payment_rejected'})));
              showSimpleDialog('Rejected payment from $senderName', Colors.orange);
            }
          });
        }
      } else if (type == 'payment_accepted' || type == 'payment_rejected') {
        if (widget.deviceType == DeviceType.browser) {
          setState(() {
            _isWaiting = false;
          });
          if (type == 'payment_accepted') {
            // The receiver sent their VA details — settle the payment from this (sender) device.
            final amountText = _amountController.text;
            final amount = double.tryParse(amountText) ?? 0.0;
            final payload = parsed; // should contain receiverId, accountNumber, bankId, bankName, accountName, accountId, accountType
            try {
              final settled = await _settlePaymentToReceiver(payload, amount, parsed['purpose'] ?? _purposeController.text);
              if (!settled) {
                showSimpleDialog('Transfer failed', Colors.red);
              } else {
                showModalBottomSheet<String?>(
                  context: context,
                  builder: (ctx) => const SuccessBottomSheet(
                    actionText: "Go to Home",
                    title: "Transfer Successful",
                    description: "Money sent successfully",
                  ),
                  isScrollControlled: true,
                );

                navigateTo(context, PaymentSuccessfulPage(
                  bankCode: payload['bankId'] ?? "",
                  accountNumber: payload['accountNumber'] ?? "",
                  reference: payload['accountId'] ?? id,
                  recipientName: await _getUserNameById(payload['receiverId'] ?? FirebaseAuth.instance.currentUser!.uid),
                  bankName: payload['bankName'] ?? "PadiPay",
                  amount: amountText,
                  actionText: "Go to Home",
                  title: "Transfer Successful",
                  description: "Money sent successfully",
                ), type: NavigationType.clearStack);
                Nearby().disconnectFromEndpoint(id);
              }
            } catch (e) {
              debugPrint('settlement error: $e');
              showSimpleDialog('Error processing transfer', Colors.red);
            }
          } else {
            showSimpleDialog('Transfer rejected', Colors.red);
          }
        }
      }
    }
  }
Future<String> _getUserNameById(String userId) async {
  try {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .get();

    if (doc.exists) {
      final data = doc.data();
      final firstName = data?['firstName'] ?? '';
      final lastName = data?['lastName'] ?? '';

      return "$firstName + $lastName";
    } else {
      print('User not found');
      return "";
    }
  } catch (e) {
    print('Error fetching user name: $e');
    return "";
  }
}

  Future<Map<String, dynamic>> _getUserInfo() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return {
        'fullName': 'Anonymous',
        'username': 'anonymous',
        'profileImage': '',
      };
    }
    DocumentSnapshot<Map<String, dynamic>> doc = await FirebaseFirestore
        .instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (!doc.exists) {
      return {'fullName': 'Unknown', 'username': 'unknown', 'profileImage': ''};
    }
    return {
      'fullName': '${doc.data()!['firstName']} ${doc.data()!['lastName']}',
      'username': doc.data()!['username'] ?? 'username',
      'profileImage': doc.data()!['profileImage'] ?? '',
    };
  }

  Future<bool> requestPermissions() async {
    if (!Platform.isAndroid) {
      setState(() {
        errorMessage = 'Nearby Connections is Android-only.';
      });
      return false;
    }

    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdk = androidInfo.version.sdkInt ?? 0;

    List<Permission> perms = [Permission.location];
    if (sdk >= 31) {
      perms.add(Permission.bluetoothScan);
      perms.add(Permission.bluetoothConnect);
      if (widget.deviceType == DeviceType.advertiser) {
        perms.add(Permission.bluetoothAdvertise);
      }
    } else {
      perms.add(Permission.bluetooth);
    }
    if (sdk >= 33) {
      perms.add(Permission.nearbyWifiDevices);
    }

    // Check if all permissions are already granted
    Map<Permission, PermissionStatus> statuses = await Future.wait(perms.map((p) => p.status)).then((results) => Map.fromIterables(perms, results));
    final notGranted = statuses.entries.where((e) => !e.value.isGranted).map((e) => e.key).toList();
    if (notGranted.isEmpty) {
      // All permissions granted, no need to show bottom sheet
      return true;
    }

    // User already saw the WiFi/data privacy consent before opening this screen,
    // so go straight to requesting the OS permission dialogs.
    bool granted = false;
    final statuses2 = await notGranted.request();
    final denied = statuses2.entries
        .where((e) => !e.value.isGranted)
        .map((e) => e.key)
        .toList();
    if (denied.isNotEmpty) {
      final deniedNames =
          denied.map((p) => p.toString().split('.').last).join(', ');
      setState(() {
        errorMessage = 'Please grant the following permissions: $deniedNames';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Permissions not granted. Cannot use nearby connections.',
            ),
          ),
        );
      }
      granted = false;
    } else {
      granted = true;
    }
    return granted;
  }

  void init() async {
    try {
      bool permissionsGranted = await requestPermissions();
      if (!permissionsGranted) {
        return;
      }
      bool locEnabled = await isLocationEnabled();
      List<String> missing = [];
      if (!locEnabled) missing.add('Location');
      if (missing.isNotEmpty) {
        setState(() {
          errorMessage =
              'Please enable the following services: ${missing.join(', ')}';
          missingServices = missing;
        });
        return;
      }
      Map<String, dynamic> userInfo = await _getUserInfo();
      String userInfoJson = jsonEncode(userInfo);
      if (widget.deviceType == DeviceType.advertiser) {
        await Nearby().startAdvertising(
          userInfoJson,
          strategy,
          onConnectionInitiated: (String id, ConnectionInfo info) {
            Map<String, dynamic> endpointInfo = jsonDecode(info.endpointName);
            pendingDeviceInfos[id] = endpointInfo;
            Nearby().acceptConnection(
              id,
              onPayLoadRecieved: _onPayloadReceived,
            );
          },
          onConnectionResult: (String id, Status status) {
            Map<String, dynamic>? info = pendingDeviceInfos.remove(id);
            if (status == Status.CONNECTED && info != null) {
              setState(() {
                connectedDevices.add(
                  Device(
                    id,
                    fullName: info['fullName'],
                    username: info['username'],
                    profileImage: info['profileImage'] ?? '',
                    state: SessionState.connected,
                  ),
                );
              });
              showSimpleDialog('Connected to $id', Colors.red);
            }
          },
          onDisconnected: (String id) {
            setState(() {
              connectedDevices.removeWhere((d) => d.deviceId == id);
              pendingDeviceInfos.remove(id);
            });
          },
          serviceId: 'com.padipay_app_and_business.wifi_transfer',
        );
      } else {
        await Nearby().startDiscovery(
          userInfoJson,
          strategy,
          onEndpointFound: (String id, String endpointName, String serviceId) {
            Map<String, dynamic> info = jsonDecode(endpointName);
            setState(() {
              if (!devices.any((d) => d.deviceId == id) &&
                  !connectedDevices.any((d) => d.deviceId == id)) {
                devices.add(
                  Device(
                    id,
                    fullName: info['fullName'],
                    username: info['username'],
                    profileImage: info['profileImage'] ?? '',
                  ),
                );
              }
            });
          },
          onEndpointLost: (String? id) {
            if (id != null) {
              setState(() {
                devices.removeWhere((d) => d.deviceId == id);
              });
            }
          },
          serviceId: 'com.padipay_app_and_business.wifi_transfer',
        );
      }
      setState(() {
        isInit = true;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Error initializing nearby connections: $e';
      });
    }
  }

  void _sendPayment(String endpointId) {
    final amountText = _amountController.text;
    if (amountText.isEmpty) return;
    final amount = double.parse(amountText);
    final purpose = _purposeController.text;
    final senderId = FirebaseAuth.instance.currentUser!.uid;
    final message = jsonEncode({
      'type': 'payment_request',
      'amount': amount,
      'purpose': purpose,
      'senderId': senderId
    });
    setState(() {
      _isWaiting = true;
    });
    Nearby().sendBytesPayload(endpointId, utf8.encode(message));
  }

  Future<bool> _settlePaymentToReceiver(Map<String, dynamic> payload, double amount, String purpose) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        showSimpleDialog('No authenticated user found', Colors.red);
        return false;
      }

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final accountId = userDoc.data()?['getAnchorData']?['virtualAccount']?['data']?['id'];
      if (accountId == null) {
        showSimpleDialog('Account details not found', Colors.red);
        return false;
      }

      // Recipient's Anchor account ID is in the WiFi acceptance payload
      final toAccountId = payload['accountId']?.toString();
      if (toAccountId == null || toAccountId.isEmpty) {
        showSimpleDialog('Recipient account ID not found', Colors.red);
        return false;
      }

      final recipientAccountNumber = payload['accountNumber'];
      final recipientBankId = payload['bankId']?.toString();
      final recipientBankName = payload['bankName'];
      final recipientAccountName = payload['accountName'];

      final ownAccountNumber = userDoc.data()?['getAnchorData']?['virtualAccount']?['data']?['attributes']?['accountNumber']?.toString();
      if (ownAccountNumber != null && ownAccountNumber == recipientAccountNumber) {
        showSimpleDialog('You cannot send money to your own account', Colors.red);
        return false;
      }

      // Book transfer (both parties on Anchor — no counterparty needed)
      final amountKobo = (amount * 100).toInt();
      debugPrint('createBookTransfer: from=$accountId to=$toAccountId amount=$amountKobo');
      final transferResult = await FirebaseFunctions.instance
          .httpsCallable('sudoTransferIntra')
          .call({
        'fromAccountId': accountId,
        'toAccountId': toAccountId,
        'amount': amountKobo,
        'currency': 'NGN',
        'narration': purpose,
        'idempotencyKey': const Uuid().v4(),
      });

      final status = transferResult.data['data']['attributes']['status'];
      final failureReason = transferResult.data['data']['attributes']['failureReason'];
      if (status == 'FAILED') {
        showSimpleDialog('Transfer failed: $failureReason', Colors.red);
        return false;
      }

      await FirebaseFirestore.instance.collection('transactions').add({
        'userId': user.uid,
        'receiverId': payload['receiverId'] ?? 'unknown',
        'type': 'wifi',
        'bank_code': recipientBankId,
        'account_number': recipientAccountNumber,
        'amount': amount,
        'reason': purpose,
        'currency': 'NGN',
        'api_response': transferResult.data,
        'reference': transferResult.data['data']['id'],
        'recipientName': recipientAccountName,
        'bankName': recipientBankName,
        'timestamp': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      debugPrint('settlePaymentToReceiver error: $e');
      showSimpleDialog('Error settling payment', Colors.red);
      return false;
    }
  }
}

class RadarSweepClipper extends CustomClipper<Path> {
  final double startAngle;
  const RadarSweepClipper({this.startAngle = 0.0});

  @override
  Path getClip(Size size) {
    final path = Path();
    final radius = size.width / 2;
    final center = Offset(radius, radius);
    const sweepAngle = pi / 6; // 30 degrees fan

    path.moveTo(center.dx, center.dy);
    path.arcTo(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
    );
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant RadarSweepClipper oldClipper) =>
      oldClipper.startAngle != startAngle;
}