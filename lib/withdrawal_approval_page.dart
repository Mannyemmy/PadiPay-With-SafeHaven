import 'package:card_app/home_pages/home_page.dart';
import 'package:card_app/ui/payment_successful_page.dart';
import 'package:card_app/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

class WithdrawalApprovalPage extends StatefulWidget {
  final String requestId;
  const WithdrawalApprovalPage({super.key, required this.requestId});
  @override
  State<WithdrawalApprovalPage> createState() => _WithdrawalApprovalPageState();
}
class _WithdrawalApprovalPageState extends State<WithdrawalApprovalPage> {
  bool isLoading = false;
  String? storedPin;
  double? amount;
  String? initiatorName;
  String? recipientAccountName;
  String? recipientBankName;
  String? recipientBankCode;
  String? recipientAccountNumber;
  String? recipientUid;
  String? recipientCollection;
  Map<String, dynamic>? initiatorDetails;
  DateTime? createdAt;
  String pinInput = '';
  String? counterpartyId;
  @override
  void initState() {
    super.initState();
    _loadRequestDetails();
  }
  Future<void> _loadRequestDetails() async {
    final doc = await FirebaseFirestore.instance
        .collection('pending_withdrawals')
        .doc(widget.requestId)
        .get();
    if (doc.exists) {
      final data = doc.data()!;
      setState(() {
        storedPin = data['pin'] as String?;
        amount = data['amount'] as double?;
        initiatorName = data['initiatorName'] as String? ?? 'Unknown';
        initiatorDetails = data['initiatorDetails'] as Map<String, dynamic>?;
        recipientAccountName = data['recipientAccountName'] as String?;
        recipientBankName = data['recipientBankName'] as String?;
        recipientBankCode = data['recipientBankCode'] as String?;
        recipientAccountNumber = data['recipientAccountNumber'] as String?;
        recipientUid = data['recipientUid'] as String?;
        recipientCollection = data['recipientCollection'] as String?;
        createdAt = (data['createdAt'] as Timestamp?)?.toDate();
      });
      if (data['status'] != 'pending' || storedPin == null) {
        showSimpleDialog('Request no longer valid', Colors.red);
        Navigator.pop(context);
      }
    }
  }
  Future<Map<String, String?>> getCurrentAccountIdAndType() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return {'accountId': null, 'accountType': null, 'bankId': null};

    

    final DocumentSnapshot<Map<String, dynamic>> userSnap =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();

    if (userSnap.exists && userSnap.data() != null) {
      final data = userSnap.data()!;
      final Map<String, dynamic>? virtualAccData =
          data['getAnchorData']?['virtualAccount']?['data'] as Map<String, dynamic>?;

      if (virtualAccData != null && virtualAccData['id'] != null) {
        final bankMap = virtualAccData['attributes']?['bank'] as Map<String, dynamic>?;
        final bankIdRaw = bankMap?['id']?.toString();
        final bankName = bankMap?['name']?.toString();
        final resolvedBankId = await resolveBankId(bankId: bankIdRaw, bankName: bankName);

        return {
          'accountId': virtualAccData['id'] as String,
          'accountType': virtualAccData['type'] as String?,
          'bankId': resolvedBankId,
        };
      }
    }

