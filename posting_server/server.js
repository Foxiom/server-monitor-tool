const express = require('express');
const cors = require('cors');
const connectToMongoDB = require('./config/db');
const { sendDeviceDetails } = require('./utils/deviceDetails');
const { collectCPUMetrics } = require('./utils/cpuMetrics');
const { collectMemoryMetrics } = require('./utils/memoryMetrics');
const { collectDiskMetrics } = require('./utils/diskMetrics');
const { collectNetworkMetrics } = require('./utils/networkMetrics');
const authRoutes = require('./routes/auth');
const User = require('./models/User');
const bcrypt = require('bcryptjs');

const app = express();
const port = 3000;
const intervalInSeconds = 60;

app.use(cors());
app.use(express.json());

app.use('/api/auth', authRoutes);

async function initializeDefaultAdmin() {
    try {
        const defaultAdminEmail = 'superadmin@gmail.com';
        const defaultAdminPassword = '12345';

        const existingAdmin = await User.findOne({ email: defaultAdminEmail });
        if (existingAdmin) {
            console.log('Default admin user already exists');
            return;
        }

        const salt = await bcrypt.genSalt(10);
        const hashedPassword = await bcrypt.hash(defaultAdminPassword, salt);

        const adminUser = new User({
            email: defaultAdminEmail,
            password: hashedPassword,
            role: 'admin'
        });

        await adminUser.save();
        console.log('Default admin user created successfully');
    } catch (error) {
        console.error('Error creating default admin user:', error);
    }
}

async function collectDeviceDetails() {
    try {
        await collectCPUMetrics();
        await collectMemoryMetrics();
        await collectDiskMetrics();
        await collectNetworkMetrics();
    } catch (error) {
        console.error('Error collecting metrics:', error);
    }
}

app.listen(port, async () => {
    console.log(`Posting server is listening on port ${port}`);
    await connectToMongoDB();
    await initializeDefaultAdmin();
    await sendDeviceDetails();
    collectDeviceDetails();
    setInterval(collectDeviceDetails, intervalInSeconds * 1000);
});