// server.js
const express = require('express');
const os = require('os');
const mongoose = require('mongoose');
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

// Memory Usage Schema
const memoryUsageSchema = new mongoose.Schema({
  totalMemory: Number,
  usedMemory: Number,
  freeMemory: Number,
  usagePercentage: Number,
  hostname: String,
  deviceId: String,
  timestamp: { type: Date, default: Date.now }
});

const MemoryUsage = mongoose.model('MemoryUsage', memoryUsageSchema);

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

// Function to get device ID (using MAC address)
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

// Function to format memory size
function formatMemorySize(bytes) {
  const mb = bytes / 1024 / 1024;
  return `${mb.toFixed(2)} MB`;
}

// Function to monitor memory usage
async function monitorMemoryUsage() {
  const totalMem = os.totalmem();
  const freeMem = os.freemem();
  const usedMem = totalMem - freeMem;
  const usagePercentage = ((usedMem / totalMem) * 100).toFixed(2);
  const deviceId = getDeviceId();

  // Log to console
  console.log('\n=== Memory Usage Report ===');
  console.log(`Total Memory: ${formatMemorySize(totalMem)}`);
  console.log(`Used Memory: ${formatMemorySize(usedMem)}`);
  console.log(`Free Memory: ${formatMemorySize(freeMem)}`);
  console.log(`Usage: ${usagePercentage}%`);
  console.log('========================\n');

  // Save to MongoDB
  try {
    const memoryData = new MemoryUsage({
      totalMemory: totalMem,
      usedMemory: usedMem,
      freeMemory: freeMem,
      usagePercentage: parseFloat(usagePercentage),
      hostname: os.hostname(),
      deviceId: deviceId
    });
    await memoryData.save();
  } catch (error) {
    console.error('Error saving memory data:', error);
  }
}

// Start memory monitoring
setInterval(monitorMemoryUsage, 30000); // Run every 30 seconds
monitorMemoryUsage(); // Run immediately on startup

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok', uptime: process.uptime() });
});

// Get memory history endpoint
app.get('/memory-history', async (req, res) => {
  try {
    const limit = parseInt(req.query.limit) || 100; // Default to last 100 records
    const history = await MemoryUsage.find()
      .sort({ timestamp: -1 })
      .limit(limit);
    res.json(history);
  } catch (error) {
    res.status(500).json({ error: 'Error fetching memory history' });
  }
});

// Comprehensive system information endpoint
app.get('/system', (req, res) => {
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
      speed: os.cpus()[0].speed
    },
    
    // System uptime
    uptimeInSeconds: os.uptime(),
    
    // Load average
    loadAverage: os.loadavg()
  };
  
  res.json(systemInfo);
});

// Default route
app.get('/', (_, res) => {
  res.send('Hello');
});

// Start the server
app.listen(PORT, () => {
  console.log(`Server is running on port ${PORT}`);
});
