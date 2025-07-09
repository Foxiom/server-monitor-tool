const os = require("os");
const CPUMetrics = require("../models/CPUMetrics");
const { getDeviceId } = require("./deviceDetails");
const Device = require("../models/Device");

function getCPUUsage() {
  const cpus = os.cpus();
  let totalIdle = 0;
  let totalTick = 0;
  let totalUser = 0;
  let totalSys = 0;

  cpus.forEach((cpu) => {
    for (const type in cpu.times) {
      totalTick += cpu.times[type];
    }
    totalIdle += cpu.times.idle;
    totalUser += cpu.times.user;
    totalSys += cpu.times.sys;
  });

  return {
    idleSeconds: totalIdle / cpus.length,
    totalSeconds: totalTick / cpus.length,
    usagePercentage: (((totalTick - totalIdle) / totalTick) * 100).toFixed(2),
    userPercentage: ((totalUser / totalTick) * 100).toFixed(2),
    sysPercentage: ((totalSys / totalTick) * 100).toFixed(2),
  };
}

async function collectCPUMetrics() {
  try {
    const deviceId = getDeviceId();
    const cpuUsage = getCPUUsage();

    const metrics = new CPUMetrics({
      deviceId: deviceId,
      idleSeconds: cpuUsage.idleSeconds,
      totalSeconds: cpuUsage.totalSeconds,
      usagePercentage: parseFloat(cpuUsage.usagePercentage),
      userPercentage: parseFloat(cpuUsage.userPercentage),
      sysPercentage: parseFloat(cpuUsage.sysPercentage),
    });

    await metrics.save();

    // save last timestamp
    await Device.findOneAndUpdate(
      { deviceId: deviceId },
      { timestamp: new Date() }
    );
    console.log("CPU metrics collected and saved:", new Date().toISOString());
  } catch (error) {
    console.error("Error collecting CPU metrics:", error);
  }
}

module.exports = { collectCPUMetrics };
