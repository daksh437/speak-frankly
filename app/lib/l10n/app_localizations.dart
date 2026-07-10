import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('hi'),
    Locale('pt'),
  ];

  /// No description provided for @navPractice.
  ///
  /// In en, this message translates to:
  /// **'Practice'**
  String get navPractice;

  /// No description provided for @navSpeak.
  ///
  /// In en, this message translates to:
  /// **'Speak'**
  String get navSpeak;

  /// No description provided for @navWords.
  ///
  /// In en, this message translates to:
  /// **'Words'**
  String get navWords;

  /// No description provided for @navProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// No description provided for @getStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get getStarted;

  /// No description provided for @startLearning.
  ///
  /// In en, this message translates to:
  /// **'Start learning'**
  String get startLearning;

  /// No description provided for @continueLabel.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @takesSeconds.
  ///
  /// In en, this message translates to:
  /// **'Takes 30 seconds'**
  String get takesSeconds;

  /// No description provided for @welcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Speak Frankly'**
  String get welcomeTitle;

  /// No description provided for @welcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Learn English by talking — no fear, just real conversation.'**
  String get welcomeSubtitle;

  /// No description provided for @featureScenarios.
  ///
  /// In en, this message translates to:
  /// **'Real-life scenarios'**
  String get featureScenarios;

  /// No description provided for @featureTapWord.
  ///
  /// In en, this message translates to:
  /// **'Tap any word'**
  String get featureTapWord;

  /// No description provided for @featureCorrections.
  ///
  /// In en, this message translates to:
  /// **'Gentle corrections'**
  String get featureCorrections;

  /// No description provided for @qLanguage.
  ///
  /// In en, this message translates to:
  /// **'What language do you speak?'**
  String get qLanguage;

  /// No description provided for @qLanguageSub.
  ///
  /// In en, this message translates to:
  /// **'We\'ll translate and explain in your language.'**
  String get qLanguageSub;

  /// No description provided for @qGoal.
  ///
  /// In en, this message translates to:
  /// **'Why do you want English?'**
  String get qGoal;

  /// No description provided for @qGoalSub.
  ///
  /// In en, this message translates to:
  /// **'We\'ll pick scenarios that fit your goal.'**
  String get qGoalSub;

  /// No description provided for @qLevel.
  ///
  /// In en, this message translates to:
  /// **'What\'s your level?'**
  String get qLevel;

  /// No description provided for @qLevelSub.
  ///
  /// In en, this message translates to:
  /// **'No test needed — just pick what feels right.'**
  String get qLevelSub;

  /// No description provided for @goalJob.
  ///
  /// In en, this message translates to:
  /// **'Job / Interview'**
  String get goalJob;

  /// No description provided for @goalTravel.
  ///
  /// In en, this message translates to:
  /// **'Travel'**
  String get goalTravel;

  /// No description provided for @goalStudy.
  ///
  /// In en, this message translates to:
  /// **'Study abroad'**
  String get goalStudy;

  /// No description provided for @goalTalking.
  ///
  /// In en, this message translates to:
  /// **'Just talking'**
  String get goalTalking;

  /// No description provided for @levelBeginner.
  ///
  /// In en, this message translates to:
  /// **'Beginner'**
  String get levelBeginner;

  /// No description provided for @levelBeginnerSub.
  ///
  /// In en, this message translates to:
  /// **'I am just starting'**
  String get levelBeginnerSub;

  /// No description provided for @levelSomeWords.
  ///
  /// In en, this message translates to:
  /// **'Some words'**
  String get levelSomeWords;

  /// No description provided for @levelSomeWordsSub.
  ///
  /// In en, this message translates to:
  /// **'I know a few words & phrases'**
  String get levelSomeWordsSub;

  /// No description provided for @levelConversational.
  ///
  /// In en, this message translates to:
  /// **'Conversational'**
  String get levelConversational;

  /// No description provided for @levelConversationalSub.
  ///
  /// In en, this message translates to:
  /// **'I can already hold a chat'**
  String get levelConversationalSub;

  /// No description provided for @goodMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get goodMorning;

  /// No description provided for @goodAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get goodAfternoon;

  /// No description provided for @goodEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get goodEvening;

  /// No description provided for @letsSpeak.
  ///
  /// In en, this message translates to:
  /// **'Let\'s speak English'**
  String get letsSpeak;

  /// No description provided for @chooseScenario.
  ///
  /// In en, this message translates to:
  /// **'Choose a scenario'**
  String get chooseScenario;

  /// No description provided for @talkAnything.
  ///
  /// In en, this message translates to:
  /// **'Talk about anything'**
  String get talkAnything;

  /// No description provided for @talkAnythingSub.
  ///
  /// In en, this message translates to:
  /// **'Type any topic — the tutor starts a chat'**
  String get talkAnythingSub;

  /// No description provided for @pictureMatch.
  ///
  /// In en, this message translates to:
  /// **'Picture match'**
  String get pictureMatch;

  /// No description provided for @pictureMatchSub.
  ///
  /// In en, this message translates to:
  /// **'Match the scene to the sentence'**
  String get pictureMatchSub;

  /// No description provided for @statStreak.
  ///
  /// In en, this message translates to:
  /// **'Streak'**
  String get statStreak;

  /// No description provided for @statXp.
  ///
  /// In en, this message translates to:
  /// **'XP'**
  String get statXp;

  /// No description provided for @statLevel.
  ///
  /// In en, this message translates to:
  /// **'Level'**
  String get statLevel;

  /// No description provided for @couldntReachServer.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the server. Check your connection and retry.'**
  String get couldntReachServer;

  /// No description provided for @fluencyMap.
  ///
  /// In en, this message translates to:
  /// **'Fluency map'**
  String get fluencyMap;

  /// No description provided for @badges.
  ///
  /// In en, this message translates to:
  /// **'Badges'**
  String get badges;

  /// No description provided for @yourLearning.
  ///
  /// In en, this message translates to:
  /// **'Your learning'**
  String get yourLearning;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @nativeLanguage.
  ///
  /// In en, this message translates to:
  /// **'Native language'**
  String get nativeLanguage;

  /// No description provided for @goalLabel.
  ///
  /// In en, this message translates to:
  /// **'Goal'**
  String get goalLabel;

  /// No description provided for @levelLabel.
  ///
  /// In en, this message translates to:
  /// **'Level'**
  String get levelLabel;

  /// No description provided for @nameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get nameLabel;

  /// No description provided for @testMyLevel.
  ///
  /// In en, this message translates to:
  /// **'Test my level'**
  String get testMyLevel;

  /// No description provided for @aboutLabel.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutLabel;

  /// No description provided for @skillConversations.
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get skillConversations;

  /// No description provided for @skillSpeaking.
  ///
  /// In en, this message translates to:
  /// **'Speaking'**
  String get skillSpeaking;

  /// No description provided for @skillVocabulary.
  ///
  /// In en, this message translates to:
  /// **'Vocabulary'**
  String get skillVocabulary;

  /// No description provided for @skillConsistency.
  ///
  /// In en, this message translates to:
  /// **'Consistency'**
  String get skillConsistency;

  /// No description provided for @savedWords.
  ///
  /// In en, this message translates to:
  /// **'Saved Words'**
  String get savedWords;

  /// No description provided for @review.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get review;

  /// No description provided for @importText.
  ///
  /// In en, this message translates to:
  /// **'Import text'**
  String get importText;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es', 'fr', 'hi', 'pt'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'hi':
      return AppLocalizationsHi();
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
