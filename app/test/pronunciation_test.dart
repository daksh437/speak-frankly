// Tests for assessPronunciation — the speaking score.
//
// This is the app's core differentiator and the only non-trivial algorithm in
// it (Needleman–Wunsch alignment plus a traceback), and it decides a number the
// learner is shown and judged by. It is also a pure function with no plugins,
// no network and no Firebase, so there is no excuse for it to be untested.
//
// The contract these lock in: the score reflects how much of the target the
// recogniser caught IN ORDER, near-misses earn partial credit, and a dropped or
// inserted word doesn't knock the rest of the sentence out of alignment.

import 'package:flutter_test/flutter_test.dart';
import 'package:speakflow/services/speech_service.dart';

void main() {
  group('assessPronunciation — overall score', () {
    test('a perfect repeat scores 100', () {
      expect(assessPronunciation('I want a coffee', 'I want a coffee').score, 100);
    });

    test('case and punctuation are ignored', () {
      expect(assessPronunciation('Hello, world!', 'hello world').score, 100);
    });

    test('saying nothing scores 0', () {
      expect(assessPronunciation('I want a coffee', '').score, 0);
    });

    test('an empty target scores 0 and grades no words', () {
      final r = assessPronunciation('', 'anything at all');
      expect(r.score, 0);
      expect(r.words, isEmpty);
    });

    test('a completely different sentence scores low', () {
      expect(assessPronunciation('I want a coffee', 'zebra piano mountain').score, lessThan(30));
    });
  });

  group('assessPronunciation — alignment', () {
    test('a dropped word costs only that word', () {
      // "a" was never heard; the other three still line up.
      final r = assessPronunciation('I want a coffee', 'I want coffee');
      expect(r.score, 75);
      expect(r.words.map((w) => w.word).toList(), ['i', 'want', 'a', 'coffee']);
      expect(r.words[2].similarity, 0.0);
      expect(r.words[3].similarity, 1.0); // NOT thrown off by the gap
    });

    test('an extra spoken word does not shift the rest', () {
      final r = assessPronunciation('I like coffee', 'I really like coffee');
      expect(r.score, 100);
      expect(r.words.every((w) => w.verdict == WordVerdict.good), isTrue);
    });

    test('word order matters — the same words jumbled score lower', () {
      final inOrder = assessPronunciation('I want a coffee', 'I want a coffee').score;
      final jumbled = assessPronunciation('I want a coffee', 'coffee a want I').score;
      expect(jumbled, lessThan(inOrder));
    });
  });

  group('assessPronunciation — partial credit', () {
    test('a near-miss earns partial credit, not a flat zero', () {
      final r = assessPronunciation('want', 'wan');
      expect(r.words.single.similarity, closeTo(0.75, 0.001));
      expect(r.words.single.verdict, WordVerdict.close);
    });

    test('a near-miss beats a completely wrong word', () {
      final near = assessPronunciation('want', 'wan').score;
      final wrong = assessPronunciation('want', 'zebra').score;
      expect(near, greaterThan(wrong));
    });
  });

  group('WordScore verdicts', () {
    test('thresholds split good / close / missed', () {
      expect(const WordScore('x', 1.0).verdict, WordVerdict.good);
      expect(const WordScore('x', 0.8).verdict, WordVerdict.good);
      expect(const WordScore('x', 0.79).verdict, WordVerdict.close);
      expect(const WordScore('x', 0.45).verdict, WordVerdict.close);
      expect(const WordScore('x', 0.44).verdict, WordVerdict.missed);
      expect(const WordScore('x', 0.0).verdict, WordVerdict.missed);
    });

    test('goodCount and missedCount describe the breakdown', () {
      final r = assessPronunciation('I want a coffee', 'I want coffee');
      expect(r.goodCount, 3);
      expect(r.missedCount, 1);
    });
  });

  group('recognizer confidence', () {
    test('is blended in at 15% when the device reports one', () {
      // Perfect words (1.0) with mediocre confidence: 1.0*0.85 + 0.6*0.15.
      final r = assessPronunciation('hello', 'hello', confidence: 0.6);
      expect(r.score, 94);
      expect(r.confidence, 0.6);
    });

    test('is ignored when the device reports none', () {
      expect(assessPronunciation('hello', 'hello', confidence: 0.0).score, 100);
    });

    test('a crisp reading edges out a mumbled one', () {
      final crisp = assessPronunciation('hello there', 'hello there', confidence: 0.95).score;
      final mumbled = assessPronunciation('hello there', 'hello there', confidence: 0.2).score;
      expect(crisp, greaterThan(mumbled));
    });
  });

  group('pronunciationScore (used by the placement test)', () {
    test('matches assessPronunciation with no confidence', () {
      expect(pronunciationScore('I want a coffee', 'I want coffee'),
          assessPronunciation('I want a coffee', 'I want coffee').score);
    });

    test('always returns 0..100', () {
      for (final said in ['', 'I want a coffee', 'zzz', 'a a a a a a a a']) {
        final s = pronunciationScore('I want a coffee', said);
        expect(s, inInclusiveRange(0, 100));
      }
    });
  });
}
