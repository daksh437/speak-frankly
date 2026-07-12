import '../models/story.dart';

/// Bundled scripted stories (BRD §4.1). Fully offline and free — no AI calls.
/// Each story is a small dialogue tree: tutor line → learner choices → next node.
List<Story> allStories() => const [
      _orderingFood,
      _jobInterview,
      _atTheDoctor,
      _shopping,
      _coffeeShop,
      _directions,
      _hotelCheckin,
      _makingFriends,
    ];

Story? storyById(String id) {
  for (final s in allStories()) {
    if (s.id == id) return s;
  }
  return null;
}

// ── 🍔 Ordering Food (A1) ───────────────────────────────────────────────────
const _orderingFood = Story(
  id: 'story-ordering-food',
  title: 'Ordering Food',
  emoji: '🍔',
  level: 'A1',
  description: 'Order a meal at a restaurant and talk to the waiter.',
  keywords: ['menu', 'order', 'drink', 'bill', 'delicious', 'recommend'],
  startId: 'greet',
  nodes: {
    'greet': StoryNode(
      'greet',
      'Good evening! Welcome. A table for how many?',
      choices: [
        StoryChoice('A table for two, please.', 'seated'),
        StoryChoice('Two people.', 'seated', note: "Understood! A little more natural: 'A table for two, please.'", good: false),
      ],
    ),
    'seated': StoryNode(
      'seated',
      'Great, this way please. Here is the menu. Can I get you something to drink?',
      choices: [
        StoryChoice('Some water, please.', 'drink_water'),
        StoryChoice('What do you recommend?', 'recommend'),
      ],
    ),
    'drink_water': StoryNode(
      'drink_water',
      'Sure, water coming up. Are you ready to order your food?',
      choices: [
        StoryChoice("Yes, I'll have a burger, please.", 'side'),
        StoryChoice('Give me a burger.', 'side', note: "Politer: 'Could I have a burger, please?'", good: false),
      ],
    ),
    'recommend': StoryNode(
      'recommend',
      'Our cheese burger is very popular and really delicious. Would you like to try it?',
      choices: [
        StoryChoice('Yes, that sounds good. One please.', 'side'),
        StoryChoice('No, I will take a salad.', 'side'),
      ],
    ),
    'side': StoryNode(
      'side',
      'Good choice! Would you like fries on the side?',
      choices: [
        StoryChoice('Yes, please, with fries.', 'wait'),
        StoryChoice('No, thank you.', 'wait'),
      ],
    ),
    'wait': StoryNode(
      'wait',
      'Perfect. Your food will be ready in ten minutes.',
      choices: [
        StoryChoice('Thank you!', 'bill'),
        StoryChoice('Can I have the bill after, please?', 'bill'),
      ],
    ),
    'bill': StoryNode(
      'bill',
      'Of course. Here is your bill. I hope you enjoyed your meal!',
      choices: [
        StoryChoice('It was delicious. Thank you!', ''),
        StoryChoice('Yes, very good. Goodbye!', ''),
      ],
    ),
  },
);

