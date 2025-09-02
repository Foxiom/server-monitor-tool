const CPUMetrics = require("../models/CPUMetrics");
const Device = require("../models/Device");
const DiskMetrics = require("../models/DiskMetrics");
const MemoryMetrics = require("../models/MemoryMetrics");
const NetworkMetrics = require("../models/NetworkMetrics");
const sendEmail = require("./Email");
const { broadcast } = require("./PushSender");

const deletePastMetrics = async () => {
  try {
    const threeMonthsAgo = new Date(Date.now() - 3 * 30 * 24 * 60 * 60 * 1000);
    await CPUMetrics.deleteMany({ timestamp: { $lt: threeMonthsAgo } });
    await MemoryMetrics.deleteMany({ timestamp: { $lt: threeMonthsAgo } });
    await DiskMetrics.deleteMany({ timestamp: { $lt: threeMonthsAgo } });
    await NetworkMetrics.deleteMany({ timestamp: { $lt: threeMonthsAgo } });
    console.log("Past metrics deleted successfully");
  } catch (error) {
    console.error("Error deleting past metrics:", error);
  }
};

const updateServerStatus = async () => {
  try {
    const servers = await Device.find().select(
      "deviceId status deviceName alertSent"
    );
    const thresholdTime = new Date(Date.now() - (2 * 60 + 10) * 1000); // 2 min 10 sec

    // Batch operations for better performance
    const bulkOperations = [];

    // Use Promise.allSettled to handle multiple servers concurrently
    const statusPromises = servers.map(async (server) => {
      const deviceId = server.deviceId;

      try {
        // Fetch all metrics concurrently
        const [latestCpuMetric, latestMemoryMetric, diskMetrics] =
          await Promise.all([
            CPUMetrics.findOne({ deviceId }).sort({ timestamp: -1 }).limit(1),
            MemoryMetrics.findOne({ deviceId })
              .sort({ timestamp: -1 })
              .limit(1),
            DiskMetrics.aggregate([
              { $match: { deviceId } },
              { $sort: { timestamp: -1 } },
              {
                $group: {
                  _id: "$filesystem",
                  latestMetric: { $first: "$$ROOT" },
                },
              },
              { $replaceRoot: { newRoot: "$latestMetric" } },
            ]),
          ]);

        // Calculate overall disk usage
        let overallDiskUsage = 0;
        if (diskMetrics.length > 0) {
          let totalUsed = 0;
          let totalSize = 0;

          for (const disk of diskMetrics) {
            if (
              typeof disk.used === "number" &&
              typeof disk.size === "number" &&
              disk.size > 0
            ) {
              totalUsed += disk.used;
              totalSize += disk.size;
            }
          }

          if (totalSize > 0) {
            overallDiskUsage = (totalUsed / totalSize) * 100;
          }
        }

        // Check if device is responsive (has recent data)
        const latestTimestamp =
          latestCpuMetric?.timestamp ||
          latestMemoryMetric?.timestamp ||
          (diskMetrics.length > 0 ? diskMetrics[0].timestamp : null);

        if (!latestTimestamp || new Date(latestTimestamp) < thresholdTime) {
          return {
            deviceId,
            alertSent: server.status !== "down" ? false : true,
            status: "down",
            reason: "No recent metrics data",
          };
        }

        // Calculate usage percentages
        const cpuUsage = latestCpuMetric
          ? parseFloat(latestCpuMetric.usagePercentage)
          : 0;
        const memoryUsage = latestMemoryMetric
          ? parseFloat(latestMemoryMetric.usagePercentage)
          : 0;

        // Determine status based on maximum usage
        const maxUsage = Math.max(cpuUsage, memoryUsage, overallDiskUsage);

        let status;
        if (maxUsage >= 90) {
          status = "critical";
        } else if (maxUsage >= 80) {
          status = "trouble";
        } else {
          status = "up";
        }

        return {
          deviceId,
          status,
          alertSent: server.status === "down" && status === "up" ? false : true,
          maxUsage: Math.round(maxUsage * 100) / 100, // Round to 2 decimal places
          cpuUsage: Math.round(cpuUsage * 100) / 100,
          memoryUsage: Math.round(memoryUsage * 100) / 100,
          diskUsage: Math.round(overallDiskUsage * 100) / 100,
        };
      } catch (error) {
        console.error(`Error processing device ${deviceId}:`, error);
        return {
          deviceId,
          alertSent: true,
          status: "down",
          reason: "Error processing metrics",
        };
      }
    });

    // Wait for all status calculations to complete
    const statusResults = await Promise.allSettled(statusPromises);

    // Process results and prepare bulk operations
    let successCount = 0;
    let errorCount = 0;

    statusResults.forEach((result) => {
      if (result.status === "fulfilled" && result.value) {
        const {
          deviceId,
          status,
          alertSent,
          maxUsage,
          cpuUsage,
          memoryUsage,
          diskUsage,
          reason,
        } = result.value;

        // Prepare update operation
        const updateData = {
          status,
          alertSent,
          lastStatusUpdate: new Date(),
        };

        // Optionally store usage metrics in device document
        if (maxUsage !== undefined) {
          updateData.metrics = {
            cpu: cpuUsage,
            memory: memoryUsage,
            disk: diskUsage,
            max: maxUsage,
            lastUpdated: new Date(),
          };
        }

        if (reason) {
          updateData.statusReason = reason;
        }

        bulkOperations.push({
          updateOne: {
            filter: { deviceId },
            update: { $set: updateData },
          },
        });

        successCount++;
      } else {
        errorCount++;
        console.error("Failed to process server status:", result.reason);
      }
    });

    // Execute bulk update if there are operations
    if (bulkOperations.length > 0) {
      const bulkResult = await Device.bulkWrite(bulkOperations);
      console.log(
        `Server status updated successfully: ${successCount} devices processed, ${bulkResult.modifiedCount} updated`
      );

      if (errorCount > 0) {
        console.warn(`${errorCount} devices failed to process`);
      }
    } else {
      console.log("No devices to update");
    }

    return {
      success: true,
      processed: successCount,
      errors: errorCount,
      updated: bulkOperations.length,
    };
  } catch (error) {
    console.error("Error updating server status:", error);
    throw error;
  }
};

