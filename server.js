const express = require('express')
const os = require('os');
const mongoose = require('mongoose');
const cors = require('cors');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
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
    try {
        const interfaces = os.networkInterfaces();
        const networkStats = [];

        for (const [interfaceName, interfaceDetails] of Object.entries(interfaces)) {
            // Skip loopback interface
            if (interfaceName === 'lo') continue;

            // Find IPv4 interface
            const ipv4Interface = interfaceDetails.find(iface => iface.family === 'IPv4');
            if (!ipv4Interface) continue;

            const stats = {
                interface: interfaceName,
                bytesReceived: 0, // These metrics are not available through os.networkInterfaces()
                bytesSent: 0,     // You might want to use a different approach to get these
                packetsReceived: 0,
                packetsSent: 0,
                errorsReceived: 0,
                errorsSent: 0
            };
            networkStats.push(stats);
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