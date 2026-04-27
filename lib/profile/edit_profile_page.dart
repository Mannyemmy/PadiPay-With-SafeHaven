import 'dart:io';
import 'package:card_app/home_pages/home_page.dart';
import 'package:card_app/profile/profile_page.dart';
import 'package:card_app/ui/bottom_nav_bar.dart';
import 'package:card_app/utils.dart' as utils;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  int _selectedIndex = 1;
  String? firstName;
  String? lastName;
  String? phone;
  String? email;
  DateTime? dobDate;
  String? dob;
  String? address1;
  String? state;
  String? city;
  String? country;
  String? gender;
  String? profilePhotoUrl;
  
  final _phoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    try {
      DocumentSnapshot snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      
      if (snap.exists) {
        var data = snap.data() as Map<String, dynamic>;
        final addressData = data['address'] as Map<String, dynamic>?;
        
        setState(() {
          firstName = data['firstName'] ?? '';
          lastName = data['lastName'] ?? '';
          phone = data['phone'] ?? '';
          email = data['email'] ?? '';
          dob = data['dateOfBirth'] ?? '';
          gender = data['gender'] ?? '';
          country = data['country'] ?? 'Nigeria';
          profilePhotoUrl = data['profilePhotoUrl'];
          
          // Extract from nested address object
          if (addressData != null) {
            address1 = addressData['street'] ?? '';
            state = addressData['state'] ?? '';
            city = addressData['city'] ?? '';
            if (country == null || country!.isEmpty) {
              country = addressData['country'] ?? 'Nigeria';
            }
          }
        });
        
        // Populate phone controller (only editable field)
        _phoneController.text = phone ?? '';
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching data: $e')),
      );
    }
  }

  Future<void> _updateProfilePhoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      File file = File(pickedFile.path);
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          final storageRef = FirebaseStorage.instance.ref(
            'profile_photos/${user.uid}.jpg',
          );
          await storageRef.putFile(file);
          final url = await storageRef.getDownloadURL();
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .update({'profilePhotoUrl': url});
          setState(() {
            profilePhotoUrl = url;
          });
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating photo: $e')),
          );
        }
      }
    }
  }

  Future<void> _selectDate() async {
    dobDate ??= DateTime.now().subtract(const Duration(days: 7300));
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: dobDate!,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != dobDate) {
      setState(() {
        dobDate = picked;
      });
    }
  }

  Future<void> _savePhoneOnly() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final newPhone = _phoneController.text.trim();
    if (newPhone.isEmpty) {
      utils.showSimpleDialog('Please enter a phone number', Colors.red);
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'phone': newPhone});

      utils.showSimpleDialog('Phone number updated successfully', Colors.green);
      utils.navigateTo(
        context,
        ProfilePage(),
        type: utils.NavigationType.clearStack,
      );
    } catch (e) {
      utils.showSimpleDialog('Error updating phone: $e', Colors.red);
    }
  }

  Future<void> _changeEmail() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final newEmailController = TextEditingController();
        final passwordController = TextEditingController();
        bool obscurePassword = true;

        return StatefulBuilder(
          builder: (_, setState) => SafeArea(
            bottom: true,
            child: Container(
              margin: const EdgeInsets.all(16.0),
              padding: const EdgeInsets.all(20.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16.0),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Change Email',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Current email: ${user.email}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // New email field
                    Text(
                      'New Email',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: newEmailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        hintText: 'Enter new email',
                        hintStyle:
                            TextStyle(color: Colors.grey.shade400, fontSize: 14),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: utils.primaryColor, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Password field for reauthentication
                    Text(
                      'Login Password',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: passwordController,
                      obscureText: obscurePassword,
                      decoration: InputDecoration(
                        hintText: 'Enter your password',
                        hintStyle:
                            TextStyle(color: Colors.grey.shade400, fontSize: 14),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: utils.primaryColor, width: 1.5),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.grey.shade500,
                            size: 20,
                          ),
                          onPressed: () => setState(
                              () => obscurePassword = !obscurePassword),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(
                                color: Colors.grey,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              final newEmail = newEmailController.text.trim();
                              final password = passwordController.text.trim();

                              if (newEmail.isEmpty || password.isEmpty) {
                                utils.showSimpleDialog(
                                    'Please fill all fields', Colors.red);
                                return;
                              }

                              try {
                                // Reauthenticate
                                final credential =
                                    EmailAuthProvider.credential(
                                  email: user.email!,
                                  password: password,
                                );
                                await user.reauthenticateWithCredential(
                                    credential);

                                // Update email
                                await user.verifyBeforeUpdateEmail(newEmail);

                                // Update Firestore
                                await FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(user.uid)
                                    .update({'email': newEmail});

                                Navigator.pop(ctx);
                                utils.showSimpleDialog(
                                  'Verification link sent to new email',
                                  Colors.green,
                                );
                              } on FirebaseAuthException catch (e) {
                                final msg = e.code == 'wrong-password' ||
                                        e.code == 'invalid-credential'
                                    ? 'Incorrect password'
                                    : e.message ?? 'Error changing email';
                                utils.showSimpleDialog(msg, Colors.red);
                              } catch (e) {
                                utils.showSimpleDialog(
                                    'Error: $e', Colors.red);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: utils.primaryColor,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Change Email',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        utils.navigateTo(
          context,
          ProfilePage(),
          type: utils.NavigationType.clearStack,
        );
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: true,
          child: SizedBox.expand(
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        // Back button
                        GestureDetector(
                          onTap: () => utils.navigateTo(
                            context,
                            ProfilePage(),
                            type: utils.NavigationType.clearStack,
                          ),
                          child: const Icon(Icons.arrow_back_ios,
                              color: Colors.black45, size: 20),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Edit Profile',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 30),
                        // Profile photo
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Stack(
                              children: [
                                CircleAvatar(
                                  radius: 60,
                                  backgroundImage: profilePhotoUrl !=
                                          null &&
                                      profilePhotoUrl!.isNotEmpty
                                      ? NetworkImage(profilePhotoUrl!)
                                      : const AssetImage(
                                          "assets/profile_placeholder.png"),
                                ),
                                Positioned(
                                  bottom: 10,
                                  right: 10,
                                  child: GestureDetector(
                                    onTap: _updateProfilePhoto,
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: utils.primaryColor,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.add_a_photo,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 30),
                        // Read-only fields
                        _buildReadOnlyField('First Name', firstName ?? ''),
                        _buildReadOnlyField('Last Name', lastName ?? ''),
                        _buildReadOnlyField('Gender',
                            _capitalizeGender(gender ?? '') ?? ''),
                        _buildReadOnlyField('Date of Birth', dob ?? ''),
                        // Email with change button
                        _buildEmailField(),
                        const SizedBox(height: 16),
                        // Phone (editable)
                        _buildPhoneField(),
                        // Address (read-only)
                        _buildReadOnlyField(
                            'Address', address1 ?? ''),
                        _buildReadOnlyField('State', state ?? ''),
                        _buildReadOnlyField('City', _getCityFromData() ?? ''),
                        _buildReadOnlyField('Country', country ?? ''),
                        const SizedBox(height: 150),
                      ],
                    ),
                  ),
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
                          utils.navigateTo(
                            context,
                            HomePage(),
                            type: utils.NavigationType.clearStack,
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
        ),
      ),
    );
  }

  String _getCityFromData() {
    return city ?? '';
  }

  String? _capitalizeGender(String gender) {
    if (gender.isEmpty) return null;
    return gender[0].toUpperCase() + gender.substring(1).toLowerCase();
  }

  Widget _buildReadOnlyField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 13,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Text(
              value.isEmpty ? '—' : value,
              style: TextStyle(
                fontSize: 14,
                color: value.isEmpty ? Colors.grey.shade400 : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Email',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 13,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text(
                    email ?? '—',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _changeEmail,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: utils.primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: const Text(
                    'Change',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Phone',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 13,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: utils.primaryColor, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _savePhoneOnly,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: utils.primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: const Text(
                    'Save',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }
}