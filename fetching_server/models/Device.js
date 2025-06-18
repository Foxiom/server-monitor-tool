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
    }
});

module.exports = mongoose.model('servers', deviceSchema);