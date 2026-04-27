import 'dart:io';

import 'package:card_app/ui/permission_explanation_sheet.dart';
import 'package:card_app/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class RequiredDocumentsPage extends StatefulWidget {
  final List<Map<String, dynamic>> requiredDocuments;

  const RequiredDocumentsPage({super.key, required this.requiredDocuments});

  @override
  State<RequiredDocumentsPage> createState() => _RequiredDocumentsPageState();
}

class _RequiredDocumentsPageState extends State<RequiredDocumentsPage> {
  List<Map<String, dynamic>> _documents = [];
  final Map<String, bool> _uploading = {};
  final ImagePicker _picker = ImagePicker();
  String? _customerId;
  bool _loading = false;

  bool get _hasPendingDocs => _documents.any(
        (d) => (d['status'] ?? '').toString().toLowerCase() == 'pending',
      );

  @override
  void initState() {
    super.initState();
    _documents = List<Map<String, dynamic>>.from(widget.requiredDocuments);
    _loadLatest();
  }

  Future<void> _loadLatest() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      setState(() => _loading = true);
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!snap.exists) return;
      final data = snap.data() as Map<String, dynamic>;
      final docs =
          (data['requiredDocuments'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .toList() ??
          [];
      setState(() {
        _documents = docs;
        _customerId = data['getAnchorData']?['customerCreation']?['data']?['id']
            ?.toString();
      });
    } catch (e) {
      print('Error loading required documents: $e');
      showSimpleDialog('Failed to load documents', Colors.red);
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<XFile?> _pickImageWithConsent(BuildContext ctx) async {
    final prefs = await SharedPreferences.getInstance();
    final consented = prefs.getBool('privacy_consent_gallery') ?? false;
    if (!consented) {
      bool agreed = false;
      if (!ctx.mounted) return null;
      await showModalBottomSheet(
        context: ctx,
        isDismissible: true,
        builder: (bsCtx) => PermissionExplanationSheet(
          type: PermissionType.gallery,
          onContinue: () async {
            await prefs.setBool('privacy_consent_gallery', true);
            agreed = true;
          },
        ),
      );
      if (!agreed) return null;
    }
    return _picker.pickImage(source: ImageSource.gallery);
  }

  Future<void> _uploadDocument(Map<String, dynamic> doc) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      showSimpleDialog('No authenticated user', Colors.red);
      return;
    }
    final docId = (doc['anchorId'] ?? doc['type'] ?? '').toString();
    if (docId.isEmpty) {
      showSimpleDialog('Missing document id', Colors.red);
      return;
    }
    if (_customerId == null || _customerId!.isEmpty) {
      showSimpleDialog('Customer ID missing', Colors.red);
      return;
    }

    final picked = await _pickImageWithConsent(context);
    if (picked == null) return;

    setState(() => _uploading[docId] = true);
    try {
      final storagePath =
          'required_documents/${user.uid}/${docId}_${DateTime.now().millisecondsSinceEpoch}${p.extension(picked.path)}';
      final ref = FirebaseStorage.instance.ref().child(storagePath);
      await ref.putFile(File(picked.path));

      final callable = FirebaseFunctions.instance.httpsCallable(
        'uploadDocument',
      );
      await callable.call({
        'customerId': _customerId,
        'documentId': docId,
        'storagePath': storagePath,
        'fileName': p.basename(picked.path),
      });

      final updatedDocs = _documents.map((d) {
        final currentId = (d['anchorId'] ?? d['type'] ?? '').toString();
        if (currentId == docId) {
          return {
            ...d,
            'status': 'submitted',
            'storagePath': storagePath,
            'fileName': p.basename(picked.path),
          };
        }
        return d;
      }).toList();

      await FirebaseFirestore.instance.collection('users').doc(user.uid).update(
        {'requiredDocuments': updatedDocs},
      );

      setState(() {
        _documents = updatedDocs;
      });
      _maybeFinish();
      showSimpleDialog('Document uploaded', Colors.green);
    } catch (e) {
      print('Upload failed: $e');
      showSimpleDialog('Upload failed: $e', Colors.red);
    } finally {
      setState(() => _uploading.remove(docId));
    }
  }

  void _maybeFinish() {
    if (!_hasPendingDocs) {
      Navigator.of(context).pop(true);
    }
  }

  Widget _statusChip(String status) {
    final normalized = status.toLowerCase();
    Color bg;
    Color fg;
    String label;
    if (normalized == 'pending') {
      bg = Colors.orange.shade100;
      fg = Colors.orange.shade800;
      label = 'Needs Submission';
    } else if (normalized == 'submitted') {
      bg = Colors.blue.shade100;
      fg = Colors.blue.shade800;
      label = 'Submitted';
    } else if (normalized == 'approved') {
      bg = Colors.green.shade100;
      fg = Colors.green.shade800;
      label = 'Approved';
    } else {
      bg = Colors.grey.shade200;
      fg = Colors.grey.shade800;
      label = status.isEmpty ? 'Unknown' : status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(color: fg, fontSize: 12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Submit Documents'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      backgroundColor: Colors.white,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) {
                final doc = _documents[index];
                final title = doc['type']?.toString() ?? 'Document';
                final description =
                    doc['description']?.toString() ?? 'No description provided';
                final status = doc['status']?.toString() ?? 'pending';
                final normalized = status.toLowerCase();
                final isPending = normalized == 'pending';
                final isSubmitted = normalized == 'submitted';
                final docId = (doc['anchorId'] ?? doc['type'] ?? '').toString();
                final uploading = _uploading[docId] == true;

                return Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            _statusChip(status),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          description,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: (isSubmitted || uploading)
                                ? null
                                : () => _uploadDocument(doc),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isSubmitted
                                  ? Colors.orange.shade200
                                  : primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: uploading
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(isSubmitted ? 'Pending review' : 'Upload'),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemCount: _documents.length,
            ),
    );
  }
}
