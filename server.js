const express = require('express')
const os = require('os');
const mongoose = require('mongoose');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const si = require('systeminformation');
const app = express()
const port = 3000
const intervalInSeconds = 60;

// Enable CORS for all routes - allowing all origins
app.use(cors());
app.use(express.json());

// JWT Secret Key
const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key';

// MongoDB Connection URL
const MONGODB_URI = 'mongodb+srv://foxiomdevelopers:j86D1QXz6UYeH1Lq@testcluster.qqvseae.mongodb.net/server-monitor';

// User Schema
const userSchema = new mongoose.Schema({
    email: {
        type: String,
        required: true,
        unique: true,
        trim: true,
        lowercase: true
    },
    password: {
        type: String,
        required: true
    },
    role: {
        type: String,
        enum: ['admin'],
        default: 'admin'
    },
    resetPasswordToken: String,
    resetPasswordExpires: Date,
    createdAt: {
        type: Date,
        default: Date.now
    }
});

// Create User Model
const User = mongoose.model('users', userSchema);

// Helper function to extract Bearer token
const extractBearerToken = (authHeader) => {
    if (!authHeader) {
        return null;
    }

    const parts = authHeader.split(' ');
    if (parts.length !== 2 || parts[0] !== 'Bearer') {
        return null;
    }

    return parts[1];
};

// Middleware to verify JWT token
const authenticateToken = async (req, res, next) => {
    try {
        const authHeader = req.headers['authorization'];
        const token = extractBearerToken(authHeader);

        if (!token) {
            return res.status(401).json({ 
                success: false, 
                message: 'Authorization header must be in the format: Bearer <token>' 
            });
        }

        const decoded = jwt.verify(token, JWT_SECRET);
        const user = await User.findById(decoded.userId);
        
        if (!user) {
            return res.status(401).json({ 
                success: false, 
                message: 'User not found' 
            });
        }

        req.user = user;
        next();
    } catch (error) {
        if (error.name === 'JsonWebTokenError') {
            return res.status(401).json({ 
                success: false, 
                message: 'Invalid token' 
            });
        }
        if (error.name === 'TokenExpiredError') {
            return res.status(401).json({ 
                success: false, 
                message: 'Token has expired' 
            });
        }
        return res.status(403).json({ 
            success: false, 
            message: 'Authentication failed' 
        });
    }
};

// Connect to MongoDB
async function connectToMongoDB() {
    try {
        await mongoose.connect(MONGODB_URI);
        console.log('Connected to MongoDB successfully');
        await initializeDefaultAdmin();
    } catch (error) {
        console.error('MongoDB connection error:', error);
    }
}

// Initialize default admin user
async function initializeDefaultAdmin() {
    try {
        const defaultAdminEmail = 'superadmin@gmail.com';
        const defaultAdminPassword = '12345';

        // Check if admin already exists
        const existingAdmin = await User.findOne({ email: defaultAdminEmail });
        if (existingAdmin) {
            console.log('Default admin user already exists');
            return;
        }

        // Hash password
        const salt = await bcrypt.genSalt(10);
        const hashedPassword = await bcrypt.hash(defaultAdminPassword, salt);

        // Create default admin user
        const adminUser = new User({
            email: defaultAdminEmail,
            password: hashedPassword,
            role: 'admin'
        });

        await adminUser.save();
        console.log('Default admin user created successfully');
    } catch (error) {
        console.error('Error creating default admin user:', error);
    }
}

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
        await collectDiskMetrics();

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

// Start the server
app.listen(port, async () => {
    console.log(`Server is listening on port ${port}`);
    await connectToMongoDB();
    await sendDeviceDetails();

    collectDeviceDetails();
    setInterval(collectDeviceDetails, intervalInSeconds * 1000);
});

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

// Function to get disk usage
async function getDiskUsage() {
    try {
        const fsSize = await si.fsSize();
        return fsSize;
    } catch (error) {
        console.error('Error getting disk usage:', error);
        return [];
    }
}

