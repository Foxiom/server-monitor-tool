const express = require('express')
const os = require('os');
const mongoose = require('mongoose');
const cors = require('cors');
const app = express()
const port = 3000
const intervalInSeconds = 60;

// Enable CORS for all routes - allowing all origins
app.use(cors());

// MongoDB Connection URL
const MONGODB_URI = 'mongodb+srv://foxiomdevelopers:j86D1QXz6UYeH1Lq@testcluster.qqvseae.mongodb.net/server-monitor';


async function sendDeviceDetails() {
    try {
        const deviceInfo = getDeviceDetails();
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


async function collectDeviceDetails() {
    try {
        const deviceId = getDeviceId();
        const cpuUsage = getCPUUsage();

        // Save CPU metrics
        const metrics = new CPUMetrics({
            deviceId: deviceId,
            idleSeconds: cpuUsage.idleSeconds,
            totalSeconds: cpuUsage.totalSeconds,
            usagePercentage: parseFloat(cpuUsage.usagePercentage),
            userPercentage: parseFloat(cpuUsage.userPercentage),
            sysPercentage: parseFloat(cpuUsage.sysPercentage)
        });

        await metrics.save();
        
        await collectMemoryMetrics();
        await collectNetworkMetrics();

        console.log('Metrics collected and saved:', new Date().toISOString());
    } catch (error) {
        console.error('Error collecting metrics:', error);
    }
}

// Function to get memory usage
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

        // Save memory metrics
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

// Memory Metrics Schema
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

// Create Memory Metrics Model
const MemoryMetrics = mongoose.model('memory_metrics', memoryMetricsSchema);



app.listen(port, async () => {
    console.log(`Server is listening on port ${port}`);
    await connectToMongoDB();
    await sendDeviceDetails();

    collectDeviceDetails();
    setInterval(collectDeviceDetails, intervalInSeconds * 1000);
})



function getDeviceDetails() {
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
    return deviceInfo;
}

// Function to calculate CPU usage
function getCPUUsage() {
    const cpus = os.cpus();
    let totalIdle = 0;
    let totalTick = 0;
    let totalUser = 0;
    let totalSys = 0;

    cpus.forEach(cpu => {
        for (const type in cpu.times) {
            totalTick += cpu.times[type];
        }
        totalIdle += cpu.times.idle;
        totalUser += cpu.times.user;
        totalSys += cpu.times.sys;
    });

    return {
        // idle: Average idle time in milliseconds per CPU core
        // This represents the time the CPU spent doing nothing
        idleSeconds: totalIdle / cpus.length,

        // total: Average total CPU time in milliseconds per CPU core
        // This represents all CPU time (user + nice + sys + idle + irq)
        totalSeconds: totalTick / cpus.length,

        // usage: CPU utilization as a percentage
        // This shows what percentage of CPU time was spent on actual work
        // 100% means all CPU cores are fully utilized
        // 0% means all CPU cores are completely idle
        usagePercentage: ((totalTick - totalIdle) / totalTick * 100).toFixed(2),

        // user: Percentage of CPU time spent in user space (applications)
        // Higher values indicate more CPU time spent running user applications
        userPercentage: (totalUser / totalTick * 100).toFixed(2),

        // sys: Percentage of CPU time spent in system space (kernel)
        // Higher values indicate more CPU time spent on system operations
        sysPercentage: (totalSys / totalTick * 100).toFixed(2)
    };
}

// Function to get primary IP address
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

// Function to get device ID
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

// Connect to MongoDB
async function connectToMongoDB() {
    try {
        await mongoose.connect(MONGODB_URI);
        console.log('Connected to MongoDB successfully');
    } catch (error) {
        console.error('MongoDB connection error:', error);
    }
}



//SCHEMA

// Device Schema
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
    cpuUsage: {
        idle: Number,
        total: Number,
        usage: String
    },
    timestamp: {
        type: Date,
        default: Date.now
    }
});

// Create Device Model
const Device = mongoose.model('servers', deviceSchema);

// CPU Metrics Schema
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

// Create CPU Metrics Model
const CPUMetrics = mongoose.model('cpu_metrics', cpuMetricsSchema);

// Network Metrics Schema
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

