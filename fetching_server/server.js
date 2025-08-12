require('dotenv').config();
const express = require('express');
const cors = require('cors');
const connectToMongoDB = require('./config/db');
const webpush = require('./config/webpush');
const authRoutes = require('./routes/auth');
const metricsRoutes = require('./routes/metrics');
const User = require('./models/User');
const bcrypt = require('bcryptjs');
const { deletePastMetrics, updateServerStatus, sendServerStatusEmail } = require('./utils/Fns');
const app = express();
const port = 3001; // Different port from data-posting-server to avoid conflicts

// Middleware
app.use(cors());
app.use(express.json());
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

// Routes
app.use('/api/auth', authRoutes);
app.use('/api', metricsRoutes);



// Run once every 24 hours
setInterval(deletePastMetrics, 24 * 60 * 60 * 1000);

// Run every 1  minutes
setInterval(updateServerStatus, 1 * 80 * 1000);
setInterval(sendServerStatusEmail, 1 * 60 * 1000);

// Start the server
app.listen(port, async () => {
  console.log(`Data Fetching Server is listening on port ${port}`);
  await connectToMongoDB();
  await initializeDefaultAdmin();
});