// ── 💼 Job Interview (B1) ───────────────────────────────────────────────────
const _jobInterview = Story(
  id: 'story-job-interview',
  title: 'Job Interview',
  emoji: '💼',
  level: 'B1',
  description: 'Practise a simple interview for an entry-level role.',
  keywords: ['experience', 'strength', 'teamwork', 'responsibility', 'opportunity'],
  startId: 'intro',
  nodes: {
    'intro': StoryNode(
      'intro',
      "Thanks for coming in. To start, could you tell me a little about yourself?",
      choices: [
        StoryChoice("Sure. I'm a hard-working person who enjoys learning new things.", 'why'),
        StoryChoice('I am good. I want this job.', 'why', note: "Try describing yourself: 'I'm reliable and I enjoy working with people.'", good: false),
      ],
    ),
    'why': StoryNode(
      'why',
      'Nice. Why are you interested in this position?',
      choices: [
        StoryChoice("It's a great opportunity to grow and use my skills.", 'branch'),
        StoryChoice('Because I need money.', 'branch', note: "Honest, but focus on the role: 'I want to learn and grow here.'", good: false),
      ],
    ),
    'branch': StoryNode(
      'branch',
      'Would you rather tell me about your strengths, or about your past experience?',
      choices: [
        StoryChoice('Let me tell you about my strengths.', 'strengths'),
        StoryChoice('I can talk about my experience.', 'experience'),
      ],
    ),
    'strengths': StoryNode(
      'strengths',
      "Please do — what would you say is your biggest strength?",
      choices: [
        StoryChoice("I'm good at teamwork and I stay calm under pressure.", 'question'),
        StoryChoice('I am never late and I work hard.', 'question'),
      ],
    ),
    'experience': StoryNode(
      'experience',
      'Great — tell me about a responsibility you had in your last role.',
      choices: [
        StoryChoice('I handled customer questions and solved their problems.', 'question'),
        StoryChoice('I helped my team finish projects on time.', 'question'),
      ],
    ),
    'question': StoryNode(
      'question',
      "That's good to hear. Do you have any questions for me?",
      choices: [
        StoryChoice('Yes — what does a normal day look like in this role?', ''),
        StoryChoice('When can I expect to hear back?', ''),
      ],
    ),
  },
);

// ── 🏥 At the Doctor (A2) ───────────────────────────────────────────────────
const _atTheDoctor = Story(
  id: 'story-at-the-doctor',
  title: 'At the Doctor',
  emoji: '🏥',
  level: 'A2',
  description: "Describe how you feel and understand the doctor's advice.",
  keywords: ['symptom', 'headache', 'fever', 'medicine', 'rest', 'prescription'],
  startId: 'hello',
  nodes: {
    'hello': StoryNode(
      'hello',
      'Hello, please have a seat. What seems to be the problem today?',
      choices: [
        StoryChoice("I don't feel well. I have a bad headache.", 'howlong'),
        StoryChoice('My head is paining.', 'howlong', note: "In English we say: 'I have a headache' or 'My head hurts.'", good: false),
      ],
    ),
    'howlong': StoryNode(
      'howlong',
      "I'm sorry to hear that. How long have you had this headache?",
      choices: [
        StoryChoice('Since yesterday morning.', 'fever'),
        StoryChoice('For about two days.', 'fever'),
      ],
    ),
    'fever': StoryNode(
      'fever',
      'I see. Do you also have a fever or any other symptoms?',
      choices: [
        StoryChoice('Yes, I have a slight fever too.', 'advise_rest'),
        StoryChoice('No, just the headache.', 'advise_medicine'),
      ],
    ),
    'advise_rest': StoryNode(
      'advise_rest',
      "Okay. You should rest, drink water, and take this medicine twice a day.",
      choices: [
        StoryChoice('How many days should I take it?', 'days'),
        StoryChoice('Okay, thank you, doctor.', 'days'),
      ],
    ),
    'advise_medicine': StoryNode(
      'advise_medicine',
      "It's probably from stress or screen time. Take this medicine if the pain is strong.",
      choices: [
        StoryChoice('How many days should I take it?', 'days'),
        StoryChoice('Should I come back if it continues?', 'days'),
      ],
    ),
    'days': StoryNode(
      'days',
      'Take it for three days. If you feel worse, please come back to see me.',
      choices: [
        StoryChoice('Thank you, doctor. I will.', ''),
        StoryChoice('Alright, thank you for your help.', ''),
      ],
    ),
  },
);