// Optional: Add a function to get status summary
const getServerStatusSummary = async () => {
  try {
    const summary = await Device.aggregate([
      {
        $group: {
          _id: "$status",
          count: { $sum: 1 },
          deviceIds: { $push: "$deviceId" },
        },
      },
    ]);

    const statusCategories = {
      all: { count: 0, deviceIds: [] },
      up: { count: 0, deviceIds: [] },
      trouble: { count: 0, deviceIds: [] },
      critical: { count: 0, deviceIds: [] },
      down: { count: 0, deviceIds: [] },
    };

    let totalDevices = 0;
    const allDeviceIds = [];

    summary.forEach((item) => {
      const status = item._id || "unknown";
      if (statusCategories[status]) {
        statusCategories[status] = {
          count: item.count,
          deviceIds: item.deviceIds,
        };
      }
      totalDevices += item.count;
      allDeviceIds.push(...item.deviceIds);
    });

    statusCategories.all = {
      count: totalDevices,
      deviceIds: allDeviceIds,
    };

    return statusCategories;
  } catch (error) {
    console.error("Error getting server status summary:", error);
    throw error;
  }
};

const sendServerStatusPush = async (devices, status) => {
  if (!devices.length) return;
  const payload = {
    title: `Servers ${status}`,
    body: devices.map((d) => d.deviceName).join(", "),
    tag: `servers-${status}`,
    url: "/dashboard/servers", // open path on click
  };
  await broadcast(payload);
};

//send server status to email
const sendServerStatusEmail = async () => {
  try {
    const downDevices = await Device.find({ status: "down", alertSent: false })
      .select("deviceId deviceName")
      .lean();
    const upDevices = await Device.find({ status: "up", alertSent: false })
      .select("deviceId deviceName")
      .lean();

    // after sending email:
    if (upDevices.length) await sendServerStatusPush(upDevices, "up");
    if (downDevices.length) await sendServerStatusPush(downDevices, "down");

    if (upDevices.length > 0) {
      const emailOptions = {
        servers: upDevices.map((device) => device.deviceName),
        status: "up",
      };
      await sendEmail(emailOptions);
      await Device.updateMany(
        { deviceId: { $in: upDevices.map((device) => device.deviceId) } },
        { alertSent: true }
      );
    }
    if (downDevices.length > 0) {
      const emailOptions = {
        servers: downDevices.map((device) => device.deviceName),
        status: "down",
      };
      await sendEmail(emailOptions);
      await Device.updateMany(
        { deviceId: { $in: downDevices.map((device) => device.deviceId) } },
        { alertSent: true }
      );
    }
    console.log("Server status email sent successfully");
  } catch (error) {
    console.error("Error sending server status email:", error);
  }
};

