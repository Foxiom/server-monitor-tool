const express = require("express");
const Device = require("../models/Device");
const CPUMetrics = require("../models/CPUMetrics");
const MemoryMetrics = require("../models/MemoryMetrics");
const DiskMetrics = require("../models/DiskMetrics");
const NetworkMetrics = require("../models/NetworkMetrics");
const authenticateToken = require("../middleware/auth");

const router = express.Router();

// Fetch network metrics
router.get("/network-metrics", authenticateToken, async (req, res) => {
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
      data: metrics,
    });
  } catch (error) {
    console.error("Error fetching network metrics:", error);
    res.status(500).json({
      success: false,
      error: "Failed to fetch network metrics",
    });
  }
});

router.get(
  "/network-metrics/:deviceId",
  authenticateToken,
  async (req, res) => {
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
            metrics: { $push: "$$ROOT" },
          },
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
              totalErrorsSent: 1,
            },
            metrics: {
              $slice: [
                {
                  $sortArray: { input: "$metrics", sortBy: { timestamp: -1 } },
                },
                100,
              ],
            },
          },
        },
      ]);

      res.json({
        success: true,
        data: stats,
      });
    } catch (error) {
      console.error("Error fetching network metrics:", error);
      res.status(500).json({
        success: false,
        error: "Failed to fetch network metrics",
      });
    }
  }
);

// Fetch CPU metrics
router.get("/cpu-metrics", authenticateToken, async (req, res) => {
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
      data: metrics,
    });
  } catch (error) {
    console.error("Error fetching CPU metrics:", error);
    res.status(500).json({
      success: false,
      error: "Failed to fetch CPU metrics",
    });
  }
});

router.get("/cpu-metrics/:deviceId", authenticateToken, async (req, res) => {
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
          metrics: { $push: "$$ROOT" },
        },
      },
      {
        $project: {
          _id: 0,
          statistics: {
            averageUsage: { $round: ["$averageUsage", 2] },
            minUsage: { $round: ["$minUsage", 2] },
            maxUsage: { $round: ["$maxUsage", 2] },
          },
          metrics: {
            $slice: [
              { $sortArray: { input: "$metrics", sortBy: { timestamp: -1 } } },
              100,
            ],
          },
        },
      },
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
          peakTime: peakTime?.timestamp,
        },
      },
    });
  } catch (error) {
    console.error("Error fetching CPU metrics:", error);
    res.status(500).json({
      success: false,
      error: "Failed to fetch CPU metrics",
    });
  }
});

// Fetch servers
router.get("/servers", authenticateToken, async (req, res) => {
  try {
    const conditions = {};
    if (req.query.deviceIds) {
      const deviceIds = req.query.deviceIds.split(",");
      conditions.deviceId = { $in: deviceIds };
    }

    if (req.query.status) {
      conditions.status = req.query.status;
    }

    if (req.query.search) {
      conditions.$or = [
        { deviceName: { $regex: req.query.search, $options: "i" } },
        { ipV4: { $regex: req.query.search, $options: "i" } },
      ];
    }
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;
    const skip = (page - 1) * limit;
    const servers = await Device.find(conditions).skip(skip).limit(limit);
    const totalDocs = await Device.countDocuments(conditions);
    const hasNextPage = totalDocs > limit * page;
    const hasPrevPage = page > 1;

    res.json({
      success: true,
      data: {
        servers,
        totalDocs,
        hasNextPage,
        hasPrevPage,
      },
    });
  } catch (error) {
    console.error("Error fetching servers with metrics:", error);
    res.status(500).json({
      success: false,
      error: "Failed to fetch servers with metrics",
    });
  }
});

// Fetch server by ID
router.get("/servers/:id", authenticateToken, async (req, res) => {
  try {
    const server = await Device.findOne({
      $or: [{ deviceId: req.params.id }, { _id: req.params.id }],
    });

    if (!server) {
      return res.status(404).json({
        success: false,
        message: "Server not found",
      });
    }

    res.json({
      success: true,
      data: server,
    });
  } catch (error) {
    console.error("Error fetching server:", error);
    res.status(500).json({
      success: false,
      message: "Error fetching server details",
    });
  }
});

