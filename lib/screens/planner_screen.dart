import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../theme.dart';

// 1. Party Type Enum
enum PartyType {
  cocktail,
  hackathon,
  dinner,
  luncheon,
}

// Helper extension for friendly display names and emojis
extension PartyTypeExtension on PartyType {
  String get displayName {
    switch (this) {
      case PartyType.cocktail:
        return 'Cocktail Party';
      case PartyType.hackathon:
        return 'Hackathon';
      case PartyType.dinner:
        return 'Dinner Gala';
      case PartyType.luncheon:
        return 'Luncheon Banquet';
    }
  }

  String get emoji {
    switch (this) {
      case PartyType.cocktail:
        return '🍹';
      case PartyType.hackathon:
        return '💻';
      case PartyType.dinner:
        return '🍽️';
      case PartyType.luncheon:
        return '🥪';
    }
  }
}

// 2. Planner Steps Enum
enum PlannerStep {
  details,
  video,
  uploading,
  success,
}

// 3. Planner State
class PlannerState {
  final PlannerStep step;
  final String partyName;
  final String partyDate;
  final PartyType partyType;
  final String guestCount;
  
  // Video step values
  final XFile? recordedVideo;
  final bool isInitializingVideo;
  final String spaceDescription;
  
  // Upload status values
  final double uploadProgress;
  final String? videoReference;
  final String? videoReferenceDownloadUrl;
  
  // UI Status
  final bool isLoading;
  final String? errorMessage;
  final String? partyId;

  PlannerState({
    required this.step,
    required this.partyName,
    required this.partyDate,
    required this.partyType,
    required this.guestCount,
    this.recordedVideo,
    required this.isInitializingVideo,
    required this.spaceDescription,
    required this.uploadProgress,
    this.videoReference,
    this.videoReferenceDownloadUrl,
    required this.isLoading,
    this.errorMessage,
    this.partyId,
  });

  PlannerState copyWith({
    PlannerStep? step,
    String? partyName,
    String? partyDate,
    PartyType? partyType,
    String? guestCount,
    XFile? recordedVideo,
    bool? isInitializingVideo,
    String? spaceDescription,
    double? uploadProgress,
    String? videoReference,
    String? videoReferenceDownloadUrl,
    bool? isLoading,
    String? errorMessage,
    String? partyId,
  }) {
    return PlannerState(
      step: step ?? this.step,
      partyName: partyName ?? this.partyName,
      partyDate: partyDate ?? this.partyDate,
      partyType: partyType ?? this.partyType,
      guestCount: guestCount ?? this.guestCount,
      recordedVideo: recordedVideo ?? this.recordedVideo,
      isInitializingVideo: isInitializingVideo ?? this.isInitializingVideo,
      spaceDescription: spaceDescription ?? this.spaceDescription,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      videoReference: videoReference ?? this.videoReference,
      videoReferenceDownloadUrl: videoReferenceDownloadUrl ?? this.videoReferenceDownloadUrl,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
      partyId: partyId ?? this.partyId,
    );
  }
}

// 4. Planner Cubit
class PlannerCubit extends Cubit<PlannerState> {
  PlannerCubit()
      : super(PlannerState(
          step: PlannerStep.details,
          partyName: "Google's Hackathon Event",
          partyDate: "23 Jan 2027",
          partyType: PartyType.hackathon,
          guestCount: "50 people",
          isInitializingVideo: false,
          spaceDescription: "",
          uploadProgress: 0.0,
          isLoading: false,
        ));

