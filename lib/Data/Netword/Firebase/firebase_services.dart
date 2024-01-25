import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:messenger/Data/Local/SharedPreference/shared_preference.dart';
import 'package:messenger/Getx/get_otp.dart';
import 'package:messenger/Getx/get_signup.dart';
import 'package:messenger/Utils/Widget/snackbar.dart';
import 'package:messenger/View/BottomNavigationState.dart';
import 'package:messenger/View/account/otp.dart';
import 'package:messenger/res/const/const.dart';

class FirebaseService {
  RxMap<String, int> messageCounts = <String, int>{}.obs;
  static String phoneNumber_ = "";
  static String name_ = "";
  static File? file_;
  Future<int> getMessageCount(String phoneNumber) async {
    // Get the DataSnapshot from the DatabaseEvent.
    DatabaseEvent event = await FirebaseDatabase.instance
        .ref('Accounts')
        .child(phoneNumber)
        .child('messageCount')
        .once();

    // Check if the event has data and retrieve the value.
    if (event.snapshot != null) {
      dynamic value = event.snapshot!.value;
      if (value != null && value is int) {
        return value;
      }
    }

    // Return a default value if no data is found.
    return 0;
  }

  static Future<void> requestOtp(
      String phoneNumber, String name, File file, SignUpState state) async {
    phoneNumber_ = phoneNumber;
    name_ = name;
    file_ = file;
    state.setPress();
    FirebaseAuth auth = FirebaseAuth.instance;
    await auth
        .verifyPhoneNumber(
      phoneNumber: '+92$phoneNumber',
      codeSent: (String verificationId, int? resendToken) async {
        state.setPress();
        Get.to(Otp(
          verificationId: verificationId,
        ));
      },
      verificationCompleted: (PhoneAuthCredential phoneAuthCredential) {},
      verificationFailed: (FirebaseAuthException error) {
        ShowSnackBar("Error", errorRead(error.toString()));
        state.setPress();
      },
      codeAutoRetrievalTimeout: (String verificationId) {},
    )
        .onError(
      (error, stackTrace) {
        state.setPress();
        ShowSnackBar("Error", errorRead(error.toString()));
      },
    );
  }