async function collectDiskMetrics() {
    try {
        const deviceId = getDeviceId();
        const diskUsage = await getDiskUsage();

        // Process each filesystem
        for (const fs of diskUsage) {
            const metrics = new DiskMetrics({
                deviceId: deviceId,
                filesystem: fs.fs,
                size: fs.size,
                used: fs.used,
                available: fs.available,
                mount: fs.mount,
                usagePercentage: fs.use
            });

            await metrics.save();
        }

        console.log('Disk metrics collected and saved:', new Date().toISOString());
    } catch (error) {
        console.error('Error collecting disk metrics:', error);
    }
}

// Disk Metrics Schema
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

// Create Disk Metrics Model
const DiskMetrics = mongoose.model('disk_metrics', diskMetricsSchema);

// Function to get CPU usage
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

//////////////////////////////////////////////////////////////AUTH ENDPOINTS//////////////////////////////////////////////////////////////

// Register Admin User
app.post('/api/auth/register', async (req, res) => {
    try {
        const { email, password } = req.body;

        // Check if user already exists
        const existingUser = await User.findOne({ email });
        if (existingUser) {
            return res.status(400).json({
                success: false,
                message: 'User already exists'
            });
        }

        // Hash password
        const salt = await bcrypt.genSalt(10);
        const hashedPassword = await bcrypt.hash(password, salt);

        // Create new user
        const user = new User({
            email,
            password: hashedPassword,
            role: 'admin'
        });

        await user.save();

        res.status(201).json({
            success: true,
            message: 'Admin user created successfully'
        });
    } catch (error) {
        console.error('Error registering user:', error);
        res.status(500).json({
            success: false,
            message: 'Error registering user'
        });
    }
});

// Login
app.post('/api/auth/login', async (req, res) => {
    try {
        const { email, password } = req.body;

        // Find user
        const user = await User.findOne({ email });
        if (!user) {
            return res.status(401).json({
                success: false,
                message: 'Invalid credentials'
            });
        }

        // Verify password
        const isValidPassword = await bcrypt.compare(password, user.password);
        if (!isValidPassword) {
            return res.status(401).json({
                success: false,
                message: 'Invalid credentials'
            });
        }

        // Generate JWT token
        const token = jwt.sign(
            { userId: user._id, role: user.role },
            JWT_SECRET,
            { expiresIn: '24h' }
        );

        res.json({
            success: true,
            token,
            user: {
                id: user._id,
                email: user.email,
                role: user.role
            }
        });
    } catch (error) {
        console.error('Error logging in:', error);
        res.status(500).json({
            success: false,
            message: 'Error logging in'
        });
    }
});

// Request Password Reset
app.post('/api/auth/forgot-password', async (req, res) => {
    try {
        const { email } = req.body;

        const user = await User.findOne({ email });
        if (!user) {
            return res.status(404).json({
                success: false,
                message: 'User not found'
            });
        }

        // Generate reset token
        const resetToken = crypto.randomBytes(32).toString('hex');
        user.resetPasswordToken = resetToken;
        user.resetPasswordExpires = Date.now() + 3600000; // Token expires in 1 hour
        await user.save();

        // In a real application, you would send this token via email
        // For this example, we'll just return it in the response
        res.json({
            success: true,
            message: 'Password reset token generated',
            resetToken // In production, remove this and send via email instead
        });
    } catch (error) {
        console.error('Error generating reset token:', error);
        res.status(500).json({
            success: false,
            message: 'Error generating reset token'
        });
    }
});

// Reset Password
app.post('/api/auth/reset-password', async (req, res) => {
    try {
        const { token, newPassword } = req.body;

        const user = await User.findOne({
            resetPasswordToken: token,
            resetPasswordExpires: { $gt: Date.now() }
        });

        if (!user) {
            return res.status(400).json({
                success: false,
                message: 'Invalid or expired reset token'
            });
        }

        // Hash new password
        const salt = await bcrypt.genSalt(10);
        user.password = await bcrypt.hash(newPassword, salt);
        user.resetPasswordToken = undefined;
        user.resetPasswordExpires = undefined;
        await user.save();

        res.json({
            success: true,
            message: 'Password has been reset successfully'
        });
    } catch (error) {
        console.error('Error resetting password:', error);
        res.status(500).json({
            success: false,
            message: 'Error resetting password'
        });
    }
});

