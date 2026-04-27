import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';

class CashbackService {
  static const double cashbackRate = 0.10;

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseFunctions _functions = FirebaseFunctions.instance;

  static double calculateCashback(double amountNaira) {
    if (amountNaira <= 0) return 0;
    return double.parse((amountNaira * cashbackRate).toStringAsFixed(2));
  }

  static double clampCashbackUsage({
    required double purchaseAmountNaira,
    required double availableCashbackNaira,
  }) {
    if (purchaseAmountNaira <= 0 || availableCashbackNaira <= 0) return 0;
    final allowed = purchaseAmountNaira < availableCashbackNaira
        ? purchaseAmountNaira
        : availableCashbackNaira;
    return double.parse(allowed.toStringAsFixed(2));
  }

  static Future<double> getCashbackBalance(String uid) async {
    final userDoc = await _firestore.collection('users').doc(uid).get();
    if (!userDoc.exists) return 0;
    final data = userDoc.data();
    final raw = data?['cashback']?['balance'];
    if (raw is num) return raw.toDouble();
    return 0;
  }

  static Future<String?> _getCompanyAccountId() async {
    final doc = await _firestore
        .collection('company')
        .doc('account_details')
        .get();
    if (!doc.exists) return null;
    final data = doc.data();
    final accountId = data?['accountId']?.toString();
    if (accountId == null || accountId.isEmpty) return null;
    return accountId;
  }

  static int _toKobo(double amountNaira) => (amountNaira * 100).round();

  static Future<String> fundPurchaseFromCashbackReserve({
    required String toAccountId,
    required double amountNaira,
    required String narration,
  }) async {
    final companyAccountId = await _getCompanyAccountId();
    if (companyAccountId == null) {
      throw Exception('Company cashback reserve account not configured');
    }

    final result = await _functions.httpsCallable('createBookTransfer').call({
      'fromAccountId': companyAccountId,
      'toAccountId': toAccountId,
      'amount': _toKobo(amountNaira),
      'currency': 'NGN',
      'narration': narration,
      'idempotencyKey': const Uuid().v4(),
    });

    final data = result.data['data'] as Map<String, dynamic>?;
    final status = (data?['attributes']?['status'] ?? '')
        .toString()
        .toUpperCase();
    if (status == 'FAILED') {
      final reason = data?['attributes']?['failureReason'] ?? 'Unknown failure';
      throw Exception('Cashback funding transfer failed: $reason');
    }

    return (data?['id'] ?? '').toString();
  }

  static Future<void> rollbackCashbackFunding({
    required String fromAccountId,
    required double amountNaira,
    required String narration,
  }) async {
    final companyAccountId = await _getCompanyAccountId();
    if (companyAccountId == null) {
      throw Exception('Company cashback reserve account not configured');
    }

    final result = await _functions.httpsCallable('createBookTransfer').call({
      'fromAccountId': fromAccountId,
      'toAccountId': companyAccountId,
      'amount': _toKobo(amountNaira),
      'currency': 'NGN',
      'narration': narration,
      'idempotencyKey': const Uuid().v4(),
    });

    final data = result.data['data'] as Map<String, dynamic>?;
    final status = (data?['attributes']?['status'] ?? '')
        .toString()
        .toUpperCase();
    if (status == 'FAILED') {
      final reason = data?['attributes']?['failureReason'] ?? 'Unknown failure';
      throw Exception('Cashback rollback transfer failed: $reason');
    }
  }

  static Future<void> recordCashbackSpend({
    required String uid,
    required double amountNaira,
    required String sourceType,
    required String sourceReference,
  }) async {
    if (amountNaira <= 0) return;

    final userRef = _firestore.collection('users').doc(uid);
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(userRef);
      final current = ((snap.data()?['cashback']?['balance'] ?? 0) as num)
          .toDouble();
      if (current + 0.0001 < amountNaira) {
        throw Exception('Insufficient cashback balance');
      }

      final nextBalance = double.parse(
        (current - amountNaira).toStringAsFixed(2),
      );
      tx.set(userRef, {
        'cashback': {
          'balance': nextBalance,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
    });

    await _firestore.collection('transactions').add({
      'userId': uid,
      'type': 'cashback_spent',
      'amount': amountNaira,
      'currency': 'NGN',
      'status': 'completed',
      'sourceType': sourceType,
      'sourceReference': sourceReference,
      'description': 'Cashback spent on $sourceType',
      'timestamp': FieldValue.serverTimestamp(),
      'createdAtFirestore': FieldValue.serverTimestamp(),
    });
  }

  static Future<double> recordCashbackEarned({
    required String uid,
    required double baseAmountNaira,
    required String sourceType,
    required String sourceReference,
  }) async {
    final cashbackAmount = calculateCashback(baseAmountNaira);
    if (cashbackAmount <= 0) return 0;

    final userRef = _firestore.collection('users').doc(uid);
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(userRef);
      final current = ((snap.data()?['cashback']?['balance'] ?? 0) as num)
          .toDouble();
      final nextBalance = double.parse(
        (current + cashbackAmount).toStringAsFixed(2),
      );
      tx.set(userRef, {
        'cashback': {
          'balance': nextBalance,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
    });

    await _firestore.collection('transactions').add({
      'userId': uid,
      'type': 'cashback_earned',
      'amount': cashbackAmount,
      'currency': 'NGN',
      'status': 'completed',
      'sourceType': sourceType,
      'sourceReference': sourceReference,
      'cashbackRate': cashbackRate,
      'description': '10% cashback from $sourceType payment',
      'timestamp': FieldValue.serverTimestamp(),
      'createdAtFirestore': FieldValue.serverTimestamp(),
    });

    return cashbackAmount;
  }
}
