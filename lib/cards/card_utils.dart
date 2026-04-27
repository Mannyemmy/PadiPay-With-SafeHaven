import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Normalizes any Nigerian phone number to +234XXXXXXXXXX international format.
String _formatBridgecardPhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (raw.startsWith('+234') && digits.length == 13) return raw; // already good
  if (digits.length == 13 && digits.startsWith('234')) return '+$digits';
  if (digits.length == 11 && digits.startsWith('0')) return '+234${digits.substring(1)}';
  if (digits.length == 10) return '+234$digits';
  // Fallback: return as-is (will surface the real error clearly)
  return raw;
}

Future<Map<String, dynamic>> createBridgecardCardHolder() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    throw Exception('User not signed in');
  }

  final userDoc = await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .get();
  if (!userDoc.exists) {
    throw Exception('User document not found');
  }

  final data = userDoc.data()!;
  if (data['bridgeCard']?['cardholder_id'] != null) {
    return {'status': 'already_exists', 'message': 'Cardholder already exists'};
  }

  if (data['getAnchorData'] == null) {
    throw Exception('Bank account not found');
  }

  final anchorData = data['getAnchorData'] as Map<String, dynamic>;
  final customerCreation =
      anchorData['customerCreation'] as Map<String, dynamic>?;
  final attributes =
      customerCreation?['data']?['attributes'] as Map<String, dynamic>?;
  final address = attributes?['address'] as Map<String, dynamic>?;
  final fullName = attributes?['fullName'] as Map<String, dynamic>?;

  if (address == null || fullName == null) {
    throw Exception('Required data missing in getAnchorData');
  }

  final body = {
    'first_name': fullName['firstName'] ?? data['firstName'],
    'last_name': fullName['lastName'] ?? data['lastName'],
    'address': {
      'address': address['addressLine_1'] ?? data['address']?['street'],
      'city': address['city'] ?? data['address']?['city'],
      'state': address['state'] ?? data['address']?['state'],
      'country': address['country'] == 'NG'
          ? 'Nigeria'
          : address['country'] ?? data['address']?['country'],
      'postal_code': address['postalCode'] ?? data['address']?['postalCode'],
      'house_no': '1',
    },
    'phone': _formatBridgecardPhone(
      data['phone'] ?? attributes?['phoneNumber'] ?? '',
    ),
    'email_address': data['email'] ?? attributes?['email'],
    'identity': {
      'id_type': 'NIGERIAN_BVN_VERIFICATION',
      'bvn': data['bvn'],
      'selfie_image':
          data['profilePhoto'] ??
          'https://image.com', 
    },
    'meta_data': {'user_id': user.uid}, 
  };

  final callable = FirebaseFunctions.instance.httpsCallable(
    'bridgecardCreateCardholderAsynchronous',
  );
  final response = await callable.call(body);
  print(response.data);
  final responseData = response.data as Map<String, dynamic>;
  print(responseData);

  if (responseData['status'] == 'success') {
    final cardholderId = responseData['data']['cardholder_id'] as String;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'bridgeCard.cardholder_id': cardholderId,
    });
  }

  return responseData;
}

Future<void> fundIssuingWallet() async {
  final callable = FirebaseFunctions.instance.httpsCallable('bridgecardFundIssuingWallet');
  
  final response2 = await callable.call({
    'currency': 'USD',
    'amount': '1000',
  });
  print(response2.data);
}