// Change Password (requires authentication)
app.post('/api/auth/change-password', authenticateToken, async (req, res) => {
    try {
        const { currentPassword, newPassword } = req.body;
        const user = req.user;

        // Verify current password
        const isValidPassword = await bcrypt.compare(currentPassword, user.password);
        if (!isValidPassword) {
            return res.status(401).json({
                success: false,
                message: 'Current password is incorrect'
            });
        }

        // Hash new password
        const salt = await bcrypt.genSalt(10);
        user.password = await bcrypt.hash(newPassword, salt);
        await user.save();

        res.json({
            success: true,
            message: 'Password changed successfully'
        });
    } catch (error) {
        console.error('Error changing password:', error);
        res.status(500).json({
            success: false,
            message: 'Error changing password'
        });
    }
});

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
    try {
        // Get all servers
        const conditions = {};
        if(req.query.deviceIds){
            const deviceIds = req.query.deviceIds.split(',');
            conditions.deviceId = { $in: deviceIds };
        }
        const servers = await Device.find(conditions);
        const serversWithMetrics = [];
        
        // For each server, get the latest metrics
        for (const server of servers) {
            const deviceId = server.deviceId;
            const serverData = server.toObject();
            
            // Get latest CPU metrics
            const latestCpuMetric = await CPUMetrics.findOne({ deviceId })
                .sort({ timestamp: -1 })
                .limit(1);
            
            // Get latest memory metrics
            const latestMemoryMetric = await MemoryMetrics.findOne({ deviceId })
                .sort({ timestamp: -1 })
                .limit(1);
            
            // Get latest disk metrics (average of all disks)
            const diskMetrics = await DiskMetrics.aggregate([
                { $match: { deviceId } },
                { $sort: { timestamp: -1 } },
                { $group: {
                    _id: "$filesystem",
                    latestMetric: { $first: "$$ROOT" }
                }},
                { $replaceRoot: { newRoot: "$latestMetric" } }
            ]);
            
            // Calculate average disk usage if there are multiple disks
            let avgDiskUsage = 0;
            if (diskMetrics.length > 0) {
                avgDiskUsage = diskMetrics.reduce((sum, disk) => sum + disk.usagePercentage, 0) / diskMetrics.length;
            }
            
            // Add metrics to server data
            serverData.metrics = {
                cpu: latestCpuMetric ? parseFloat(latestCpuMetric.usagePercentage) : null,
                memory: latestMemoryMetric ? parseFloat(latestMemoryMetric.usagePercentage) : null,
                disk: diskMetrics.length > 0 ? parseFloat(avgDiskUsage.toFixed(2)) : null,
                lastUpdated: latestCpuMetric ? latestCpuMetric.timestamp : null
            };
            
            serversWithMetrics.push(serverData);
        }
        
        res.json({
            success: true,
            data: serversWithMetrics
        });
    } catch (error) {
        console.error('Error fetching servers with metrics:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to fetch servers with metrics'
        });
    }
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

// API Endpoint to fetch disk metrics
app.get('/api/disk-metrics', async (req, res) => {
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

        const metrics = await DiskMetrics.find(query)
            .sort({ timestamp: -1 })
            .limit(100);

        res.json({
            success: true,
            data: metrics
        });
    } catch (error) {
        console.error('Error fetching disk metrics:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to fetch disk metrics'
        });
    }
});