// Fetch memory metrics
router.get("/memory-metrics", authenticateToken, async (req, res) => {
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
      data: metrics,
    });
  } catch (error) {
    console.error("Error fetching memory metrics:", error);
    res.status(500).json({
      success: false,
      error: "Failed to fetch memory metrics",
    });
  }
});

router.get("/memory-metrics/:deviceId", authenticateToken, async (req, res) => {
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
          metrics: { $push: "$$ROOT" },
        },
      },
      {
        $project: {
          _id: 0,
          statistics: {
            averageUsage: { $round: ["$averageUsage", 2] },
            minUsage: { $round: ["$minUsage", 2] },
            maxUsage: { $round: ["$maxUsage", 2] },
          },
          metrics: {
            $slice: [
              { $sortArray: { input: "$metrics", sortBy: { timestamp: -1 } } },
              100,
            ],
          },
        },
      },
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
          peakTime: peakTime?.timestamp,
        },
      },
    });
  } catch (error) {
    console.error("Error fetching memory metrics:", error);
    res.status(500).json({
      success: false,
      error: "Failed to fetch memory metrics",
    });
  }
});

// Fetch disk metrics
router.get("/disk-metrics", authenticateToken, async (req, res) => {
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
      data: metrics,
    });
  } catch (error) {
    console.error("Error fetching disk metrics:", error);
    res.status(500).json({
      success: false,
      error: "Failed to fetch disk metrics",
    });
  }
});

router.get("/disk-metrics/:deviceId", authenticateToken, async (req, res) => {
  try {
    const { deviceId } = req.params;

    const stats = await DiskMetrics.aggregate([
      { $match: { deviceId } },
      {
        $group: {
          _id: null,
          averageUsage: { $avg: "$usagePercentage" },
          minUsage: { $min: "$usagePercentage" },
          maxUsage: { $max: "$usagePercentage" },
        },
      },
      {
        $project: {
          _id: 0,
          averageUsage: { $round: ["$averageUsage", 2] },
          minUsage: { $round: ["$minUsage", 2] },
          maxUsage: { $round: ["$maxUsage", 2] },
        },
      },
    ]);

    const peakTime = await DiskMetrics.findOne(
      { deviceId, usagePercentage: stats[0]?.maxUsage },
      { timestamp: 1 }
    );

    const latestMetricsByFilesystem = await DiskMetrics.aggregate([
      { $match: { deviceId } },
      {
        $sort: { timestamp: -1 },
      },
      {
        $group: {
          _id: "$filesystem",
          latestMetric: { $first: "$$ROOT" },
        },
      },
      {
        $replaceRoot: { newRoot: "$latestMetric" },
      },
    ]);

    res.json({
      success: true,
      data: {
        statistics: {
          ...stats[0],
          peakTime: peakTime?.timestamp,
        },
        metrics: latestMetricsByFilesystem,
      },
    });
  } catch (error) {
    console.error("Error fetching disk metrics:", error);
    res.status(500).json({
      success: false,
      error: "Failed to fetch disk metrics",
    });
  }
});

