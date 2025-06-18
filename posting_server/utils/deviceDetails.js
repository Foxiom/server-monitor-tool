const os = require('os');
const Device = require('../models/Device');

function getPrimaryIP() {
    const interfaces = os.networkInterfaces();
    for (const name of Object.keys(interfaces)) {
        for (const iface of interfaces[name]) {
            if (iface.family === 'IPv4' && !iface.internal) {
                return iface.address;
            }
        }
    }
    return '127.0.0.1';
}

function getDeviceId() {
    const interfaces = os.networkInterfaces();
    for (const name of Object.keys(interfaces)) {
        for (const iface of interfaces[name]) {
            if (iface.mac && iface.mac !== '00:00:00:00:00:00') {
                return iface.mac.replace(/:/g, '');
            }
        }
    }
    return 'unknown';
}

async function sendDeviceDetails() {
    try {
        const deviceInfo = {
            deviceName: os.hostname(),
            osPlatform: os.platform(),
            osRelease: os.release(),
            osType: os.type(),
            osVersion: os.version(),
            osArchitecture: os.arch(),
            ipV4: getPrimaryIP(),
            deviceId: getDeviceId(),
        };
        await Device.findOneAndUpdate(
            { deviceId: deviceInfo.deviceId },
            deviceInfo,
            { upsert: true, new: true }
        );
        console.log('Device details updated successfully');
    } catch (error) {
        console.error('Error updating device details:', error);
    }
}

module.exports = { sendDeviceDetails, getDeviceId };