// Create Network Metrics Model
const NetworkMetrics = mongoose.model('network_metrics', networkMetricsSchema);

// Function to get network statistics
async function getNetworkStats() {
    const { exec } = require('child_process');
    const util = require('util');
    const execPromise = util.promisify(exec);

    try {
        // Get network interface statistics using netstat
        const { stdout } = await execPromise('netstat -ib');
        const lines = stdout.split('\n');
        const networkStats = [];

        // Skip header lines
        for (let i = 2; i < lines.length; i++) {
            const line = lines[i].trim().split(/\s+/);
            if (line.length >= 10) {
                const interfaceName = line[0];
                // Skip loopback interface
                if (interfaceName === 'lo0') continue;

                const stats = {
                    interface: interfaceName,
                    bytesReceived: parseInt(line[6]) || 0,
                    bytesSent: parseInt(line[9]) || 0,
                    packetsReceived: parseInt(line[4]) || 0,
                    packetsSent: parseInt(line[7]) || 0,
                    errorsReceived: parseInt(line[5]) || 0,
                    errorsSent: parseInt(line[8]) || 0
                };
                networkStats.push(stats);
            }
        }
        return networkStats;
    } catch (error) {
        console.error('Error getting network statistics:', error);
        return [];
    }
}

async function collectNetworkMetrics() {
    try {
        const deviceId = getDeviceId();
        const networkStats = await getNetworkStats();

        // Save network metrics for each interface
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


//////////////////////////////////////////////////////////////API ENDPOINTS//////////////////////////////////////////////////////////////

// API Endpoint to fetch network metrics
app.get('/api/network-metrics', async (req, res) => {
    try {
        const { deviceId, startDate, endDate } = req.query;
        let query = {};

        if (deviceId) {
            query.deviceId = deviceId;
        }

        if (startDate || endDate) {
            query.timestamp = {};
            if (startDate) {
                query.timestamp.$gte = new Date(startDate);
            }
            if (endDate) {
                query.timestamp.$lte = new Date(endDate);
            }
        }

        const metrics = await NetworkMetrics.find(query)
            .sort({ timestamp: -1 })
            .limit(100);

        res.json({
            success: true,
            data: metrics
        });
    } catch (error) {
        console.error('Error fetching network metrics:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to fetch network metrics'
        });
    }
});

app.get('/api/network-metrics/:deviceId', async (req, res) => {
    try {
        const { deviceId } = req.params;
        
        // Use aggregation pipeline to calculate statistics
        const stats = await NetworkMetrics.aggregate([
            { $match: { deviceId } },
            {
                $group: {
                    _id: "$interface",
                    totalBytesReceived: { $sum: "$bytesReceived" },
                    totalBytesSent: { $sum: "$bytesSent" },
                    totalPacketsReceived: { $sum: "$packetsReceived" },
                    totalPacketsSent: { $sum: "$packetsSent" },
                    totalErrorsReceived: { $sum: "$errorsReceived" },
                    totalErrorsSent: { $sum: "$errorsSent" },
                    metrics: { $push: "$$ROOT" }
                }
            },
            {
                $project: {
                    _id: 0,
                    interface: "$_id",
                    statistics: {
                        totalBytesReceived: 1,
                        totalBytesSent: 1,
                        totalPacketsReceived: 1,
                        totalPacketsSent: 1,
                        totalErrorsReceived: 1,
                        totalErrorsSent: 1
                    },
                    metrics: {
                        $slice: [
                            { $sortArray: { input: "$metrics", sortBy: { timestamp: -1 } } },
                            100
                        ]
                    }
                }
            }
        ]);

        res.json({
            success: true,
            data: stats
        });
    } catch (error) {
        console.error('Error fetching network metrics:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to fetch network metrics'
        });
    }
});

// API Endpoint to fetch CPU metrics
app.get('/api/cpu-metrics', async (req, res) => {
    try {
        const { deviceId, startDate, endDate } = req.query;
        let query = {};

        if (deviceId) {
            query.deviceId = deviceId;
        }

        // Add date range filter if provided
        if (startDate || endDate) {
            query.timestamp = {};
            if (startDate) {
                query.timestamp.$gte = new Date(startDate);
            }
            if (endDate) {
                query.timestamp.$lte = new Date(endDate);
            }
        }

        const metrics = await CPUMetrics.find(query)
            .sort({ timestamp: -1 })
            .limit(100);

        res.json({
            success: true,
            data: metrics
        });
    } catch (error) {
        console.error('Error fetching CPU metrics:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to fetch CPU metrics'
        });
    }
});