// Fetch server status counts
router.get("/server-status", authenticateToken, async (req, res) => {
  try {
    // const servers = await Device.find();
    // const statusCategories = {
    //   all: {
    //     count: servers.length,
    //     deviceIds: servers.map((server) => server.deviceId),
    //   },
    //   up: { count: 0, deviceIds: [] },
    //   trouble: { count: 0, deviceIds: [] },
    //   critical: { count: 0, deviceIds: [] },
    //   down: { count: 0, deviceIds: [] },
    // };

    // const thresholdTime = new Date(Date.now() - 1 * 120 * 1000);

    // for (const server of servers) {
    //   const deviceId = server.deviceId;

    //   const latestCpuMetric = await CPUMetrics.findOne({ deviceId })
    //     .sort({ timestamp: -1 })
    //     .limit(1);

    //   const latestMemoryMetric = await MemoryMetrics.findOne({ deviceId })
    //     .sort({ timestamp: -1 })
    //     .limit(1);

    //   // Fetch all latest disk metrics for this device
    //   const diskMetrics = await DiskMetrics.aggregate([
    //     { $match: { deviceId } },
    //     { $sort: { timestamp: -1 } },
    //     {
    //       $group: {
    //         _id: "$filesystem",
    //         latestMetric: { $first: "$$ROOT" },
    //       },
    //     },
    //     { $replaceRoot: { newRoot: "$latestMetric" } },
    //   ]);

    //   // Calculate overall disk usage percentage
    //   let overallDiskUsage = 0;
    //   let totalUsed = 0;
    //   let totalSize = 0;
    //   if (diskMetrics.length > 0) {
    //     for (const disk of diskMetrics) {
    //       if (
    //         typeof disk.used === "number" &&
    //         typeof disk.size === "number" &&
    //         disk.size > 0
    //       ) {
    //         totalUsed += disk.used;
    //         totalSize += disk.size;
    //       }
    //     }
    //     if (totalSize > 0) {
    //       overallDiskUsage = (totalUsed / totalSize) * 100;
    //     }
    //   }

    //   const latestTimestamp =
    //     latestCpuMetric?.timestamp ||
    //     latestMemoryMetric?.timestamp ||
    //     (diskMetrics.length > 0 ? diskMetrics[0].timestamp : null);

    //   if (!latestTimestamp || new Date(latestTimestamp) < thresholdTime) {
    //     statusCategories.down.count++;
    //     statusCategories.down.deviceIds.push(deviceId);
    //     continue;
    //   }

    //   const cpuUsage = latestCpuMetric
    //     ? parseFloat(latestCpuMetric.usagePercentage)
    //     : 0;
    //   const memoryUsage = latestMemoryMetric
    //     ? parseFloat(latestMemoryMetric.usagePercentage)
    //     : 0;

    //   // Use overallDiskUsage instead of maxDiskUsage
    //   const maxUsage = Math.max(cpuUsage, memoryUsage, overallDiskUsage);

    //   if (maxUsage >= 90) {
    //     statusCategories.critical.count++;
    //     statusCategories.critical.deviceIds.push(deviceId);
    //   } else if (maxUsage >= 80) {
    //     statusCategories.trouble.count++;
    //     statusCategories.trouble.deviceIds.push(deviceId);
    //   } else {
    //     statusCategories.up.count++;
    //     statusCategories.up.deviceIds.push(deviceId);
    //   }
    // }

    const result = await Device.aggregate([
      {
        $group: {
          _id: null,
          all: { $sum: 1 },
          up: {
            $sum: { $cond: [{ $eq: ["$status", "up"] }, 1, 0] },
          },
          down: {
            $sum: { $cond: [{ $eq: ["$status", "down"] }, 1, 0] },
          },
          critical: {
            $sum: { $cond: [{ $eq: ["$status", "critical"] }, 1, 0] },
          },
          trouble: {
            $sum: { $cond: [{ $eq: ["$status", "trouble"] }, 1, 0] },
          },
        },
      },
      {
        $project: {
          _id: 0,
          all: 1,
          up: 1,
          down: 1,
          critical: 1,
          trouble: 1,
        },
      },
    ]);

    if (!result.length || Object.keys(result[0]).length === 0) {
      return res.status(200).json({
        success: true,
        data: {
          all: 0,
          up: 0,
          down: 0,
          critical: 0,
          trouble: 0,
        },
      });
    }

    res.status(200).json({
      success: true,
      data: result[0],
    });
  } catch (error) {
    console.error("Error fetching server status counts:", error);
    res.status(500).json({
      success: false,
      error: "Failed to fetch server status counts",
    });
  }
});

