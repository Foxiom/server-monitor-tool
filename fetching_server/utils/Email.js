const nodemailer = require("nodemailer");
const handlebars = require("handlebars");
const fs = require("fs");
const path = require("path");

// Read the HTML template file synchronously
const emailTemplateSource = fs.readFileSync(
  path.join(__dirname, "../view/serverStatus.hbs"),
  "utf8"
);

const emailTemplate = handlebars.compile(emailTemplateSource);

const sendEmail = async (options) => {
  try {
    // 1) Create a transporter
    const transporter = nodemailer.createTransport({
      service: "gmail",
      auth: {
        user: process.env.EMAIL_USERNAME,
        pass: process.env.EMAIL_PASSWORD,
      },
    });

    // 2) Define the email options
    const mailOptions = {
      from: process.env.EMAIL_USERNAME,
      to: process.env.EMAIL_TO,
      subject: "Server Status",
      html: emailTemplate({
        servers: options.servers,
        isUp: options.status === "up" 
      }),      
    };

    // 3) Actually send the email
    const info = await transporter.sendMail(mailOptions);

    return { code: 200, message: "success", data: info?.messageId };
  } catch (error) {
    console.error("Error sending email:", error);
    return { code: 500, message: "Error sending email" };
  }
};

module.exports = sendEmail;
