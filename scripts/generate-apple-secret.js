const jwt = require("jsonwebtoken");
const fs = require("fs");
const path = require("path");

const P8_PATH = process.env.APPLE_P8_PATH;
const TEAM_ID = process.env.APPLE_TEAM_ID;
const CLIENT_ID = process.env.APPLE_CLIENT_ID;
const KEY_ID = process.env.APPLE_KEY_ID;

if (!P8_PATH || !TEAM_ID || !CLIENT_ID || !KEY_ID) {
  console.error(
    "Usage:\n" +
      "  APPLE_P8_PATH=./AuthKey_XXXX.p8 \\\n" +
      "  APPLE_TEAM_ID=YOUR_TEAM_ID \\\n" +
      "  APPLE_KEY_ID=YOUR_KEY_ID \\\n" +
      "  APPLE_CLIENT_ID=com.yourteam.noteworks.signin \\\n" +
      "  node scripts/generate-apple-secret.js"
  );
  process.exit(1);
}

const privateKey = fs.readFileSync(path.resolve(P8_PATH));

const token = jwt.sign({}, privateKey, {
  algorithm: "ES256",
  expiresIn: "180d",
  audience: "https://appleid.apple.com",
  issuer: TEAM_ID,
  subject: CLIENT_ID,
  keyid: KEY_ID,
});

console.log("\nApple client secret (paste into Supabase):\n");
console.log(token);
console.log("\nExpires in 180 days. Regenerate before then.\n");