  void updatePartyName(String name) => emit(state.copyWith(partyName: name));
  void updatePartyDate(String date) => emit(state.copyWith(partyDate: date));
  void updatePartyType(PartyType type) => emit(state.copyWith(partyType: type));
  void updateGuestCount(String count) => emit(state.copyWith(guestCount: count));
  void updateSpaceDescription(String desc) => emit(state.copyWith(spaceDescription: desc));
  void updateVideo(XFile? video) => emit(state.copyWith(recordedVideo: video));
  void updateIsInitializingVideo(bool val) => emit(state.copyWith(isInitializingVideo: val));

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
        'date': state.partyDate,
        'type': state.partyType.name,
        'guestCount': state.guestCount,
        'createdAt': FieldValue.serverTimestamp(),
      });

      emit(state.copyWith(
        step: PlannerStep.video,
        partyId: docRef.id,
        isLoading: false,
      ));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to save event details: ${e.toString()}',
      ));
    }
  }

  Future<void> uploadVideo(XFile videoFile) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final partyId = state.partyId;
    if (uid == null || partyId == null) {
      emit(state.copyWith(errorMessage: 'Authentication or Party ID is missing.'));
      return;
    }

    emit(state.copyWith(
      step: PlannerStep.uploading,
      isLoading: true,
      uploadProgress: 0.0,
      errorMessage: null,
    ));

    try {
      // 1. Read bytes for cross-platform compatibility (Web + Mobile)
      final bytes = await videoFile.readAsBytes();
      final ext = videoFile.name.contains('.') ? videoFile.name.split('.').last : 'mp4';
      final fileName = 'video_${DateTime.now().millisecondsSinceEpoch}.$ext';
      
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('users/$uid/parties/$partyId/videos/$fileName');

      // 2. Start upload task
      final uploadTask = storageRef.putData(
        bytes,
        SettableMetadata(contentType: 'video/mp4'),
      );

      // 3. Track progress stream
      final subscription = uploadTask.snapshotEvents.listen((event) {
        if (event.totalBytes > 0) {
          final progress = event.bytesTransferred / event.totalBytes;
          emit(state.copyWith(uploadProgress: progress));
        }
      });

      // 4. Await completeness
      await uploadTask;
      await subscription.cancel();

      // 5. Retrieve references
      final downloadUrl = await storageRef.getDownloadURL();
      final storagePath = storageRef.fullPath;

      // 6. Update Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('parties')
          .doc(partyId)
          .update({
        'videoReference': storagePath,
        'videoReferenceDownloadUrl': downloadUrl,
      });

      emit(state.copyWith(
        step: PlannerStep.success,
        isLoading: false,
        videoReference: storagePath,
        videoReferenceDownloadUrl: downloadUrl,
      ));
    } catch (e) {
      emit(state.copyWith(
        step: PlannerStep.video,
        isLoading: false,
        errorMessage: 'Failed to upload video: ${e.toString()}',
      ));
    }
  }

  void goBackToDetails() {
    emit(state.copyWith(step: PlannerStep.details, errorMessage: null));
  }
}

// 5. Planner Page Widget (Bloc Wrapper)
class PlannerPage extends StatelessWidget {
  const PlannerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => PlannerCubit(),
      child: const PlannerForm(),
    );
  }
}

class PlannerForm extends StatefulWidget {
  const PlannerForm({super.key});

  @override
  State<PlannerForm> createState() => _PlannerFormState();
}

