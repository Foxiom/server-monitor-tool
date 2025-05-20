// server.js
const express = require('express');
const os = require('os');
const app = express();
const PORT = process.env.PORT || 9999;

// Function to get primary IP address
function getPrimaryIP() {
  const interfaces = os.networkInterfaces();
  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name]) {
      // Skip internal and non-IPv4 addresses
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

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok', uptime: process.uptime() });
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
app.get('/', (req, res) => {
  res.send('Hello from Express!');
});

// Start the server
app.listen(PORT, () => {
  console.log(`Server is running on port ${PORT}`);
});
