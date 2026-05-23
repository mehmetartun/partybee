import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
// ignore: unnecessary_import
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:get_thumbnail_video/video_thumbnail.dart';
// ignore: implementation_imports
import 'package:get_thumbnail_video/src/image_format.dart';

// import 'package:cloud_functions/cloud_functions.dart';

import '../../../models/enums.dart';

part 'planner_state.dart';

enum PlannerStep { details, video, uploading, receiving, success }

class PlannerCubit extends Cubit<PlannerState> {
  PlannerCubit()
    : super(
        PlannerState(
          step: PlannerStep.details,
          partyName: "Google's Hackathon Event",
          partyDate: DateTime(2027, 1, 23),
          partyType: PartyType.hackathon,
          guestCount: 50,
          isInitializingVideo: false,
          spaceDescription: "",
          uploadProgress: 0.0,
          isLoading: false,
        ),
      );

  void updatePartyName(String name) => emit(state.copyWith(partyName: name));
  void updatePartyDate(DateTime date) => emit(state.copyWith(partyDate: date));
  void updatePartyType(PartyType type) => emit(state.copyWith(partyType: type));
  void updateGuestCount(int count) => emit(state.copyWith(guestCount: count));
  void updateSpaceDescription(String desc) =>
      emit(state.copyWith(spaceDescription: desc));
  void updateVideo(XFile? video) => emit(state.copyWith(recordedVideo: video));
  void updateIsInitializingVideo(bool val) =>
      emit(state.copyWith(isInitializingVideo: val));

  Future<void> saveDetailsAndNext() async {
    if (state.partyName.trim().isEmpty) {
      emit(state.copyWith(errorMessage: 'Please enter a party name'));
      return;
    }

    emit(state.copyWith(isLoading: true, errorMessage: null));
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User is not authenticated. Please log in first.');
      }

      final uid = user.uid;
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('parties')
          .doc(); // Auto-generates unique partyId

      await docRef.set({
        'partyId': docRef.id,
        'name': state.partyName,
        'date': Timestamp.fromDate(state.partyDate),
        'type': state.partyType.name,
        'guestCount': state.guestCount,
        'createdAt': FieldValue.serverTimestamp(),
      });

