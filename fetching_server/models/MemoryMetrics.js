const mongoose = require('mongoose');

const memoryMetricsSchema = new mongoose.Schema({
    deviceId: {
        type: String,
        required: true
    },
    totalMemory: Number,
    freeMemory: Number,
    usedMemory: Number,
    usagePercentage: Number,
    timestamp: {
        type: Date,
        default: Date.now
    }
});

module.exports = mongoose.model('memory_metrics', memoryMetricsSchema);