// server.js
const express = require('express');
const os = require('os');
const app = express();
const PORT = process.env.PORT || 9999;

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
    
    // Memory information
    memory: {
      total: os.totalmem(),
      free: os.freemem(),
      used: os.totalmem() - os.freemem(),
      usagePercentage: ((os.totalmem() - os.freemem()) / os.totalmem() * 100).toFixed(2)
    },
    
    // CPU information
    cpu: {
      model: os.cpus()[0].model,
      cores: os.cpus().length,
      speed: os.cpus()[0].speed
    },
    
    // Network information
    network: os.networkInterfaces(),
    
    // System uptime
    uptime: os.uptime(),
    
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
