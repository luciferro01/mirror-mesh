import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../utils/network_utils.dart';

import 'screen_selection_screen.dart';
import 'room_active_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentRoomAsync = ref.watch(currentRoomProvider);
    final networkInfoAsync = ref.watch(networkInfoProvider);
    final serverStatus = ref.watch(serverStatusProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: currentRoomAsync.when(
        data: (room) {
          if (room != null && room.isActive) {
            return RoomActiveScreen(room: room);
          }
          return _buildHomeContent(
            context,
            ref,
            networkInfoAsync,
            serverStatus,
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _buildErrorContent(context, error.toString()),
      ),
    );
  }

  Widget _buildHomeContent(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<DeviceNetworkInfo> networkInfoAsync,
    ServerStatus serverStatus,
  ) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context, ref),
            const SizedBox(height: 32),
            _buildStatusCard(networkInfoAsync, serverStatus),
            const SizedBox(height: 32),
            _buildQuickActions(context, ref),
            const SizedBox(height: 32),
            _buildFeaturesSection(),
            const SizedBox(height: 32),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF00FF88).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.cast, color: Color(0xFF00FF88), size: 32),
        ),
        const SizedBox(width: 16),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mirror Mesh',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                'Share your screen wirelessly',
                style: TextStyle(fontSize: 16, color: Colors.white70),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => _showSettings(context),
          icon: const Icon(Icons.settings, color: Colors.white70),
        ),
      ],
    );
  }

  Widget _buildStatusCard(
    AsyncValue<DeviceNetworkInfo> networkInfoAsync,
    ServerStatus serverStatus,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF00FF88).withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.wifi, color: Color(0xFF00FF88), size: 20),
              SizedBox(width: 8),
              Text(
                'Network Status',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          networkInfoAsync.when(
            data: (networkInfo) => _buildNetworkInfo(networkInfo, serverStatus),
            loading: () => const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text(
                  'Checking network...',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
            error: (error, _) => Text(
              'Network error: $error',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkInfo(
    DeviceNetworkInfo networkInfo,
    ServerStatus serverStatus,
  ) {
    return Column(
      children: [
        _buildInfoRow(
          'Local IP',
          networkInfo.ipAddress ?? 'Not available',
          networkInfo.ipAddress != null ? Icons.check_circle : Icons.error,
          networkInfo.ipAddress != null ? const Color(0xFF00FF88) : Colors.red,
        ),
        const SizedBox(height: 12),
        _buildInfoRow(
          'WiFi Network',
          networkInfo.wifiName ?? 'Not connected',
          networkInfo.isWifiConnected ? Icons.wifi : Icons.wifi_off,
          networkInfo.isWifiConnected ? const Color(0xFF00FF88) : Colors.orange,
        ),
        const SizedBox(height: 12),
        _buildInfoRow(
          'Server Status',
          serverStatus.isRunning
              ? 'Running on port ${serverStatus.port}'
              : 'Stopped',
          serverStatus.isRunning ? Icons.play_circle : Icons.stop_circle,
          serverStatus.isRunning ? const Color(0xFF00FF88) : Colors.grey,
        ),
      ],
    );
  }

  Widget _buildInfoRow(
    String label,
    String value,
    IconData icon,
    Color iconColor,
  ) {
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 16),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActions(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildActionCard(
                'Share Screen',
                'Start sharing your screen',
                Icons.screen_share,
                const Color(0xFF00FF88),
                () => _startScreenSharing(context, ref),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildActionCard(
                'View Guide',
                'How to connect devices',
                Icons.help_outline,
                Colors.blue,
                () => _showUserGuide(context),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionCard(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturesSection() {
    const features = [
      'Real-time screen sharing via WebRTC',
      'Connect multiple devices simultaneously',
      'No app installation required for viewers',
      'Works on local network (WiFi)',
      'Adjustable quality settings',
      'Secure room-based connections',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Features',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        ...features.map(
          (feature) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: Color(0xFF00FF88),
                  size: 16,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    feature,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return const Center(
      child: Text(
        'Mirror Mesh - Cross-platform Screen Sharing',
        style: TextStyle(color: Colors.white38, fontSize: 12),
      ),
    );
  }

  Widget _buildErrorContent(BuildContext context, String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Something went wrong',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00FF88),
                foregroundColor: Colors.black,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  void _startScreenSharing(BuildContext context, WidgetRef ref) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ScreenSelectionScreen()));
  }

  void _showSettings(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  void _showUserGuide(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          'How to Connect',
          style: TextStyle(color: Colors.white),
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '1. Start screen sharing from this device\n'
              '2. A unique room code will be generated\n'
              '3. Open the provided URL on any device\n'
              '4. Devices must be on the same WiFi network\n'
              '5. No app installation needed for viewers',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Got it',
              style: TextStyle(color: Color(0xFF00FF88)),
            ),
          ),
        ],
      ),
    );
  }
}