// Delete server and all related metrics data
router.put("/servers/:deviceId", authenticateToken, async (req, res) => {
  try {
    const { deviceId } = req.params;
    const { name } = req.body;
    if (!name) {
      return res.status(400).json({
        success: false,
        message: "Name is required",
      });
    }

    // Find the server first to check if it exists
    const server = await Device.findOne({ deviceId });

    if (!server) {
      return res.status(404).json({
        success: false,
        message: "Server not found",
      });
    }

    // Update the server name
    await Device.updateOne({ deviceId }, { deviceName: name });

    res.json({
      success: true,
      message: `Server ${deviceId} name updated successfully`,
    });
  } catch (error) {
    console.error("Error updating server name:", error);
    res.status(500).json({
      success: false,
      error: "Failed to update server name",
    });
  }
});
// Delete server and all related metrics data
router.delete("/servers/:deviceId", authenticateToken, async (req, res) => {
  try {
    const { deviceId } = req.params;

    // Find the server first to check if it exists
    const server = await Device.findOne({ deviceId });

    if (!server) {
      return res.status(404).json({
        success: false,
        message: "Server not found",
      });
    }

    // Delete the server and all related metrics in parallel
    await Promise.all([
      Device.deleteOne({ deviceId }),
      CPUMetrics.deleteMany({ deviceId }),
      MemoryMetrics.deleteMany({ deviceId }),
      DiskMetrics.deleteMany({ deviceId }),
      NetworkMetrics.deleteMany({ deviceId }),
    ]);

    res.json({
      success: true,
      message: `Server ${deviceId} and all related metrics have been deleted successfully`,
    });
  } catch (error) {
    console.error("Error deleting server and related metrics:", error);
    res.status(500).json({
      success: false,
      error: "Failed to delete server and related metrics",
    });
  }
});

router.post("/reports", authenticateToken, async (req, res) => {
  try {
    // Define time ranges
    const now = new Date();
    const last24Hours = new Date(now.getTime() - 24 * 60 * 60 * 1000);
    const lastWeek = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
    const lastMonth = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
    const condition = {};
    if (
      req.body?.deviceIds &&
      req.body.deviceIds.length > 0 &&
      req.body.deviceIds[0] !== "all"
    ) {
      condition.deviceId = { $in: req.body.deviceIds };
    }

    if (req.body?.removedIds && req.body.removedIds.length > 0) {
      condition.deviceId = { $nin: req.body.removedIds };
    }

    // Get all active devices
    const devices = await Device.find(
      condition,
      "deviceId deviceName ipV4 status"
    ).lean();

    if (!devices || devices.length === 0) {
      return res.json({
        success: true,
        data: [],
        message: "No devices found",
      });
    }

    const deviceIds = devices.map((device) => device.deviceId);

    // Parallel aggregation for all metrics and time periods
    const [
      cpu24h,
      cpuWeek,
      cpuMonth,
      memory24h,
      memoryWeek,
      memoryMonth,
      disk24h,
      diskWeek,
      diskMonth,
      network24h,
      networkWeek,
      networkMonth,
    ] = await Promise.all([
      // CPU Metrics
      aggregateMetrics(CPUMetrics, deviceIds, last24Hours, "cpu"),
      aggregateMetrics(CPUMetrics, deviceIds, lastWeek, "cpu"),
      aggregateMetrics(CPUMetrics, deviceIds, lastMonth, "cpu"),

      // Memory Metrics
      aggregateMetrics(MemoryMetrics, deviceIds, last24Hours, "memory"),
      aggregateMetrics(MemoryMetrics, deviceIds, lastWeek, "memory"),
      aggregateMetrics(MemoryMetrics, deviceIds, lastMonth, "memory"),

      // Disk Metrics
      aggregateMetrics(DiskMetrics, deviceIds, last24Hours, "disk"),
      aggregateMetrics(DiskMetrics, deviceIds, lastWeek, "disk"),
      aggregateMetrics(DiskMetrics, deviceIds, lastMonth, "disk"),

      // Network Metrics
      aggregateMetrics(NetworkMetrics, deviceIds, last24Hours, "network"),
      aggregateMetrics(NetworkMetrics, deviceIds, lastWeek, "network"),
      aggregateMetrics(NetworkMetrics, deviceIds, lastMonth, "network"),
    ]);

    // Organize data by device
    const reports = devices.map((device) => {
      const deviceId = device.deviceId;

      return {
        deviceId: device.deviceId,
        deviceName: device.deviceName,
        ipV4: device.ipV4,
        status: device.status,
        reports: {
          last24Hours: {
            cpu: findMetricByDeviceId(cpu24h, deviceId),
            memory: findMetricByDeviceId(memory24h, deviceId),
            disk: findMetricByDeviceId(disk24h, deviceId),
            network: findMetricByDeviceId(network24h, deviceId),
          },
          lastWeek: {
            cpu: findMetricByDeviceId(cpuWeek, deviceId),
            memory: findMetricByDeviceId(memoryWeek, deviceId),
            disk: findMetricByDeviceId(diskWeek, deviceId),
            network: findMetricByDeviceId(networkWeek, deviceId),
          },
          lastMonth: {
            cpu: findMetricByDeviceId(cpuMonth, deviceId),
            memory: findMetricByDeviceId(memoryMonth, deviceId),
            disk: findMetricByDeviceId(diskMonth, deviceId),
            network: findMetricByDeviceId(networkMonth, deviceId),
          },
        },
      };
    });

    res.json({
      success: true,
      data: reports,
      totalDevices: devices.length,
      generatedAt: now,
    });
  } catch (error) {
    console.error("Error generating reports:", error);
    res.status(500).json({
      success: false,
      error: "Failed to generate reports",
      details: error.message,
    });
  }
});