// ── 🛍️ Shopping for Clothes (A2) ───────────────────────────────────────────
const _shopping = Story(
  id: 'story-shopping',
  title: 'Shopping for Clothes',
  emoji: '🛍️',
  level: 'A2',
  description: 'Ask for sizes, try clothes on, and pay at the store.',
  keywords: ['size', 'try on', 'fitting room', 'colour', 'price', 'card'],
  startId: 'welcome',
  nodes: {
    'welcome': StoryNode(
      'welcome',
      'Hi there! Welcome. Are you looking for anything special today?',
      choices: [
        StoryChoice("Yes, I'm looking for a blue shirt.", 'size'),
        StoryChoice("I'm just looking, thanks.", 'looking'),
      ],
    ),
    'looking': StoryNode(
      'looking',
      'No problem, take your time. Let me know if you need any help.',
      choices: [
        StoryChoice('Actually, do you have this shirt in blue?', 'size'),
        StoryChoice('Thanks, I will.', 'size'),
      ],
    ),
    'size': StoryNode(
      'size',
      'Sure! What size do you need?',
      choices: [
        StoryChoice('Medium, please.', 'tryon'),
        StoryChoice('I am not sure. Can you help me?', 'tryon'),
      ],
    ),
    'tryon': StoryNode(
      'tryon',
      'Here you go. Would you like to try it on? The fitting room is over there.',
      choices: [
        StoryChoice('Yes, where is the fitting room?', 'fits'),
        StoryChoice('No, I think it will fit.', 'price'),
      ],
    ),
    'fits': StoryNode(
      'fits',
      'It looks great on you! Would you like to buy it?',
      choices: [
        StoryChoice('Yes, I love it. How much is it?', 'price'),
        StoryChoice('It fits well. I will take it.', 'price'),
      ],
    ),
    'price': StoryNode(
      'price',
      "It's twenty dollars. How would you like to pay?",
      choices: [
        StoryChoice('By card, please.', ''),
        StoryChoice('With cash.', ''),
      ],
    ),
  },
);

// ── ☕ At a Coffee Shop (A1) ────────────────────────────────────────────────
const _coffeeShop = Story(
  id: 'story-coffee-shop',
  title: 'At a Coffee Shop',
  emoji: '☕',
  level: 'A1',
  description: 'Order a coffee and a snack to go.',
  keywords: ['coffee', 'size', 'milk', 'to go', 'card'],
  startId: 'hi',
  nodes: {
    'hi': StoryNode(
      'hi',
      'Hi! Welcome. What can I get for you?',
      choices: [
        StoryChoice("Can I have a coffee, please?", 'size'),
        StoryChoice('One coffee.', 'size', note: "Add 'please' to be polite: 'A coffee, please.'", good: false),
      ],
    ),
    'size': StoryNode(
      'size',
      'Sure! What size — small, medium, or large?',
      choices: [
        StoryChoice('Medium, please.', 'milk'),
        StoryChoice('A large one.', 'milk'),
      ],
    ),
    'milk': StoryNode(
      'milk',
      'Would you like any milk or sugar?',
      choices: [
        StoryChoice('A little milk, no sugar.', 'snack'),
        StoryChoice('No, thank you. Black is fine.', 'snack'),
      ],
    ),
    'snack': StoryNode(
      'snack',
      'Anything to eat with that? Our cookies are fresh.',
      choices: [
        StoryChoice('Yes, one cookie please.', 'pay'),
        StoryChoice('No, just the coffee.', 'pay'),
      ],
    ),
    'pay': StoryNode(
      'pay',
      "Great. That'll be four dollars. For here or to go?",
      choices: [
        StoryChoice('To go, please. Here is my card.', ''),
        StoryChoice('For here. Can I pay by card?', ''),
      ],
    ),
  },
);

// ── 🗺️ Asking for Directions (A1) ──────────────────────────────────────────
const _directions = Story(
  id: 'story-directions',
  title: 'Asking for Directions',
  emoji: '🗺️',
  level: 'A1',
  description: 'Ask a stranger how to reach the station.',
  keywords: ['left', 'right', 'straight', 'corner', 'near'],
  startId: 'excuse',
  nodes: {
    'excuse': StoryNode(
      'excuse',
      'Hi, you look lost — can I help you?',
      choices: [
        StoryChoice('Yes, please. Where is the train station?', 'straight'),
        StoryChoice('Station where?', 'straight', note: "Try: 'How do I get to the station?'", good: false),
      ],
    ),
    'straight': StoryNode(
      'straight',
      "Sure! Go straight down this road, then turn left at the corner. Got it?",
      choices: [
        StoryChoice('Turn left at the corner. Is it far?', 'near'),
        StoryChoice('Sorry, can you say that again?', 'repeat'),
      ],
    ),
    'repeat': StoryNode(
      'repeat',
      'No problem. Go straight, then turn left at the corner. The station is right there.',
      choices: [
        StoryChoice('Okay, straight then left. Thank you!', 'near'),
      ],
    ),
    'near': StoryNode(
      'near',
      "It's very near — about a five minute walk.",
      choices: [
        StoryChoice('Thank you so much for your help!', ''),
        StoryChoice('Great, thanks! Have a nice day.', ''),
      ],
    ),
  },
);