      emit(
        state.copyWith(
          step: PlannerStep.video,
          partyId: docRef.id,
          isLoading: false,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: 'Failed to save event details: ${e.toString()}',
        ),
      );
    }
  }

  Future<void> uploadVideo(XFile videoFile) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final partyId = state.partyId;
    if (uid == null || partyId == null) {
      emit(
        state.copyWith(errorMessage: 'Authentication or Party ID is missing.'),
      );
      return;
    }

    emit(
      state.copyWith(
        step: PlannerStep.uploading,
        isLoading: true,
        uploadProgress: 0.0,
        errorMessage: null,
      ),
    );

    VideoPlayerController? videoController;
    try {
      // 1. Get the video duration to space frames equally
      if (kIsWeb) {
        videoController = VideoPlayerController.networkUrl(
          Uri.parse(videoFile.path),
        );
      } else {
        videoController = VideoPlayerController.file(File(videoFile.path));
      }
      await videoController.initialize();
      final duration = videoController.value.duration;
      await videoController.dispose();
      videoController = null;

      // 2. Read bytes for cross-platform compatibility (Web + Mobile)
      final bytes = await videoFile.readAsBytes();
      final ext = videoFile.name.contains('.')
          ? videoFile.name.split('.').last
          : 'mp4';
      final fileName = 'video_${DateTime.now().millisecondsSinceEpoch}.$ext';

      final storageRef = FirebaseStorage.instance.ref().child(
        'users/$uid/parties/$partyId/videos/$fileName',
      );

      // 3. Start upload task for the video (counts as 50% of progress)
      final uploadTask = storageRef.putData(
        bytes,
        SettableMetadata(contentType: 'video/mp4'),
      );

      // Track progress stream for the video
      final subscription = uploadTask.snapshotEvents.listen((event) {
        if (event.totalBytes > 0) {
          final progress = (event.bytesTransferred / event.totalBytes) * 0.5;
          emit(state.copyWith(uploadProgress: progress));
        }
      });

      await uploadTask;
      await subscription.cancel();

      final videoDownloadUrl = await storageRef.getDownloadURL();
      final videoStoragePath = storageRef.fullPath;

      // 4. Create and upload 5 equally spaced images
      final List<Map<String, String>> imageReferences = [];

      for (int i = 0; i < 5; i++) {
        // Calculate timestamp for this frame
        final double ratio = i / 4.0;
        final targetDuration = Duration(
          milliseconds: (duration.inMilliseconds * ratio).toInt(),
        );

        // Format label: e.g. "Frame 1 (0:00)"
        final minutes = targetDuration.inMinutes;
        final seconds = targetDuration.inSeconds % 60;
        final timeLabel = "$minutes:${seconds.toString().padLeft(2, '0')}";

        final String label;
        if (i == 0) {
          label = "Start Frame ($timeLabel)";
        } else if (i == 4) {
          label = "End Frame ($timeLabel)";
        } else {
          label = "Frame ${i + 1} ($timeLabel)";
        }

        // Attempt to extract the actual frame from the video path, falling back to canvas drawing on failure
        Uint8List imageBytes;
        try {
          imageBytes = await VideoThumbnail.thumbnailData(
            video: videoFile.path,
            imageFormat: ImageFormat.JPEG,
            maxHeight: 1200,
            maxWidth: 1200,
            timeMs: targetDuration.inMilliseconds,
            quality: 75,
          );
        } catch (e) {
          debugPrint(
            'Frame extraction failed, falling back to visual placeholder: $e',
          );
          imageBytes = await _generateFramePlaceholder(i, label);
        }

        // Upload to Firebase Storage: /users/userId/parties/partyId/images
        final imgFileName =
            'frame_${i}_${DateTime.now().millisecondsSinceEpoch}.png';
        final imgStorageRef = FirebaseStorage.instance.ref().child(
          'users/$uid/parties/$partyId/images/$imgFileName',
        );

        await imgStorageRef.putData(
          imageBytes,
          SettableMetadata(contentType: 'image/png'),
        );

        final imgDownloadUrl = await imgStorageRef.getDownloadURL();
        final imgStoragePath = imgStorageRef.fullPath;

        // Save reference to upload in Firestore
        imageReferences.add({
          'downloadUrl': imgDownloadUrl,
          'storagePath': imgStoragePath,
          'label': label,
          'timeOffsetMs': targetDuration.inMilliseconds.toString(),
        });

        // Update overall progress (from 50% to 100%)
        emit(state.copyWith(uploadProgress: 0.5 + ((i + 1) / 5) * 0.5));
      }

      // 5. Save image references in the Firestore collection /users/userId/parties/partyId/images/
      final firestoreInstance = FirebaseFirestore.instance;
      final imagesCollection = firestoreInstance
          .collection('users')
          .doc(uid)
          .collection('parties')
          .doc(partyId)
          .collection('images');

      for (final imgRef in imageReferences) {
        await imagesCollection.add({
          'storagePath': imgRef['storagePath'],
          'downloadUrl': imgRef['downloadUrl'],
          'label': imgRef['label'],
          'timeOffsetMs': int.parse(imgRef['timeOffsetMs']!),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      // 6. Update Firestore parent party document with the video reference
      await firestoreInstance
          .collection('users')
          .doc(uid)
          .collection('parties')
          .doc(partyId)
          .update({
            'videoReference': videoStoragePath,
            'videoReferenceDownloadUrl': videoDownloadUrl,
          });

      emit(
        state.copyWith(
          step: PlannerStep.receiving,
          isLoading: false,
          videoReference: videoStoragePath,
          videoReferenceDownloadUrl: videoDownloadUrl,
        ),
      );

      // Invoke recommendations function
      await getRecommendations();
    } catch (e) {
      await videoController?.dispose();
      emit(
        state.copyWith(
          step: PlannerStep.video,
          isLoading: false,
          errorMessage: 'Failed to upload video: ${e.toString()}',
        ),
      );
    }
  }

  Future<Uint8List> _generateFramePlaceholder(
    int frameIndex,
    String label,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 640, 480));

    // Draw background with gradient to visually distinguish frames
    final paint = Paint()
      ..shader =
          ui.Gradient.linear(const Offset(0, 0), const Offset(640, 480), [
            const Color(0xFF0F172A),
            frameIndex == 0
                ? Colors.indigo.shade800
                : frameIndex == 4
                ? Colors.pink.shade800
                : Colors.purple.shade800,
          ]);
    canvas.drawRect(const Rect.fromLTWH(0, 0, 640, 480), paint);

    // Draw frame decoration border
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawRect(const Rect.fromLTWH(20, 20, 600, 440), borderPaint);

    // Draw camera overlay (simulate frame capture)
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 28,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(320 - textPainter.width / 2, 220));

    final subTextPainter = TextPainter(
      text: TextSpan(
        text: "Venue Scan Frame ${frameIndex + 1} of 5",
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.6),
          fontSize: 16,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    subTextPainter.layout();
    subTextPainter.paint(canvas, Offset(320 - subTextPainter.width / 2, 270));

    // End recording and convert to image
    final picture = recorder.endRecording();
    final img = await picture.toImage(640, 480);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> getRecommendations() async {
    emit(state.copyWith(isLoading: true, errorMessage: null));
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final partyId = state.partyId;

      if (uid == null || partyId == null) {
        throw Exception('User ID or Party ID is missing.');
      }

      final callable = FirebaseFunctions.instance.httpsCallable(
        'characterizeRoom',
      );
      final partyTypeStr = state.partyType.name;
      final guestCount = state.guestCount;
      final prompt =
          "Analyze the empty room represented by these images. We are planning to host a **$partyTypeStr** party for **$guestCount** guests. "
          "Explain how we should organize this room to best accommodate this party type and number of guests. "
          "Assume the room is completely empty, and specify a detailed itemized list of equipment, seating, tables, audio/video systems, and lighting we should rent. "
          "Provide the response strictly in raw markdown format without any HTML formatting or wrappers.";

      final collectionPath = 'users/$uid/parties/$partyId/images';

      final results = await callable.call({
        'collectionPath': collectionPath,
        'prompt': prompt,
      });

      String? firstImageDownloadUrl;
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection(collectionPath)
            .orderBy('timeOffsetMs')
            .limit(1)
            .get();
        if (snapshot.docs.isNotEmpty) {
          firstImageDownloadUrl =
              snapshot.docs.first.data()['downloadUrl'] as String?;
        }
      } catch (e) {
        debugPrint('Failed to fetch first image from Firestore: $e');
      }

      final recImage =
          firstImageDownloadUrl ??
          'https://firebasestorage.googleapis.com/v0/b/party-bee-30d70.firebasestorage.app/o/users%2FVCmciSPxQThVCuCyYrUl9hFwCHU2%2Fparties%2F5lOUJK1kxMqMieGyxcwt%2Fimages%2Fframe_4_1779494828211.png?alt=media&token=00d2f7c6-ea4d-48f6-80de-93f88df1ce62';

      // And then show a text saying "results are.... "
      emit(
        state.copyWith(
          isLoading: false,
          recommendationImage: recImage,
          recommendationText: results.data['markdown'],
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: 'Failed to retrieve recommendations: ${e.toString()}',
        ),
      );
    }
  }

  Future<void> saveResults() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final partyId = state.partyId;
    final recImage = state.recommendationImage;
    final recText = state.recommendationText;

    if (uid == null || partyId == null || recImage == null || recText == null) {
      emit(
        state.copyWith(
          errorMessage:
              'Required recommendation data or auth details are missing.',
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        step: PlannerStep.success,
        isLoading: true,
        errorMessage: null,
      ),
    );

    try {
      // 1. Fetch image bytes from the recommendation image URL
      final response = await http.get(Uri.parse(recImage));
      if (response.statusCode != 200) {
        throw Exception('Failed to download recommendation image');
      }
      final bytes = response.bodyBytes;

      // 2. Upload to Firebase Storage
      final fileName =
          'recommendation_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final storageRef = FirebaseStorage.instance.ref().child(
        'users/$uid/parties/$partyId/recommendation_images/$fileName',
      );

      await storageRef.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      // 3. Retrieve download URL and storage path
      final downloadUrl = await storageRef.getDownloadURL();
      final storagePath = storageRef.fullPath;

      // 4. Update Firestore party object under the 'results' field
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('parties')
          .doc(partyId)
          .update({
            'results': {
              'text': recText,
              'imageDownloadUrl': downloadUrl,
              'imageStoragePath': storagePath,
            },
          });

      emit(state.copyWith(isLoading: false));
    } catch (e) {
      emit(
        state.copyWith(
          step: PlannerStep.receiving,
          isLoading: false,
          errorMessage: 'Failed to save results: ${e.toString()}',
        ),
      );
    }
  }

  void goBackToDetails() {
    emit(state.copyWith(step: PlannerStep.details, errorMessage: null));
  }
}