    return {'accountId': null, 'accountType': null, 'bankId': null};
  }
  Future<void> _createCounterparty() async {
    if (recipientAccountName == null || recipientBankCode == null || recipientAccountNumber == null) {
      showSimpleDialog('Recipient details incomplete', Colors.red);
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        showSimpleDialog('No authenticated user found', Colors.red);
        return;
      }

      final details = await getCurrentAccountIdAndType();
      final String? accountId = details['accountId'];
      final String? accountType = details['accountType'];
      final String? bankId = details['bankId'];

      if (accountId == null || accountId.isEmpty) {
        showSimpleDialog('Account ID not found', Colors.red);
        return;
      }
      if (bankId == null || bankId.isEmpty) {
        showSimpleDialog('Bank ID not found', Colors.red);
        return;
      }
      if (accountType == null) {
        showSimpleDialog('Account Type not found', Colors.red);
        return;
      }

      // Check if counterparty already exists
      final query = await FirebaseFirestore.instance.collection('counterparties')
          .where('userId', isEqualTo: user.uid)
          .where('recipientAccountNumber', isEqualTo: recipientAccountNumber)
          .where('recipientBankCode', isEqualTo: recipientBankCode)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        setState(() {
          counterpartyId = query.docs.first.id;
        });
        return;
      }

      final result = await FirebaseFunctions.instance
          .httpsCallable('sudoCreateCounterparty')
          .call({
        'accountId': accountId,
        'bankId': recipientBankCode,
        'accountType': accountType,
        'accountName': recipientAccountName,
        'bankName': recipientBankName,
        'accountNumber': recipientAccountNumber,
        'bankCode': recipientBankCode,
      });
      final counterpartyIdd = result.data['data']['id'];
      await FirebaseFirestore.instance
          .collection('counterparties')
          .doc(counterpartyIdd)
          .set({
        ...result.data,
        'userId': user.uid,
        'recipientAccountNumber': recipientAccountNumber,
        'recipientBankCode': recipientBankCode,
        'ownerAccountId': accountId,
      });

      setState(() {
        counterpartyId = counterpartyIdd;
      });
    } catch (e) {
      debugPrint('createCounterparty error: $e');
      showSimpleDialog('Error creating counterparty', Colors.red);
    }
  }
  Future<void> _createNipTransfer() async {
    if (counterpartyId == null || amount == null) {
      showSimpleDialog('Counterparty or amount missing', Colors.red);
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        showSimpleDialog('No authenticated user found', Colors.red);
        return;
      }

      final details = await getCurrentAccountIdAndType();
      final String? accountId = details['accountId'];
      final String? accountType = details['accountType'];

      if (accountId == null || accountId.isEmpty || accountType == null) {
        showSimpleDialog('Account details not found', Colors.red);
        return;
      }

      final result = await FirebaseFunctions.instance
          .httpsCallable('sudoTransferNip')
          .call({
        'accountType': accountType,
        'accountId': accountId,
        'counterpartyId': counterpartyId,
        'amount': amount! * 100,
        'currency': 'NGN',
        'narration': 'Withdrawal to ${recipientAccountName ?? 'Customer'}',
        'idempotencyKey': const Uuid().v4(),
      });

      final status = result.data['data']['attributes']['status'];
      final failureReason = result.data['data']['attributes']['failureReason'];
      if (status == "FAILED") {
        showSimpleDialog('Transfer failed: $failureReason', Colors.red);
        return;
      }

      final transferRef = result.data['data']['id'];

      // Update pending withdrawal
      await FirebaseFirestore.instance
          .collection('pending_withdrawals')
          .doc(widget.requestId)
          .update({
        'status': 'approved',
        'pin': null,
        'transferRef': transferRef,
        'approvedAt': FieldValue.serverTimestamp(),
      });

      // Save transaction
      await FirebaseFirestore.instance.collection('transactions').add({
        'userId': user.uid,
        'receiverId': recipientUid ?? 'unknown',
        'type': 'withdrawal',
        'bank_code': recipientBankCode,
        'account_number': recipientAccountNumber,
        'amount': amount!,
        'reason': 'Customer Withdrawal',
        'currency': 'NGN',
        'api_response': result.data,
        'reference': transferRef,
        'recipientName': recipientAccountName,
        'bankName': recipientBankName,
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (context) => PaymentSuccessfulPage(
            bankName: recipientBankName ?? 'Unknown Bank',
            actionText: 'Continue to Home',
            title: 'Withdrawal Successful',
            description: 'Funds have been transferred successfully to the recipient\'s bank account.',
            amount: amount.toString(),
            recipientName: recipientAccountName ?? 'Unknown',
            bankCode: recipientBankCode ?? '',
            accountNumber: recipientAccountNumber ?? '',
            reference: transferRef,
          ),
        ).then((_) {
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => const HomePage()),
            );
          }
        });
      }
    } catch (e) {
      debugPrint('createNipTransfer error: $e');
      showSimpleDialog('Error processing transfer', Colors.red);
    }
  }
  Future<void> _approveWithdrawal() async {
    if (pinInput != storedPin) {
      setState(() {
        pinInput = '';
      });
      showSimpleDialog('Invalid PIN', Colors.red);
      return;
    }
    setState(() => isLoading = true);
    try {
      await _createCounterparty();
      if (counterpartyId == null) {
        return;
      }
      await _createNipTransfer();
    } catch (e) {
      showSimpleDialog('Approval failed', Colors.red);
    } finally {
      setState(() => isLoading = false);
    }
  }
  Future<void> _declineWithdrawal() async {
    try {
      await FirebaseFirestore.instance
          .collection('pending_withdrawals')
          .doc(widget.requestId)
          .update({
            'status': 'declined',
            'pin': null, // Invalidate PIN
          });
      showSimpleDialog('Request declined', Colors.orange);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const HomePage()),
        );
      }
    } catch (e) {
      showSimpleDialog('Decline failed', Colors.red);
    }
  }
  void _onNumberTap(int number) {
    if (pinInput.length < 4) {
      setState(() {
        pinInput += number.toString();
      });
    }
  }
  void _onBackspaceTap() {
    if (pinInput.isNotEmpty) {
      setState(() {
        pinInput = pinInput.substring(0, pinInput.length - 1);
      });
    }
  }
  void _onEnterTap() {
    _approveWithdrawal();
  }
  List<Widget> _buildKeypadRow(List<dynamic> items, bool isBottomRow) {
    return items.map<Widget>((item) {
      if (item is int) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.all(4.0),
            child: ElevatedButton(
              onPressed: () => _onNumberTap(item),
              style: ElevatedButton.styleFrom(
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(20),
              ),
              child: Text(
                item.toString(),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        );
      } else if (item == 'backspace') {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.all(4.0),
            child: ElevatedButton(
              onPressed: _onBackspaceTap,
              style: ElevatedButton.styleFrom(
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(20),
              ),
              child: const Icon(Icons.backspace, size: 24),
            ),
          ),
        );
      } else if (item == 'enter') {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.all(4.0),
            child: ElevatedButton(
              onPressed: pinInput.length == 4 ? _onEnterTap : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: pinInput.length == 4 ? Colors.green : Colors.grey,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(vertical: 20),
              ),
              child: const Text(
                'Enter',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ),
        );
      }
      return const SizedBox.shrink();
    }).toList();
  }
  @override
  Widget build(BuildContext context) {
    if (storedPin == null || amount == null || initiatorName == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final List<int> numbers = List.generate(10, (index) => index)..shuffle();
    final List<List<dynamic>> keypadLayout = [
      [numbers[0], numbers[1], numbers[2]],
      [numbers[3], numbers[4], numbers[5]],
      [numbers[6], numbers[7], numbers[8]],
      [numbers[9], 'backspace', 'enter'],
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text('Confirm Withdrawal to ${recipientAccountName ?? 'Customer'}'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Text(
                  'Amount: ₦${amount!.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (createdAt != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Initiated: ${createdAt!.day}/${createdAt!.month}/${createdAt!.year} at ${createdAt!.hour.toString().padLeft(2, '0')}:${createdAt!.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  ),
                ],
                const SizedBox(height: 40),
                const Text(
                  'Enter PIN to Confirm',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(4, (index) => Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey),
                      color: pinInput.length > index ? Colors.blue : Colors.transparent,
                    ),
                    child: const Icon(Icons.circle, color: Colors.white, size: 20),
                  )),
                ),
                const SizedBox(height: 40),
                Expanded(
                  child: IgnorePointer(
                    ignoring: isLoading,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: keypadLayout.map((row) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(children: _buildKeypadRow(row, row.contains('enter'))),
                      )).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isLoading ? null : _declineWithdrawal,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        child: const Text(
                          'Decline',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}