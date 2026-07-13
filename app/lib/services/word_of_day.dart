/// Word of the Day (daily challenge). A bundled, offline list — one useful word
/// or phrase is surfaced each day (deterministic by date) to build a daily habit.
class DailyWord {
  final String word;
  final String meaning;
  final String example;
  const DailyWord(this.word, this.meaning, this.example);
}

class WordOfDay {
  static const List<DailyWord> _words = [
    DailyWord('appreciate', 'to be thankful for something', 'I really appreciate your help.'),
    DailyWord('available', 'free or ready to use', 'Are you available tomorrow?'),
    DailyWord('by the way', 'used to add a new topic', 'By the way, did you call her?'),
    DailyWord('confident', 'sure about yourself', 'She is confident when she speaks.'),
    DailyWord('convenient', 'easy and useful for you', 'Is this time convenient for you?'),
    DailyWord('curious', 'wanting to know more', "I'm curious about your new job."),
    DailyWord('deal with', 'to handle a problem', 'I will deal with it tomorrow.'),
    DailyWord('delicious', 'tasting very good', 'This soup is delicious!'),
    DailyWord('depend on', 'to be decided by something', 'It depends on the weather.'),
    DailyWord('eventually', 'in the end, after some time', 'He eventually found a job.'),
    DailyWord('figure out', 'to understand or solve', "Let me figure out the answer."),
    DailyWord('fluent', 'able to speak easily', 'She is fluent in English.'),
    DailyWord('get along', 'to have a good relationship', 'I get along with my coworkers.'),
    DailyWord('grateful', 'feeling thankful', "I'm grateful for this chance."),
    DailyWord('handle', 'to manage or control', 'Can you handle this task?'),
    DailyWord('honest', 'telling the truth', 'Please be honest with me.'),
    DailyWord('improve', 'to get better', 'I want to improve my speaking.'),
    DailyWord('in charge of', 'responsible for', "She's in charge of the team."),
    DailyWord('look forward to', 'to feel happy about the future', 'I look forward to meeting you.'),
    DailyWord('make sense', 'to be clear or logical', 'That makes sense now.'),
    DailyWord('manage to', 'to succeed in doing', 'I managed to finish on time.'),
    DailyWord('mention', 'to say something briefly', 'She mentioned your name.'),
    DailyWord('nervous', 'worried or anxious', "I'm nervous about the interview."),
    DailyWord('on purpose', 'done intentionally', "I didn't do it on purpose."),
    DailyWord('opportunity', 'a good chance', 'This is a great opportunity.'),
    DailyWord('point out', 'to show or tell', 'She pointed out my mistake.'),
    DailyWord('polite', 'having good manners', 'He is always polite to others.'),
    DailyWord('prefer', 'to like better', 'I prefer tea to coffee.'),
    DailyWord('recommend', 'to suggest something good', 'Can you recommend a good book?'),
    DailyWord('reliable', 'able to be trusted', 'He is a reliable worker.'),
    DailyWord('remind', 'to help someone remember', 'Please remind me tomorrow.'),
    DailyWord('run out of', 'to have none left', 'We ran out of milk.'),
    DailyWord('satisfied', 'happy with something', 'I am satisfied with the result.'),
    DailyWord('schedule', 'a plan of times', "What's your schedule today?"),
    DailyWord('struggle', 'to have difficulty', 'I struggle with pronunciation.'),
    DailyWord('take care of', 'to look after', 'She takes care of her family.'),
    DailyWord('turn out', 'to happen in the end', 'It turned out to be easy.'),
    DailyWord('used to', 'something true in the past', 'I used to live in Delhi.'),
    DailyWord('willing', 'happy to do something', "I'm willing to learn."),
    DailyWord('worth it', 'good enough for the effort', 'The hard work was worth it.'),
  ];

  /// Today's word — the same for everyone on a given day, changes each day.
  static DailyWord today() {
    final now = DateTime.now();
    final doy = int.parse('${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}');
    return _words[doy % _words.length];
  }
}
