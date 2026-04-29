import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

Future<void> safehavenFetchDepositAccount() async {
  try {
    // Get the current user
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('No authenticated user');
    }

    // Fetch user document from Firestore
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (!userDoc.exists) {
      throw Exception('User document not found');
    }

    // Extract accountId from safehavenData.virtualAccount.data.id
    final data = userDoc.data()!;
    final safehavenData = data['safehavenData'] as Map<String, dynamic>?;
    if (safehavenData == null) {
      throw Exception('Sudo data not found');
    }

    final virtualAccount = safehavenData['virtualAccount'] as Map<String, dynamic>?;
    if (virtualAccount == null) {
      throw Exception('Virtual account data not found');
    }

    final accountData = virtualAccount['data'] as Map<String, dynamic>?;
    if (accountData == null) {
      throw Exception('Account data not found');
    }

    final accountId = accountData['id']?.toString();
    if (accountId == null || accountId.isEmpty) {
      throw Exception('Account ID not found');
    }

    // Call the Cloud Function with the accountId
    final callable = FirebaseFunctions.instance.httpsCallable('safehavenFetchDepositAccount');
    final result = await callable.call({'accountId': accountId});

    // Print the response
    print(result.data);
  } catch (e) {
    print('Error fetching deposit account: $e');
  }
}
