const si = require("systeminformation");
const DiskMetrics = require("../models/DiskMetrics");
const { getDeviceId } = require("./deviceDetails");
const Device = require("../models/Device");

async function getDiskUsage() {
  try {
    const fsSize = await si.fsSize();
    return fsSize;
  } catch (error) {
    console.error("Error getting disk usage:", error);
    return [];
  }
}

async function collectDiskMetrics() {
  try {
    const deviceId = getDeviceId();
    const diskUsage = await getDiskUsage();

    for (const fs of diskUsage) {
      const metrics = new DiskMetrics({
        deviceId: deviceId,
        filesystem: fs.fs,
        size: fs.size,
        used: fs.used,
        available: fs.available,
        mount: fs.mount,
        usagePercentage: fs.use,
      });

      await metrics.save();
    }

    // save last timestamp
    await Device.findOneAndUpdate(
      { deviceId: deviceId },
      { timestamp: new Date() }
    );

    console.log("Disk metrics collected and saved:", new Date().toISOString());
  } catch (error) {
    console.error("Error collecting disk metrics:", error);
  }
}

module.exports = { collectDiskMetrics };