app.get('/api/cpu-metrics/:deviceId', async (req, res) => {
    try {
        const { deviceId } = req.params;
        
        // Use aggregation pipeline to calculate statistics
        const stats = await CPUMetrics.aggregate([
            { $match: { deviceId } },
            {
                $group: {
                    _id: null,
                    averageUsage: { $avg: "$usagePercentage" },
                    minUsage: { $min: "$usagePercentage" },
                    maxUsage: { $max: "$usagePercentage" },
                    metrics: { $push: "$$ROOT" }
                }
            },
            {
                $project: {
                    _id: 0,
                    statistics: {
                        averageUsage: { $round: ["$averageUsage", 2] },
                        minUsage: { $round: ["$minUsage", 2] },
                        maxUsage: { $round: ["$maxUsage", 2] }
                    },
                    metrics: {
                        $slice: [
                            { $sortArray: { input: "$metrics", sortBy: { timestamp: -1 } } },
                            100
                        ]
                    }
                }
            }
        ]);

        // Find the peak time (timestamp of maximum usage)
        const peakTime = await CPUMetrics.findOne(
            { deviceId, usagePercentage: stats[0]?.statistics.maxUsage },
            { timestamp: 1 }
        );

        res.json({
            success: true,
            data: {
                ...stats[0],
                statistics: {
                    ...stats[0]?.statistics,
                    peakTime: peakTime?.timestamp
                }
            }
        });
    } catch (error) {
        console.error('Error fetching CPU metrics:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to fetch CPU metrics'
        });
    }
});


app.get('/api/servers', async (req, res) => {
    const servers = await Device.find();
    res.json({
        success: true,
        data: servers
    });
})

// API Endpoint to fetch memory metrics
app.get('/api/memory-metrics', async (req, res) => {
    try {
        const { deviceId, startDate, endDate } = req.query;
        let query = {};

        if (deviceId) {
            query.deviceId = deviceId;
        }

        if (startDate || endDate) {
            query.timestamp = {};
            if (startDate) {
                query.timestamp.$gte = new Date(startDate);
            }
            if (endDate) {
                query.timestamp.$lte = new Date(endDate);
            }
        }

        const metrics = await MemoryMetrics.find(query)
            .sort({ timestamp: -1 })
            .limit(100);

        res.json({
            success: true,
            data: metrics
        });
    } catch (error) {
        console.error('Error fetching memory metrics:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to fetch memory metrics'
        });
    }
});

app.get('/api/memory-metrics/:deviceId', async (req, res) => {
    try {
        const { deviceId } = req.params;
        
        // Use aggregation pipeline to calculate statistics
        const stats = await MemoryMetrics.aggregate([
            { $match: { deviceId } },
            {
                $group: {
                    _id: null,
                    averageUsage: { $avg: "$usagePercentage" },
                    minUsage: { $min: "$usagePercentage" },
                    maxUsage: { $max: "$usagePercentage" },
                    metrics: { $push: "$$ROOT" }
                }
            },
            {
                $project: {
                    _id: 0,
                    statistics: {
                        averageUsage: { $round: ["$averageUsage", 2] },
                        minUsage: { $round: ["$minUsage", 2] },
                        maxUsage: { $round: ["$maxUsage", 2] }
                    },
                    metrics: {
                        $slice: [
                            { $sortArray: { input: "$metrics", sortBy: { timestamp: -1 } } },
                            100
                        ]
                    }
                }
            }
        ]);

        // Find the peak time (timestamp of maximum usage)
        const peakTime = await MemoryMetrics.findOne(
            { deviceId, usagePercentage: stats[0]?.statistics.maxUsage },
            { timestamp: 1 }
        );

        res.json({
            success: true,
            data: {
                ...stats[0],
                statistics: {
                    ...stats[0]?.statistics,
                    peakTime: peakTime?.timestamp
                }
            }
        });
    } catch (error) {
        console.error('Error fetching memory metrics:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to fetch memory metrics'
        });
    }
});