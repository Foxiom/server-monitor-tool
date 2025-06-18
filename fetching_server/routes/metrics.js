const express = require('express');
const Device = require('../models/Device');
const CPUMetrics = require('../models/CPUMetrics');
const MemoryMetrics = require('../models/MemoryMetrics');
const DiskMetrics = require('../models/DiskMetrics');
const NetworkMetrics = require('../models/NetworkMetrics');
const authenticateToken = require('../middleware/auth');

const router = express.Router();

// Fetch network metrics
router.get('/network-metrics', authenticateToken, async (req, res) => {
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

router.get('/network-metrics/:deviceId', authenticateToken, async (req, res) => {
  try {
    const { deviceId } = req.params;

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

// Fetch CPU metrics
router.get('/cpu-metrics', authenticateToken, async (req, res) => {
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

router.get('/cpu-metrics/:deviceId', authenticateToken, async (req, res) => {
  try {
    const { deviceId } = req.params;

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

// Fetch servers
router.get('/servers', authenticateToken, async (req, res) => {
  try {
    const conditions = {};
    if (req.query.deviceIds) {
      const deviceIds = req.query.deviceIds.split(',');
      conditions.deviceId = { $in: deviceIds };
    }
    const servers = await Device.find(conditions);
    const serversWithMetrics = [];

    for (const server of servers) {
      const deviceId = server.deviceId;
      const serverData = server.toObject();

      const latestCpuMetric = await CPUMetrics.findOne({ deviceId })
        .sort({ timestamp: -1 })
        .limit(1);

      const latestMemoryMetric = await MemoryMetrics.findOne({ deviceId })
        .sort({ timestamp: -1 })
        .limit(1);

      const diskMetrics = await DiskMetrics.aggregate([
        { $match: { deviceId } },
        { $sort: { timestamp: -1 } },
        {
          $group: {
            _id: "$filesystem",
            latestMetric: { $first: "$$ROOT" }
          }
        },
        { $replaceRoot: { newRoot: "$latestMetric" } }
      ]);

      let avgDiskUsage = 0;
      if (diskMetrics.length > 0) {
        avgDiskUsage = diskMetrics.reduce((sum, disk) => sum + disk.usagePercentage, 0) / diskMetrics.length;
      }

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
});

// Fetch server by ID
router.get('/servers/:id', authenticateToken, async (req, res) => {
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

// Fetch memory metrics
router.get('/memory-metrics', authenticateToken, async (req, res) => {
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

router.get('/memory-metrics/:deviceId', authenticateToken, async (req, res) => {
  try {
    const { deviceId } = req.params;

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

// Fetch disk metrics
router.get('/disk-metrics', authenticateToken, async (req, res) => {
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

router.get('/disk-metrics/:deviceId', authenticateToken, async (req, res) => {
  try {
    const { deviceId } = req.params;

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

    const peakTime = await DiskMetrics.findOne(
      { deviceId, usagePercentage: stats[0]?.maxUsage },
      { timestamp: 1 }
    );

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

// Fetch server status counts
router.get('/server-status', authenticateToken, async (req, res) => {
  try {
    const servers = await Device.find();
    const statusCategories = {
      up: { count: 0, deviceIds: [] },
      trouble: { count: 0, deviceIds: [] },
      critical: { count: 0, deviceIds: [] },
      down: { count: 0, deviceIds: [] }
    };

    const thresholdTime = new Date(Date.now() - 5 * 60 * 1000);

    for (const server of servers) {
      const deviceId = server.deviceId;

      const latestCpuMetric = await CPUMetrics.findOne({ deviceId })
        .sort({ timestamp: -1 })
        .limit(1);

      const latestMemoryMetric = await MemoryMetrics.findOne({ deviceId })
        .sort({ timestamp: -1 })
        .limit(1);

      const diskMetrics = await DiskMetrics.aggregate([
        { $match: { deviceId } },
        { $sort: { timestamp: -1 } },
        {
          $group: {
            _id: "$filesystem",
            latestMetric: { $first: "$$ROOT" }
          }
        },
        { $replaceRoot: { newRoot: "$latestMetric" } }
      ]);

      const latestTimestamp = latestCpuMetric?.timestamp || latestMemoryMetric?.timestamp ||
        (diskMetrics.length > 0 ? diskMetrics[0].timestamp : null);

      if (!latestTimestamp || new Date(latestTimestamp) < thresholdTime) {
        statusCategories.down.count++;
        statusCategories.down.deviceIds.push(deviceId);
        continue;
      }

      const cpuUsage = latestCpuMetric ? parseFloat(latestCpuMetric.usagePercentage) : 0;
      const memoryUsage = latestMemoryMetric ? parseFloat(latestMemoryMetric.usagePercentage) : 0;

      let maxDiskUsage = 0;
      if (diskMetrics.length > 0) {
        maxDiskUsage = Math.max(...diskMetrics.map(disk => disk.usagePercentage || 0));
      }

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

module.exports = router;