const os = require('os');
const MemoryMetrics = require('../models/MemoryMetrics');
const { getDeviceId } = require('./deviceDetails');

function getMemoryUsage() {
    const totalMemory = os.totalmem();
    const freeMemory = os.freemem();
    const usedMemory = totalMemory - freeMemory;

    return {
        totalMemory: totalMemory,
        freeMemory: freeMemory,
        usedMemory: usedMemory,
        usagePercentage: ((usedMemory / totalMemory) * 100).toFixed(2)
    };
}

async function collectMemoryMetrics() {
    try {
        const deviceId = getDeviceId();
        const memoryUsage = getMemoryUsage();

        const metrics = new MemoryMetrics({
            deviceId: deviceId,
            totalMemory: memoryUsage.totalMemory,
            freeMemory: memoryUsage.freeMemory,
            usedMemory: memoryUsage.usedMemory,
            usagePercentage: parseFloat(memoryUsage.usagePercentage)
        });

        await metrics.save();
        console.log('Memory metrics collected and saved:', new Date().toISOString());
    } catch (error) {
        console.error('Error collecting memory metrics:', error);
    }
}

module.exports = { collectMemoryMetrics };