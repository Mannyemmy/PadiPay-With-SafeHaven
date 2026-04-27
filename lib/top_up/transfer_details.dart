import 'package:card_app/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AddViaBankTransfer extends StatefulWidget {
  const AddViaBankTransfer({super.key});

  @override
  State<AddViaBankTransfer> createState() => _AddViaBankTransferState();
}

class _AddViaBankTransferState extends State<AddViaBankTransfer> {
  String accountNumber = "";
  Future<DocumentSnapshot> _fetchUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('No user logged in');
    return FirebaseFirestore.instance.collection('users').doc(user.uid).get();
  }


  @override
  void initState() {
    super.initState();
    fetchDepositAccount();
  }


  Future<void> fetchDepositAccount() async {
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

      // Extract accountId from getAnchorData.virtualAccount.data.id
      final data = userDoc.data()!;
      final anchorData = data['getAnchorData'] as Map<String, dynamic>?;
      if (anchorData == null) {
        throw Exception('Anchor data not found');
      }

      final virtualAccount =
          anchorData['virtualAccount'] as Map<String, dynamic>?;
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
      final callable = FirebaseFunctions.instance.httpsCallable(
        'fetchDepositAccount',
      );
      final result = await callable.call({'accountId': accountId});

      // Print the response
      print(result.data);
    } catch (e) {
      print('Error fetching deposit account: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        surfaceTintColor: Colors.white,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: _fetchUserData(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: primaryColor),
            );
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('No data found'));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>?;
          final getAnchorData =
              data?['getAnchorData']?['virtualAccount']?['data']?['attributes']
                  as Map<String, dynamic>? ??
              {};
          final bankName = getAnchorData['bank']?['name'] as String? ?? 'N/A';
          final accountNumber =
              getAnchorData['accountNumber'] as String? ?? 'N/A';
          final accountName = getAnchorData['accountName'] as String? ?? 'N/A';

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add Via Bank Transfer',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade100),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Bank Name",
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w300,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                bankName,
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: bankName));
                              showSimpleDialog('Copied to clipboard', Colors.green);
                            },
                            child: const Icon(
                              Icons.copy,
                              color: Colors.grey,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Account Number",
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w300,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                accountNumber,
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(
                                ClipboardData(text: accountNumber),
                              );
                              showSimpleDialog('Copied to clipboard', Colors.green);
                            },
                            child: const Icon(
                              Icons.copy,
                              color: Colors.grey,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Account Name",
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w300,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                accountName,
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(
                                ClipboardData(text: accountName),
                              );
                              showSimpleDialog('Copied to clipboard', Colors.green);
                            },
                            child: const Icon(
                              Icons.copy,
                              color: Colors.grey,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: primaryColor.withValues(alpha: 0.1),
                    border: Border.all(
                      color: primaryColor.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    "Transfer funds from your bank app to this account.\nYour wallet will be credited automatically.",
                    style: TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
