/**
 * Seed scenario library. In a later phase these move to Firestore so they can be
 * edited without a deploy, but hardcoding the MVP set keeps the app usable offline
 * and with zero setup. Each scenario drives the tutor's system prompt.
 *
 * levels: A0 (absolute beginner) → C1 (advanced), roughly CEFR-aligned.
 */
const SCENARIOS = [
  {
    id: 'ordering-food',
    title: 'Ordering Food',
    emoji: '🍔',
    theme: 'daily',
    level: 'A1',
    description: 'Order a meal at a restaurant and talk to the waiter.',
    setup: 'You are a friendly waiter at a casual restaurant. The learner is a customer who just sat down.',
    goals: ['Greet and be seated', 'Order a drink and a main dish', 'Ask for the bill'],
    starter: 'Hi there! Welcome. Here is the menu — can I get you something to drink first?',
    keywords: ['menu', 'order', 'drink', 'main course', 'bill', 'delicious', 'recommend'],
  },
  {
    id: 'job-interview',
    title: 'Job Interview',
    emoji: '💼',
    theme: 'work',
    level: 'B1',
    description: 'Practice a simple job interview for an entry-level role.',
    setup: 'You are a polite hiring manager interviewing the learner for an entry-level job. Ask common interview questions one at a time.',
    goals: ['Introduce yourself', 'Talk about your strengths', 'Ask a question about the role'],
    starter: "Thanks for coming in today. To start, could you tell me a little about yourself?",
    keywords: ['experience', 'strength', 'weakness', 'team', 'responsibility', 'salary', 'opportunity'],
  },
  {
    id: 'shopping',
    title: 'Shopping for Clothes',
    emoji: '🛍️',
    theme: 'daily',
    level: 'A1',
    description: 'Buy clothes: ask for size, color, and price.',
    setup: 'You are a helpful shop assistant in a clothing store. The learner wants to buy something.',
    goals: ['Ask for a size', 'Ask the price', 'Decide to buy or not'],
    starter: 'Hello! Are you looking for anything in particular today?',
    keywords: ['size', 'price', 'try on', 'fit', 'color', 'discount', 'receipt'],
  },
  {
    id: 'doctor-visit',
    title: 'At the Doctor',
    emoji: '🏥',
    theme: 'daily',
    level: 'A2',
    description: 'Describe symptoms to a doctor.',
    setup: 'You are a kind doctor. The learner is a patient describing how they feel. Ask gentle follow-up questions.',
    goals: ['Describe a symptom', 'Answer the doctor’s questions', 'Understand the advice'],
    starter: 'Good morning. Please have a seat. So, what seems to be the problem today?',
    keywords: ['pain', 'fever', 'headache', 'medicine', 'rest', 'prescription', 'appointment'],
  },
  {
    id: 'small-talk',
    title: 'Making Small Talk',
    emoji: '💬',
    theme: 'social',
    level: 'A2',
    description: 'Chat casually with a new acquaintance.',
    setup: 'You are a friendly person meeting the learner at a social event. Keep the conversation light and ask about their hobbies, work, and weekend.',
    goals: ['Introduce yourself', 'Ask and answer casual questions', 'Keep the conversation going'],
    starter: "Hi! I don't think we've met — I'm Alex. So, what do you do?",
    keywords: ['hobby', 'weekend', 'weather', 'interesting', 'nice to meet you', 'by the way'],
  },
  {
    id: 'airport',
    title: 'At the Airport',
    emoji: '✈️',
    theme: 'travel',
    level: 'A2',
    description: 'Check in for a flight and pass through the gate.',
    setup: 'You are an airline check-in agent. The learner is a traveler checking in for a flight.',
    goals: ['Check in and show your passport', 'Ask about your gate and baggage', 'Understand boarding info'],
    starter: 'Good afternoon! May I see your passport and ticket, please?',
    keywords: ['passport', 'boarding pass', 'gate', 'luggage', 'window seat', 'delay', 'departure'],
  },
];

function listScenarios() {
  return SCENARIOS.map(({ setup, ...pub }) => pub); // hide the internal system-prompt setup
}

function getScenario(id) {
  return SCENARIOS.find((s) => s.id === id) || null;
}

module.exports = { listScenarios, getScenario, SCENARIOS };
