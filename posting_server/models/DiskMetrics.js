const mongoose = require('mongoose');

const diskMetricsSchema = new mongoose.Schema({
    deviceId: {
        type: String,
        required: true
    },
    filesystem: String,
    size: Number,
    used: Number,
    available: Number,
    mount: String,
    usagePercentage: Number,
    timestamp: {
        type: Date,
        default: Date.now
    }
});

module.exports = mongoose.model('disk_metrics', diskMetricsSchema);