// Helper function to aggregate metrics efficiently
async function aggregateMetrics(Model, deviceIds, startTime, metricType) {
  // For network metrics (cumulative), we need first and last values
  // For CPU, memory, disk (instantaneous), we use average/min/max
  if (metricType === "network") {
    const pipeline = [
      {
        $match: {
          deviceId: { $in: deviceIds },
          timestamp: { $gte: startTime },
        },
      },
      {
        $sort: { deviceId: 1, timestamp: 1 },
      },
      {
        $group: {
          _id: "$deviceId",
          dataPoints: { $sum: 1 },
          firstRecorded: { $min: "$timestamp" },
          lastRecorded: { $max: "$timestamp" },
          // Get first and last values for cumulative metrics
          firstBytesReceived: { $first: "$bytesReceived" },
          lastBytesReceived: { $last: "$bytesReceived" },
          firstBytesSent: { $first: "$bytesSent" },
          lastBytesSent: { $last: "$bytesSent" },
          firstPacketsReceived: { $first: "$packetsReceived" },
          lastPacketsReceived: { $last: "$packetsReceived" },
          firstPacketsSent: { $first: "$packetsSent" },
          lastPacketsSent: { $last: "$packetsSent" },
          firstErrorsReceived: { $first: "$errorsReceived" },
          lastErrorsReceived: { $last: "$errorsReceived" },
          firstErrorsSent: { $first: "$errorsSent" },
          lastErrorsSent: { $last: "$errorsSent" },
        },
      },
      {
        $addFields: {
          // Calculate the difference (actual usage during the period)
          totalBytesReceived: {
            $cond: [
              { $gte: ["$lastBytesReceived", "$firstBytesReceived"] },
              { $subtract: ["$lastBytesReceived", "$firstBytesReceived"] },
              "$lastBytesReceived", // Handle counter reset case
            ],
          },
          totalBytesSent: {
            $cond: [
              { $gte: ["$lastBytesSent", "$firstBytesSent"] },
              { $subtract: ["$lastBytesSent", "$firstBytesSent"] },
              "$lastBytesSent",
            ],
          },
          totalPacketsReceived: {
            $cond: [
              { $gte: ["$lastPacketsReceived", "$firstPacketsReceived"] },
              { $subtract: ["$lastPacketsReceived", "$firstPacketsReceived"] },
              "$lastPacketsReceived",
            ],
          },
          totalPacketsSent: {
            $cond: [
              { $gte: ["$lastPacketsSent", "$firstPacketsSent"] },
              { $subtract: ["$lastPacketsSent", "$firstPacketsSent"] },
              "$lastPacketsSent",
            ],
          },
          totalErrorsReceived: {
            $cond: [
              { $gte: ["$lastErrorsReceived", "$firstErrorsReceived"] },
              { $subtract: ["$lastErrorsReceived", "$firstErrorsReceived"] },
              "$lastErrorsReceived",
            ],
          },
          totalErrorsSent: {
            $cond: [
              { $gte: ["$lastErrorsSent", "$firstErrorsSent"] },
              { $subtract: ["$lastErrorsSent", "$firstErrorsSent"] },
              "$lastErrorsSent",
            ],
          },
        },
      },
      {
        $addFields: {
          // Calculate averages based on time period
          avgBytesReceived: {
            $cond: [
              { $gt: ["$dataPoints", 1] },
              {
                $divide: [
                  "$totalBytesReceived",
                  {
                    $subtract: [
                      {
                        $divide: [
                          { $subtract: ["$lastRecorded", "$firstRecorded"] },
                          1000,
                        ],
                      },
                      0,
                    ],
                  },
                ],
              },
              0,
            ],
          },
          avgBytesSent: {
            $cond: [
              { $gt: ["$dataPoints", 1] },
              {
                $divide: [
                  "$totalBytesSent",
                  {
                    $subtract: [
                      {
                        $divide: [
                          { $subtract: ["$lastRecorded", "$firstRecorded"] },
                          1000,
                        ],
                      },
                      0,
                    ],
                  },
                ],
              },
              0,
            ],
          },
        },
      },
    ];

    return await Model.aggregate(pipeline).exec();
  } else {
    // For instantaneous metrics (CPU, memory, disk)
    const pipeline = [
      {
        $match: {
          deviceId: { $in: deviceIds },
          timestamp: { $gte: startTime },
        },
      },
      {
        $group: {
          _id: "$deviceId",
          ...getAggregationFields(metricType),
          dataPoints: { $sum: 1 },
          firstRecorded: { $min: "$timestamp" },
          lastRecorded: { $max: "$timestamp" },
        },
      },
    ];

    return await Model.aggregate(pipeline).exec();
  }
}

