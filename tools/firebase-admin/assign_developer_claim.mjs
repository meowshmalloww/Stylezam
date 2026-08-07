import { applicationDefault, cert, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import fs from "node:fs";

const requestedEmail = process.argv[2]?.trim().toLowerCase();
const allowedEmails = new Set(
  (process.env.STYLEZAM_DEVELOPER_EMAILS ?? "")
    .split(",")
    .map((value) => value.trim().toLowerCase())
    .filter(Boolean),
);

if (!requestedEmail || !requestedEmail.includes("@")) {
  throw new Error("Usage: npm run grant-developer -- developer@example.com");
}
if (!allowedEmails.has(requestedEmail)) {
  throw new Error("Refusing to grant access: email is not in STYLEZAM_DEVELOPER_EMAILS.");
}

const serviceAccountPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
const credential = serviceAccountPath
  ? cert(JSON.parse(fs.readFileSync(serviceAccountPath, "utf8")))
  : applicationDefault();

initializeApp({ credential });
const auth = getAuth();
const user = await auth.getUserByEmail(requestedEmail);
const existingClaims = user.customClaims ?? {};
await auth.setCustomUserClaims(user.uid, {
  ...existingClaims,
  developer: true,
  plan: "developer",
  role: "authenticated",
});

console.log(`Developer and Supabase authenticated claims granted to Firebase UID ${user.uid}.`);
console.log("Sign out and back in, or tap Refresh developer access in Stylezam.");