class _PlannerFormState extends State<PlannerForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _dateController;
  late final TextEditingController _guestController;
  late final TextEditingController _descriptionController;

  final ImagePicker _picker = ImagePicker();
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    final cubit = context.read<PlannerCubit>();
    _nameController = TextEditingController(text: cubit.state.partyName);
    _dateController = TextEditingController(text: cubit.state.partyDate);
    _guestController = TextEditingController(text: cubit.state.guestCount);
    _descriptionController = TextEditingController(text: cubit.state.spaceDescription);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dateController.dispose();
    _guestController.dispose();
    _descriptionController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _takeVideo(PlannerCubit cubit) async {
    try {
      final XFile? video = await _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(seconds: 30),
      );

      if (video == null) return;

      cubit.updateVideo(video);
      cubit.updateIsInitializingVideo(true);

      // Dispose existing controller if any
      if (_videoController != null) {
        await _videoController!.dispose();
        _videoController = null;
      }

      // Initialize VideoPlayerController platform-sensitively
      final VideoPlayerController controller;
      if (kIsWeb) {
        controller = VideoPlayerController.networkUrl(Uri.parse(video.path));
      } else {
        controller = VideoPlayerController.file(File(video.path));
      }

      await controller.initialize();
      controller.setLooping(true);

      setState(() {
        _videoController = controller;
      });
      cubit.updateIsInitializingVideo(false);
    } catch (e) {
      cubit.updateIsInitializingVideo(false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error capturing video: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  Future<void> _discardVideo(PlannerCubit cubit) async {
    if (_videoController != null) {
      await _videoController!.dispose();
      _videoController = null;
    }
    cubit.updateVideo(null);
  }

  void _useVideo(PlannerCubit cubit) {
    final video = cubit.state.recordedVideo;
    if (video != null) {
      cubit.uploadVideo(video);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No video captured to upload.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<PlannerCubit>();
    final state = cubit.state;

    // Listeners and triggers
    if (state.errorMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(state.errorMessage!),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Plan A Party',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
        leading: state.step == PlannerStep.video
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                onPressed: () => cubit.goBackToDetails(),
                tooltip: 'Back to Details',
              )
            : null,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: PremiumTheme.backgroundGradient,
        child: SafeArea(
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: state.step == PlannerStep.details
                      ? _buildDetailsStep(cubit, state)
                      : state.step == PlannerStep.video
                          ? _buildVideoStep(cubit, state)
                          : state.step == PlannerStep.uploading
                              ? _buildUploadingStep(cubit, state)
                              : _buildSuccessStep(cubit, state),
                ),
              ),
              if (state.isLoading && state.step != PlannerStep.uploading)
                Container(
                  color: Colors.black.withValues(alpha: 0.5),
                  child: const Center(
                    child: CircularProgressIndicator(color: PremiumTheme.primary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailsStep(PlannerCubit cubit, PlannerState state) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Step Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: PremiumTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'STEP 1 OF 2',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: PremiumTheme.primary,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Tell us about your event',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Fill out the details to create your Firestore event timeline.',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: PremiumTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 32),

          // Details Form Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Party Name
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Party Name',
                      prefixIcon: Icon(Icons.celebration_rounded, size: 20),
                    ),
                    onChanged: cubit.updatePartyName,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a name for the party';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // Pick Date
                  TextFormField(
                    controller: _dateController,
                    decoration: const InputDecoration(
                      labelText: 'Party Date',
                      prefixIcon: Icon(Icons.calendar_today_rounded, size: 20),
                    ),
                    onChanged: cubit.updatePartyDate,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please choose a date';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // Guest Count
                  TextFormField(
                    controller: _guestController,
                    decoration: const InputDecoration(
                      labelText: 'Expected Guest Count',
                      prefixIcon: Icon(Icons.people_outline_rounded, size: 20),
                    ),
                    onChanged: cubit.updateGuestCount,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter expected guests';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),

                  // Party Type Header
                  const Text(
                    'Party Type',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: PremiumTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Choice Chips Grid for Enum
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: PartyType.values.map((type) {
                      final isSelected = state.partyType == type;
                      return ChoiceChip(
                        label: Text('${type.emoji} ${type.displayName}'),
                        selected: isSelected,
                        selectedColor: PremiumTheme.primary.withValues(alpha: 0.25),
                        backgroundColor: PremiumTheme.surface,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : PremiumTheme.textSecondary,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        side: BorderSide(
                          color: isSelected ? PremiumTheme.primary : PremiumTheme.border,
                          width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            cubit.updatePartyType(type);
                          }
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Next Button
          Container(
            decoration: PremiumTheme.primaryButtonGradient,
            child: ElevatedButton.icon(
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  cubit.saveDetailsAndNext();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                elevation: 0,
              ),
              icon: const Icon(Icons.arrow_forward_rounded, color: Colors.white),
              label: const Text('Save & Continue'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoStep(PlannerCubit cubit, PlannerState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Step Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: PremiumTheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'STEP 2 OF 2',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: PremiumTheme.primary,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Greeting & Instructions text
        const Text(
          'Start by describing your space',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Take a short video of your space',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: PremiumTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 32),

        // Description Input Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Space Description',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: PremiumTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _descriptionController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Describe the dimensions, theme, lighting, and any key characteristics of your space...',
                    alignLabelWithHint: true,
                  ),
                  onChanged: cubit.updateSpaceDescription,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Video Capture Section
        if (state.recordedVideo == null) ...[
          // Card representing camera placeholder
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 48.0, horizontal: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: PremiumTheme.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: PremiumTheme.primary.withValues(alpha: 0.3),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.video_call_rounded,
                      size: 40,
                      color: PremiumTheme.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'No Space Video Captured',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: PremiumTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Capture a quick walk-around of your venue to help us optimize your layout setup.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: PremiumTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Container(
                    decoration: PremiumTheme.primaryButtonGradient,
                    child: ElevatedButton.icon(
                      onPressed: () => _takeVideo(cubit),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        elevation: 0,
                        minimumSize: const Size(200, 52),
                      ),
                      icon: const Icon(Icons.videocam_rounded, color: Colors.white),
                      label: const Text('Take Video'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ] else ...[
          // Display recorded video player card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.video_file_rounded, color: PremiumTheme.accent, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Captured Venue Video',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                        onPressed: () => _discardVideo(cubit),
                        tooltip: 'Delete Video',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Player frame
                  Container(
                    height: 220,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: PremiumTheme.border,
                        width: 1.5,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (state.isInitializingVideo)
                          const Center(
                            child: CircularProgressIndicator(color: PremiumTheme.primary),
                          )
                        else if (_videoController != null && _videoController!.value.isInitialized)
                          AspectRatio(
                            aspectRatio: _videoController!.value.aspectRatio,
                            child: VideoPlayer(_videoController!),
                          )
                        else
                          const Center(
                            child: Text(
                              'Error initializing video player',
                              style: TextStyle(color: Colors.redAccent),
                            ),
                          ),
                        
                        // Floating control overlay
                        if (_videoController != null && _videoController!.value.isInitialized)
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _videoController!.value.isPlaying
                                    ? _videoController!.pause()
                                    : _videoController!.play();
                              });
                            },
                            child: Container(
                              color: Colors.black.withValues(alpha: 0.25),
                              child: Center(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.2),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Icon(
                                    _videoController!.value.isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 32,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Control Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _takeVideo(cubit),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: PremiumTheme.border),
                            minimumSize: const Size(0, 52),
                          ),
                          icon: const Icon(Icons.replay_rounded, size: 20),
                          label: const Text('Take New Video', style: TextStyle(fontSize: 14)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Container(
                          decoration: PremiumTheme.primaryButtonGradient,
                          child: ElevatedButton.icon(
                            onPressed: () => _useVideo(cubit),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              elevation: 0,
                              minimumSize: const Size(0, 52),
                            ),
                            icon: const Icon(Icons.check_rounded, color: Colors.white),
                            label: const Text('Use Video', style: TextStyle(fontSize: 14)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildUploadingStep(PlannerCubit cubit, PlannerState state) {
    final percent = (state.uploadProgress * 100).toStringAsFixed(0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: PremiumTheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'UPLOADING VIDEO',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: PremiumTheme.primary,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'Sending your video to Cloud Storage',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Please do not close this screen or navigate away.',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: PremiumTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 48),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 140,
                      height: 140,
                      child: CircularProgressIndicator(
                        value: state.uploadProgress,
                        strokeWidth: 8,
                        backgroundColor: PremiumTheme.surface,
                        color: PremiumTheme.primary,
                      ),
                    ),
                    Text(
                      '$percent%',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                const Text(
                  'Uploading Venue Video...',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: PremiumTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Saving reference details to Cloud Firestore.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: PremiumTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessStep(PlannerCubit cubit, PlannerState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.greenAccent, width: 2),
                  ),
                  child: const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 48,
                    color: Colors.greenAccent,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Planning Flow Completed!',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your party details and spatial layout video have been successfully saved.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: PremiumTheme.textSecondary,
                  ),
                ),
                const Divider(height: 40, color: PremiumTheme.border),
                
                // Summary details
                _buildSummaryRow('Event Name', state.partyName),
                const SizedBox(height: 12),
                _buildSummaryRow('Date', state.partyDate),
                const SizedBox(height: 12),
                _buildSummaryRow('Guests', state.guestCount),
                const SizedBox(height: 12),
                _buildSummaryRow('Type', '${state.partyType.emoji} ${state.partyType.displayName}'),
                
                const SizedBox(height: 32),
                Container(
                  decoration: PremiumTheme.primaryButtonGradient,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      elevation: 0,
                      minimumSize: const Size(double.infinity, 54),
                    ),
                    icon: const Icon(Icons.home_rounded, color: Colors.white),
                    label: const Text('Back to Home'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: PremiumTheme.textSecondary,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}