//delete network metrics first of month
const deleteNetworkMetrics = async () => {
  try {
    // Get all devices with their deviceIds
    const devices = await Device.find({}, { deviceId: 1 }).lean();
    const deviceIds = devices.map((device) => device.deviceId);

    if (deviceIds.length === 0) {
      console.log("No devices found");
      return;
    }

    console.log(`Processing ${deviceIds.length} devices...`);

    // Calculate date range for previous month
    const now = new Date();
    const previousMonthStart = new Date(
      now.getFullYear(),
      now.getMonth() - 1,
      1
    );
    const previousMonthEnd = new Date(
      now.getFullYear(),
      now.getMonth(),
      0,
      23,
      59,
      59,
      999
    );

    // Calculate aggregated metrics for each device using proper cumulative calculation
    const aggregatedMetrics = await NetworkMetrics.aggregate([
      {
        $match: {
          deviceId: { $in: deviceIds },
          timestamp: {
            $gte: previousMonthStart,
            $lte: previousMonthEnd,
          },
        },
      },
      {
        $sort: { deviceId: 1, timestamp: 1 },
      },
      {
        $group: {
          _id: "$deviceId",
          dataPoints: { $sum: 1 },
          firstTimestamp: { $min: "$timestamp" },
          lastTimestamp: { $max: "$timestamp" },

          // Get first and last values for cumulative metrics
          firstBytesReceived: { $first: { $ifNull: ["$bytesReceived", 0] } },
          lastBytesReceived: { $last: { $ifNull: ["$bytesReceived", 0] } },
          firstBytesSent: { $first: { $ifNull: ["$bytesSent", 0] } },
          lastBytesSent: { $last: { $ifNull: ["$bytesSent", 0] } },
          firstPacketsReceived: { $first: "$packetsReceived" },
          lastPacketsReceived: { $last: "$packetsReceived" },
          firstPacketsSent: { $first: "$packetsSent" },
          lastPacketsSent: { $last: "$packetsSent" },
          firstErrorsReceived: { $first: { $ifNull: ["$errorsReceived", 0] } },
          lastErrorsReceived: { $last: { $ifNull: ["$errorsReceived", 0] } },
          firstErrorsSent: { $first: { $ifNull: ["$errorsSent", 0] } },
          lastErrorsSent: { $last: { $ifNull: ["$errorsSent", 0] } },

          // Check if we have any non-null packet data
          hasPacketData: {
            $sum: {
              $cond: [
                {
                  $or: [
                    { $ne: ["$packetsReceived", null] },
                    { $ne: ["$packetsSent", null] },
                  ],
                },
                1,
                0,
              ],
            },
          },
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
              { $eq: ["$hasPacketData", 0] }, // No packet data available
              0, // Use 0 instead of null for storage
              {
                $cond: [
                  {
                    $and: [
                      { $ne: ["$firstPacketsReceived", null] },
                      { $ne: ["$lastPacketsReceived", null] },
                      {
                        $gte: ["$lastPacketsReceived", "$firstPacketsReceived"],
                      },
                    ],
                  },
                  {
                    $subtract: [
                      "$lastPacketsReceived",
                      "$firstPacketsReceived",
                    ],
                  },
                  { $ifNull: ["$lastPacketsReceived", 0] },
                ],
              },
            ],
          },
          totalPacketsSent: {
            $cond: [
              { $eq: ["$hasPacketData", 0] }, // No packet data available
              0, // Use 0 instead of null for storage
              {
                $cond: [
                  {
                    $and: [
                      { $ne: ["$firstPacketsSent", null] },
                      { $ne: ["$lastPacketsSent", null] },
                      { $gte: ["$lastPacketsSent", "$firstPacketsSent"] },
                    ],
                  },
                  { $subtract: ["$lastPacketsSent", "$firstPacketsSent"] },
                  { $ifNull: ["$lastPacketsSent", 0] },
                ],
              },
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
          // Calculate averages based on time period duration
          avgBytesReceived: {
            $cond: [
              {
                $and: [
                  { $gt: ["$dataPoints", 1] },
                  {
                    $gt: [
                      { $subtract: ["$lastTimestamp", "$firstTimestamp"] },
                      0,
                    ],
                  },
                ],
              },
              {
                $divide: [
                  "$totalBytesReceived",
                  {
                    $divide: [
                      { $subtract: ["$lastTimestamp", "$firstTimestamp"] },
                      1000,
                    ],
                  },
                ],
              },
              0,
            ],
          },
          avgBytesSent: {
            $cond: [
              {
                $and: [
                  { $gt: ["$dataPoints", 1] },
                  {
                    $gt: [
                      { $subtract: ["$lastTimestamp", "$firstTimestamp"] },
                      0,
                    ],
                  },
                ],
              },
              {
                $divide: [
                  "$totalBytesSent",
                  {
                    $divide: [
                      { $subtract: ["$lastTimestamp", "$firstTimestamp"] },
                      1000,
                    ],
                  },
                ],
              },
              0,
            ],
          },
        },
      },
      {
        $project: {
          _id: 1,
          totalBytesReceived: 1,
          totalBytesSent: 1,
          avgBytesReceived: 1,
          avgBytesSent: 1,
          totalPacketsReceived: 1,
          totalPacketsSent: 1,
          totalErrorsReceived: 1,
          totalErrorsSent: 1,
          dataPoints: 1,
        },
      },
    ]);

    console.log(`Calculated metrics for ${aggregatedMetrics.length} devices`);

    // Batch update devices with their previous month metrics
    const bulkOperations = aggregatedMetrics.map((metrics) => ({
      updateOne: {
        filter: { deviceId: metrics._id },
        update: {
          $set: {
            previousMonthNetworkMetrics: {
              totalBytesReceived: Math.max(0, metrics.totalBytesReceived || 0),
              totalBytesSent: Math.max(0, metrics.totalBytesSent || 0),
              avgBytesReceived: Math.round(
                Math.max(0, metrics.avgBytesReceived || 0)
              ),
              avgBytesSent: Math.round(Math.max(0, metrics.avgBytesSent || 0)),
              totalPacketsReceived: Math.max(
                0,
                metrics.totalPacketsReceived || 0
              ),
              totalPacketsSent: Math.max(0, metrics.totalPacketsSent || 0),
              totalErrorsReceived: Math.max(
                0,
                metrics.totalErrorsReceived || 0
              ),
              totalErrorsSent: Math.max(0, metrics.totalErrorsSent || 0),
              dataPoints: metrics.dataPoints || 0,
            },
          },
        },
      },
    }));

    // Execute bulk update if there are operations to perform
    if (bulkOperations.length > 0) {
      const updateResult = await Device.bulkWrite(bulkOperations, {
        ordered: false,
      });
      console.log(
        `Updated ${updateResult.modifiedCount} devices with previous month metrics`
      );
    }

    // Handle devices that have no network metrics (set empty/zero values)
    const devicesWithMetrics = new Set(aggregatedMetrics.map((m) => m._id));
    const devicesWithoutMetrics = deviceIds.filter(
      (id) => !devicesWithMetrics.has(id)
    );

    if (devicesWithoutMetrics.length > 0) {
      const emptyMetricsUpdate = await Device.updateMany(
        { deviceId: { $in: devicesWithoutMetrics } },
        {
          $set: {
            previousMonthNetworkMetrics: {
              totalBytesReceived: 0,
              totalBytesSent: 0,
              avgBytesReceived: 0,
              avgBytesSent: 0,
              totalPacketsReceived: 0,
              totalPacketsSent: 0,
              totalErrorsReceived: 0,
              totalErrorsSent: 0,
              dataPoints: 0,
            },
          },
        }
      );
      console.log(
        `Updated ${emptyMetricsUpdate.modifiedCount} devices with empty metrics`
      );
    }

    // Delete all network metrics after successful update
    const deleteResult = await NetworkMetrics.deleteMany({
      deviceId: { $in: deviceIds },
    });

    console.log(
      `Successfully deleted ${deleteResult.deletedCount} network metrics records`
    );
    console.log(
      "Previous month network metrics updated and historical data cleared"
    );
  } catch (error) {
    console.error(
      "Error updating previous month metrics and deleting network data:",
      error
    );
    throw error; // Re-throw to allow caller to handle the error
  }
};

module.exports = {
  deletePastMetrics,
  updateServerStatus,
  sendServerStatusEmail,
  getServerStatusSummary,
  deleteNetworkMetrics,
};
