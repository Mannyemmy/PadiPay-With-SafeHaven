import 'dart:convert';
import 'dart:io';

import 'package:card_app/ui/permission_explanation_sheet.dart';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kGeminiApiKey = 'AIzaSyAsQ8zSoIKzK89Qh8PwijvYOjp6486VRP8';

class AccountScanResult {
  final String? accountNumber;
  final String? bankName;

  const AccountScanResult({this.accountNumber, this.bankName});
}

/// Shows a privacy consent sheet (once per install) before letting the user
/// choose camera or gallery, then extracts account details via Gemini.
/// Returns [AccountScanResult] on success, or null if cancelled / failed.
Future<AccountScanResult?> scanAccountFromImage(BuildContext context) async {
  // Gate: show camera/gallery privacy notice on first use
  final prefs = await SharedPreferences.getInstance();
  final cameraConsented = prefs.getBool('privacy_consent_camera') ?? false;
  final galleryConsented = prefs.getBool('privacy_consent_gallery') ?? false;

  if (!cameraConsented || !galleryConsented) {
    bool userAgreed = false;
    if (!context.mounted) return null;
    await showModalBottomSheet(
      context: context,
      isDismissible: true,
      builder: (ctx) => PermissionExplanationSheet(
        type: PermissionType.camera,
        onContinue: () async {
          await prefs.setBool('privacy_consent_camera', true);
          await prefs.setBool('privacy_consent_gallery', true);
          userAgreed = true;
        },
      ),
    );
    if (!userAgreed) return null;
  }

  if (!context.mounted) return null;
  final ImageSource? source = await showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              'Scan Account Details',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Take or upload a photo of the account details',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF007AFF),
                child: Icon(Icons.camera_alt, color: Colors.white),
              ),
              title: const Text('Take a Photo'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF007AFF),
                child: Icon(Icons.photo_library, color: Colors.white),
              ),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    ),
  );

  if (source == null) return null;

  final picker = ImagePicker();
  final XFile? xFile = await picker.pickImage(
    source: source,
    imageQuality: 85,
    maxWidth: 1024,
  );
  if (xFile == null) return null;

  if (context.mounted) {
    // Show loading indicator while AI processes the image
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Extracting account details...'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  try {
    final imageBytes = await File(xFile.path).readAsBytes();

    final model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: _kGeminiApiKey,
    );

    const prompt = '''
Analyse this image which shows banking account details (handwritten or printed).
Extract the account number and bank name.

Return ONLY a valid JSON object with exactly these fields (no markdown, no explanation):
{"accountNumber":"<digits only>","bankName":"<bank name>"}

Rules:
- accountNumber must contain digits only (remove spaces, dashes, slashes).
- bankName should be the full bank name as written in the image.
- If a field cannot be determined, use null for its value.
''';

    final response = await model.generateContent([
      Content.multi([
        TextPart(prompt),
        DataPart('image/jpeg', imageBytes),
      ]),
    ]);

    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();

    final text = response.text?.trim() ?? '';
    debugPrint('Gemini response: $text');

    // Strip markdown code fences if present
    final cleaned = text
        .replaceAll(RegExp(r'^```json\s*', multiLine: true), '')
        .replaceAll(RegExp(r'^```\s*', multiLine: true), '')
        .trim();

    final Map<String, dynamic> json = jsonDecode(cleaned);
    return AccountScanResult(
      accountNumber: json['accountNumber']?.toString(),
      bankName: json['bankName']?.toString(),
    );
  } catch (e) {
    print('scanAccountFromImage error: $e');
    debugPrint('scanAccountFromImage error: $e');
    if (context.mounted) {
      try {
        Navigator.of(context, rootNavigator: true).pop();
      } catch (_) {}
      showModalBottomSheet(
        context: context,
        builder: (ctx) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            bottom: true,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Text(
                    'Error',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Could not extract account details: $e',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF007AFF),
                      ),
                      child: const Text(
                        'OK',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return null;
  }
}
