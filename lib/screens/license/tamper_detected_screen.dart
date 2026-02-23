import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';

class TamperDetectedScreen extends StatelessWidget {
  const TamperDetectedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.red[900],
      body: Center(
        child: Container(
          padding: EdgeInsets.all(32),
          constraints: BoxConstraints(maxWidth: 500),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.security, size: 100, color: Colors.white),
              SizedBox(height: 32),
              Text(
                'تم اكتشاف تلاعب بالنظام',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 16),
              Text(
                'تم رصد محاولة تغيير تاريخ النظام للتلاعب بصلاحية الترخيص.\n\n'
                'البرنامج محمي ضد هذا النوع من المحاولات.',
                style: TextStyle(color: Colors.white70, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 32),
              Card(
                color: Colors.white10,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(
                        'للتواصل مع الدعم الفني:',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      SelectableText(
                        'support@yourcompany.com\n+20 XXX XXX XXXX',
                        style: TextStyle(
                          color: Colors.white70,
                          fontFamily: 'monospace',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  // Exit app only on desktop
                  if (!kIsWeb) {
                    exit(0);
                  }
                  // On web, do nothing or show a message
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.red[900],
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
                child: Text('إغلاق البرنامج'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
