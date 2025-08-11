const mongoose = require('mongoose');
const Schema = mongoose.Schema;
const SubscriptionSchema = new Schema({
  subscription: { type: Object, required: true },
  createdAt: { type: Date, default: Date.now }
});
module.exports = mongoose.model('subscriptions', SubscriptionSchema);
