import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final networkInfoAsync = ref.watch(networkInfoProvider);
    final serverStatus = ref.watch(serverStatusProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSection('Network Information', Icons.wifi, [
              networkInfoAsync.when(
                data: (networkInfo) =>
                    _buildNetworkCard(networkInfo, serverStatus),
                loading: () =>
                    _buildLoadingCard('Loading network information...'),
                error: (error, _) =>
                    _buildErrorCard('Network Error', error.toString()),
              ),
            ]),
            const SizedBox(height: 32),
            _buildSection('Quality Presets', Icons.high_quality, [
              _buildQualityPresetCard(
                'Low Quality',
                '720p • 24fps',
                'Best for slow networks',
              ),
              _buildQualityPresetCard(
                'Medium Quality',
                '1080p • 30fps',
                'Balanced performance',
              ),
              _buildQualityPresetCard(
                'High Quality',
                '1080p • 60fps',
                'Best quality for fast networks',
              ),
            ]),
            const SizedBox(height: 32),
            _buildSection('Application', Icons.info, [
              _buildSettingCard(
                'About Mirror Mesh',
                'Version information and credits',
                Icons.info_outline,
                () => _showAboutDialog(context),
              ),
              _buildSettingCard(
                'User Guide',
                'How to use the application',
                Icons.help_outline,
                () => _showUserGuide(context),
              ),
              _buildSettingCard(
                'Privacy & Security',
                'Data usage and security information',
                Icons.security,
                () => _showPrivacyInfo(context),
              ),
            ]),
            const SizedBox(height: 32),
            _buildSection('System', Icons.computer, [
              _buildSettingCard(
                'Permissions',
                'Screen recording and network access',
                Icons.security,
                () => _showPermissionsInfo(context),
              ),
              _buildSettingCard(
                'Troubleshooting',
                'Common issues and solutions',
                Icons.build,
                () => _showTroubleshooting(context),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, IconData icon, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: const Color(0xFF00FF88), size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...children,
      ],
    );
  }

  Widget _buildNetworkCard(dynamic networkInfo, ServerStatus serverStatus) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF00FF88).withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow(
            'Local IP Address',
            networkInfo.ipAddress ?? 'Not available',
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            'WiFi Network',
            networkInfo.wifiName ?? 'Not connected',
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            'Connection Status',
            networkInfo.isWifiConnected ? 'Connected' : 'Disconnected',
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            'Server Status',
            serverStatus.isRunning ? 'Running' : 'Stopped',
          ),
          if (serverStatus.isRunning && serverStatus.port != null) ...[
            const SizedBox(height: 12),
            _buildInfoRow('Server Port', serverStatus.port.toString()),
          ],
        ],
      ),
    );
  }

  Widget _buildQualityPresetCard(
    String title,
    String specs,
    String description,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.high_quality, color: Color(0xFF00FF88), size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  specs,
                  style: const TextStyle(
                    color: Color(0xFF00FF88),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingCard(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: const Color(0xFF00FF88), size: 24),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: Colors.white54,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingCard(String message) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00FF88)),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            message,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(String title, String error) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            error,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
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

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Row(
          children: [
            Icon(Icons.cast, color: Color(0xFF00FF88), size: 24),
            SizedBox(width: 8),
            Text('Mirror Mesh', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version: 1.0.0', style: TextStyle(color: Colors.white70)),
            SizedBox(height: 8),
            Text(
              'A cross-platform screen sharing application built with Flutter.',
              style: TextStyle(color: Colors.white70),
            ),
            SizedBox(height: 16),
            Text(
              'Features:',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '• Real-time WebRTC screen sharing\n'
              '• Multi-device viewer support\n'
              '• No app installation for viewers\n'
              '• Local network security\n'
              '• Quality settings control',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Close',
              style: TextStyle(color: Color(0xFF00FF88)),
            ),
          ),
        ],
      ),
    );
  }

  void _showUserGuide(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text('User Guide', style: TextStyle(color: Colors.white)),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Getting Started:',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 8),
              Text(
                '1. Click "Share Screen" on the home page\n'
                '2. Select the screen or window to share\n'
                '3. Choose quality settings\n'
                '4. Click "Start Sharing"\n'
                '5. Share the generated URL with viewers',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              SizedBox(height: 16),
              Text(
                'For Viewers:',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 8),
              Text(
                '• Open the shared URL in any web browser\n'
                '• No app installation required\n'
                '• Must be on the same WiFi network\n'
                '• Works on phones, tablets, computers',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              SizedBox(height: 16),
              Text(
                'Tips:',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 8),
              Text(
                '• Use lower quality for better performance\n'
                '• Ensure strong WiFi signal\n'
                '• Close unnecessary applications\n'
                '• Check firewall settings if issues occur',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
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

  void _showPrivacyInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          'Privacy & Security',
          style: TextStyle(color: Colors.white),
        ),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Data Privacy:',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 8),
              Text(
                '• No data is stored on external servers\n'
                '• All communication stays on local network\n'
                '• No personal information is collected\n'
                '• Screen content is not recorded or saved',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              SizedBox(height: 16),
              Text(
                'Security:',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 8),
              Text(
                '• Connections are limited to local network\n'
                '• Room codes provide access control\n'
                '• Sessions end when sharing stops\n'
                '• No internet access required',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              SizedBox(height: 16),
              Text(
                'Permissions:',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 8),
              Text(
                '• Screen recording: Required to capture screen\n'
                '• Network access: Required for local connections\n'
                '• No other permissions are needed',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Understood',
              style: TextStyle(color: Color(0xFF00FF88)),
            ),
          ),
        ],
      ),
    );
  }

  void _showPermissionsInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text('Permissions', style: TextStyle(color: Colors.white)),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Required Permissions:',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Screen Recording:',
                style: TextStyle(
                  color: Color(0xFF00FF88),
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Allows the app to capture your screen content for sharing. This is the core functionality of the application.',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              SizedBox(height: 16),
              Text(
                'Network Access:',
                style: TextStyle(
                  color: Color(0xFF00FF88),
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Enables the app to create a local server and communicate with viewers on your network.',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              SizedBox(height: 16),
              Text(
                'Note:',
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'If screen sharing is not working, check your system\'s screen recording permissions in Settings > Privacy & Security.',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK', style: TextStyle(color: Color(0xFF00FF88))),
          ),
        ],
      ),
    );
  }

  void _showTroubleshooting(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          'Troubleshooting',
          style: TextStyle(color: Colors.white),
        ),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Common Issues:',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Can\'t see screen options:',
                style: TextStyle(color: Color(0xFF00FF88)),
              ),
              SizedBox(height: 4),
              Text(
                '• Grant screen recording permission\n• Restart the application\n• Check system privacy settings',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              SizedBox(height: 12),
              Text(
                'Viewers can\'t connect:',
                style: TextStyle(color: Color(0xFF00FF88)),
              ),
              SizedBox(height: 4),
              Text(
                '• Ensure same WiFi network\n• Check firewall settings\n• Try different port\n• Verify local IP address',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              SizedBox(height: 12),
              Text(
                'Poor video quality:',
                style: TextStyle(color: Color(0xFF00FF88)),
              ),
              SizedBox(height: 4),
              Text(
                '• Lower quality settings\n• Close other applications\n• Check network speed\n• Move closer to router',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              SizedBox(height: 12),
              Text(
                'Connection drops:',
                style: TextStyle(color: Color(0xFF00FF88)),
              ),
              SizedBox(height: 4),
              Text(
                '• Improve WiFi signal\n• Reduce number of viewers\n• Check network stability\n• Restart router if needed',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Close',
              style: TextStyle(color: Color(0xFF00FF88)),
            ),
          ),
        ],
      ),
    );
  }
}
