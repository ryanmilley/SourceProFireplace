import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';

void main() {
  runApp(const FireplaceApp());
}

class FireplaceApp extends StatelessWidget {
  const FireplaceApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fireplace Controller',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.orange,
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
      ),
      home: const RemoteDashboard(),
    );
  }
}

class RemoteDashboard extends StatefulWidget {
  const RemoteDashboard({Key? key}) : super(key: key);

  @override
  State<RemoteDashboard> createState() => _RemoteDashboardState();
}

class _RemoteDashboardState extends State<RemoteDashboard> {
  BluetoothCharacteristic? _writeCharacteristic;
  String _statusMessage = "Status: Disconnected";
  bool _isConnecting = false;

  final String targetServiceUuid = "0000ffe0-0000-1000-8000-00805f9b34fb";
  final String targetCharacteristicUuid = "0000ffe1-0000-1000-8000-00805f9b34fb";
  final int spHeader = 0x55;
  final int spLen = 0x06;

  Future<void> _startBleScan() async {
    setState(() {
      _isConnecting = true;
      _statusMessage = "Status: Scanning for Fireplace...";
    });

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    } catch (e) {
      setState(() {
        _statusMessage = "Scan failed to start: $e";
        _isConnecting = false;
      });
      return;
    }

    FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult r in results) {
        String name = r.device.localName.toUpperCase();
        if (name.contains('FIREPLACE') || name.contains('EFP') || name.contains('AMBA')) {
          await FlutterBluePlus.stopScan();
          _connectToFireplace(r.device);
          break;
        }
      }
    }, onError: (e) {
      setState(() {
        _isConnecting = false;
        _statusMessage = "Error during scan: $e";
      });
    });
  }

  Future<void> _connectToFireplace(BluetoothDevice device) async {
    try {
      await device.connect();
      setState(() {
        _statusMessage = "Status: Discovering services...";
      });

      List<BluetoothService> services = await device.discoverServices();
      for (BluetoothService service in services) {
        if (service.uuid.toString().toLowerCase() == targetServiceUuid) {
          for (BluetoothCharacteristic characteristic in service.characteristics) {
            if (characteristic.uuid.toString().toLowerCase() == targetCharacteristicUuid) {
              setState(() {
                _writeCharacteristic = characteristic;
                _statusMessage = "🔥 Connected to ${device.localName}!";
                _isConnecting = false;
              });
              return;
            }
          }
        }
      }
      setState(() {
        _statusMessage = "Error: Target characteristic not found.";
        _isConnecting = false;
      });
    } catch (e) {
      setState(() {
        _statusMessage = "Connection failed: $e";
        _isConnecting = false;
      });
    }
  }

  Future<void> _transmitCommand(int commandType, int settingValue) async {
    if (_writeCharacteristic == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please connect to the fireplace first!")),
      );
      return;
    }

    List<int> packet = [spHeader, spLen, commandType, settingValue, 0x01, 0x00];
    int checksum = packet.reduce((acc, current) => acc + current) & 0xFF;
    packet.add(checksum);

    try {
      await _writeCharacteristic!.write(packet, withoutResponse: true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Transmission error: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Source Pro Control Panel'),
        backgroundColor: Colors.black54,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orangeAccent),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              icon: _isConnecting 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.bluetooth),
              label: const Text('1. Connect Fireplace'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _isConnecting ? null : _startBleScan,
            ),
            const SizedBox(height: 40),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.symmetric(vertical: 16)),
                    onPressed: () => _transmitCommand(0x01, 0x01),
                    child: const Text('Power ON'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.grey, padding: const EdgeInsets.symmetric(vertical: 16)),
                    onPressed: () => _transmitCommand(0x01, 0x00),
                    child: const Text('Power OFF'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
