const CPUMetrics = require("../models/CPUMetrics");
const Device = require("../models/Device");
const DiskMetrics = require("../models/DiskMetrics");
const MemoryMetrics = require("../models/MemoryMetrics");
const sendEmail = require("./Email");

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
    const servers = await Device.find().select("deviceId");
    const thresholdTime = new Date(Date.now() - 2 * 60 * 1000); // 2 minutes threshold

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
            alertSent: server.status !== "down" ? false : server.alertSent,
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
          alertSent:
            server.status === "down" && status == "up" ? false : server.alertSent,
          maxUsage: Math.round(maxUsage * 100) / 100, // Round to 2 decimal places
          cpuUsage: Math.round(cpuUsage * 100) / 100,
          memoryUsage: Math.round(memoryUsage * 100) / 100,
          diskUsage: Math.round(overallDiskUsage * 100) / 100,
        };
      } catch (error) {
        console.error(`Error processing device ${deviceId}:`, error);
        return {
          deviceId,
          alertSent: server.alertSent,
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

//send server status to email
const sendServerStatusEmail = async () => {
  try {
    const downDevices = await Device.find({ status: "down", alertSent: false })
      .select("deviceId deviceName")
      .lean();
    const upDevices = await Device.find({ status: "up", alertSent: false })
      .select("deviceId deviceName")
      .lean();

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

module.exports = {
  deletePastMetrics,
  updateServerStatus,
  sendServerStatusEmail,
  getServerStatusSummary,
};
