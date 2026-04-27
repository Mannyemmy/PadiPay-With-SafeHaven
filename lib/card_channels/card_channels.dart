
import 'package:card_app/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ChangeCardChannelsPage extends StatefulWidget {
  final Map<String, dynamic> card;
  const ChangeCardChannelsPage({super.key, required this.card});

  @override
  State<ChangeCardChannelsPage> createState() => _ChangeCardChannelsPageState();
}

class _ChangeCardChannelsPageState extends State<ChangeCardChannelsPage> {
  bool _posEnabled = true;
  bool _atmEnabled = true;
  bool _webEnabled = true;
  bool _loading = true;
  bool _saving = false;

  String? get _firestoreDocId =>
      (widget.card['firestoreDocId'] ?? widget.card['id'])?.toString();

  @override
  void initState() {
    super.initState();
    _loadChannels();
  }

  Future<void> _loadChannels() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final docId = _firestoreDocId;
    if (uid == null || docId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('cards')
          .doc(docId)
          .get();
      final channels = snap.data()?['channels'] as Map<String, dynamic>?;
      if (mounted) {
        setState(() {
          _posEnabled = channels?['pos'] != false;
          _atmEnabled = channels?['atm'] != false;
          _webEnabled = channels?['web'] != false;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveChannel(String channel, bool value) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final docId = _firestoreDocId;
    if (uid == null || docId == null) return;
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('cards')
          .doc(docId)
          .update({'channels.$channel': value});
    } catch (e) {
      if (mounted) showSimpleDialog('Failed to update channel setting: $e', Colors.red);
      // Revert toggle
      if (mounted) {
        setState(() {
          if (channel == 'pos') _posEnabled = !value;
          if (channel == 'atm') _atmEnabled = !value;
          if (channel == 'web') _webEnabled = !value;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            decoration: const BoxDecoration(
              color: navyBlue,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
                ),
                const SizedBox(height: 60),
                const Text(
                  'Card Channels',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Control where your card can be used',
                  style: TextStyle(fontSize: 13, color: Colors.white70),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: primaryColor, borderRadius: BorderRadius.circular(4)),
                      child: const Icon(Icons.payment, color: Colors.white, size: 20),
                    ),
                    title: const Text('POS'),
                    subtitle: const Text('Allow this card to work on POS terminals'),
                    value: _posEnabled,
                    onChanged: _saving ? null : (val) {
                      setState(() => _posEnabled = val);
                      _saveChannel('pos', val);
                    },
                  ),
                  SwitchListTile(
                    secondary: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: primaryColor, borderRadius: BorderRadius.circular(4)),
                      child: const Icon(Icons.atm, color: Colors.white, size: 20),
                    ),
                    title: const Text('ATM'),
                    subtitle: const Text('Allow this card to work on ATMs'),
                    value: _atmEnabled,
                    onChanged: _saving ? null : (val) {
                      setState(() => _atmEnabled = val);
                      _saveChannel('atm', val);
                    },
                  ),
                  SwitchListTile(
                    secondary: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: primaryColor, borderRadius: BorderRadius.circular(4)),
                      child: const Icon(Icons.web, color: Colors.white, size: 20),
                    ),
                    title: const Text('Web / Online'),
                    subtitle: const Text('Allow this card to work on online stores'),
                    value: _webEnabled,
                    onChanged: _saving ? null : (val) {
                      setState(() => _webEnabled = val);
                      _saveChannel('web', val);
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
