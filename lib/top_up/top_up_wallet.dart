import 'package:card_app/top_up/transfer_details.dart';
import 'package:card_app/utils.dart';
import 'package:flutter/material.dart';


class TopUpWallet extends StatelessWidget {
  const TopUpWallet({super.key});

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
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Top Up Your Wallet',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.grey.shade200,
                child: Icon(Icons.account_balance, color: Colors.grey),
              ),
              title: const Text(
                'Add via a bank transfer',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: const Text(
                'Fund your account by sending money to your unique NG bank account',
                style: TextStyle(fontWeight: FontWeight.w300),
              ),
              onTap: () {
               navigateTo(context, AddViaBankTransfer());
              },
            ),
            const Divider(color: Colors.grey, thickness: 0.1),
            // ListTile(
            //   leading: CircleAvatar(
            //     backgroundColor: Colors.grey.shade200,
            //     child: Icon(Icons.currency_bitcoin, color: Colors.grey),
            //   ),
            //   title: const Text(
            //     'Add via Crypto',
            //     style: TextStyle(fontWeight: FontWeight.w500),
            //   ),
            //   subtitle: const Text(
            //     'Send crypto through different networks to any wallet',
            //     style: TextStyle(fontWeight: FontWeight.w300),
            //   ),
            //   onTap: () {
            //     navigateTo(context, CryptoTopUp());
            //   },
            // ),
          ],
        ),
      ),
    );
  }
}
