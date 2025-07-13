import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../models/room.dart';

class ScreenSelectionScreen extends ConsumerStatefulWidget {
  const ScreenSelectionScreen({super.key});

  @override
  ConsumerState<ScreenSelectionScreen> createState() =>
      _ScreenSelectionScreenState();
}

class _ScreenSelectionScreenState extends ConsumerState<ScreenSelectionScreen> {
  ScreenSource? selectedSource;
  QualitySettings selectedQuality = QualitySettings.medium;
  bool isCreating = false;

  @override
  Widget build(BuildContext context) {
    final screenSourcesAsync = ref.watch(screenSourcesProvider);

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
          'Select Screen to Share',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInstructions(),
                    const SizedBox(height: 32),
                    _buildQualitySettings(),
                    const SizedBox(height: 32),
                    _buildScreenSourcesSection(screenSourcesAsync),
                  ],
                ),
              ),
            ),
            _buildBottomActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructions() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF00FF88).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF00FF88).withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Color(0xFF00FF88), size: 20),
              SizedBox(width: 8),
              Text(
                'How it works',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF00FF88),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            '1. Choose the screen or window you want to share\n'
            '2. Select video quality based on your network\n'
            '3. Start sharing to generate a room code\n'
            '4. Share the URL with viewers on your network',
            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildQualitySettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Video Quality',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildQualityOption(
                'Low',
                '720p • 24fps',
                'Better for slower networks',
                QualitySettings.low,
                Icons.network_cell,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildQualityOption(
                'Medium',
                '1080p • 30fps',
                'Balanced quality & performance',
                QualitySettings.medium,
                Icons.wifi_2_bar,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildQualityOption(
                'High',
                '1080p • 60fps',
                'Best quality for fast networks',
                QualitySettings.high,
                Icons.wifi,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQualityOption(
    String title,
    String specs,
    String description,
    QualitySettings quality,
    IconData icon,
  ) {
    final isSelected = selectedQuality.quality == quality.quality;

    return GestureDetector(
      onTap: () => setState(() => selectedQuality = quality),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF00FF88).withValues(alpha: 0.1)
              : const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF00FF88) : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? const Color(0xFF00FF88) : Colors.white70,
              size: 24,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isSelected ? const Color(0xFF00FF88) : Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              specs,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScreenSourcesSection(
    AsyncValue<List<ScreenSource>> screenSourcesAsync,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Available Screens & Windows',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        screenSourcesAsync.when(
          data: (sources) => _buildSourcesList(sources),
          loading: () => _buildLoadingState(),
          error: (error, stack) => _buildErrorState(error.toString()),
        ),
      ],
    );
  }

  Widget _buildSourcesList(List<ScreenSource> sources) {
    if (sources.isEmpty) {
      return _buildEmptyState();
    }

    return Column(
      children: sources
          .map(
            (source) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildSourceCard(source),
            ),
          )
          .toList(),
    );
  }

  Widget _buildSourceCard(ScreenSource source) {
    final isSelected = selectedSource?.id == source.id;

    return GestureDetector(
      onTap: () => setState(() => selectedSource = source),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF00FF88).withValues(alpha: 0.1)
              : const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF00FF88)
                : Colors.white.withValues(alpha: 0.1),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 80,
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFF3A3A3A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: source.thumbnail != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        source.thumbnail!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildDefaultThumbnail(source.type),
                      ),
                    )
                  : _buildDefaultThumbnail(source.type),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: isSelected
                          ? const Color(0xFF00FF88)
                          : Colors.white,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        _getSourceIcon(source.type),
                        size: 14,
                        color: Colors.white54,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _getSourceTypeLabel(source.type),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: Color(0xFF00FF88),
                size: 24,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultThumbnail(ScreenSourceType type) {
    return Icon(_getSourceIcon(type), color: Colors.white54, size: 24);
  }

  IconData _getSourceIcon(ScreenSourceType type) {
    switch (type) {
      case ScreenSourceType.screen:
        return Icons.monitor;
      case ScreenSourceType.window:
        return Icons.crop_landscape;
      case ScreenSourceType.application:
        return Icons.apps;
    }
  }

  String _getSourceTypeLabel(ScreenSourceType type) {
    switch (type) {
      case ScreenSourceType.screen:
        return 'Full Screen';
      case ScreenSourceType.window:
        return 'Window';
      case ScreenSourceType.application:
        return 'Application';
    }
  }

  Widget _buildLoadingState() {
    return Container(
      padding: const EdgeInsets.all(40),
      child: const Center(
        child: Column(
          children: [
            CircularProgressIndicator(color: Color(0xFF00FF88)),
            SizedBox(height: 16),
            Text(
              'Scanning for available screens and windows...',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 32),
          const SizedBox(height: 8),
          const Text(
            'Unable to detect screens',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            error,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => ref.refresh(screenSourcesProvider),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(40),
      child: const Center(
        child: Column(
          children: [
            Icon(
              Icons.desktop_access_disabled,
              color: Colors.white54,
              size: 48,
            ),
            SizedBox(height: 16),
            Text(
              'No screens or windows found',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Make sure you have granted screen recording permissions',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomActions() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Color(0xFF2A2A2A),
        border: Border(top: BorderSide(color: Colors.white12, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  selectedSource?.name ?? 'No screen selected',
                  style: TextStyle(
                    color: selectedSource != null
                        ? Colors.white
                        : Colors.white54,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (selectedSource != null)
                  Text(
                    '${selectedQuality.width}x${selectedQuality.height} • ${selectedQuality.frameRate}fps',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton(
            onPressed: selectedSource != null && !isCreating
                ? _startSharing
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00FF88),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: isCreating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                    ),
                  )
                : const Text(
                    'Start Sharing',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _startSharing() async {
    if (selectedSource == null) return;

    setState(() => isCreating = true);

    try {
      final roomActions = ref.read(roomActionsProvider);
      await roomActions.createRoom(
        screenSource: selectedSource!,
        qualitySettings: selectedQuality,
      );

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() => isCreating = false);
        _showErrorDialog(error.toString());
      }
    }
  }

  void _showErrorDialog(String error) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          'Failed to Start Sharing',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(error, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK', style: TextStyle(color: Color(0xFF00FF88))),
          ),
        ],
      ),
    );
  }
}
