part of 'planner_cubit.dart';

// 3. Planner State
class PlannerState {
  final PlannerStep step;
  final String partyName;
  final DateTime partyDate;
  final PartyType partyType;
  final int guestCount;

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

  // Recommendations step values
  final String? recommendationImage;
  final String? recommendationText;

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
    this.recommendationImage,
    this.recommendationText,
  });

  PlannerState copyWith({
    PlannerStep? step,
    String? partyName,
    DateTime? partyDate,
    PartyType? partyType,
    int? guestCount,
    XFile? recordedVideo,
    bool? isInitializingVideo,
    String? spaceDescription,
    double? uploadProgress,
    String? videoReference,
    String? videoReferenceDownloadUrl,
    bool? isLoading,
    String? errorMessage,
    String? partyId,
    String? recommendationImage,
    String? recommendationText,
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
      videoReferenceDownloadUrl:
          videoReferenceDownloadUrl ?? this.videoReferenceDownloadUrl,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
      partyId: partyId ?? this.partyId,
      recommendationImage: recommendationImage ?? this.recommendationImage,
      recommendationText: recommendationText ?? this.recommendationText,
    );
  }
}
