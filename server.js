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
function monitorMemoryUsage() {
  const totalMem = os.totalmem();
  const freeMem = os.freemem();
  const usedMem = totalMem - freeMem;
  const usagePercentage = ((usedMem / totalMem) * 100).toFixed(2);

  console.log('\n=== Memory Usage Report ===');
  console.log(`Total Memory: ${formatMemorySize(totalMem)}`);
  console.log(`Used Memory: ${formatMemorySize(usedMem)}`);
  console.log(`Free Memory: ${formatMemorySize(freeMem)}`);
  console.log(`Usage: ${usagePercentage}%`);
  console.log('========================\n');
}

// Start memory monitoring
setInterval(monitorMemoryUsage, 30000); // Run every 30 seconds
monitorMemoryUsage(); // Run immediately on startup

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
app.get('/', (_, res) => {
  res.send('Hello');
});

// Start the server
app.listen(PORT, () => {
  console.log(`Server is running on port ${PORT}`);
});
