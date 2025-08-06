const express = require("express");
const cors = require("cors");
const connectToMongoDB = require("./config/db");
const { sendDeviceDetails } = require("./utils/deviceDetails");
const { collectCPUMetrics } = require("./utils/cpuMetrics");
const { collectMemoryMetrics } = require("./utils/memoryMetrics");
const { collectDiskMetrics } = require("./utils/diskMetrics");
const { collectNetworkMetrics } = require("./utils/networkMetrics");

const app = express();
const port = 3000;
const intervalInSeconds = 120;

app.use(cors());
app.use(express.json());


async function collectDeviceDetails() {
  try {
    await collectCPUMetrics();
    await collectMemoryMetrics();
    await collectDiskMetrics();
    await collectNetworkMetrics();
  } catch (error) {
    console.error("Error collecting metrics:", error);
  }
}

app.listen(port, async () => {
  console.log(`Posting server is listening on port ${port}`);
  await connectToMongoDB();
  await sendDeviceDetails();
  collectDeviceDetails();
  setInterval(collectDeviceDetails, intervalInSeconds * 1000);
});
