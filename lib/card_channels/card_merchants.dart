import 'package:card_app/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

String _normalizeMerchantKey(String name) {
  return name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}

class ManageMerchantsPage extends StatefulWidget {
  final Map<String, dynamic> card;
  const ManageMerchantsPage({super.key, required this.card});

  @override
  State<ManageMerchantsPage> createState() => _ManageMerchantsPageState();
}

class _ManageMerchantsPageState extends State<ManageMerchantsPage> {
  bool _loading = true;
  bool _saving = false;

  /// key → display name (e.g. 'netflix_com' → 'NETFLIX.COM')
  Map<String, String> _merchantNames = {};

  /// key → true when that merchant is blocked on this card
  Map<String, bool> _blocked = {};

  String? get _firestoreDocId =>
      (widget.card['firestoreDocId'] ?? widget.card['id'])?.toString();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      // 1. Collect unique merchants from ALL card transactions for this user.
      final txSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('transactions')
          .where('source', isEqualTo: 'sudo_card')
          .get();

      final Map<String, String> names = {};
      for (final doc in txSnap.docs) {
        final raw = doc.data()['merchant']?.toString() ?? '';
        if (raw.isEmpty || raw == 'Unknown merchant') continue;
        final key = _normalizeMerchantKey(raw);
        if (key.isNotEmpty) names[key] = raw;
      }

      // 2. Load blocked merchants for this specific card.
      Map<String, bool> blocked = {};
      final docId = _firestoreDocId;
      if (docId != null && docId.isNotEmpty) {
        final cardSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('cards')
            .doc(docId)
            .get();
        final bm =
            cardSnap.data()?['blockedMerchants'] as Map<String, dynamic>?;
        if (bm != null) {
          bm.forEach((k, v) {
            if (v == false) blocked[k] = true; // false in Firestore = blocked
          });
        }
      }

      if (mounted) {
        setState(() {
          _merchantNames = names;
          _blocked = blocked;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        showSimpleDialog('Failed to load merchants: $e', Colors.red);
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _toggleMerchant(String key, {required bool block}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final docId = _firestoreDocId;
    if (uid == null || docId == null || docId.isEmpty) return;

    setState(() => _saving = true);
    try {
      if (block) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('cards')
            .doc(docId)
            .update({'blockedMerchants.$key': false}); // false = blocked
        if (mounted) setState(() => _blocked[key] = true);
      } else {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('cards')
            .doc(docId)
            .update({'blockedMerchants.$key': FieldValue.delete()});
        if (mounted) setState(() => _blocked.remove(key));
      }
    } catch (e) {
      if (mounted) {
        showSimpleDialog('Failed to update merchant setting: $e', Colors.red);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final merchants = _merchantNames.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            decoration: const BoxDecoration(
              color: navyBlue,
              borderRadius:
                  BorderRadius.vertical(bottom: Radius.circular(20)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.arrow_back_ios,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(height: 60),
                const Text(
                  'Manage Merchants',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Block specific merchants on this card',
                  style: TextStyle(fontSize: 13, color: Colors.white70),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (merchants.isEmpty)
            const Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No merchants yet.\nMerchants will appear here after your card is used.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: merchants.length,
                itemBuilder: (context, i) {
                  final key = merchants[i].key;
                  final displayName = merchants[i].value;
                  final isBlocked = _blocked[key] == true;
                  return SwitchListTile(
                    secondary: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isBlocked
                            ? Colors.red.shade100
                            : primaryColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(
                        Icons.storefront,
                        color: isBlocked ? Colors.red : Colors.white,
                        size: 20,
                      ),
                    ),
                    title: Text(displayName),
                    subtitle: Text(isBlocked
                        ? 'Blocked on this card'
                        : 'Allowed on this card'),
                    value: !isBlocked, // ON = allowed, OFF = blocked
                    onChanged: _saving
                        ? null
                        : (val) =>
                            _toggleMerchant(key, block: !val),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
