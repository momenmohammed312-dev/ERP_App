import 'package:flutter/material.dart';
import '../services/update_service.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo update;

  const UpdateDialog({super.key, required this.update});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _statusMessage = '';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            widget.update.isCritical ? Icons.warning : Icons.system_update,
            color: widget.update.isCritical ? Colors.red : Colors.blue,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.update.isCritical ? 'تحديث مهم متاح' : 'تحديث جديد متاح',
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Version info
            Text(
              'الإصدار ${widget.update.version}',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 4),
            Text(
              'الحجم: ${widget.update.sizeString}',
              style: TextStyle(color: Colors.grey[600]),
            ),

            if (widget.update.isCritical) ...[
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error, color: Colors.red),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'هذا تحديث أمني مهم - يُنصح بشدة بتثبيته فوراً',
                        style: TextStyle(color: Colors.red[900]),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            SizedBox(height: 16),

            // Changelog
            Text('ما الجديد:', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            ...widget.update.changelog.map(
              (item) => Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• '),
                    Expanded(child: Text(item)),
                  ],
                ),
              ),
            ),

            // Features
            if (widget.update.features.isNotEmpty) ...[
              SizedBox(height: 16),
              Text(
                'ميزات جديدة:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              ...widget.update.features.map(
                (item) => Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.star, size: 16, color: Colors.orange),
                      SizedBox(width: 4),
                      Expanded(child: Text(item)),
                    ],
                  ),
                ),
              ),
            ],

            // Download progress
            if (_isDownloading) ...[
              SizedBox(height: 16),
              LinearProgressIndicator(value: _downloadProgress),
              SizedBox(height: 8),
              Text(
                _statusMessage,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ],
        ),
      ),
      actions: _isDownloading
          ? [] // No buttons while downloading
          : [
              if (!widget.update.isCritical)
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('لاحقاً'),
                ),
              ElevatedButton(
                onPressed: _downloadAndInstall,
                child: Text('تحديث الآن'),
              ),
            ],
    );
  }

  Future<void> _downloadAndInstall() async {
    setState(() {
      _isDownloading = true;
      _statusMessage = 'جاري التحميل...';
    });

    try {
      final updateService = UpdateService();

      // Download
      final file = await updateService.downloadUpdate(widget.update, (
        progress,
      ) {
        setState(() {
          _downloadProgress = progress;
          _statusMessage = 'تحميل: ${(progress * 100).toStringAsFixed(0)}%';
        });
      });

      if (file == null) {
        throw Exception('Download failed');
      }

      setState(() {
        _statusMessage = 'جاري التثبيت...';
      });

      // Install (will exit app)
      await updateService.installUpdate(file);
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _statusMessage = '';
      });

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('خطأ'),
            content: Text('فشل التحديث: $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('حسناً'),
              ),
            ],
          ),
        );
      }
    }
  }
}
