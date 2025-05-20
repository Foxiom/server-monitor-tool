// server.js
const express = require('express');
const os = require('os');
const mongoose = require('mongoose');
const diskInfo = require('node-disk-info');
const app = express();
const PORT = process.env.PORT || 9999;

// MongoDB connection
mongoose.connect('mongodb+srv://foxiomdevelopers:j86D1QXz6UYeH1Lq@testcluster.qqvseae.mongodb.net/server-monitor', {
  useNewUrlParser: true,
  useUnifiedTopology: true
}).then(() => {
  console.log('Connected to MongoDB');
}).catch((err) => {
  console.error('MongoDB connection error:', err);
});

// System Metrics Schema
const systemMetricsSchema = new mongoose.Schema({
  timestamp: { type: Date, default: Date.now },
  hostname: String,
  deviceId: String,
  
  // Memory metrics
  memory: {
    total: Number,
    used: Number,
    free: Number,
    usagePercentage: Number
  },
  
  // CPU metrics
  cpu: {
    model: String,
    cores: Number,
    speed: Number,
    loadAverage: [Number],
    usagePercentage: Number
  },
  
  // Network metrics
  network: {
    interfaces: [{
      name: String,
      address: String,
      netmask: String,
      mac: String,
      family: String
    }],
    bytesReceived: Number,
    bytesSent: Number
  }
});

const SystemMetrics = mongoose.model('SystemMetrics', systemMetricsSchema);

// Server Schema
const serverSchema = new mongoose.Schema({
  hostname: String,
  platform: String,
  release: String,
  type: String,
  arch: String,
  deviceId: String,
  ipAddress: String,
  memory: {
    totalInMB: Number,
    freeInMB: Number,
    usedInMB: Number,
    usagePercentage: Number
  },
  cpu: {
    model: String,
    cores: Number,
    speed: Number,
    loadAverage: [Number]
  },
  uptimeInSeconds: Number,
  network: Object,
  lastUpdated: { type: Date, default: Date.now }
});

const Server = mongoose.model('Server', serverSchema);

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

// Function to calculate CPU usage
function calculateCPUUsage() {
  const cpus = os.cpus();
  let totalIdle = 0;
  let totalTick = 0;

  cpus.forEach(cpu => {
    for (const type in cpu.times) {
      totalTick += cpu.times[type];
    }
    totalIdle += cpu.times.idle;
  });

  return {
    idle: totalIdle / cpus.length,
    total: totalTick / cpus.length
  };
}

let lastCPUInfo = calculateCPUUsage();

// Function to get network stats
function getNetworkStats() {
  const interfaces = os.networkInterfaces();
  const stats = {
    interfaces: [],
    bytesReceived: 0,
    bytesSent: 0
  };

  for (const [name, netInterface] of Object.entries(interfaces)) {
    for (const iface of netInterface) {
      if (iface.family === 'IPv4' && !iface.internal) {
        stats.interfaces.push({
          name,
          address: iface.address,
          netmask: iface.netmask,
          mac: iface.mac,
          family: iface.family
        });
      }
    }
  }

  return stats;
}

// Function to monitor system metrics
async function monitorSystemMetrics() {
  try {
    // Get memory info
    const totalMem = os.totalmem();
    const freeMem = os.freemem();
    const usedMem = totalMem - freeMem;
    const memUsagePercentage = ((usedMem / totalMem) * 100).toFixed(2);

    // Get CPU info
    const currentCPUInfo = calculateCPUUsage();
    const idleDifference = currentCPUInfo.idle - lastCPUInfo.idle;
    const totalDifference = currentCPUInfo.total - lastCPUInfo.total;
    const cpuUsagePercentage = 100 - Math.round(100 * idleDifference / totalDifference);
    lastCPUInfo = currentCPUInfo;



    // Get network info
    const networkStats = getNetworkStats();

    // Create metrics document
    const metrics = new SystemMetrics({
      hostname: os.hostname(),
      deviceId: getDeviceId(),
      memory: {
        total: totalMem,
        used: usedMem,
        free: freeMem,
        usagePercentage: parseFloat(memUsagePercentage)
      },
      cpu: {
        model: os.cpus()[0].model,
        cores: os.cpus().length,
        speed: os.cpus()[0].speed,
        loadAverage: os.loadavg(),
        usagePercentage: cpuUsagePercentage
      },
      network: networkStats
    });

    // Save to MongoDB
    await metrics.save();

    // Log to console
    console.log('\n=== System Metrics Report ===');
    console.log(`Memory Usage: ${memUsagePercentage}%`);
    console.log(`CPU Usage: ${cpuUsagePercentage}%`);
    console.log('Disk Usage:');
    disks.forEach(disk => {
      console.log(`  ${disk.mounted}: ${disk.capacity} used`);
    });
    console.log('========================\n');

  } catch (error) {
    console.error('Error monitoring system metrics:', error);
  }
}

// Start monitoring
setInterval(monitorSystemMetrics, 30000); // Run every 30 seconds
monitorSystemMetrics(); // Run immediately on startup

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok', uptime: process.uptime() });
});

// Get metrics history endpoint
app.get('/metrics-history', async (req, res) => {
  try {
    const limit = parseInt(req.query.limit) || 100;
    const history = await SystemMetrics.find()
      .sort({ timestamp: -1 })
      .limit(limit);
    res.json(history);
  } catch (error) {
    res.status(500).json({ error: 'Error fetching metrics history' });
  }
});

// Get latest metrics endpoint
app.get('/metrics', async (req, res) => {
  try {
    const latestMetrics = await SystemMetrics.findOne()
      .sort({ timestamp: -1 });
    res.json(latestMetrics);
  } catch (error) {
    res.status(500).json({ error: 'Error fetching latest metrics' });
  }
});

// Comprehensive system information endpoint
app.get('/system', async (req, res) => {
  const systemInfo = {
    // Basic system info
    hostname: os.hostname(),
    platform: os.platform(),
    release: os.release(),
    type: os.type(),
    arch: os.arch(),
    
    // Device identification
    deviceId: getDeviceId(),
    ipAddress: getPrimaryIP(),
    
    // Memory information
    memory: {
      totalInMB: os.totalmem() / 1024 / 1024,
      freeInMB: os.freemem() / 1024 / 1024,
      usedInMB: (os.totalmem() - os.freemem()) / 1024 / 1024,
      usagePercentage: ((os.totalmem() - os.freemem()) / os.totalmem() * 100).toFixed(2)
    },
    
    // CPU information
    cpu: {
      model: os.cpus()[0].model,
      cores: os.cpus().length,
      speed: os.cpus()[0].speed,
      loadAverage: os.loadavg()
    },
    
    // System uptime
    uptimeInSeconds: os.uptime(),
    
    // Network information
    network: os.networkInterfaces()
  };
  
  try {
    // Update or create server document
    await Server.findOneAndUpdate(
      { deviceId: systemInfo.deviceId },
      { ...systemInfo, lastUpdated: new Date() },
      { upsert: true, new: true }
    );
    
    res.json(systemInfo);
  } catch (error) {
    console.error('Error saving server information:', error);
    res.status(500).json({ error: 'Error saving server information' });
  }
});

// Default route
app.get('/', (_, res) => {
  res.send('Hello');
});

// Start the server
app.listen(PORT, () => {
  console.log(`Server is running on port ${PORT}`);
});
