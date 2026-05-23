// 1. Party Type Enum
enum PartyType { cocktail, hackathon, dinner, luncheon }

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
