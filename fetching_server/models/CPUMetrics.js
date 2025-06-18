const mongoose = require('mongoose');

const cpuMetricsSchema = new mongoose.Schema({
    deviceId: {
        type: String,
        required: true
    },
    idleSeconds: Number,
    totalSeconds: Number,
    usagePercentage: Number,
    userPercentage: Number,
    sysPercentage: Number,
    timestamp: {
        type: Date,
        default: Date.now
    }
});

module.exports = mongoose.model('cpu_metrics', cpuMetricsSchema);