// Helper function to get aggregation fields based on metric type
function getAggregationFields(metricType) {
  switch (metricType) {
    case "cpu":
      return {
        avgUsagePercentage: { $avg: "$usagePercentage" },
        maxUsagePercentage: { $max: "$usagePercentage" },
        minUsagePercentage: { $min: "$usagePercentage" },
        avgUserPercentage: { $avg: "$userPercentage" },
        avgSysPercentage: { $avg: "$sysPercentage" },
      };

    case "memory":
      return {
        avgUsagePercentage: { $avg: "$usagePercentage" },
        maxUsagePercentage: { $max: "$usagePercentage" },
        minUsagePercentage: { $min: "$usagePercentage" },
        avgTotalMemory: { $avg: "$totalMemory" },
        avgUsedMemory: { $avg: "$usedMemory" },
        avgFreeMemory: { $avg: "$freeMemory" },
      };

    case "disk":
      return {
        avgUsagePercentage: { $avg: "$usagePercentage" },
        maxUsagePercentage: { $max: "$usagePercentage" },
        minUsagePercentage: { $min: "$usagePercentage" },
        avgSize: { $avg: "$size" },
        avgUsed: { $avg: "$used" },
        avgAvailable: { $avg: "$available" },
      };

    case "network":
      // This is handled in the aggregateMetrics function for network
      return {};

    default:
      return {};
  }
}

// Helper function to find metric data for a specific device
function findMetricByDeviceId(metricsArray, deviceId) {
  const metric = metricsArray.find((m) => m._id === deviceId);
  if (!metric) {
    return {
      available: false,
      message: "No data available for this period",
    };
  }

  // Remove the _id field and add availability flag
  const { _id, ...data } = metric;

  // Clean up network-specific fields that are not needed in the response
  const cleanedData = { ...data };
  delete cleanedData.firstBytesReceived;
  delete cleanedData.lastBytesReceived;
  delete cleanedData.firstBytesSent;
  delete cleanedData.lastBytesSent;
  delete cleanedData.firstPacketsReceived;
  delete cleanedData.lastPacketsReceived;
  delete cleanedData.firstPacketsSent;
  delete cleanedData.lastPacketsSent;
  delete cleanedData.firstErrorsReceived;
  delete cleanedData.lastErrorsReceived;
  delete cleanedData.firstErrorsSent;
  delete cleanedData.lastErrorsSent;

  return {
    available: true,
    ...cleanedData,
    // Round percentage values to 2 decimal places
    ...Object.keys(cleanedData).reduce((acc, key) => {
      if (key.includes("Percentage") && typeof cleanedData[key] === "number") {
        acc[key] = Math.round(cleanedData[key] * 100) / 100;
      }
      return acc;
    }, {}),
  };
}

module.exports = router;
