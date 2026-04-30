import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:app_settings/app_settings.dart';
import 'package:card_app/ui/payment_successful_page.dart';
import 'package:card_app/utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_nfc_hce/flutter_nfc_hce.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart';

class NFCPromptBottomSheet extends StatefulWidget {
  final bool isReader;
  const NFCPromptBottomSheet({super.key, this.isReader = true});
  @override
  State<NFCPromptBottomSheet> createState() => _NFCPromptBottomSheetState();
}

class _NFCPromptBottomSheetState extends State<NFCPromptBottomSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool isNfcAvailable = false;
  final FlutterNfcHce _flutterNfcHce = FlutterNfcHce();
  StreamSubscription<QuerySnapshot>? _transactionSub;
  Timestamp? _lastTimestamp;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _scaleAnimation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _checkNfcAvailability();
  }

  Future<void> _checkNfcAvailability() async {
    try {
      final availability = await NfcManager.instance.checkAvailability();
      if (availability == NfcAvailability.enabled) {
        setState(() {
          isNfcAvailable = true;
        });
      } else {
        isNfcAvailable = false;
      }

      if (isNfcAvailable) {
        _setupNfc();
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to check NFC status: $e')));
    }
  }

  Future<void> _setupNfc() async {
    if (widget.isReader) {
      NfcManager.instance.startSession(
        pollingOptions: {
          NfcPollingOption.iso14443,
          NfcPollingOption.iso15693,
          NfcPollingOption.iso18092,
        },
        onDiscovered: (NfcTag tag) async {
          print("Seen: $tag");

          String receivedMessage = '';
          Ndef? ndef = Ndef.from(tag);
          if (ndef != null && ndef.cachedMessage != null) {
            for (var record in ndef.cachedMessage!.records) {
              if (record.typeNameFormat == TypeNameFormat.wellKnown &&
                  String.fromCharCodes(record.type) == 'T') {
                int langLength = record.payload[0];
                receivedMessage += utf8.decode(
                  record.payload.sublist(langLength + 1),
                );
              }
            }
            print('Received: $receivedMessage');
          } else {
            print('No NDEF support, trying IsoDep for HCE NDEF');
            final isoDep = IsoDepAndroid.from(tag);
            if (isoDep != null) {
              print('IsoDep tag detected');
              try {
                // Select NDEF AID for Type 4 HCE (D2760000850101)
                final selectAid = Uint8List.fromList([
                  0x00, 0xA4, 0x04, 0x00, 0x07, 0xD2, 0x76, 0x00, 0x00, 0x85, 0x01, 0x01
                ]);
                print('Sending select AID command');
                var response = await isoDep.transceive(selectAid);
                print('Select AID response: ${response.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
                if (response.length >= 2 &&
                    response[response.length - 2] == 0x90 &&
                    response[response.length - 1] == 0x00) {
                  // Read Capability Container (15 bytes from offset 0)
                  final readCC = Uint8List.fromList([0x00, 0xB0, 0x00, 0x00, 0x0F]);
                  print('Sending read CC command');
                  response = await isoDep.transceive(readCC);
                  print('CC response: ${response.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
                  if (response.length >= 17 &&  // Min CC + SW
                      response[response.length - 2] == 0x90 &&
                      response[response.length - 1] == 0x00) {
                    // Parse NLEN (NDEF length) from bytes 12-13 (big-endian)
                    int nlen = (response[12] << 8) | response[13];
                    print('NDEF length: $nlen');
                    if (nlen > 0 && nlen <= 255) {
                      // Read NDEF (short read, assume <256 bytes)
                      final readNdef = Uint8List.fromList([0x00, 0xB0, 0x00, 0x0F, nlen]);
                      print('Sending read NDEF command');
                      response = await isoDep.transceive(readNdef);
                      print('NDEF response: ${response.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
                      if (response.length >= nlen + 2 &&
                          response[response.length - 2] == 0x90 &&
                          response[response.length - 1] == 0x00) {
                        // Parse as single well-known text record (skip MB/ME/SR/IL/TNF=1, type='T', lang, text)
                        Uint8List ndefBytes = response.sublist(0, nlen);
                        print('NDEF bytes: ${ndefBytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')}');
                        if (ndefBytes.length >= 4 &&
                            ndefBytes[0] & 0xD0 == 0xD1 &&  // MB=1, ME=1, TNF=1 (well-known)
                            ndefBytes[1] == 0x01 &&  // Type length=1 ('T')
                            String.fromCharCodes(ndefBytes.sublist(2, 3)) == 'T') {  // Type='T'
                          int payloadStart = 3;  // After TNF+type+typeLen
                          int langLength = ndefBytes[payloadStart] & 0x3F;  // RFC 4646 lang (low 6 bits)
                          payloadStart += 1 + langLength;
                          if (payloadStart < ndefBytes.length) {
                            receivedMessage = utf8.decode(ndefBytes.sublist(payloadStart));
                            print('Parsed HCE NDEF text: $receivedMessage');
                          }
                        } else {
                          print('NDEF parse failed: invalid format');
                        }
                      } else {
                        print('NDEF read failed');
                        showSimpleDialog('Failed to read NDEF data', Colors.red);
                      }
                    } else {
                      print('Invalid NDEF length: $nlen');
                      showSimpleDialog('No NDEF data or too large', Colors.orange);
                    }
                  } else {
                    print('CC read failed');
                    showSimpleDialog('Failed to read CC', Colors.red);
                  }
                } else {
                  print('AID select failed');
                  showSimpleDialog('HCE NDEF AID not selected', Colors.red);
                }
              } catch (e) {
                print('IsoDep error: $e');
                showSimpleDialog('Error reading HCE: $e', Colors.red);
              } finally {

              }
            } else {
              print('Invalid IsoDep tag');
              showSimpleDialog('Unsupported tag type', Colors.red);
            }
          }

          // Delay stop to allow UI update
          await Future.delayed(const Duration(milliseconds: 500));
          await NfcManager.instance.stopSession();

          if (mounted && receivedMessage.isNotEmpty) {
            User? currentUser = FirebaseAuth.instance.currentUser;
            if (currentUser != null) {
              await FirebaseFirestore.instance.collection('transactions').add({
                'senderId': currentUser.uid,
                'receiverId': receivedMessage,
                'amount': 0.0,
                'purpose': 'nfc_connection',
                'timestamp': Timestamp.now(),
                'status': 'pending',
                'type': 'nfc_connection',
              });
            }
            DocumentSnapshot receiverDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(receivedMessage)
                .get();
            String receiverName = receiverDoc.exists
                ? '${receiverDoc['firstName']} ${receiverDoc['lastName']}'
                : receivedMessage;
            showSimpleDialog('Connected to $receiverName', Colors.green);
            Navigator.pop(context);
            navigateTo(
              context,
              TransferPage(endpointId: receivedMessage),
              type: NavigationType.push,
            );
          } else if (mounted) {
            showSimpleDialog('No valid data received, try again', Colors.orange);
          }
        },
        alertMessageIos: widget.isReader
            ? 'Hold the back of your phone to the merchant device'
            : 'Hold the back of your phone to the back of the customer device',
        onSessionErrorIos: (error) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('NFC error: $error')));
        },
      );
    } else {
      if (Platform.isAndroid) {
        try {
          User? currentUser = FirebaseAuth.instance.currentUser;
          if (currentUser == null) {
            showSimpleDialog('Not logged in', Colors.red);
            return;
          }
          String endpointId = currentUser.uid;
          var query = await FirebaseFirestore.instance
              .collection('transactions')
              .where('receiverId', isEqualTo: endpointId)
              .orderBy('timestamp', descending: true)
              .limit(1)
              .get();
          _lastTimestamp = query.docs.isNotEmpty
              ? query.docs.first['timestamp']
              : null;
          await _flutterNfcHce.startNfcHce(endpointId);
          print('HCE started successfully with UID: $endpointId');
          _listenForTransaction();
        } catch (e) {
          print('Failed to start HCE: $e');
          showSimpleDialog('Failed to share: $e', Colors.red);
        }
      } else {
        showSimpleDialog('NFC sharing not supported on this platform', Colors.red);
      }
    }
  }

  void _listenForTransaction() {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    String uid = currentUser.uid;
    _transactionSub = FirebaseFirestore.instance
        .collection('transactions')
        .where('receiverId', isEqualTo: uid)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen((snapshot) async {
          if (snapshot.docs.isNotEmpty) {
            var doc = snapshot.docs.first;
            Timestamp ts = doc['timestamp'];
            if (_lastTimestamp == null || ts.compareTo(_lastTimestamp!) > 0) {
              _lastTimestamp = ts;
              String transType = doc['type'] ?? '';
              if (transType == 'nfc_connection') {
                String senderId = doc['senderId'];
                DocumentSnapshot senderDoc = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(senderId)
                    .get();
                String senderName =
                    '${senderDoc['firstName']} ${senderDoc['lastName']}';
                showSimpleDialog('Connected to $senderName', Colors.green);
                await doc.reference.delete();
              } else {
                String amount = doc['amount'].toString();
                String senderId = doc['senderId'];
                DocumentSnapshot senderDoc = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(senderId)
                    .get();
                String senderName =
                    '${senderDoc['firstName']} ${senderDoc['lastName']}';
                /////
                if (mounted) {
                  Navigator.pop(context);
                  await _flutterNfcHce.stopNfcHce();
                  navigateTo(
                    context,
                    PaymentSuccessfulPage(
                      reference: "",
                      accountNumber: "",
                      bankCode: "0",
                      bankName: "PadiPay",
                      recipientName: senderName,
                      amount: amount,
                      actionText: "Go to Home",
                      title: "Payment Received",
                      description: "You received ₦$amount from $senderName",
                    ),
                    type: NavigationType.clearStack,
                  );
                }
              }
            }
          }
        });
  }

  @override
  void dispose() {
    _controller.dispose();
    NfcManager.instance.stopSession();
    if (!widget.isReader && Platform.isAndroid) {
      _flutterNfcHce.stopNfcHce();
    }
    _transactionSub?.cancel();
    super.dispose();
  }



  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(bottom: true,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.isReader
                    ? 'Place Your Phone\nNear the POS'
                    : 'Place the Reader\nNear Your Phone',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (!isNfcAvailable) ...[
                const Text(
                  'NFC is not enabled. Please enable it to proceed.',
                  style: TextStyle(fontSize: 14, color: Colors.red),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    AppSettings.openAppSettings(type: AppSettingsType.nfc);
                    Future.delayed(
                      const Duration(seconds: 2),
                      _checkNfcAvailability,
                    );
                  },
                  child: const Text('Enable NFC'),
                ),
              ] else ...[
                Text(
                  widget.isReader
                      ? 'Hold the back of your phone to the merchant device'
                      : 'Hold the back of your phone to the back of the customer device',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                ScaleTransition(
                  scale: _scaleAnimation,
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.blue,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class TransferPage extends StatefulWidget {
  final String endpointId;
  const TransferPage({super.key, required this.endpointId});

  @override
  State<TransferPage> createState() => _TransferPageState();
}

class _TransferPageState extends State<TransferPage> {
  final _amountController = TextEditingController();
  final _purposeController = TextEditingController();
  String? receiverName;

  @override
  void initState() {
    super.initState();
    _fetchReceiverName();
  }

  Future<void> _fetchReceiverName() async {
    var doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.endpointId)
        .get();
    if (doc.exists) {
      setState(() {
        receiverName = '${doc['firstName']} ${doc['lastName']}';
      });
    }
  }

  Future<Map<String, dynamic>?> _getSafehavenAccountForUser(String uid) async {
    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = userDoc.data() ?? <String, dynamic>{};
    final safehavenVa =
        data['safehavenData']?['virtualAccount']?['data'] as Map?;

    final setupDoc = await FirebaseFirestore.instance
        .collection('safehavenUserSetup')
        .doc(uid)
        .get();
    final setup = setupDoc.data() ?? <String, dynamic>{};

    final accountId =
        safehavenVa?['id']?.toString() ?? setup['safehavenAccountId']?.toString();
    final accountNumber = safehavenVa?['attributes']?['accountNumber']
            ?.toString() ??
        setup['safehavenAccountNumber']?.toString();
    final rawBankId =
        safehavenVa?['attributes']?['bank']?['id']?.toString() ??
            setup['safehavenBankCode']?.toString();
    final bankName =
        safehavenVa?['attributes']?['bank']?['name']?.toString() ??
            setup['safehavenBankName']?.toString();
    final bankId =
        await resolveBankId(bankId: rawBankId, bankName: bankName) ?? '999240';
    final accountName =
        safehavenVa?['attributes']?['accountName']?.toString() ??
            setup['safehavenAccountName']?.toString();

    if ((accountId == null || accountId.isEmpty) &&
        (accountNumber == null || accountNumber.isEmpty)) {
      return null;
    }

    return {
      'accountId': accountId,
      'accountNumber': accountNumber,
      'bankId': bankId,
      'bankName': bankName,
      'accountName': accountName,
    };
  }

  void _sendPayment() async {
    if (_amountController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter an amount')));
      return;
    }
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Not logged in')));
      return;
    }
    double? amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid amount')));
      return;
    }
    String purpose = _purposeController.text;

    final pinVerified = await verifyTransactionPin();
    if (!pinVerified) {
      return;
    }

    // Perform real settlement with SafeHaven book transfer.
    try {
      final settled = await _settleNfcPayment(amount, purpose);
      if (!settled) {
        showSimpleDialog('Transfer failed', Colors.red);
        return;
      }

      navigateTo(
        context,
        PaymentSuccessfulPage(
          reference: "",
          accountNumber: "",
          bankCode: "0",
          bankName: "PadiPay",
          recipientName: receiverName ?? "",
          amount: amount.toString(),
          actionText: "Go to Home",
          title: "Transfer Successful",
          description: "You sent ₦${amount.toString()} to ${receiverName ?? ''}",
        ),
        type: NavigationType.clearStack,
      );
    } catch (e) {
      debugPrint('NFC settlement error: $e');
      showSimpleDialog('Error processing transfer', Colors.red);
    } finally {
      NfcManager.instance.stopSession();
    }
  }

  Future<bool> _settleNfcPayment(double amount, String purpose) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        showSimpleDialog('No authenticated user found', Colors.red);
        return false;
      }

      // Sender's account details
      final senderAccount = await _getSafehavenAccountForUser(user.uid);
      final senderAccountId = senderAccount?['accountId']?.toString() ?? '';
      final senderAccountNumber =
          senderAccount?['accountNumber']?.toString() ?? '';
      final fromAccountId = senderAccountId.isNotEmpty
          ? senderAccountId
          : senderAccountNumber;
      if (fromAccountId.isEmpty) {
        showSimpleDialog('Account details not found', Colors.red);
        return false;
      }

      // Recipient's VA details
      final recipientAccount =
          await _getSafehavenAccountForUser(widget.endpointId);
      if (recipientAccount == null) {
        showSimpleDialog('Recipient does not have a virtual account', Colors.red);
        return false;
      }
      final recipientAccountNumber =
          recipientAccount['accountNumber']?.toString() ?? '';
      final toAccountId = recipientAccountNumber.isNotEmpty
          ? recipientAccountNumber
          : recipientAccount['accountId']?.toString();
      if (toAccountId == null || toAccountId.isEmpty) {
        showSimpleDialog('Recipient account details not found', Colors.red);
        return false;
      }

      final recipientBankName = recipientAccount['bankName'];
      final recipientAccountName = recipientAccount['accountName'];
      final recipientBankId =
          recipientAccount['bankId']?.toString() ?? '999240';

      // Prevent sending to own account
      final ownAccountNumber = senderAccount?['accountNumber']?.toString();
      if (ownAccountNumber != null &&
          ownAccountNumber.isNotEmpty &&
          ownAccountNumber == recipientAccountNumber) {
        showSimpleDialog('You cannot send money to your own account', Colors.red);
        return false;
      }

      // SafeHaven book transfer; no counterparty needed for internal accounts.
      final amountKobo = (amount * 100).round();
      debugPrint('safehavenTransferIntra: from=$fromAccountId to=$toAccountId amount=$amountKobo bank=$recipientBankId');
      final transferResult = await FirebaseFunctions.instance
          .httpsCallable('safehavenTransferIntra')
          .call({
        'fromAccountId': fromAccountId,
        'toAccountId': toAccountId,
        'toBankCode': recipientBankId,
        'amount': amountKobo,
        'currency': 'NGN',
        'narration': purpose.trim().isEmpty ? 'NFC payment' : purpose.trim(),
        'idempotencyKey': const Uuid().v4(),
      });

      final status = transferResult.data['data']['attributes']['status'];
      final failureReason = transferResult.data['data']['attributes']['failureReason'];
      if (status == 'FAILED') {
        showSimpleDialog('Transfer failed: $failureReason', Colors.red);
        return false;
      }

      await FirebaseFirestore.instance.collection('transactions').add({
        'userId': user.uid,
        'receiverId': widget.endpointId,
        'type': 'nfc',
        'bank_code': recipientBankId,
        'account_number': recipientAccountNumber,
        'amount': amount,
        'reason': purpose,
        'currency': 'NGN',
        'api_response': transferResult.data,
        'reference': transferResult.data['data']['id'],
        'recipientName': recipientAccountName,
        'bankName': recipientBankName,
        'timestamp': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      debugPrint('settleNfcPayment error: $e');
      showSimpleDialog('Error settling payment', Colors.red);
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(bottom: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).pop();
                    },
                    child: Icon(
                      Icons.arrow_back_ios,
                      color: Colors.black87,
                      size: 20,
                    ),
                  ),
                  SizedBox(width: 20),
                  Text(
                    receiverName == null
                        ? 'Bank Transfer'
                        : 'Send to $receiverName',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Text('Enter Amount'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: TextField(
                controller: _amountController,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  prefixText: '₦ ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: const BorderSide(color: Colors.blue),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: const BorderSide(color: Colors.blue, width: 2),
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Text('Payment Purpose'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: TextField(
                controller: _purposeController,
                decoration: InputDecoration(
                  hintText: 'Purpose of payment (Optional)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: BorderSide.none,
                  ),
                  fillColor: Colors.grey[200],
                  filled: true,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton(
                onPressed: _sendPayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                ),
                child: const Text(
                  'Continue',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