// ── 🏨 Hotel Check-in (A2) ──────────────────────────────────────────────────
const _hotelCheckin = Story(
  id: 'story-hotel-checkin',
  title: 'Hotel Check-in',
  emoji: '🏨',
  level: 'A2',
  description: 'Check into a hotel and ask about breakfast.',
  keywords: ['reservation', 'room', 'breakfast', 'wifi', 'key'],
  startId: 'welcome',
  nodes: {
    'welcome': StoryNode(
      'welcome',
      'Good evening, welcome! Do you have a reservation?',
      choices: [
        StoryChoice('Yes, under the name Kumar.', 'found'),
        StoryChoice('No, do you have any rooms free?', 'walkin'),
      ],
    ),
    'found': StoryNode(
      'found',
      'Let me check… yes, a room for two nights. Here you are.',
      choices: [
        StoryChoice('Great. What time is breakfast?', 'breakfast'),
        StoryChoice('Thank you. Is there wifi in the room?', 'wifi'),
      ],
    ),
    'walkin': StoryNode(
      'walkin',
      "You're in luck — we have one room left for tonight.",
      choices: [
        StoryChoice("Perfect, I'll take it. What time is breakfast?", 'breakfast'),
        StoryChoice('Good. Is there wifi in the room?', 'wifi'),
      ],
    ),
    'breakfast': StoryNode(
      'breakfast',
      'Breakfast is from seven to ten in the morning, on the ground floor.',
      choices: [
        StoryChoice('Great, thank you. Can I have my key?', 'key'),
      ],
    ),
    'wifi': StoryNode(
      'wifi',
      'Yes, free wifi. The password is on the desk in your room.',
      choices: [
        StoryChoice('Perfect. Could I have my key, please?', 'key'),
      ],
    ),
    'key': StoryNode(
      'key',
      'Of course. Room 204, second floor. Enjoy your stay!',
      choices: [
        StoryChoice('Thank you very much!', ''),
        StoryChoice('Thanks a lot. Have a good night!', ''),
      ],
    ),
  },
);

// ── 💬 Making Friends (A2) ──────────────────────────────────────────────────
const _makingFriends = Story(
  id: 'story-making-friends',
  title: 'Making a New Friend',
  emoji: '💬',
  level: 'A2',
  description: 'Chat with someone new at a party.',
  keywords: ['hobby', 'weekend', 'nice to meet you', 'by the way', 'catch up'],
  startId: 'intro',
  nodes: {
    'intro': StoryNode(
      'intro',
      "Hi! I don't think we've met. I'm Sam.",
      choices: [
        StoryChoice("Hi Sam, nice to meet you! I'm Alex.", 'how'),
        StoryChoice('Hello. I am Alex.', 'how', note: "Warmer: 'Nice to meet you, I'm Alex.'", good: false),
      ],
    ),
    'how': StoryNode(
      'how',
      'Nice to meet you too! So, how do you know the host?',
      choices: [
        StoryChoice("We work together. And you?", 'hobby'),
        StoryChoice("We're old college friends. What about you?", 'hobby'),
      ],
    ),
    'hobby': StoryNode(
      'hobby',
      "Oh nice! So what do you like to do in your free time?",
      choices: [
        StoryChoice('I love playing football on weekends.', 'common'),
        StoryChoice('I enjoy reading and cooking.', 'common'),
      ],
    ),
    'common': StoryNode(
      'common',
      "That's cool! We should hang out sometime. Can I get your number?",
      choices: [
        StoryChoice('Sure! That sounds great.', ''),
        StoryChoice("Of course. Let's catch up soon!", ''),
      ],
    ),
  },
);
