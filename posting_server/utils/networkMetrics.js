const si = require('systeminformation');
const NetworkMetrics = require('../models/NetworkMetrics');
const { getDeviceId } = require('./deviceDetails');

async function getNetworkStats() {
    try {
        const networkStats = await si.networkStats();
        return networkStats.map(stat => ({
            interface: stat.iface,
            bytesReceived: stat.rx_bytes,
            bytesSent: stat.tx_bytes,
            packetsReceived: stat.rx_packets,
            packetsSent: stat.tx_packets,
            errorsReceived: stat.rx_errors,
            errorsSent: stat.tx_errors
        }));
    } catch (error) {
        console.error('Error getting network statistics:', error);
        return [];
    }
}

async function collectNetworkMetrics() {
    try {
        const deviceId = getDeviceId();
        const networkStats = await getNetworkStats();

        for (const stats of networkStats) {
            const metrics = new NetworkMetrics({
                deviceId: deviceId,
                ...stats
            });
            await metrics.save();
        }
        console.log('Network metrics collected and saved:', new Date().toISOString());
    } catch (error) {
        console.error('Error collecting network metrics:', error);
    }
}

module.exports = { collectNetworkMetrics };