import 'package:card_app/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// ignore_for_file: unused_element, unused_field, dead_code, unnecessary_cast, unused_import

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

String _normKey(String name) => name
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
    .replaceAll(RegExp(r'^_+|_+$'), '');

class SubscriptionsPage extends StatefulWidget {
  final Map<String, dynamic> card;
  const SubscriptionsPage({super.key, required this.card});

  @override
  State<SubscriptionsPage> createState() => _SubscriptionsPageState();
}

class _SubscriptionsPageState extends State<SubscriptionsPage> {
  bool _loading = true;
  List<_SubEntry> _subs = [];

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
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('card_subscriptions')
          .orderBy('lastChargedAt', descending: true)
          .get();

      // Also load blocked merchants for this card
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
            if (v == false) blocked[k] = true;
          });
        }
      }

      final entries = snap.docs.map((d) {
        final data = d.data();
        return _SubEntry(
          id: d.id,
          merchantKey: data['merchantKey'] as String? ?? d.id,
          merchantName: data['merchantName'] as String? ?? d.id,
          lastAmount: (data['lastAmount'] as num?)?.toDouble() ?? 0,
          currency: data['currency'] as String? ?? 'NGN',
          lastChargedAt: (data['lastChargedAt'] as Timestamp?)?.toDate(),
          estimatedNextChargeAt:
              (data['estimatedNextChargeAt'] as Timestamp?)?.toDate(),
          reminderEnabled: data['reminderEnabled'] as bool? ?? true,
          reminderDaysBefore: data['reminderDaysBefore'] as int? ?? 3,
          isBlocked: blocked[data['merchantKey'] as String? ?? d.id] == true,
        );
      }).toList();

      if (mounted) setState(() {
        _subs = entries;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        showSimpleDialog('Failed to load subscriptions: $e', Colors.red);
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _setReminderEnabled(
      _SubEntry sub, bool enabled) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('card_subscriptions')
          .doc(sub.id)
          .update({'reminderEnabled': enabled});
      if (mounted) {
        setState(() {
          final idx = _subs.indexWhere((s) => s.id == sub.id);
          if (idx != -1) {
            _subs[idx] = _subs[idx].copyWith(reminderEnabled: enabled);
          }
        });
      }
    } catch (e) {
      if (mounted) showSimpleDialog('Update failed: $e', Colors.red);
    }
  }

  Future<void> _setReminderDays(_SubEntry sub, int days) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('card_subscriptions')
          .doc(sub.id)
          .update({'reminderDaysBefore': days});
      if (mounted) {
        setState(() {
          final idx = _subs.indexWhere((s) => s.id == sub.id);
          if (idx != -1) {
            _subs[idx] = _subs[idx].copyWith(reminderDaysBefore: days);
          }
        });
      }
    } catch (e) {
      if (mounted) showSimpleDialog('Update failed: $e', Colors.red);
    }
  }

  Future<void> _toggleBlock(_SubEntry sub) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final docId = _firestoreDocId;
    if (uid == null || docId == null || docId.isEmpty) return;

    try {
      final key = sub.merchantKey;
      if (!sub.isBlocked) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('cards')
            .doc(docId)
            .update({'blockedMerchants.$key': false}); // false = blocked
      } else {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('cards')
            .doc(docId)
            .update({'blockedMerchants.$key': FieldValue.delete()});
      }
      if (mounted) {
        setState(() {
          final idx = _subs.indexWhere((s) => s.id == sub.id);
          if (idx != -1) {
            _subs[idx] = _subs[idx].copyWith(isBlocked: !sub.isBlocked);
          }
        });
        final action = sub.isBlocked ? 'unblocked' : 'blocked';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${sub.merchantName} $action on this card')),
        );
      }
    } catch (e) {
      if (mounted) showSimpleDialog('Failed to update merchant: $e', Colors.red);
    }
  }

  String _formatCurrency(double amount, String currency) {
    final symbol = currency == 'NGN' ? '₦' : '\$';
    return '$symbol${NumberFormat('#,##0.00', 'en_NG').format(amount)}';
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    return DateFormat('d MMM yyyy').format(dt);
  }

  String _daysUntilLabel(DateTime? dt) {
    if (dt == null) return 'Unknown';
    final diff = dt.difference(DateTime.now());
    if (diff.isNegative) return 'Overdue';
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Tomorrow';
    return 'In ${diff.inDays} days';
  }

  Color _nextChargeColor(DateTime? dt) {
    if (dt == null) return Colors.grey;
    final diff = dt.difference(DateTime.now()).inDays;
    if (diff < 0) return Colors.grey;
    if (diff <= 3) return Colors.orange.shade700;
    if (diff <= 7) return Colors.amber.shade700;
    return Colors.green.shade700;
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
                  'Subscriptions',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Recurring merchants detected on your cards',
                  style: TextStyle(fontSize: 13, color: Colors.white70),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_subs.isEmpty)
            const Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No recurring charges detected yet.\nUse your card and we\'ll track subscription patterns here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: _subs.length,
                itemBuilder: (context, i) => _SubCard(
                  sub: _subs[i],
                  formatCurrency: _formatCurrency,
                  formatDate: _formatDate,
                  daysUntilLabel: _daysUntilLabel,
                  nextChargeColor: _nextChargeColor,
                  onToggleReminder: (val) =>
                      _setReminderEnabled(_subs[i], val),
                  onReminderDaysChanged: (days) =>
                      _setReminderDays(_subs[i], days),
                  onToggleBlock: () => _toggleBlock(_subs[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Data class ────────────────────────────────────────────────────────────────

class _SubEntry {
  final String id;
  final String merchantKey;
  final String merchantName;
  final double lastAmount;
  final String currency;
  final DateTime? lastChargedAt;
  final DateTime? estimatedNextChargeAt;
  final bool reminderEnabled;
  final int reminderDaysBefore;
  final bool isBlocked;

  const _SubEntry({
    required this.id,
    required this.merchantKey,
    required this.merchantName,
    required this.lastAmount,
    required this.currency,
    this.lastChargedAt,
    this.estimatedNextChargeAt,
    required this.reminderEnabled,
    required this.reminderDaysBefore,
    required this.isBlocked,
  });

  _SubEntry copyWith({
    bool? reminderEnabled,
    int? reminderDaysBefore,
    bool? isBlocked,
  }) =>
      _SubEntry(
        id: id,
        merchantKey: merchantKey,
        merchantName: merchantName,
        lastAmount: lastAmount,
        currency: currency,
        lastChargedAt: lastChargedAt,
        estimatedNextChargeAt: estimatedNextChargeAt,
        reminderEnabled: reminderEnabled ?? this.reminderEnabled,
        reminderDaysBefore: reminderDaysBefore ?? this.reminderDaysBefore,
        isBlocked: isBlocked ?? this.isBlocked,
      );
}

// ── Card widget ───────────────────────────────────────────────────────────────

class _SubCard extends StatelessWidget {
  final _SubEntry sub;
  final String Function(double, String) formatCurrency;
  final String Function(DateTime?) formatDate;
  final String Function(DateTime?) daysUntilLabel;
  final Color Function(DateTime?) nextChargeColor;
  final ValueChanged<bool> onToggleReminder;
  final ValueChanged<int> onReminderDaysChanged;
  final VoidCallback onToggleBlock;

  const _SubCard({
    required this.sub,
    required this.formatCurrency,
    required this.formatDate,
    required this.daysUntilLabel,
    required this.nextChargeColor,
    required this.onToggleReminder,
    required this.onReminderDaysChanged,
    required this.onToggleBlock,
  });

  @override
  Widget build(BuildContext context) {
    final nextColor = nextChargeColor(sub.estimatedNextChargeAt);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Merchant name + block button
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: navyBlue.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.storefront_outlined,
                      color: navyBlue, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    sub.merchantName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                if (sub.isBlocked)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      border: Border.all(color: Colors.red.shade200),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('Blocked',
                        style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Amount + last charge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _InfoPair(
                  label: 'Last charge',
                  value: formatCurrency(sub.lastAmount, sub.currency),
                ),
                _InfoPair(
                  label: 'Charged on',
                  value: formatDate(sub.lastChargedAt),
                  align: TextAlign.right,
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Next expected charge
            if (sub.estimatedNextChargeAt != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Next expected charge',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                  Row(
                    children: [
                      Text(
                        daysUntilLabel(sub.estimatedNextChargeAt),
                        style: TextStyle(
                            color: nextColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '(${formatDate(sub.estimatedNextChargeAt)})',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            const Divider(height: 1),
            const SizedBox(height: 8),

            // Reminder toggle + days
            Row(
              children: [
                const Icon(Icons.notifications_outlined,
                    size: 18, color: Colors.grey),
                const SizedBox(width: 6),
                const Text('Remind me',
                    style: TextStyle(fontSize: 13, color: Colors.grey)),
                const Spacer(),
                if (sub.reminderEnabled) ...[
                  DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: sub.reminderDaysBefore,
                      isDense: true,
                      style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                          fontFamily: 'Poppins'),
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('1 day before')),
                        DropdownMenuItem(value: 3, child: Text('3 days before')),
                        DropdownMenuItem(value: 7, child: Text('1 week before')),
                      ],
                      onChanged: (v) {
                        if (v != null) onReminderDaysChanged(v);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Switch(
                  value: sub.reminderEnabled,
                  onChanged: onToggleReminder,
                  activeColor: navyBlue,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Block / Unblock button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onToggleBlock,
                icon: Icon(
                  sub.isBlocked
                      ? Icons.lock_open_outlined
                      : Icons.block_outlined,
                  size: 16,
                  color: sub.isBlocked
                      ? Colors.green.shade700
                      : Colors.red.shade700,
                ),
                label: Text(
                  sub.isBlocked
                      ? 'Unblock this merchant'
                      : 'Block this merchant on this card',
                  style: TextStyle(
                    fontSize: 13,
                    color: sub.isBlocked
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: sub.isBlocked
                        ? Colors.green.shade200
                        : Colors.red.shade200,
                  ),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoPair extends StatelessWidget {
  final String label;
  final String value;
  final TextAlign align;

  const _InfoPair({
    required this.label,
    required this.value,
    this.align = TextAlign.left,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: align == TextAlign.right
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(label,
            textAlign: align,
            style: const TextStyle(color: Colors.grey, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value,
            textAlign: align,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 14)),
      ],
    );
  }
}