  static Future<void> verifyOtp(
      String otp, String verificationId, OtpState controller) async {
    try {
      controller.setPress();
      FirebaseAuth auth = FirebaseAuth.instance;
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
          verificationId: verificationId, smsCode: otp);
      await auth.signInWithCredential(credential).then(
        (value) async {
          FirebaseStorage storage = FirebaseStorage.instance;
          var sref = storage.ref('$phoneNumber_.jpeg');
          var uploadtask = sref.putFile(file_!);
          await Future.value(uploadtask).then(
            (v) async {
              sref.getDownloadURL().then((url) {
                FirebaseDatabase.instance
                    .ref('Accounts')
                    .child(phoneNumber_)
                    .set({
                  'name': name_,
                  'phoneNumber': phoneNumber_,
                  'url': url
                }).then(
                  (value) {
                    SharedPref.saveData(name_, phoneNumber_, url);
                    controller.setPress();
                    ShowSnackBar("Successful", "Verified");
                    Get.to(const BottomNavigationState());
                  },
                );
              }).onError(
                (error, stackTrace) {
                  FirebaseAuth.instance.signOut();
                  controller.setPress();
                  ShowSnackBar("Error", errorRead(error.toString()));
                  return;
                },
              );
            },
          ).onError(
            (error, stackTrace) {
              FirebaseAuth.instance.signOut();
              controller.setPress();
              ShowSnackBar("Error", errorRead(error.toString()));
              return;
            },
          );
        },
      ).onError(
        (error, stackTrace) {
          controller.setPress();
          ShowSnackBar("Error", errorRead(error.toString()));
        },
      );
    } catch (e) {
      controller.setPress();
      FirebaseAuth.instance.signOut();
    }
  }

  static Future<void> sendMessage(String sender, String receiver, String name,
      String message, String url) async {
    try {
      FirebaseDatabase.instance
          .ref('Accounts')
          .child(sender)
          .child('Chat')
          .child(receiver)
          .set({
        'name': name,
        'phoneNumber': receiver,
        'url': url,
        'latestMessage': message
      });

      FirebaseDatabase.instance
          .ref('Accounts')
          .child(receiver)
          .child('Chat')
          .child(sender)
          .set({
        'name': await SharedPref.getName(),
        'phoneNumber': await SharedPref.getNumber(),
        'url': await SharedPref.getUrl(),
        'latestMessage': message
      });
      String time = DateFormat('h:mm:a').format(DateTime.now());
      FirebaseDatabase.instance
          .ref('Chats')
          .child(sender)
          .child(receiver)
          .child(DateTime.now().microsecondsSinceEpoch.toString())
          .set({
        'sender': sender,
        'receiver': receiver,
        'message': message,
        'time': time
      });

      FirebaseDatabase.instance
          .ref('Chats')
          .child(receiver)
          .child(sender)
          .child(DateTime.now().microsecondsSinceEpoch.toString())
          .set({
        'sender': sender,
        'receiver': receiver,
        'message': message,
        'time': time,
      });

      await FirebaseDatabase.instance
          .ref('Accounts')
          .child(sender)
          .update({'messageCount': FieldValue.increment(1)});

      await FirebaseDatabase.instance
          .ref('Accounts')
          .child(receiver)
          .update({'messageCount': FieldValue.increment(1)});
      FirebaseService firebaseService = FirebaseService();
      await firebaseService.getMessageCounts();
    } catch (e) {
      print("Error sending message: $e");
    }
  }

  Future<void> getMessageCounts() async {
    // Create an instance of FirebaseService
    final FirebaseService firebaseService = FirebaseService();

    // Get the list of chats for the current user.
    DatabaseEvent event = await FirebaseDatabase.instance
        .ref('Accounts')
        .child(number)
        .child('Chat')
        .once();

    // Initialize a map to store message counts for each chat.
    Map<String, int> updatedMessageCounts = {};

    // Check if the event has data.
    if (event.snapshot != null) {
      dynamic snapshotValue = event.snapshot!.value;
      if (snapshotValue is Map<String, dynamic>) {
        Map<String, dynamic> chatData = snapshotValue;
        if (chatData != null) {
          for (var entry in chatData.entries) {
            String phoneNumber = entry.key;
            int messageCount =
                await firebaseService.getMessageCount(phoneNumber);
            updatedMessageCounts[phoneNumber] = messageCount;
          }
        }
      } else {
        // Handle the case where the value is not of the expected type
        print("Snapshot value is not a Map<String, dynamic>");
      }
    } else {
      // Handle the case where the snapshot is null
      print("Snapshot is null");
    }

    // Update the messageCounts map in your state.
    messageCounts = updatedMessageCounts.obs;
  }

  Future<void> updateMessageCount(String phoneNumber) async {
    int messageCount = await FirebaseService().getMessageCount(phoneNumber);
    messageCounts[phoneNumber] = messageCount;
  }

  static Future<void> setStatusOnline() async {
    FirebaseDatabase.instance
        .ref('Accounts')
        .child(number)
        .update({'status': 'Online'});
  }

  static Future<void> setStatusOffline() async {
    String time = DateFormat('h:mm:a').format(DateTime.now());
    FirebaseDatabase.instance
        .ref('Accounts')
        .child(number)
        .update({'status': time});
  }

  static Future<void> sendImage(String sender, String receiver) async {
    String key = DateTime.now().microsecondsSinceEpoch.toString();

    FirebaseDatabase.instance
        .ref('Chats')
        .child(sender)
        .child(receiver)
        .child(key)
        .set({
      'sender': sender,
      'receiver': receiver,
      'message': 'image__',
    });

    FirebaseDatabase.instance
        .ref('Chats')
        .child(receiver)
        .child(sender)
        .child(key)
        .set({
      'sender': sender,
      'receiver': receiver,
      'message': 'image__',
    });

    var picker = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picker != null) {
      FirebaseStorage storage = FirebaseStorage.instance;
      var sref = storage.ref('${DateTime.now().microsecondsSinceEpoch}.jpeg');
      var uploadtask = sref.putFile(File(picker.path));
      await Future.value(uploadtask).then((v) async {
        sref.getDownloadURL().then((url) {
          String time = DateFormat('h:mm:a').format(DateTime.now());
          FirebaseDatabase.instance
              .ref('Chats')
              .child(sender)
              .child(receiver)
              .child(key)
              .set({
            'sender': sender,
            'receiver': receiver,
            'message': 'image__',
            'time': time,
            'url': url
          });

          FirebaseDatabase.instance
              .ref('Chats')
              .child(receiver)
              .child(sender)
              .child(key)
              .set({
            'sender': sender,
            'receiver': receiver,
            'message': 'image__',
            'time': time,
            'url': url
          });
        });
      });
    }
  }

  static String errorRead(String error) {
    return error.substring(error.indexOf(']') + 1, error.length);
  }
}