// API Endpoint to fetch disk metrics by device ID
app.get('/api/disk-metrics/:deviceId', async (req, res) => {
    try {
        const { deviceId } = req.params;
        
        // Get overall statistics across all disks
        const stats = await DiskMetrics.aggregate([
            { $match: { deviceId } },
            {
                $group: {
                    _id: null,
                    averageUsage: { $avg: "$usagePercentage" },
                    minUsage: { $min: "$usagePercentage" },
                    maxUsage: { $max: "$usagePercentage" }
                }
            },
            {
                $project: {
                    _id: 0,
                    averageUsage: { $round: ["$averageUsage", 2] },
                    minUsage: { $round: ["$minUsage", 2] },
                    maxUsage: { $round: ["$maxUsage", 2] }
                }
            }
        ]);

        // Find the peak time (timestamp of maximum usage)
        const peakTime = await DiskMetrics.findOne(
            { deviceId, usagePercentage: stats[0]?.maxUsage },
            { timestamp: 1 }
        );
        
        // Get the latest metrics for each filesystem
        const latestMetricsByFilesystem = await DiskMetrics.aggregate([
            { $match: { deviceId } },
            {
                $sort: { timestamp: -1 }
            },
            {
                $group: {
                    _id: "$filesystem",
                    latestMetric: { $first: "$$ROOT" }
                }
            },
            {
                $replaceRoot: { newRoot: "$latestMetric" }
            }
        ]);

        res.json({
            success: true,
            data: {
                statistics: {
                    ...stats[0],
                    peakTime: peakTime?.timestamp
                },
                metrics: latestMetricsByFilesystem
            }
        });
    } catch (error) {
        console.error('Error fetching disk metrics:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to fetch disk metrics'
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

// API Endpoint to get server status counts and categorized device IDs
app.get('/api/server-status', async (req, res) => {
    try {
        // Get all servers with their metrics
        const servers = await Device.find();
        
        // Initialize status categories
        const statusCategories = {
            up: { count: 0, deviceIds: [] },
            trouble: { count: 0, deviceIds: [] },
            critical: { count: 0, deviceIds: [] },
            down: { count: 0, deviceIds: [] }
        };
        
        // Set threshold time for determining if a server is down (no data in last 5 minutes)
        const thresholdTime = new Date(Date.now() - 5 * 60 * 1000); // 5 minutes ago
        
        // Process each server
        for (const server of servers) {
            const deviceId = server.deviceId;
            
            // Get latest metrics
            const latestCpuMetric = await CPUMetrics.findOne({ deviceId })
                .sort({ timestamp: -1 })
                .limit(1);
                
            const latestMemoryMetric = await MemoryMetrics.findOne({ deviceId })
                .sort({ timestamp: -1 })
                .limit(1);
                
            const diskMetrics = await DiskMetrics.aggregate([
                { $match: { deviceId } },
                { $sort: { timestamp: -1 } },
                { $group: {
                    _id: "$filesystem",
                    latestMetric: { $first: "$$ROOT" }
                }},
                { $replaceRoot: { newRoot: "$latestMetric" } }
            ]);
            
            // Check if server is down (no recent data)
            const latestTimestamp = latestCpuMetric?.timestamp || latestMemoryMetric?.timestamp || 
                                   (diskMetrics.length > 0 ? diskMetrics[0].timestamp : null);
            
            if (!latestTimestamp || new Date(latestTimestamp) < thresholdTime) {
                statusCategories.down.count++;
                statusCategories.down.deviceIds.push(deviceId);
                continue;
            }
            
            // Get usage percentages
            const cpuUsage = latestCpuMetric ? parseFloat(latestCpuMetric.usagePercentage) : 0;
            const memoryUsage = latestMemoryMetric ? parseFloat(latestMemoryMetric.usagePercentage) : 0;
            
            // Calculate max disk usage
            let maxDiskUsage = 0;
            if (diskMetrics.length > 0) {
                maxDiskUsage = Math.max(...diskMetrics.map(disk => disk.usagePercentage || 0));
            }
            
            // Determine status based on highest usage
            const maxUsage = Math.max(cpuUsage, memoryUsage, maxDiskUsage);
            
            if (maxUsage >= 90) {
                statusCategories.critical.count++;
                statusCategories.critical.deviceIds.push(deviceId);
            } else if (maxUsage >= 80) {
                statusCategories.trouble.count++;
                statusCategories.trouble.deviceIds.push(deviceId);
            } else {
                statusCategories.up.count++;
                statusCategories.up.deviceIds.push(deviceId);
            }
        }
        
        res.json({
            success: true,
            data: statusCategories
        });
    } catch (error) {
        console.error('Error fetching server status counts:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to fetch server status counts'
        });
    }
});

// Get server by ID
app.get('/api/servers/:id', authenticateToken, async (req, res) => {
    try {
    const server = await Device.findOne({$or: [{ deviceId: req.params.id }, { _id: req.params.id }] });
        
        if (!server) {
            return res.status(404).json({
                success: false,
                message: 'Server not found'
            });
        }

        res.json({
            success: true,
            data: server
        });
    } catch (error) {
        console.error('Error fetching server:', error);
        res.status(500).json({
            success: false,
            message: 'Error fetching server details'
        });
    }
});