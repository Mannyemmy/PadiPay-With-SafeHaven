import 'package:card_app/home_pages/card_page.dart';
import 'package:card_app/home_pages/home_page.dart';
import 'package:card_app/home_pages/transactions_page.dart';
import 'package:card_app/profile/profile_page.dart';
import 'package:card_app/ui/bottom_nav_bar.dart';
import 'package:card_app/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  int _selectedIndex = 4;
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _markAllAsRead();
  }

  Future<void> _markAllAsRead() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final unread = await _firestore
          .collection('users')
          .doc(uid)
          .collection('notifications')
          .where('read', isEqualTo: false)
          .get();
      final batch = _firestore.batch();
      for (final doc in unread.docs) {
        batch.update(doc.reference, {'read': true});
      }
      await batch.commit();
    } catch (_) {}
  }

  Color _colorForType(String? type) {
    switch (type) {
      case 'transfer_sent':
      case 'transfer_received':
      case 'payment_received':
      case 'bill_success':
      case 'card_created':
        return primaryColor;
      case 'transfer_failed':
      case 'bill_failed':
      case 'login':
      case 'card_failed':
        return const Color(0xFFC20013);
      default:
        return const Color(0xFF9000FF);
    }
  }

  String _relativeTime(Timestamp? ts) {
    if (ts == null) return '';
    final now = DateTime.now();
    final date = ts.toDate();
    final diff = now.difference(date);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} minute${diff.inMinutes == 1 ? '' : 's'} ago';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    }
    return DateFormat('MMM d, y').format(date);
  }

  String _formatAmount(dynamic amount) {
    if (amount == null) return '';
    final num val = (amount is num)
        ? amount
        : num.tryParse(amount.toString()) ?? 0;
    if (val == 0) return '';
    return '\u20A6${NumberFormat('#,##0.##').format(val)}';
  }

  void _showDetail(BuildContext context, Map<String, dynamic> data) {
    final type = data['type'] as String?;
    final title = data['title'] as String? ?? '';
    final body = data['body'] as String? ?? '';
    final ts = data['timestamp'] as Timestamp?;
    final amount = data['amount'];
    final color = _colorForType(type);
    final amountStr = _formatAmount(amount);
    final dateStr = ts != null
        ? DateFormat('MMMM d, y • HH:mm').format(ts.toDate())
        : '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.notifications_outlined,
                    color: color,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (body.isNotEmpty) ...[
              Text(
                body,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (amountStr.isNotEmpty) _detailRow('Amount', amountStr),
            if (type != null)
              _detailRow('Type', type.replaceAll('_', ' ').toUpperCase()),
            if (dateStr.isNotEmpty) _detailRow('Date', dateStr),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context, Map<String, dynamic> data) {
    final type = data['type'] as String?;
    final title = data['title'] as String? ?? '';
    final body = data['body'] as String? ?? '';
    final ts = data['timestamp'] as Timestamp?;
    final amount = data['amount'];
    final color = _colorForType(type);
    final amountStr = _formatAmount(amount);

    return GestureDetector(
      onTap: () => _showDetail(context, data),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(15),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 0),
        child: IntrinsicHeight(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 10),
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        fontSize: 16,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      body,
                      style: const TextStyle(
                        fontWeight: FontWeight.w300,
                        color: Colors.white,
                        fontSize: 12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _relativeTime(ts),
                      style: const TextStyle(
                        fontWeight: FontWeight.w300,
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
              if (amountStr.isNotEmpty)
                SizedBox(
                  width: 110,
                  height: double.infinity,
                  child: Stack(
                    children: [
                      Image.asset("assets/wavy_line.png", fit: BoxFit.fill),
                      Positioned.fill(
                        child: Align(
                          alignment: Alignment.center,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 5),
                            child: Text(
                              amountStr,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                SizedBox(
                  width: 100,
                  height: double.infinity,
                  child: Image.asset("assets/wavy_line.png", fit: BoxFit.fill),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = _auth.currentUser?.uid;
    return Scaffold(
      body: SizedBox.expand(
        child: Stack(
          children: [
            Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: navyBlue,
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(20),
                    ),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 100),
                      Text(
                        'Notifications',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 20),
                    ],
                  ),
                ),
                Expanded(
                  child: uid == null
                      ? const Center(child: Text('Not signed in'))
                      : StreamBuilder<QuerySnapshot>(
                          stream: _firestore
                              .collection('users')
                              .doc(uid)
                              .collection('notifications')
                              .orderBy('timestamp', descending: true)
                              .limit(50)
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }

                            final docs = snapshot.data?.docs ?? [];

                            if (docs.isEmpty) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(32.0),
                                  child: Text(
                                    'No notifications yet.\nYour activity will appear here.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.black54,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              );
                            }

                            final unreadCount = docs.where((d) {
                              final data = d.data() as Map<String, dynamic>;
                              return data['read'] == false;
                            }).length;

                            return ListView.separated(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                20,
                                16,
                                100,
                              ),
                              itemCount: docs.length + 1,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                if (index == 0) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Text(
                                      unreadCount > 0
                                          ? '$unreadCount Unread'
                                          : 'All caught up',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black87,
                                        fontSize: 16,
                                      ),
                                    ),
                                  );
                                }
                                final data =
                                    docs[index - 1].data()
                                        as Map<String, dynamic>;
                                return _buildCard(context, data);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
            Positioned(
              bottom: 25,
              left: 0,
              right: 0,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: BottomNavBar(
                  currentIndex: _selectedIndex,
                  onTap: (index) {
                    if (index == 0) {
                      navigateTo(
                        context,
                        HomePage(),
                        type: NavigationType.push,
                      );
                    } else if (index == 1) {
                      navigateTo(
                        context,
                        CardsPage(),
                        type: NavigationType.push,
                      );
                    } else if (index == 2) {
                      navigateTo(
                        context,
                        TransactionsPage(),
                        type: NavigationType.push,
                      );
                    } else if (index == 3) {
                      navigateTo(
                        context,
                        ProfilePage(),
                        type: NavigationType.push,
                      );
                    } else {
                      setState(() => _selectedIndex = index);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
