// utils/pushSender.js
const webpush = require('../config/webpush');
const Subscription = require('../models/Subscription');

async function sendToSubscription(sub, payload) {
  try {
    await webpush.sendNotification(sub.subscription, JSON.stringify(payload));
  } catch (err) {
    // cleanup expired or forbidden subs
    if (err.statusCode === 410 || err.statusCode === 404) {
      await Subscription.deleteOne({ 'subscription.endpoint': sub.subscription.endpoint });
    } else {
      console.error('Push send error', err);
    }
  }
}

async function broadcast(payload, filter = {}) {
  const subs = await Subscription.find(filter);
  await Promise.all(subs.map(s => sendToSubscription(s, payload)));
}

module.exports = { broadcast, sendToSubscription };
