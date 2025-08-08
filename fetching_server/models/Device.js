const mongoose = require('mongoose');

const deviceSchema = new mongoose.Schema({
    deviceName: String,
    osPlatform: String,
    osRelease: String,
    osType: String,
    osVersion: String,
    osArchitecture: String,
    ipV4: {
        type: String,
        unique: true
    },
    deviceId: {
        type: String,
        unique: true
    },
    timestamp: {
        type: Date,
        default: Date.now
    },
    status: {
        type: String,
        enum: ['up', 'down', "critical", "trouble"],
        default: 'up'
    },
    alertSent: {
        type: Boolean,
        default: false
    },
    metrics: {
        cpu: Number,
        memory: Number,
        disk: Number,
        lastUpdated: Date
    }
});

module.exports = mongoose.model('servers', deviceSchema);