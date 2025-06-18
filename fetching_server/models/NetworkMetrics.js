const mongoose = require('mongoose');

const networkMetricsSchema = new mongoose.Schema({
    deviceId: {
        type: String,
        required: true
    },
    interface: String,
    bytesReceived: Number,
    bytesSent: Number,
    packetsReceived: Number,
    packetsSent: Number,
    errorsReceived: Number,
    errorsSent: Number,
    timestamp: {
        type: Date,
        default: Date.now
    }
});

module.exports = mongoose.model('network_metrics', networkMetricsSchema);